"""
ADD WAREHOUSE TOOL - Rapid Delivery Service (AWS Version)
Use this script to add warehouses to AWS OpenSearch and ElastiCache.

USAGE:
  python add_warehouse.py               - Add all 10 test warehouses
  python add_warehouse.py list          - List all warehouses
  python add_warehouse.py add <id> <lat> <lon>  - Add single warehouse

REQUIRES: Run from EC2 instance (ElastiCache is VPC-only)
  ssh -i k3s-key ubuntu@<API_SERVER_IP>
  python3 add_warehouse.py
"""

import sys
import json
import requests
import os

# AWS CONFIGURATION - Auto-detect from environment
# These are set by the K8s pods, or use defaults for EC2 shell
OPENSEARCH_URL = os.environ.get('OPENSEARCH_URL', 'https://search-rapid-search-bu2kcyndpnpudetiv3s6raq5oa.us-east-1.es.amazonaws.com')
REDIS_HOST = os.environ.get('REDIS_HOST', 'rapid-redis.pqqgpc.0001.use1.cache.amazonaws.com')
REDIS_PORT = int(os.environ.get('REDIS_PORT', 6379))
AWS_REGION = os.environ.get('AWS_REGION', 'us-east-1')

# AWS SigV4 Authentication for OpenSearch

def get_aws_auth():
    """Get AWS SigV4 auth for OpenSearch requests"""
    try:
        from requests_aws4auth import AWS4Auth
        import boto3
        
        credentials = boto3.Session().get_credentials()
        if credentials:
            return AWS4Auth(
                credentials.access_key,
                credentials.secret_key,
                AWS_REGION,
                'es',
                session_token=credentials.token
            )
    except ImportError:
        print("  Install: pip install boto3 requests-aws4auth")
    except Exception as e:
        print(f"  AWS auth error: {e}")
    return None

AWS_AUTH = get_aws_auth()

# 10 TEST WAREHOUSES - Major Indian Cities
TEST_WAREHOUSES = [
    # Jaipur Area (for your location)
    {"id": "wh_jaipur_central", "lat": 26.9124, "lon": 75.7873, "city": "Jaipur Central"},
    {"id": "wh_jaipur_amer", "lat": 26.9855, "lon": 75.8513, "city": "Jaipur Amer"},
    {"id": "wh_jaipur_malviya", "lat": 26.8505, "lon": 75.8043, "city": "Jaipur Malviya Nagar"},
    {"id": "wh_lnmiit", "lat": 26.9020, "lon": 75.8680, "city": "LNMIIT Jaipur"},
    
    # Delhi NCR
    {"id": "wh_delhi_central", "lat": 28.6139, "lon": 77.2090, "city": "Delhi Central"},
    {"id": "wh_delhi_gurgaon", "lat": 28.4595, "lon": 77.0266, "city": "Gurgaon"},
    {"id": "wh_delhi_noida", "lat": 28.5355, "lon": 77.3910, "city": "Noida"},
    
    # Mumbai
    {"id": "wh_mumbai_central", "lat": 19.0760, "lon": 72.8777, "city": "Mumbai Central"},
    {"id": "wh_mumbai_thane", "lat": 19.2183, "lon": 72.9781, "city": "Thane"},
    
    # Bangalore
    {"id": "wh_bangalore_central", "lat": 12.9716, "lon": 77.5946, "city": "Bangalore Central"},
    
    # Chennai
    {"id": "wh_chennai_central", "lat": 13.0827, "lon": 80.2707, "city": "Chennai Central"},
]

# Default inventory for new warehouses
DEFAULT_INVENTORY = {
    "apple": 100,
    "milk": 50,
    "bread": 50,
    "coke": 100,
    "chips": 75,
    "eggs": 60,
    "banana": 80,
    "cookie": 40,
    "rice": 200,
    "water": 150,
}


def add_warehouse_to_opensearch(warehouse_id: str, lat: float, lon: float, city: str = ""):
    """Add a warehouse to OpenSearch"""
    warehouse_doc = {
        "id": warehouse_id,
        "location": {"lat": lat, "lon": lon},
        "city": city
    }
    
    try:
        res = requests.put(
            f"{OPENSEARCH_URL}/warehouses/_doc/{warehouse_id}",
            json=warehouse_doc,
            headers={"Content-Type": "application/json"},
            auth=AWS_AUTH,
            timeout=30
        )
        if res.status_code not in [200, 201]:
            print(f"      Response: {res.status_code} - {res.text[:100]}")
        return res.status_code in [200, 201]
    except requests.exceptions.Timeout:
        print(f"      ⏱️ Timeout - retrying...")
        try:
            res = requests.put(
                f"{OPENSEARCH_URL}/warehouses/_doc/{warehouse_id}",
                json=warehouse_doc,
                headers={"Content-Type": "application/json"},
                auth=AWS_AUTH,
                timeout=60
            )
            return res.status_code in [200, 201]
        except Exception as e:
            print(f"❌ OpenSearch Error: {e}")
            return False
    except Exception as e:
        print(f"❌ OpenSearch Error: {e}")
        return False


def add_warehouse_to_redis(warehouse_id: str):
    """Add inventory to Redis (skip gracefully if VPC-only)"""
    try:
        import redis
        r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True, socket_timeout=2, socket_connect_timeout=2)
        r.ping()  # Quick test
        
        for item_id, quantity in DEFAULT_INVENTORY.items():
            key = f"{warehouse_id}:{item_id}"
            r.set(key, quantity)
        return True
    except Exception as e:
        # Expected to fail from laptop (ElastiCache is VPC-only)
        return False


def add_single_warehouse(warehouse_id: str, lat: float, lon: float, city: str = ""):
    """Add a single warehouse"""
    print(f"\n📦 Adding Warehouse: {warehouse_id} ({city})")
    print(f"   Location: ({lat}, {lon})")
    
    os_success = add_warehouse_to_opensearch(warehouse_id, lat, lon, city)
    redis_success = add_warehouse_to_redis(warehouse_id)
    
    if os_success:
        print(f"   ✅ OpenSearch: Added")
    else:
        print(f"   ❌ OpenSearch: Failed")
    
    if redis_success:
        print(f"   ✅ Redis: {len(DEFAULT_INVENTORY)} items added")
    else:
        print(f"   ⚠️  Redis: Skipped (VPC-only)")
    
    return os_success


def add_all_warehouses():
    """Add all 10 test warehouses"""
    print("\n" + "=" * 60)
    print("🏪 Adding 10 Test Warehouses to AWS")
    print("=" * 60)
    
    # First, ensure the index exists with geo_point mapping
    mapping = {
        "mappings": {
            "properties": {
                "id": {"type": "keyword"},
                "city": {"type": "text"},
                "location": {"type": "geo_point"}
            }
        }
    }
    
    try:
        # Delete and recreate index
        requests.delete(f"{OPENSEARCH_URL}/warehouses", auth=AWS_AUTH, timeout=10)
        requests.put(f"{OPENSEARCH_URL}/warehouses", json=mapping, 
                    headers={"Content-Type": "application/json"}, auth=AWS_AUTH, timeout=10)
        print("✅ OpenSearch index created")
    except Exception as e:
        print(f"⚠️  Index setup: {e}")
    
    success_count = 0
    for wh in TEST_WAREHOUSES:
        if add_single_warehouse(wh["id"], wh["lat"], wh["lon"], wh.get("city", "")):
            success_count += 1
    
    # Refresh index
    try:
        requests.post(f"{OPENSEARCH_URL}/warehouses/_refresh", auth=AWS_AUTH, timeout=10)
    except:
        pass
    
    print("\n" + "=" * 60)
    print(f"✅ Added {success_count}/{len(TEST_WAREHOUSES)} warehouses to OpenSearch")
    print("=" * 60)
    
    print("\n📍 Test Coordinates (copy to Flutter app):")
    print("-" * 40)
    for wh in TEST_WAREHOUSES[:3]:
        print(f"   {wh['city']}: {wh['lat']}, {wh['lon']}")


def list_warehouses():
    """List all warehouses in OpenSearch"""
    print("\n📍 Warehouses in OpenSearch:")
    print("-" * 60)
    
    try:
        res = requests.get(
            f"{OPENSEARCH_URL}/warehouses/_search",
            json={"size": 100},
            headers={"Content-Type": "application/json"},
            auth=AWS_AUTH,
            timeout=10
        )
        
        if res.status_code != 200:
            print(f"   Error: {res.status_code} - {res.text[:100]}")
            return
        
        hits = res.json().get('hits', {}).get('hits', [])
        
        if not hits:
            print("   No warehouses found. Run: python add_warehouse.py")
            return
        
        for hit in hits:
            wh = hit['_source']
            loc = wh.get('location', {})
            city = wh.get('city', '')
            print(f"   • {wh['id']:25} ({loc.get('lat'):8.4f}, {loc.get('lon'):8.4f}) - {city}")
        
        print(f"\nTotal: {len(hits)} warehouses")
        
    except Exception as e:
        print(f"❌ Error: {e}")


def delete_warehouse(warehouse_id: str):
    """Remove a warehouse"""
    try:
        requests.delete(f"{OPENSEARCH_URL}/warehouses/_doc/{warehouse_id}", auth=AWS_AUTH, timeout=10)
        print(f"🗑️  Deleted warehouse: {warehouse_id}")
    except Exception as e:
        print(f"❌ Error: {e}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        # Default: Add all warehouses
        add_all_warehouses()
        list_warehouses()
    elif sys.argv[1] == "list":
        list_warehouses()
    elif sys.argv[1] == "delete" and len(sys.argv) >= 3:
        delete_warehouse(sys.argv[2])
    elif sys.argv[1] == "add" and len(sys.argv) >= 5:
        add_single_warehouse(sys.argv[2], float(sys.argv[3]), float(sys.argv[4]), 
                            sys.argv[5] if len(sys.argv) > 5 else "")
    else:
        print(__doc__)
        print("\nCommands:")
        print("  python add_warehouse.py              - Add all 10 test warehouses")
        print("  python add_warehouse.py list         - List all warehouses")
        print("  python add_warehouse.py add <id> <lat> <lon> [city]")
        print("  python add_warehouse.py delete <id>  - Delete a warehouse")


