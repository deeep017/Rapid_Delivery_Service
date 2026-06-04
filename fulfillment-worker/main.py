import os
import json
import time
import signal
import sys
import psycopg2
import redis
import logging
import threading
from prometheus_client import Counter, Histogram, Gauge, start_http_server as start_metrics_server
try:
    from kafka import KafkaConsumer
    from kafka.errors import KafkaError, NoBrokersAvailable
    KAFKA_AVAILABLE = True
except ImportError:
    KAFKA_AVAILABLE = False
    logging.warning("kafka-python not installed, Kafka mode unavailable")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)

# Graceful shutdown flag
shutdown_requested = False

def signal_handler(signum, frame):
    global shutdown_requested
    logging.info("Shutdown signal received, finishing current work...")
    shutdown_requested = True

signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)

# Environment
ENV = os.environ.get("ENV", "prod")
NO_KAFKA = os.environ.get("NO_KAFKA", "false").lower() == "true"
SQS_QUEUE_URL = os.environ.get("SQS_QUEUE_URL")
DB_HOST = os.environ.get("DB_HOST")
DB_PORT = int(os.environ.get("DB_PORT", "5432"))
DB_NAME = os.environ.get("DB_NAME", "rapid_delivery")
DB_USER = os.environ.get("DB_USER", "postgres")
DB_PASS = os.environ.get("DB_PASS", "postgres")
REDIS_HOST = os.environ.get("REDIS_HOST", "localhost")
REDIS_PORT = int(os.environ.get("REDIS_PORT", "6379"))
KAFKA_BOOTSTRAP_SERVERS = os.environ.get("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")

# Local mode doesn't require SQS
if ENV != "local" and not SQS_QUEUE_URL:
    raise RuntimeError("SQS_QUEUE_URL is required in production mode")

if not DB_HOST:
    raise RuntimeError("DB_HOST is required")

logging.info(f"Starting fulfillment worker (ENV={ENV})")
logging.info(f"DB Host: {DB_HOST}:{DB_PORT}/{DB_NAME}")

# =====================================================
# PROMETHEUS METRICS for Fulfillment Worker
# =====================================================

orders_processed = Counter(
    'fulfillment_orders_processed_total',
    'Total orders processed by fulfillment worker',
    ['status']  # 'completed', 'failed', 'skipped'
)
order_processing_time = Histogram(
    'fulfillment_processing_seconds',
    'Time to process a single order',
    buckets=[0.1, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0]
)
stock_deductions = Counter(
    'fulfillment_stock_deductions_total',
    'Stock deducted per item per warehouse',
    ['warehouse_id', 'item_id']
)
stock_deduction_quantity = Counter(
    'fulfillment_stock_deduction_quantity_total',
    'Total quantity deducted',
    ['warehouse_id', 'item_id']
)
active_processing = Gauge(
    'fulfillment_active_processing',
    'Orders currently being processed'
)
worker_polls = Counter(
    'fulfillment_poll_cycles_total',
    'Total poll cycles (Kafka or DB)',
    ['source']  # 'kafka', 'db'
)

# Start Prometheus metrics HTTP server on port 8002
try:
    start_metrics_server(8002)
    logging.info("Prometheus metrics server started on port 8002")
except Exception as e:
    logging.warning(f"Could not start metrics server: {e}")

# Initialize SQS only in production
sqs = None
if ENV != "local":
    import boto3
    AWS_REGION = os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION")
    if not AWS_REGION:
        temp_session = boto3.session.Session()
        AWS_REGION = temp_session.region_name
    if not AWS_REGION:
        raise RuntimeError("AWS region could not be resolved.")
    logging.info(f"AWS Region: {AWS_REGION}")
    logging.info(f"SQS Queue: {SQS_QUEUE_URL}")
    sqs = boto3.client("sqs", region_name=AWS_REGION)

# Redis connection for stock updates
try:
    redis_client = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)
    redis_client.ping()
    logging.info(f"Redis connected: {REDIS_HOST}:{REDIS_PORT}")
except Exception as e:
    logging.warning(f"Redis not available: {e}")
    redis_client = None


# Database Connection
def get_db_connection():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASS
    )

# Update Redis stock after order processing
def update_redis_stock(warehouse_id: str, item_id: str, quantity: int):
    if redis_client:
        key = f"{warehouse_id}:{item_id}"
        try:
            current = redis_client.get(key)
            if current:
                new_stock = max(0, int(current) - quantity)
                redis_client.set(key, new_stock)
                logging.info(f"Redis updated: {key} = {new_stock}")
        except Exception as e:
            logging.warning(f"Redis update failed: {e}")

# Order Processing Logic
def process_order(order_data: dict) -> bool:
    order_id = order_data.get("order_id")
    items = order_data.get("items", [])
    warehouse_id = order_data.get("warehouse_id")

    if not order_id or not items:
        logging.error("Invalid order payload")
        orders_processed.labels(status='failed').inc()
        return False

    start_time = time.time()
    active_processing.inc()
    conn = get_db_connection()
    cur = conn.cursor()

    try:
        logging.info(f"Processing order {order_id}")

        # Update order status to PROCESSING
        cur.execute(
            "UPDATE orders SET status = %s WHERE order_id = %s AND status = %s",
            ('PROCESSING', order_id, 'PENDING')
        )
        
        if cur.rowcount == 0:
            logging.info(f"Order {order_id} already processed or not found")
            conn.rollback()
            orders_processed.labels(status='skipped').inc()
            return True

        # Update Redis stock for each item
        for item in items:
            item_warehouse = item.get("warehouse_id", warehouse_id)
            item_id = item["item_id"]
            qty = item["quantity"]
            update_redis_stock(item_warehouse, item_id, qty)
            # Track stock deductions in Prometheus
            stock_deductions.labels(warehouse_id=item_warehouse or 'unknown', item_id=item_id).inc()
            stock_deduction_quantity.labels(warehouse_id=item_warehouse or 'unknown', item_id=item_id).inc(qty)

        # Mark order as COMPLETED
        cur.execute(
            "UPDATE orders SET status = %s WHERE order_id = %s",
            ('COMPLETED', order_id)
        )

        conn.commit()
        elapsed = time.time() - start_time
        order_processing_time.observe(elapsed)
        orders_processed.labels(status='completed').inc()
        logging.info(f"Order {order_id} completed in {elapsed:.2f}s")
        return True

    except Exception as e:
        conn.rollback()
        logging.error(f"Order {order_id} failed: {e}")
        orders_processed.labels(status='failed').inc()
        # Mark as FAILED
        try:
            cur.execute(
                "UPDATE orders SET status = %s WHERE order_id = %s",
                ('FAILED', order_id)
            )
            conn.commit()
        except:
            pass
        return False

    finally:
        active_processing.dec()
        cur.close()
        conn.close()


# LOCAL MODE: Consume from Kafka
def create_kafka_consumer(max_retries=10, initial_backoff=2):
    """Create Kafka consumer with exponential backoff retry logic."""
    backoff = initial_backoff

    for attempt in range(1, max_retries + 1):
        if shutdown_requested:
            return None

        try:
            logging.info(f"Connecting to Kafka at {KAFKA_BOOTSTRAP_SERVERS} (attempt {attempt}/{max_retries})...")
            consumer = KafkaConsumer(
                'order_events',
                bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
                auto_offset_reset='earliest',
                enable_auto_commit=True,
                group_id='fulfillment-group',
                value_deserializer=lambda x: json.loads(x.decode('utf-8')),
                consumer_timeout_ms=1000,  # Allow periodic shutdown checks
                session_timeout_ms=30000,
                heartbeat_interval_ms=10000,
            )
            logging.info("Kafka Consumer connected successfully")
            return consumer

        except NoBrokersAvailable as e:
            logging.warning(f"No Kafka brokers available: {e}")
        except KafkaError as e:
            logging.warning(f"Kafka connection error: {e}")
        except Exception as e:
            logging.warning(f"Unexpected error connecting to Kafka: {e}")

        if attempt < max_retries:
            logging.info(f"Retrying in {backoff} seconds...")
            time.sleep(backoff)
            backoff = min(backoff * 2, 60)  # Cap at 60 seconds

    logging.error("Failed to connect to Kafka after all retries")
    return None


def poll_kafka_forever():
    """Consume messages from Kafka with graceful shutdown support."""
    global shutdown_requested

    while not shutdown_requested:
        consumer = create_kafka_consumer()

        if consumer is None:
            if shutdown_requested:
                logging.info("Shutdown requested, exiting...")
                return
            logging.error("Could not establish Kafka connection, retrying in 30s...")
            time.sleep(30)
            continue

        try:
            logging.info("Waiting for messages on 'order_events' topic...")

            while not shutdown_requested:
                # Poll with timeout to allow shutdown checks
                messages = consumer.poll(timeout_ms=1000)

                for topic_partition, records in messages.items():
                    for message in records:
                        if shutdown_requested:
                            break
                        logging.info(f"Received Kafka message: {message.value}")
                        process_order(message.value)

        except KafkaError as e:
            logging.error(f"Kafka error during consumption: {e}")
        except Exception as e:
            logging.error(f"Unexpected error: {e}")
        finally:
            try:
                consumer.close()
                logging.info("Kafka consumer closed")
            except Exception:
                pass

        if not shutdown_requested:
            logging.info("Reconnecting to Kafka in 5 seconds...")
            time.sleep(5)


# PRODUCTION MODE: Poll SQS for orders
def poll_sqs_forever():
    logging.info("PRODUCTION MODE: Polling SQS for orders...")

    while True:
        try:
            response = sqs.receive_message(
                QueueUrl=SQS_QUEUE_URL,
                MaxNumberOfMessages=1,
                WaitTimeSeconds=20
            )

            messages = response.get("Messages", [])

            if not messages:
                time.sleep(2)
                continue

            for msg in messages:
                receipt_handle = msg["ReceiptHandle"]
                body = json.loads(msg["Body"])

                if process_order(body):
                    sqs.delete_message(
                        QueueUrl=SQS_QUEUE_URL,
                        ReceiptHandle=receipt_handle
                    )

        except Exception as e:
            logging.error(f"SQS polling error: {e}")
            time.sleep(5)


# DB POLLING MODE — used when NO_KAFKA=true (no Kafka container needed)
def poll_db_forever():
    """Poll PostgreSQL for PENDING orders and process them directly.
    Used in local dev when Kafka is not available.
    """
    logging.info("NO_KAFKA MODE: Polling PostgreSQL for PENDING orders every 3s...")

    while not shutdown_requested:
        try:
            conn = get_db_connection()
            cur = conn.cursor()

            # Find PENDING orders
            cur.execute("""
                SELECT order_id, customer_id, warehouse_id, items
                FROM orders
                WHERE status = 'PENDING'
                ORDER BY created_at ASC
                LIMIT 10
            """)
            rows = cur.fetchall()
            cur.close()
            conn.close()

            if rows:
                logging.info(f"Found {len(rows)} PENDING order(s) to process")
                for row in rows:
                    if shutdown_requested:
                        break
                    order_data = {
                        "order_id": row[0],
                        "customer_id": row[1],
                        "warehouse_id": row[2],
                        "items": row[3] if isinstance(row[3], list) else json.loads(row[3])
                    }
                    process_order(order_data)

        except Exception as e:
            logging.error(f"DB polling error: {e}")

        time.sleep(3)  # Poll every 3 seconds

    logging.info("DB polling stopped")


# Entrypoint
if __name__ == "__main__":
    logging.info(f"Starting fulfillment worker in {ENV} mode (NO_KAFKA={NO_KAFKA})")

    if ENV == "local" and NO_KAFKA:
        # No Kafka container — poll DB directly
        poll_db_forever()
    elif ENV == "local":
        poll_kafka_forever()
    else:
        poll_sqs_forever()

    logging.info("Fulfillment worker stopped")