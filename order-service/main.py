# import os
# import json
# import psycopg2
# from fastapi import FastAPI, HTTPException
# from fastapi.middleware.cors import CORSMiddleware
# from pydantic import BaseModel
# from typing import List

# app = FastAPI()
# app.add_middleware(
#     CORSMiddleware,
#     allow_origins=["*"],
#     allow_credentials=True,
#     allow_methods=["*"],
#     allow_headers=["*"],
# )

# # Environment Variables
# DB_HOST = os.environ.get('DB_HOST', 'postgres')
# DB_NAME = os.environ.get('DB_NAME', 'postgres')
# DB_USER = os.environ.get('DB_USER', 'postgres')
# DB_PASS = os.environ.get('DB_PASS', 'password')
# # For local testing, we print to console instead of sending to real SQS
# SQS_QUEUE_URL = os.environ.get('ORDER_QUEUE_URL', 'mock-queue')

# # Pydantic Models (Input Validation)
# class OrderItem(BaseModel):
#     item_id: str
#     warehouse_id: str
#     quantity: int

# class OrderRequest(BaseModel):
#     customer_id: str
#     items: List[OrderItem]

# def get_db_connection():
#     return psycopg2.connect(
#         host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASS
#     )

# @app.post("/order")
# def place_order(order: OrderRequest):
#     conn = get_db_connection()
#     cursor = conn.cursor()
    
#     try:
#         # 1. Start Transaction
#         # In Python psycopg2, transactions are implicit when you start executing commands
        
#         items_data = []
        
#         for item in order.items:
#             # 2. LOCK ROW (ACID) - The "Resume" Logic
#             cursor.execute(
#                 "SELECT stock FROM inventory WHERE item_id=%s AND warehouse_id=%s FOR UPDATE",
#                 (item.item_id, item.warehouse_id)
#             )
#             row = cursor.fetchone()
            
#             if not row:
#                 raise Exception(f"Item {item.item_id} not found in warehouse {item.warehouse_id}")
            
#             stock = row[0]
#             if stock < item.quantity:
#                 raise Exception(f"Insufficient stock for item {item.item_id}")
            
#             # 3. Update Stock
#             new_stock = stock - item.quantity
#             cursor.execute(
#                 "UPDATE inventory SET stock=%s WHERE item_id=%s AND warehouse_id=%s",
#                 (new_stock, item.item_id, item.warehouse_id)
#             )
            
#             # Record item details for the order log
#             items_data.append(item.dict())

#         # 4. Create Order Record
#         items_json = json.dumps(items_data)
#         cursor.execute(
#             "INSERT INTO orders (customer_id, status, items) VALUES (%s, %s, %s) RETURNING order_id",
#             (order.customer_id, 'PENDING', items_json)
#         )
#         order_id = cursor.fetchone()[0]
        
#         # 5. Commit Transaction
#         conn.commit()
        
#         # 6. Mock SQS (Simulate sending message)
#         print(f"SQS MESSAGE SENT: Order {order_id} placed for items {items_data}")
        
#         return {"status": "success", "order_id": order_id}

#     except Exception as e:
#         conn.rollback()
#         raise HTTPException(status_code=400, detail=str(e))
#     finally:
#         cursor.close()
#         conn.close()

#         # NEW: Model for Order Response
# class OrderResponse(BaseModel):
#     order_id: int
#     status: str
#     items: List[dict]
#     created_at: str

# @app.get("/orders/{customer_id}")
# def get_order_history(customer_id: str):
#     conn = get_db_connection()
#     cursor = conn.cursor()
#     try:
#         # Query Aurora/Postgres for user's orders
#         cursor.execute(
#             "SELECT order_id, status, items, created_at FROM orders WHERE customer_id = %s ORDER BY order_id DESC",
#             (customer_id,)
#         )
#         rows = cursor.fetchall()
        
#         history = []
#         for row in rows:
#             # Parse JSON items from DB
#             items_data = row[2] if isinstance(row[2], list) else json.loads(row[2])
            
#             history.append({
#                 "order_id": row[0],
#                 "status": row[1], # e.g., 'PENDING'
#                 "items": items_data,
#                 "created_at": str(row[3])
#             })
            
#         return history
#     except Exception as e:
#         raise HTTPException(status_code=500, detail=str(e))
#     finally:
#         cursor.close()
#         conn.close()



import os
import json
import boto3
import uuid
import time
import atexit
import psycopg2
from datetime import datetime
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional
try:
    from kafka import KafkaProducer
    from kafka.errors import KafkaError, NoBrokersAvailable
    KAFKA_LIB_AVAILABLE = True
except ImportError:
    KAFKA_LIB_AVAILABLE = False
from prometheus_fastapi_instrumentator import Instrumentator
from prometheus_client import Counter, Histogram, Gauge, Info
import logging

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)

app = FastAPI(title="Order Service", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# =====================================================
# PROMETHEUS METRICS
# =====================================================

# Auto-instrument all endpoints
Instrumentator().instrument(app).expose(app)

# --- Custom Business Metrics ---
orders_placed_total = Counter(
    'orders_placed_total',
    'Total orders placed',
    ['warehouse_id', 'status']
)
items_ordered_total = Counter(
    'items_ordered_total',
    'Total items ordered',
    ['item_id', 'warehouse_id']
)
order_items_quantity = Counter(
    'order_items_quantity_total',
    'Total quantity of items ordered',
    ['item_id', 'warehouse_id']
)
order_value = Histogram(
    'order_value_rupees',
    'Order value distribution in rupees',
    buckets=[50, 100, 200, 500, 1000, 2000, 5000]
)
multi_warehouse_orders = Counter(
    'multi_warehouse_orders_total',
    'Orders spanning multiple warehouses'
)
order_failures = Counter(
    'order_failures_total',
    'Failed order attempts',
    ['error_type']
)
active_orders = Gauge(
    'active_orders_current',
    'Currently active (PENDING/PROCESSING) orders'
)
order_service_info = Info(
    'order_service',
    'Order service build information'
)
order_service_info.info({'version': '1.0.0', 'env': os.getenv('ENV', 'prod')})

# Config
SQS_QUEUE_URL = os.environ.get('SQS_QUEUE_URL')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', '')  # SNS topic for notifications
REGION = os.environ.get("AWS_REGION", "us-east-1")
ENV = os.getenv("ENV", "prod")
NO_KAFKA = os.getenv("NO_KAFKA", "false").lower() == "true"
KAFKA_BOOTSTRAP_SERVERS = os.environ.get("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")

# Database Config
DB_HOST = os.environ.get('DB_HOST', 'postgres')
DB_PORT = int(os.environ.get('DB_PORT', '5432'))
DB_NAME = os.environ.get('DB_NAME', 'postgres')
DB_USER = os.environ.get('DB_USER', 'postgres')
DB_PASS = os.environ.get('DB_PASS', 'password')

# Initialize clients
sqs = None
sns = None
producer = None

def create_kafka_producer(max_retries=5, initial_backoff=2):
    """Create Kafka producer with retry logic and exponential backoff."""
    backoff = initial_backoff

    for attempt in range(1, max_retries + 1):
        try:
            logging.info(f"Connecting to Kafka at {KAFKA_BOOTSTRAP_SERVERS} (attempt {attempt}/{max_retries})...")
            prod = KafkaProducer(
                bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
                value_serializer=lambda v: json.dumps(v).encode('utf-8'),
                acks='all',  # Wait for all replicas to acknowledge
                retries=3,   # Retry failed sends
                retry_backoff_ms=500,
            )
            logging.info("Kafka Producer connected successfully")
            return prod

        except NoBrokersAvailable as e:
            logging.warning(f"No Kafka brokers available: {e}")
        except KafkaError as e:
            logging.warning(f"Kafka connection error: {e}")
        except Exception as e:
            logging.warning(f"Unexpected error connecting to Kafka: {e}")

        if attempt < max_retries:
            logging.info(f"Retrying in {backoff} seconds...")
            time.sleep(backoff)
            backoff = min(backoff * 2, 30)

    logging.warning("Failed to connect to Kafka - producer will be unavailable")
    return None


def get_kafka_producer():
    """Get or create Kafka producer with lazy initialization."""
    global producer
    # Skip Kafka entirely when NO_KAFKA=true or kafka lib not installed
    if NO_KAFKA or not KAFKA_LIB_AVAILABLE:
        return None
    if producer is None and ENV == "local":
        producer = create_kafka_producer()
    return producer


def cleanup_producer():
    """Cleanup Kafka producer on shutdown."""
    global producer
    if producer:
        try:
            producer.flush(timeout=5)
            producer.close(timeout=5)
            logging.info("Kafka producer closed")
        except Exception as e:
            logging.warning(f"Error closing Kafka producer: {e}")


if ENV != "local":
    sqs = boto3.client("sqs", region_name=REGION)
    sns = boto3.client("sns", region_name=REGION)
elif not NO_KAFKA:
    # Register cleanup handler only when using Kafka
    atexit.register(cleanup_producer)
else:
    logging.info("NO_KAFKA=true: Skipping Kafka producer init (DB-only mode)")

def get_db_connection():
    """Get PostgreSQL database connection"""
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASS,
            connect_timeout=5
        )
        return conn
    except Exception as e:
        logging.error(f"DB Connection Error: {e}")
        raise HTTPException(status_code=503, detail="Database unavailable")


class OrderItem(BaseModel):
    item_id: str
    warehouse_id: str
    quantity: int

class OrderRequest(BaseModel):
    customer_id: str
    items: List[OrderItem]

@app.get("/")
def health_check():
    return {"status": "healthy", "service": "order-service"}

@app.post("/orders")
def place_order(order: OrderRequest):
    parent_order_id = str(uuid.uuid4())[:12]
    
    # Group items by warehouse_id for proper multi-warehouse handling
    warehouse_groups = {}
    for item in order.items:
        wh = item.warehouse_id
        warehouse_groups.setdefault(wh, []).append(item)
    
    is_multi_warehouse = len(warehouse_groups) > 1
    sub_order_ids = []
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        try:
            for wh_id, items in warehouse_groups.items():
                # Each warehouse gets its own sub-order
                if is_multi_warehouse:
                    sub_order_id = f"{parent_order_id}-{wh_id}"
                else:
                    sub_order_id = parent_order_id
                
                sub_order_ids.append(sub_order_id)
                
                message_body = {
                    "order_id": sub_order_id,
                    "parent_order_id": parent_order_id,
                    "customer_id": order.customer_id,
                    "warehouse_id": wh_id,
                    "items": [item.dict() for item in items],
                    "is_multi_warehouse": is_multi_warehouse,
                    "total_warehouses": len(warehouse_groups),
                }
                
                # 1. Store sub-order in database
                cursor.execute("""
                    INSERT INTO orders (order_id, customer_id, warehouse_id, status, items, created_at) 
                    VALUES (%s, %s, %s, %s, %s, %s)
                """, (
                    sub_order_id,
                    order.customer_id,
                    wh_id,
                    'PENDING',
                    json.dumps(message_body['items']),
                    datetime.utcnow()
                ))
                
                # 2. Send to message queue
                if ENV == "local":
                    kafka_producer = get_kafka_producer()
                    if kafka_producer:
                        try:
                            future = kafka_producer.send('order_events', message_body)
                            future.get(timeout=10)
                            logging.info(f"Sent sub-order {sub_order_id} to Kafka (warehouse: {wh_id})")
                        except Exception as e:
                            logging.error(f"Kafka error for {sub_order_id}: {e}")
                    else:
                        logging.info(f"Sub-order {sub_order_id} saved to DB (no Kafka)")
                else:
                    sqs.send_message(
                        QueueUrl=SQS_QUEUE_URL,
                        MessageBody=json.dumps(message_body)
                    )
                
                # 3. Record Prometheus metrics per warehouse
                orders_placed_total.labels(warehouse_id=wh_id, status='success').inc()
                
                for item in items:
                    items_ordered_total.labels(item_id=item.item_id, warehouse_id=item.warehouse_id).inc()
                    order_items_quantity.labels(item_id=item.item_id, warehouse_id=item.warehouse_id).inc(item.quantity)
            
            conn.commit()
            active_orders.inc()
            
        except Exception as db_error:
            conn.rollback()
            logging.error(f"DB Error placing order: {db_error}")
            raise
        finally:
            cursor.close()
            conn.close()
        
        # Track multi-warehouse metric
        if is_multi_warehouse:
            multi_warehouse_orders.inc()
            logging.info(f"Multi-warehouse order {parent_order_id} split into {len(sub_order_ids)} sub-orders: {sub_order_ids}")
        
        return {
            "status": "success",
            "order_id": parent_order_id,
            "sub_orders": sub_order_ids,
            "warehouses": list(warehouse_groups.keys()),
            "is_multi_warehouse": is_multi_warehouse,
            "message": f"Order placed successfully" + (f" (split across {len(warehouse_groups)} warehouses)" if is_multi_warehouse else ""),
        }
    
    except HTTPException:
        raise
    except Exception as e:
        logging.error(f"Order Error: {e}")
        order_failures.labels(error_type=type(e).__name__).inc()
        orders_placed_total.labels(warehouse_id='error', status='failed').inc()
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/orders/{customer_id}")
def get_order_history(customer_id: str):
    """Get order history from database"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT order_id, customer_id, status, items, created_at 
            FROM orders 
            WHERE customer_id = %s 
            ORDER BY created_at DESC
            LIMIT 50
        """, (customer_id,))
        
        rows = cursor.fetchall()
        cursor.close()
        conn.close()
        
        orders = []
        for row in rows:
            # Parse items JSON from database
            items_data = row[3] if isinstance(row[3], list) else json.loads(row[3])
            
            orders.append({
                "order_id": row[0],
                "customer_id": row[1],
                "status": row[2],
                "items": items_data,
                "created_at": row[4].isoformat() if row[4] else None
            })
        
        return orders
    
    except HTTPException:
        raise
    except Exception as e:
        logging.error(f"Order History Error: {e}")
        # Return empty list instead of error for better UX
        return []


# SELLER/WAREHOUSE ORDER ENDPOINTS

@app.get("/warehouse/{warehouse_id}/orders")
def get_warehouse_orders(warehouse_id: str):
    """Get orders for a specific warehouse (for sellers/managers)"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT order_id, customer_id, warehouse_id, status, items, created_at 
            FROM orders 
            WHERE warehouse_id = %s 
            ORDER BY created_at DESC
            LIMIT 100
        """, (warehouse_id,))
        
        rows = cursor.fetchall()
        cursor.close()
        conn.close()
        
        orders = []
        for row in rows:
            # Parse items JSON from database
            items_data = row[4] if isinstance(row[4], list) else json.loads(row[4])
            
            orders.append({
                "order_id": row[0],
                "customer_id": row[1],
                "warehouse_id": row[2],
                "status": row[3],
                "items": items_data,
                "created_at": row[5].isoformat() if row[5] else None
            })
        
        return {"orders": orders, "count": len(orders), "warehouse_id": warehouse_id}
    
    except HTTPException:
        raise
    except Exception as e:
        logging.error(f"Warehouse Orders Error: {e}")
        return {"orders": [], "count": 0, "warehouse_id": warehouse_id}


# SNS NOTIFICATION ENDPOINTS

class SubscribeRequest(BaseModel):
    warehouse_id: str
    email: str
    notification_type: Optional[str] = "all"  # 'orders', 'low_stock', 'all'

@app.post("/subscribe")
def subscribe_to_notifications(request: SubscribeRequest):
    """Subscribe email to SNS notifications for a warehouse"""
    if ENV == "local":
        logging.info(f"LOCAL: Would subscribe {request.email} to {request.warehouse_id} notifications")
        return {
            "success": True,
            "message": f"Subscribed {request.email} to notifications (local mode)",
            "warehouse_id": request.warehouse_id
        }
    
    if not SNS_TOPIC_ARN:
        raise HTTPException(status_code=503, detail="SNS notifications not configured")
    
    try:
        # Subscribe email to SNS topic with filter policy
        response = sns.subscribe(
            TopicArn=SNS_TOPIC_ARN,
            Protocol='email',
            Endpoint=request.email,
            Attributes={
                'FilterPolicy': json.dumps({
                    'warehouse_id': [request.warehouse_id],
                    'notification_type': [request.notification_type, 'all']
                })
            }
        )
        
        subscription_arn = response.get('SubscriptionArn', 'pending confirmation')
        
        return {
            "success": True,
            "message": f"Subscription pending - check {request.email} for confirmation",
            "subscription_arn": subscription_arn,
            "warehouse_id": request.warehouse_id
        }
    except Exception as e:
        logging.error(f"SNS Subscribe Error: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to subscribe: {str(e)}")


@app.post("/notify")
def send_notification(data: dict):
    """Send notification via SNS (internal use)"""
    if ENV == "local":
        logging.info(f"LOCAL NOTIFICATION: {data}")
        return {"success": True, "message": "Notification logged (local mode)"}
    
    if not SNS_TOPIC_ARN:
        return {"success": False, "message": "SNS not configured"}
    
    try:
        warehouse_id = data.get('warehouse_id', 'unknown')
        notification_type = data.get('type', 'order')
        message = data.get('message', 'New notification from Rapid Delivery')
        
        response = sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Message=message,
            Subject=f"Rapid Delivery - {notification_type.title()} Alert",
            MessageAttributes={
                'warehouse_id': {
                    'DataType': 'String',
                    'StringValue': warehouse_id
                },
                'notification_type': {
                    'DataType': 'String',
                    'StringValue': notification_type
                }
            }
        )
        
        return {
            "success": True,
            "message_id": response.get('MessageId'),
            "warehouse_id": warehouse_id
        }
    except Exception as e:
        logging.error(f"SNS Publish Error: {e}")
        return {"success": False, "error": str(e)}