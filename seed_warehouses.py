#!/usr/bin/env python3
"""
Seed Warehouses to OpenSearch and Redis
Run this script from the EC2 instance (Redis is VPC-only)

Usage: python3 seed_warehouses.py
"""

import json
import redis
import requests
import boto3
from requests_aws4auth import AWS4Auth

# ===== CONFIGURATION =====
REDIS_HOST = "rapid-redis.pqqgpc.0001.use1.cache.amazonaws.com"
REDIS_PORT = 6379
OPENSEARCH_URL = "https://search-rapid-search-bu2kcyndpnpudetiv3s6raq5oa.us-east-1.es.amazonaws.com"
AWS_REGION = "us-east-1"

# ===== WAREHOUSE DATA =====
WAREHOUSES = [
    # Jaipur (multiple)
    {"id": "wh_jaipur_central", "lat": 26.9124, "lon": 75.7873, "city": "Jaipur Central", "address": "MI Road, Jaipur"},
    {"id": "wh_jaipur_amer", "lat": 26.9855, "lon": 75.8513, "city": "Jaipur Amer", "address": "Amer Road, Jaipur"},
    {"id": "wh_jaipur_malviya", "lat": 26.8505, "lon": 75.8043, "city": "Jaipur Malviya Nagar", "address": "Malviya Nagar, Jaipur"},
    {"id": "wh_jaipur_mansarovar", "lat": 26.8725, "lon": 75.7623, "city": "Jaipur Mansarovar", "address": "Mansarovar, Jaipur"},
    {"id": "wh_lnmiit", "lat": 26.9020, "lon": 75.8680, "city": "LNMIIT Jaipur", "address": "LNMIIT Campus, Jaipur"},
    
    # Delhi NCR
    {"id": "wh_delhi_central", "lat": 28.6139, "lon": 77.2090, "city": "Delhi Central", "address": "Connaught Place, Delhi"},
    {"id": "wh_delhi_gurgaon", "lat": 28.4595, "lon": 77.0266, "city": "Gurgaon", "address": "Cyber Hub, Gurgaon"},
    {"id": "wh_delhi_noida", "lat": 28.5355, "lon": 77.3910, "city": "Noida", "address": "Sector 18, Noida"},
    
    # Mumbai
    {"id": "wh_mumbai_central", "lat": 19.0760, "lon": 72.8777, "city": "Mumbai Central", "address": "Nariman Point, Mumbai"},
    {"id": "wh_mumbai_thane", "lat": 19.2183, "lon": 72.9781, "city": "Thane", "address": "Thane West, Mumbai"},
    {"id": "wh_mumbai_bandra", "lat": 19.0596, "lon": 72.8295, "city": "Mumbai Bandra", "address": "Bandra West, Mumbai"},
    
    # Bangalore
    {"id": "wh_bangalore_central", "lat": 12.9716, "lon": 77.5946, "city": "Bangalore Central", "address": "MG Road, Bangalore"},
    {"id": "wh_bangalore_whitefield", "lat": 12.9698, "lon": 77.7499, "city": "Bangalore Whitefield", "address": "Whitefield, Bangalore"},
    {"id": "wh_bangalore_electronic_city", "lat": 12.8456, "lon": 77.6603, "city": "Electronic City", "address": "Electronic City, Bangalore"},
    
    # Chennai
    {"id": "wh_chennai_central", "lat": 13.0827, "lon": 80.2707, "city": "Chennai Central", "address": "T Nagar, Chennai"},
    {"id": "wh_chennai_omr", "lat": 12.9165, "lon": 80.2270, "city": "Chennai OMR", "address": "OMR Road, Chennai"},
    
    # Hyderabad
    {"id": "wh_hyderabad_central", "lat": 17.3850, "lon": 78.4867, "city": "Hyderabad Central", "address": "Banjara Hills, Hyderabad"},
    {"id": "wh_hyderabad_hitech", "lat": 17.4435, "lon": 78.3772, "city": "Hyderabad Hi-Tech City", "address": "Hi-Tech City, Hyderabad"},
    
    # Pune
    {"id": "wh_pune_central", "lat": 18.5204, "lon": 73.8567, "city": "Pune Central", "address": "FC Road, Pune"},
    {"id": "wh_pune_hinjewadi", "lat": 18.5912, "lon": 73.7380, "city": "Pune Hinjewadi", "address": "Hinjewadi, Pune"},
]

# Products with initial stock
PRODUCTS = {
    "apple": {"name": "Fresh Apple", "price": 120, "unit": "kg", "stock": 500},
    "milk": {"name": "Amul Milk 1L", "price": 60, "unit": "bottle", "stock": 1000},
    "bread": {"name": "Brown Bread", "price": 45, "unit": "pack", "stock": 300},
    "coke": {"name": "Coca Cola 500ml", "price": 40, "unit": "bottle", "stock": 800},
    "chips": {"name": "Lays Classic", "price": 20, "unit": "pack", "stock": 600},
    "eggs": {"name": "Farm Fresh Eggs (12)", "price": 90, "unit": "dozen", "stock": 400},
    "banana": {"name": "Fresh Banana", "price": 50, "unit": "dozen", "stock": 700},
    "cookie": {"name": "Oreo Cookies", "price": 35, "unit": "pack", "stock": 500},
    "water": {"name": "Mineral Water 1L", "price": 25, "unit": "bottle", "stock": 2000},
    "rice": {"name": "Basmati Rice 1kg", "price": 150, "unit": "kg", "stock": 300},
    "dal": {"name": "Toor Dal 1kg", "price": 180, "unit": "kg", "stock": 250},
    "sugar": {"name": "Sugar 1kg", "price": 55, "unit": "kg", "stock": 400},
    "tea": {"name": "Tata Tea 500g", "price": 250, "unit": "pack", "stock": 350},
    "coffee": {"name": "Nescafe 200g", "price": 450, "unit": "jar", "stock": 200},
    "oil": {"name": "Sunflower Oil 1L", "price": 160, "unit": "bottle", "stock": 400},
    "banana": {"name": "Banana", "price": 50, "unit": "dozen", "stock": 100},
}


def get_aws_auth():
    """Get AWS SigV4 auth for OpenSearch"""
    credentials = boto3.Session().get_credentials()
    return AWS4Auth(
        credentials.access_key,
        credentials.secret_key,
        AWS_REGION,
        'es',
        session_token=credentials.token
    )


def seed_opensearch(auth):
    """Seed warehouse locations to OpenSearch"""
    print("\n🔍 Seeding OpenSearch...")
    
    # Delete existing index
    try:
        requests.delete(f"{OPENSEARCH_URL}/warehouses", auth=auth, timeout=10)
        print("   Deleted existing 'warehouses' index")
    except Exception as e:
        print(f"   No existing index to delete: {e}")
    
    # Create index with geo_point mapping
    mapping = {
        "mappings": {
            "properties": {
                "id": {"type": "keyword"},
                "location": {"type": "geo_point"},
                "city": {"type": "text"},
                "address": {"type": "text"}
            }
        }
    }
    
    response = requests.put(f"{OPENSEARCH_URL}/warehouses", json=mapping, auth=auth, timeout=10)
    if response.status_code == 200:
        print("   ✅ Created 'warehouses' index with geo_point mapping")
    else:
        print(f"   ❌ Failed to create index: {response.text}")
        return False
    
    # Seed each warehouse
    success_count = 0
    for wh in WAREHOUSES:
        doc = {
            "id": wh["id"],
            "location": {"lat": wh["lat"], "lon": wh["lon"]},
            "city": wh["city"],
            "address": wh.get("address", "")
        }
        
        response = requests.put(
            f"{OPENSEARCH_URL}/warehouses/_doc/{wh['id']}",
            json=doc,
            auth=auth,
            timeout=10
        )
        
        if response.status_code in [200, 201]:
            success_count += 1
            print(f"   ✅ {wh['id']} ({wh['city']})")
        else:
            print(f"   ❌ {wh['id']}: {response.text}")
    
    print(f"\n   📊 OpenSearch: {success_count}/{len(WAREHOUSES)} warehouses seeded")
    return True


def seed_redis():
    """Seed inventory to Redis"""
    print("\n📦 Seeding Redis Inventory...")
    
    try:
        r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)
        r.ping()
        print(f"   ✅ Connected to Redis at {REDIS_HOST}")
    except Exception as e:
        print(f"   ❌ Failed to connect to Redis: {e}")
        return False
    
    # Clear existing inventory
    keys = r.keys("wh_*:*")
    if keys:
        r.delete(*keys)
        print(f"   Cleared {len(keys)} existing inventory keys")
    
    # Seed inventory for each warehouse
    total_keys = 0
    for wh in WAREHOUSES:
        for product_id, product_info in PRODUCTS.items():
            key = f"{wh['id']}:{product_id}"
            r.set(key, product_info["stock"])
            total_keys += 1
    
    print(f"   📊 Redis: {total_keys} inventory keys created")
    print(f"      ({len(WAREHOUSES)} warehouses × {len(PRODUCTS)} products)")
    
    # Store product metadata
    for product_id, product_info in PRODUCTS.items():
        r.hset(f"product:{product_id}", mapping={
            "name": product_info["name"],
            "price": product_info["price"],
            "unit": product_info["unit"]
        })
    print(f"   📊 Redis: {len(PRODUCTS)} product metadata entries")
    
    return True


def verify_data(auth):
    """Verify seeded data"""
    print("\n🔍 Verifying Data...")
    
    # Verify OpenSearch
    response = requests.get(
        f"{OPENSEARCH_URL}/warehouses/_count",
        auth=auth,
        timeout=10
    )
    if response.status_code == 200:
        count = response.json().get("count", 0)
        print(f"   OpenSearch: {count} warehouse documents")
    
    # Verify Redis
    try:
        r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)
        inventory_keys = len(r.keys("wh_*:*"))
        product_keys = len(r.keys("product:*"))
        print(f"   Redis: {inventory_keys} inventory keys, {product_keys} product metadata")
    except Exception as e:
        print(f"   ❌ Redis verification failed: {e}")
    
    # Test geo query
    print("\n🌍 Testing Geo Query (Jaipur - 26.85, 75.80)...")
    query = {
        "size": 3,
        "query": {
            "geo_distance": {
                "distance": "20km",
                "location": {"lat": 26.85, "lon": 75.80}
            }
        },
        "sort": [
            {
                "_geo_distance": {
                    "location": {"lat": 26.85, "lon": 75.80},
                    "order": "asc",
                    "unit": "km"
                }
            }
        ]
    }
    
    response = requests.get(
        f"{OPENSEARCH_URL}/warehouses/_search",
        json=query,
        auth=auth,
        timeout=10
    )
    
    if response.status_code == 200:
        hits = response.json().get("hits", {}).get("hits", [])
        print(f"   Found {len(hits)} nearby warehouses:")
        for hit in hits:
            wh = hit["_source"]
            dist = hit["sort"][0] if "sort" in hit else "?"
            print(f"      - {wh['city']} ({dist:.1f} km)")
    else:
        print(f"   ❌ Geo query failed: {response.text}")


def main():
    print("=" * 60)
    print("🚀 Rapid Delivery Service - Warehouse Seeder")
    print("=" * 60)
    
    # Get AWS auth
    print("\n🔐 Getting AWS credentials...")
    try:
        auth = get_aws_auth()
        print("   ✅ AWS SigV4 auth ready")
    except Exception as e:
        print(f"   ❌ Failed to get AWS auth: {e}")
        return
    
    # Seed data
    opensearch_ok = seed_opensearch(auth)
    redis_ok = seed_redis()
    
    if opensearch_ok and redis_ok:
        verify_data(auth)
        print("\n" + "=" * 60)
        print("✅ SEEDING COMPLETE!")
        print(f"   • {len(WAREHOUSES)} warehouses in OpenSearch")
        print(f"   • {len(WAREHOUSES) * len(PRODUCTS)} inventory entries in Redis")
        print(f"   • {len(PRODUCTS)} products configured")
        print("=" * 60)
    else:
        print("\n❌ Seeding failed - check errors above")


if __name__ == "__main__":
    main()
