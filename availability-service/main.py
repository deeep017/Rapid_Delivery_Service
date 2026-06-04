import os
import json
import requests
import redis
import logging
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional
from prometheus_fastapi_instrumentator import Instrumentator
from prometheus_client import Counter, Gauge, Histogram, Info

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
# Pydantic models for request bodies
class StockUpdateRequest(BaseModel):
    stock: int

# AWS SigV4 Authentication for OpenSearch
def get_aws_auth():
    """Get AWS SigV4 auth for OpenSearch requests"""
    try:
        import boto3
        from requests_aws4auth import AWS4Auth
        
        region = os.environ.get('AWS_REGION', 'us-east-1')
        credentials = boto3.Session().get_credentials()
        if credentials:
            return AWS4Auth(
                credentials.access_key,
                credentials.secret_key,
                region,
                'es',
                session_token=credentials.token
            )
    except ImportError:
        logging.warning("boto3/requests-aws4auth not available, using unsigned requests")
    except Exception as e:
        logging.warning(f"AWS auth setup failed: {e}")
    return None

AWS_AUTH = get_aws_auth()

app = FastAPI(title="Availability Service", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allows all origins (Flutter Web, Mobile, etc.)
    allow_credentials=True,
    allow_methods=["*"],  # Allows all methods (GET, POST, etc.)
    allow_headers=["*"],  # Allows all headers
)

# =====================================================
# PROMETHEUS METRICS
# =====================================================

# Auto-instrument all FastAPI endpoints (request count, latency, status)
Instrumentator().instrument(app).expose(app)

# --- Custom Business Metrics ---
stock_lookups = Counter(
    'availability_stock_lookups_total',
    'Total stock lookup requests',
    ['item_id', 'warehouse_id', 'found']
)
aggregated_queries = Counter(
    'availability_aggregated_queries_total',
    'Multi-warehouse aggregated searches',
    ['warehouse_count']
)
low_stock_events = Counter(
    'availability_low_stock_events_total',
    'Items found with stock below threshold',
    ['warehouse_id', 'item_id']
)
warehouse_product_count = Gauge(
    'availability_warehouse_products',
    'Number of products at each warehouse',
    ['warehouse_id']
)
inventory_stock_level = Gauge(
    'inventory_stock_level',
    'Current stock level per warehouse per item',
    ['warehouse_id', 'item_id']
)
service_info = Info(
    'availability_service',
    'Availability service build information'
)
service_info.info({'version': '1.0.0', 'env': os.environ.get('ENV', 'prod')})

# --- Background Inventory Gauge Updater ---
# Updates Prometheus gauges every 30s by scanning Redis
# This is the FIX for inventory vanishing from dashboard
import threading, time as _time

def _inventory_gauge_updater():
    """Background thread: scans Redis every 30s and updates Prometheus gauges."""
    while True:
        try:
            _time.sleep(30)
            if not r:
                continue
            warehouses_seen = {}
            for key in r.scan_iter("wh_*"):
                parts = key.split(':')
                if len(parts) != 2:
                    continue
                wh_id, item_id = parts[0], parts[1]
                qty = r.get(key)
                stock = int(qty) if qty else 0
                inventory_stock_level.labels(warehouse_id=wh_id, item_id=item_id).set(stock)
                warehouses_seen.setdefault(wh_id, 0)
                warehouses_seen[wh_id] += 1
            for wh_id, count in warehouses_seen.items():
                warehouse_product_count.labels(warehouse_id=wh_id).set(count)
            logging.debug(f"Inventory gauges updated: {sum(warehouses_seen.values())} keys from {len(warehouses_seen)} warehouses")
        except Exception as e:
            logging.warning(f"Inventory gauge update error: {e}")

_gauge_thread = threading.Thread(target=_inventory_gauge_updater, daemon=True)
_gauge_thread.start()
logging.info("Started background inventory gauge updater (every 30s)")

# Environment variables (Defaults provided for local testing)
OPENSEARCH_URL = os.environ.get('OPENSEARCH_URL', 'http://localhost:9200')
REDIS_HOST = os.environ.get('REDIS_HOST', 'localhost')
REDIS_PORT = int(os.environ.get('REDIS_PORT', 6379))

# Configurable business rules (override via env vars)
MAX_DELIVERY_DISTANCE_KM = float(os.environ.get('MAX_DELIVERY_DISTANCE_KM', '30.0'))
MAX_WAREHOUSE_SEARCH = int(os.environ.get('MAX_WAREHOUSE_SEARCH', '10'))
LOW_STOCK_THRESHOLD = int(os.environ.get('LOW_STOCK_THRESHOLD', '20'))

# Initialize Redis Connection
# In production, add error handling if Redis is down
try:
    r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)
    r.ping()
    logging.info(f"Redis connected: {REDIS_HOST}:{REDIS_PORT}")
except Exception as e:
    logging.warning(f"Redis connection failed: {e}")
    r = None

@app.get("/")
def health_check():
    return {"status": "healthy", "service": "availability-service"}

@app.get("/availability")
def check_availability(
    item_id: str = Query(...),
    lat: float = Query(...),
    lon: float = Query(...)
):
    if not r:
        raise HTTPException(status_code=503, detail="Redis unavailable")

    # 1. Search OpenSearch for warehouses sorted by distance
    # here we just take for size 10, but we will filter them manually
    query = {
        "size": MAX_WAREHOUSE_SEARCH, 
        "sort": [
            { "_geo_distance": { "location": { "lat": lat, "lon": lon }, "order": "asc", "unit": "km" } }
        ]
    }

    try:
        url = f"{OPENSEARCH_URL}/warehouses/_search"
        res = requests.get(url, json=query, auth=AWS_AUTH, headers={"Content-Type": "application/json"})
        hits = res.json().get('hits', {}).get('hits', [])
    except Exception as e:
        return {"available": False, "reason": "Search failed"}

    # 2. THE INTELLIGENT LOOP
    for hit in hits:
        warehouse_id = hit['_source']['id']
        distance = hit['sort'][0] # Distance in KM
        
        # RULE 1: Max Distance Limit (30km)
        if distance > MAX_DELIVERY_DISTANCE_KM:
            # Since hits are sorted, if this one is too far, all subsequent ones are too.
            # We stop immediately.
            break 
            
        # RULE 2: Check Stock
        key = f"{warehouse_id}:{item_id}"
        qty = r.get(key)
        
        if qty is not None and int(qty) > 0:
            # Success! We found the closest VALID warehouse
            return {
                "available": True,
                "warehouse_id": warehouse_id,
                "distance_km": distance,
                "quantity": int(qty)
            }

    # If loop finishes without returning, no valid warehouse was found
    return {"available": False, "message": "No stock or no delivery in your area"}


@app.get("/availability/aggregated")
def check_aggregated_availability(
    lat: float = Query(...),
    lon: float = Query(...),
    max_distance: float = Query(30.0),
    max_warehouses: int = Query(3),
):
    """
    AGGREGATED AVAILABILITY — Multi-Warehouse Inventory
    
    Returns ALL products from up to `max_warehouses` nearest warehouses
    within `max_distance` km. Each product includes per-warehouse
    stock breakdown so the frontend can show delivery time badges
    and the cart can run consolidation.
    """
    if not r:
        raise HTTPException(status_code=503, detail="Redis unavailable")

    # 1. Find nearby warehouses sorted by distance
    query = {
        "size": max_warehouses * 2,  # fetch extra in case some are beyond max_distance
        "query": {
            "geo_distance": {
                "distance": f"{int(max_distance)}km",
                "location": {"lat": lat, "lon": lon}
            }
        },
        "sort": [
            {"_geo_distance": {"location": {"lat": lat, "lon": lon}, "order": "asc", "unit": "km"}}
        ]
    }

    try:
        url = f"{OPENSEARCH_URL}/warehouses/_search"
        res = requests.get(url, json=query, auth=AWS_AUTH, headers={"Content-Type": "application/json"})
        hits = res.json().get('hits', {}).get('hits', [])
    except Exception as e:
        logging.error(f"OpenSearch query failed: {e}")
        return {"warehouses": [], "products": []}

    # 2. Filter to max_warehouses within max_distance
    nearby_warehouses = []
    for hit in hits:
        distance = hit['sort'][0]
        if distance > max_distance:
            break
        if len(nearby_warehouses) >= max_warehouses:
            break
        
        source = hit['_source']
        eta = _calculate_eta(distance)
        nearby_warehouses.append({
            "id": source['id'],
            "city": source.get('city', source['id']),
            "distance_km": round(distance, 1),
            "eta_minutes": eta,
        })

    if not nearby_warehouses:
        return {"warehouses": [], "products": []}

    # 3. For each warehouse, scan Redis for ALL products
    # product_id -> { sources: [...], total_stock: N }
    product_map = {}

    for wh in nearby_warehouses:
        wh_id = wh["id"]
        pattern = f"{wh_id}:*"
        
        for key in r.scan_iter(pattern):
            item_id = key.split(':')[1] if ':' in key else key
            qty = r.get(key)
            stock = int(qty) if qty else 0

            if stock <= 0:
                continue  # Skip out-of-stock items

            if item_id not in product_map:
                product_map[item_id] = {
                    "id": item_id,
                    "name": _get_product_name(item_id),
                    "price": _get_product_price(item_id),
                    "category": _get_product_category(item_id),
                    "categoryId": _get_category_id(item_id),
                    "unit": "1 unit",
                    "imageEmoji": _get_product_emoji(item_id),
                    "total_stock": 0,
                    "best_warehouse": None,
                    "best_eta": 999,
                    "sources": [],
                }

            product_map[item_id]["total_stock"] += stock
            product_map[item_id]["sources"].append({
                "warehouse_id": wh_id,
                "stock": stock,
                "distance_km": wh["distance_km"],
                "eta_minutes": wh["eta_minutes"],
            })

            # Track best (closest) warehouse for this product
            if wh["eta_minutes"] < product_map[item_id]["best_eta"]:
                product_map[item_id]["best_eta"] = wh["eta_minutes"]
                product_map[item_id]["best_warehouse"] = wh_id

    # 4. Convert to list and sort by name
    products = sorted(product_map.values(), key=lambda p: p["name"])

    logging.info(
        f"Aggregated: {len(nearby_warehouses)} warehouses, "
        f"{len(products)} products for ({lat}, {lon})"
    )

    return {
        "warehouses": nearby_warehouses,
        "products": products,
    }


def _calculate_eta(distance_km: float) -> int:
    """Calculate delivery ETA in minutes based on distance"""
    if distance_km <= 5:
        return 10
    elif distance_km <= 15:
        return 25
    elif distance_km <= 30:
        return 40
    return 60


# INVENTORY MANAGEMENT ENDPOINTS (for Manager flow)

@app.get("/warehouses")
def get_warehouses():
    """Get list of all warehouses from OpenSearch"""
    try:
        query = {"size": 100, "query": {"match_all": {}}}
        url = f"{OPENSEARCH_URL}/warehouses/_search"
        res = requests.get(url, json=query, auth=AWS_AUTH, headers={"Content-Type": "application/json"})
        hits = res.json().get('hits', {}).get('hits', [])
        
        warehouses = []
        for hit in hits:
            source = hit['_source']
            warehouses.append({
                "id": source.get('id'),
                "city": source.get('city'),
                "lat": source.get('location', {}).get('lat'),
                "lon": source.get('location', {}).get('lon'),
            })
        
        return {"warehouses": warehouses, "count": len(warehouses)}
    except Exception as e:
        logging.error(f"Error fetching warehouses: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to fetch warehouses: {str(e)}")


@app.get("/inventory/{warehouse_id}")
def get_warehouse_inventory(warehouse_id: str):
    """Get all inventory for a specific warehouse from Redis"""
    if not r:
        raise HTTPException(status_code=503, detail="Redis unavailable")
    
    try:
        # Scan Redis for all keys matching this warehouse
        pattern = f"{warehouse_id}:*"
        keys = list(r.scan_iter(pattern))
        
        inventory = []
        for key in keys:
            item_id = key.split(':')[1] if ':' in key else key
            qty = r.get(key)
            inventory.append({
                "product_id": item_id,
                "name": _get_product_name(item_id),
                "category": _get_product_category(item_id),
                "stock": int(qty) if qty else 0,
                "min_stock": 10,  # Default threshold
                "price": _get_product_price(item_id),
            })
        
        return {"inventory": inventory, "warehouse_id": warehouse_id, "count": len(inventory)}
    except Exception as e:
        logging.error(f"Error fetching inventory: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to fetch inventory: {str(e)}")


@app.get("/products/{warehouse_id}")
def get_warehouse_products(warehouse_id: str):
    """Get products with stock > 0 for a warehouse - used by buyer app"""
    if not r:
        raise HTTPException(status_code=503, detail="Redis unavailable")
    
    try:
        pattern = f"{warehouse_id}:*"
        keys = list(r.scan_iter(pattern))
        
        products = []
        for key in keys:
            item_id = key.split(':')[1] if ':' in key else key
            qty = r.get(key)
            stock = int(qty) if qty else 0
            
            if stock > 0:  # Only include products with stock
                products.append({
                    "id": item_id,
                    "name": _get_product_name(item_id),
                    "category": _get_product_category(item_id),
                    "categoryId": _get_category_id(item_id),
                    "stock": stock,
                    "price": _get_product_price(item_id),
                    "unit": "1 unit",
                    "imageEmoji": _get_product_emoji(item_id),
                })
        
        return {"products": products, "warehouse_id": warehouse_id, "count": len(products)}
    except Exception as e:
        logging.error(f"Error fetching products: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to fetch products: {str(e)}")


@app.put("/inventory/{warehouse_id}/{product_id}")
def update_stock(warehouse_id: str, product_id: str, data: StockUpdateRequest):
    """Update stock for a specific product in a warehouse - persists to Redis"""
    if not r:
        raise HTTPException(status_code=503, detail="Redis unavailable")
    
    try:
        key = f"{warehouse_id}:{product_id}"
        new_stock = data.stock
        
        # Get old stock for logging
        old_stock = r.get(key)
        old_stock = int(old_stock) if old_stock else 0
        
        # Update Redis
        r.set(key, new_stock)
        
        logging.info(f"Stock updated: {key} | {old_stock} -> {new_stock}")
        
        return {
            "success": True,
            "warehouse_id": warehouse_id,
            "product_id": product_id,
            "old_stock": old_stock,
            "new_stock": new_stock,
            "message": f"Stock updated from {old_stock} to {new_stock}"
        }
    except Exception as e:
        logging.error(f"Error updating stock: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to update stock: {str(e)}")


# HELPER FUNCTIONS

# Product catalog — SINGLE SOURCE OF TRUTH
# Must match Flutter data_repository.dart product IDs
PRODUCT_CATALOG = {
    # Fruits
    "apple": {"name": "Red Apple", "category": "Fruits", "price": 120},
    "banana": {"name": "Bananas", "category": "Fruits", "price": 60},
    "orange": {"name": "Nagpur Orange", "category": "Fruits", "price": 89},
    "grapes": {"name": "Green Grapes", "category": "Fruits", "price": 79},
    "tomato": {"name": "Tomatoes", "category": "Vegetables", "price": 40},
    "potato": {"name": "Potatoes", "category": "Vegetables", "price": 30},
    "onion": {"name": "Onions", "category": "Vegetables", "price": 35},
    # Dairy
    "milk": {"name": "Fresh Milk", "category": "Dairy", "price": 65},
    "eggs": {"name": "Farm Eggs (12)", "category": "Dairy", "price": 85},
    "curd": {"name": "Fresh Curd", "category": "Dairy", "price": 35},
    "paneer": {"name": "Paneer", "category": "Dairy", "price": 85},
    "cheese": {"name": "Cheese Slice", "category": "Dairy", "price": 150},
    "butter": {"name": "Butter", "category": "Dairy", "price": 55},
    # Snacks
    "chips": {"name": "Potato Chips", "category": "Snacks", "price": 35},
    "cookie": {"name": "Choco Cookies", "category": "Snacks", "price": 45},
    "namkeen": {"name": "Mixed Namkeen", "category": "Snacks", "price": 35},
    "chocolate": {"name": "Chocolate Bar", "category": "Snacks", "price": 80},
    # Beverages
    "coke": {"name": "Cola Can", "category": "Beverages", "price": 40},
    "water": {"name": "Mineral Water", "category": "Beverages", "price": 20},
    "juice": {"name": "Mango Juice", "category": "Beverages", "price": 95},
    "coffee": {"name": "Coffee Beans", "category": "Beverages", "price": 450},
    "tea": {"name": "Green Tea", "category": "Beverages", "price": 120},
    # Bakery
    "bread": {"name": "Wheat Bread", "category": "Bakery", "price": 45},
    "cake": {"name": "Chocolate Cake", "category": "Bakery", "price": 299},
    # Grocery
    "rice": {"name": "Basmati Rice", "category": "Grocery", "price": 180},
    "oil": {"name": "Cooking Oil", "category": "Grocery", "price": 180},
    "atta": {"name": "Wheat Flour", "category": "Grocery", "price": 249},
    "pasta": {"name": "Pasta", "category": "Grocery", "price": 75},
    # Frozen / Meat
    "icecream": {"name": "Ice Cream", "category": "Frozen", "price": 149},
    "chicken": {"name": "Chicken Breast", "category": "Meat", "price": 320},
    "fish": {"name": "Fresh Fish", "category": "Meat", "price": 280},
}

def _get_product_name(product_id: str) -> str:
    return PRODUCT_CATALOG.get(product_id, {}).get('name', product_id.replace('_', ' ').title())

def _get_product_category(product_id: str) -> str:
    return PRODUCT_CATALOG.get(product_id, {}).get('category', 'General')

def _get_product_price(product_id: str) -> int:
    return PRODUCT_CATALOG.get(product_id, {}).get('price', 100)

def _get_category_id(product_id: str) -> str:
    """Map category name to category ID (matches Flutter categories)"""
    category = _get_product_category(product_id).lower()
    category_map = {
        'fruits': 'fruits',
        'vegetables': 'fruits',  # Group veggies with fruits
        'dairy': 'dairy',
        'snacks': 'snacks',
        'beverages': 'beverages',
        'bakery': 'bakery',
        'grocery': 'grocery',
        'grains': 'grocery',
        'frozen': 'frozen',
        'meat': 'frozen',
        'general': 'grocery',
    }
    return category_map.get(category, 'grocery')

def _get_product_emoji(product_id: str) -> str:
    """Get emoji for product display"""
    emoji_map = {
        'apple': '🍎', 'banana': '🍌', 'orange': '🍊', 'grapes': '🍇',
        'tomato': '🍅', 'potato': '🥔', 'onion': '🧅',
        'milk': '🥛', 'eggs': '🥚', 'curd': '🥄', 'paneer': '🧀',
        'cheese': '🧀', 'butter': '🧈',
        'chips': '🍟', 'cookie': '🍪', 'namkeen': '🥜', 'chocolate': '🍫',
        'coke': '🥤', 'water': '💧', 'juice': '🧃', 'coffee': '☕', 'tea': '🍵',
        'bread': '🍞', 'cake': '🎂',
        'rice': '🍚', 'oil': '🫒', 'atta': '🌾', 'pasta': '🍝',
        'icecream': '🍦', 'chicken': '🍗', 'fish': '🐟',
    }
    return emoji_map.get(product_id, '📦')


# =====================================================
# PROMETHEUS SCRAPING ENDPOINTS
# =====================================================
# LOW_STOCK_THRESHOLD is configured via env var above

@app.get("/metrics/inventory")
def scrape_inventory_metrics():
    """Scrape all Redis inventory keys and update Prometheus gauges.
    Called periodically by Prometheus via scrape config.
    Also detects low-stock situations for alerting.
    """
    if not r:
        return {"status": "redis_unavailable"}

    warehouses_seen = {}
    low_stock_items = []

    for key in r.scan_iter("wh_*"):
        parts = key.split(':')
        if len(parts) != 2:
            continue
        wh_id, item_id = parts[0], parts[1]
        qty = r.get(key)
        stock = int(qty) if qty else 0

        # Update Prometheus gauge
        inventory_stock_level.labels(warehouse_id=wh_id, item_id=item_id).set(stock)

        # Count products per warehouse
        warehouses_seen.setdefault(wh_id, 0)
        warehouses_seen[wh_id] += 1

        # Detect low stock
        if 0 < stock < LOW_STOCK_THRESHOLD:
            low_stock_events.labels(warehouse_id=wh_id, item_id=item_id).inc()
            low_stock_items.append({
                "warehouse_id": wh_id,
                "item_id": item_id,
                "stock": stock,
                "name": _get_product_name(item_id),
            })

    # Update products-per-warehouse gauge
    for wh_id, count in warehouses_seen.items():
        warehouse_product_count.labels(warehouse_id=wh_id).set(count)

    return {
        "status": "ok",
        "warehouses_scanned": len(warehouses_seen),
        "total_keys": sum(warehouses_seen.values()),
        "low_stock_items": low_stock_items,
    }


@app.get("/metrics/demand")
def get_demand_insights():
    """Analyze inventory patterns across warehouses for demand prediction.
    
    Returns items that are:
    1. Running low at specific warehouses (restock needed)
    2. Unevenly distributed (some warehouses have too much, others too little)
    3. Completely out of stock somewhere but available elsewhere
    
    This powers the warehouse manager dashboard's "Demand Forecast" panel.
    """
    if not r:
        return {"status": "redis_unavailable"}

    # Scan all inventory
    # item_id -> { wh_id: stock, ... }
    item_distribution = {}
    for key in r.scan_iter("wh_*"):
        parts = key.split(':')
        if len(parts) != 2:
            continue
        wh_id, item_id = parts[0], parts[1]
        stock = int(r.get(key) or 0)

        item_distribution.setdefault(item_id, {})
        item_distribution[item_id][wh_id] = stock

    # Analyze patterns
    restock_needed = []   # Low/out of stock at a warehouse
    imbalanced = []       # Uneven distribution
    hot_items = []        # Low everywhere (high demand signal)

    for item_id, warehouses in item_distribution.items():
        stocks = list(warehouses.values())
        avg_stock = sum(stocks) / len(stocks) if stocks else 0
        max_stock = max(stocks) if stocks else 0
        min_stock = min(stocks) if stocks else 0
        total_stock = sum(stocks)

        # Restock: any warehouse with stock < threshold
        for wh_id, stock in warehouses.items():
            if stock < LOW_STOCK_THRESHOLD:
                restock_needed.append({
                    "item_id": item_id,
                    "item_name": _get_product_name(item_id),
                    "warehouse_id": wh_id,
                    "current_stock": stock,
                    "avg_stock_elsewhere": round(avg_stock, 1),
                    "suggested_restock": max(0, int(avg_stock * 1.5) - stock),
                    "priority": "critical" if stock == 0 else "warning",
                })

        # Imbalanced: huge variance across warehouses (ratio > 5x)
        if min_stock > 0 and max_stock / min_stock > 5 and len(stocks) > 1:
            imbalanced.append({
                "item_id": item_id,
                "item_name": _get_product_name(item_id),
                "min_stock": min_stock,
                "max_stock": max_stock,
                "distribution": warehouses,
                "recommendation": "Redistribute stock from over-stocked to under-stocked warehouses",
            })

        # Hot items: low total across all warehouses
        if total_stock < LOW_STOCK_THRESHOLD * len(stocks) and len(stocks) > 1:
            hot_items.append({
                "item_id": item_id,
                "item_name": _get_product_name(item_id),
                "total_stock": total_stock,
                "warehouse_count": len(stocks),
                "avg_per_warehouse": round(avg_stock, 1),
                "recommendation": "Increase supply — demand exceeding stock across all warehouses",
            })

    # Sort by priority
    restock_needed.sort(key=lambda x: x["current_stock"])
    hot_items.sort(key=lambda x: x["total_stock"])

    return {
        "restock_needed": restock_needed[:20],
        "imbalanced_items": imbalanced[:10],
        "high_demand_items": hot_items[:10],
        "summary": {
            "total_items_tracked": len(item_distribution),
            "items_needing_restock": len(restock_needed),
            "imbalanced_items": len(imbalanced),
            "high_demand_items": len(hot_items),
        },
    }