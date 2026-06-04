"""
=============================================================
LOCAL SEEDER - Rapid Delivery Service
=============================================================
Seeds LOCAL Docker containers (PostgreSQL, Redis, OpenSearch)
for development and testing WITHOUT AWS.

PREREQUISITES:
  docker-compose -f docker-compose-local.yaml up -d

USAGE:
  python local/seed_local.py

This creates:
  - PostgreSQL: items, orders tables + sample data
  - Redis: VARIED inventory for 10 warehouses (Jaipur, Delhi, Mumbai, etc.)
  - OpenSearch: Warehouse geo-locations for nearest search
=============================================================
"""

import psycopg2
from opensearchpy import OpenSearch
import redis
import time

# =====================================================
# LOCAL CONFIGURATION - Docker Compose defaults
# =====================================================
POSTGRES_CONFIG = {
    "host": "localhost",
    "port": 5432,
    "database": "rapid_delivery",
    "user": "postgres",
    "password": "postgres"
}

REDIS_CONFIG = {
    "host": "localhost",
    "port": 6379
}

OPENSEARCH_CONFIG = {
    "host": "localhost",
    "port": 9200
}

# =====================================================
# WAREHOUSES — geo-locations for OpenSearch
# =====================================================
WAREHOUSES = [
    # Jaipur Region (4 warehouses — primary test region)
    ("wh_jaipur_central", 26.9124, 75.7873, "Jaipur Central"),
    ("wh_jaipur_malviya", 26.8505, 75.8043, "Jaipur Malviya Nagar"),
    ("wh_lnmiit",         26.9020, 75.8680, "LNMIIT Jaipur"),
    ("wh_jaipur_amer",    26.9855, 75.8513, "Jaipur Amer"),
    # Delhi NCR
    ("wh_delhi_central",  28.6139, 77.2090, "Delhi Central"),
    ("wh_delhi_gurgaon",  28.4595, 77.0266, "Gurgaon"),
    ("wh_delhi_noida",    28.5355, 77.3910, "Noida"),
    # Other metros
    ("wh_mumbai_central",    19.0760, 72.8777, "Mumbai Central"),
    ("wh_bangalore_central", 12.9716, 77.5946, "Bangalore Central"),
    ("wh_chennai_central",   13.0827, 80.2707, "Chennai Central"),
    ("wh_hyderabad_central", 17.3850, 78.4867, "Hyderabad Central"),
]

# =====================================================
# VARIED INVENTORY per warehouse
# Different warehouses stock DIFFERENT items at DIFFERENT levels.
# This tests multi-warehouse aggregation properly.
# =====================================================
INVENTORY = {
    # --- JAIPUR REGION ---
    # Jaipur Central: Big warehouse, has most items, high stock
    "wh_jaipur_central": {
        "apple": 150, "banana": 200, "orange": 80,  "grapes": 60,
        "milk": 300,  "eggs": 200,   "curd": 100,
        "chips": 250, "cookie": 100, "namkeen": 80,
        "coke": 300,  "water": 500,  "juice": 120,
        "bread": 200, "cake": 30,
        "rice": 100,  "oil": 80,     "atta": 60,
        "icecream": 50,
        # NOTE: No paneer, no cheese, no coffee — forces multi-warehouse
    },
    # Malviya Nagar: Small store, dairy-focused
    "wh_jaipur_malviya": {
        "milk": 400,  "eggs": 150,  "curd": 200,  "paneer": 80,
        "cheese": 60, "butter": 100,
        "bread": 100, "cake": 50,
        "apple": 50,  "banana": 80,
        "water": 200,
        # This warehouse is the ONLY one in Jaipur with paneer + cheese
    },
    # LNMIIT: Campus store, snacks + beverages heavy
    "wh_lnmiit": {
        "chips": 300, "cookie": 200, "namkeen": 150, "chocolate": 100,
        "coke": 400,  "water": 600,  "juice": 200,   "coffee": 80, "tea": 60,
        "bread": 80,  "cake": 20,
        "banana": 100, "apple": 40,
        "milk": 100,   "eggs": 50,
        "icecream": 100,
        # ONLY warehouse with coffee + tea + chocolate in Jaipur
    },
    # Amer: Bulk warehouse, grocery + staples
    "wh_jaipur_amer": {
        "rice": 500,  "oil": 300,   "atta": 400,  "pasta": 200,
        "potato": 300, "tomato": 200, "onion": 250,
        "milk": 200,  "eggs": 100,
        "apple": 80,  "banana": 120, "orange": 150, "grapes": 100,
        "chicken": 80, "fish": 50,
        # ONLY warehouse with potato, tomato, onion, chicken, fish in Jaipur
    },

    # --- DELHI NCR ---
    "wh_delhi_central": {
        "apple": 200, "banana": 150, "orange": 100, "grapes": 80,
        "milk": 300,  "eggs": 200,   "paneer": 100, "curd": 80,
        "chips": 200, "cookie": 100, "namkeen": 120,
        "coke": 250,  "water": 400,  "juice": 150,
        "bread": 200, "rice": 150,   "oil": 100,    "atta": 80,
        "icecream": 60, "coffee": 40,
    },
    "wh_delhi_gurgaon": {
        "apple": 100, "milk": 200,   "bread": 150,  "eggs": 100,
        "chips": 150, "coke": 200,   "water": 300,
        "rice": 80,   "oil": 60,     "atta": 40,
        "chicken": 60, "fish": 40,
    },
    "wh_delhi_noida": {
        "banana": 120, "orange": 80,  "grapes": 60,
        "milk": 150,   "paneer": 50,  "cheese": 40,  "butter": 60,
        "cookie": 80,  "chocolate": 60,
        "juice": 100,  "coffee": 30,  "tea": 40,
        "cake": 40,    "icecream": 80,
    },

    # --- OTHER METROS ---
    "wh_mumbai_central": {
        "apple": 150, "banana": 200, "orange": 120,
        "milk": 250,  "eggs": 150,   "paneer": 80,
        "chips": 200, "coke": 300,   "water": 400,
        "bread": 180, "rice": 120,   "oil": 80,
        "fish": 100,  "chicken": 80,
        "icecream": 60, "cake": 30,
    },
    "wh_bangalore_central": {
        "apple": 100, "banana": 150, "grapes": 80,
        "milk": 200,  "eggs": 120,   "curd": 60,
        "chips": 150, "coffee": 100, "tea": 80,
        "bread": 120, "rice": 100,   "oil": 60,    "atta": 50,
        "chicken": 50,
    },
    "wh_chennai_central": {
        "banana": 200, "orange": 100,
        "milk": 250,   "curd": 150,  "eggs": 100,
        "rice": 200,   "oil": 120,   "atta": 80,
        "chips": 100,  "coke": 200,  "water": 350,
        "fish": 120,   "chicken": 60,
    },
    "wh_hyderabad_central": {
        "apple": 80,  "banana": 120, "orange": 60,  "grapes": 40,
        "milk": 180,  "eggs": 100,   "paneer": 60,
        "chips": 120, "namkeen": 100, "chocolate": 50,
        "coke": 180,  "juice": 80,   "coffee": 50,
        "bread": 100, "rice": 130,   "oil": 70,
        "chicken": 70, "icecream": 40,
    },
}

# Items for PostgreSQL items table
ITEMS = [
    ("apple", "Red Apple", 120),
    ("banana", "Bananas", 60),
    ("orange", "Nagpur Orange", 89),
    ("grapes", "Green Grapes", 79),
    ("milk", "Fresh Milk", 65),
    ("eggs", "Farm Eggs (12)", 85),
    ("curd", "Fresh Curd", 35),
    ("paneer", "Paneer", 85),
    ("cheese", "Cheese Slice", 150),
    ("butter", "Butter", 55),
    ("chips", "Potato Chips", 35),
    ("cookie", "Choco Cookies", 45),
    ("namkeen", "Mixed Namkeen", 35),
    ("chocolate", "Chocolate Bar", 80),
    ("coke", "Cola Can", 40),
    ("water", "Mineral Water", 20),
    ("juice", "Mango Juice", 95),
    ("coffee", "Coffee Beans", 450),
    ("tea", "Green Tea", 120),
    ("bread", "Wheat Bread", 45),
    ("cake", "Chocolate Cake", 299),
    ("rice", "Basmati Rice", 180),
    ("oil", "Cooking Oil", 180),
    ("atta", "Wheat Flour", 249),
    ("pasta", "Pasta", 75),
    ("icecream", "Ice Cream", 149),
    ("chicken", "Chicken Breast", 320),
    ("fish", "Fresh Fish", 280),
    ("tomato", "Tomatoes", 40),
    ("potato", "Potatoes", 30),
    ("onion", "Onions", 35),
]


# =====================================================
# SEEDING FUNCTIONS
# =====================================================

def seed_postgres():
    """Create tables and seed items in PostgreSQL"""
    print("\n📦 PostgreSQL (localhost:5432)")
    print("-" * 50)
    
    try:
        conn = psycopg2.connect(**POSTGRES_CONFIG)
        cur = conn.cursor()
        
        # Create items table
        cur.execute("""
            CREATE TABLE IF NOT EXISTS items (
                id VARCHAR(50) PRIMARY KEY,
                name VARCHAR(200) NOT NULL,
                price DECIMAL(10,2) NOT NULL
            )
        """)
        
        # Drop and recreate orders table with correct schema (includes warehouse_id for seller filtering)
        cur.execute("DROP TABLE IF EXISTS orders CASCADE")
        cur.execute("""
            CREATE TABLE orders (
                order_id VARCHAR(50) PRIMARY KEY,
                customer_id VARCHAR(100) NOT NULL,
                warehouse_id VARCHAR(100),
                status VARCHAR(50) DEFAULT 'PENDING',
                items JSONB NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        cur.execute("CREATE INDEX IF NOT EXISTS idx_orders_customer ON orders(customer_id)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_orders_warehouse ON orders(warehouse_id)")
        print("   ✅ Created orders table with warehouse_id column")
        
        # Insert items
        for item_id, name, price in ITEMS:
            cur.execute("""
                INSERT INTO items (id, name, price) 
                VALUES (%s, %s, %s)
                ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, price = EXCLUDED.price
            """, (item_id, name, price))
        
        conn.commit()
        cur.close()
        conn.close()
        print(f"   ✅ {len(ITEMS)} items seeded")
        
    except Exception as e:
        print(f"   ❌ Error: {e}")
        print("   Make sure PostgreSQL is running: docker-compose up -d postgres")


def seed_redis():
    """Seed VARIED inventory in Redis"""
    print("\n📦 Redis (localhost:6379)")
    print("-" * 50)
    
    try:
        r = redis.Redis(**REDIS_CONFIG, decode_responses=True)
        r.ping()
        
        # Clear existing inventory keys first
        for key in r.scan_iter("wh_*"):
            r.delete(key)
        print("   🗑️  Cleared old inventory data")
        
        total_entries = 0
        for warehouse_id, items in INVENTORY.items():
            for item_id, quantity in items.items():
                key = f"{warehouse_id}:{item_id}"
                r.set(key, quantity)
            total_entries += len(items)
            print(f"   ✅ {warehouse_id}: {len(items)} products (varied stock)")
        
        print(f"   ✅ Total: {total_entries} inventory entries across {len(INVENTORY)} warehouses")
        
        # Print sample to verify
        print("\n   📊 Sample stock verification:")
        test_items = ["paneer", "coffee", "chicken"]
        for item in test_items:
            locations = []
            for wh_id in INVENTORY:
                key = f"{wh_id}:{item}"
                qty = r.get(key)
                if qty and int(qty) > 0:
                    locations.append(f"{wh_id}({qty})")
            if locations:
                print(f"      {item}: {', '.join(locations)}")
            else:
                print(f"      {item}: NOT STOCKED")
        
    except Exception as e:
        print(f"   ❌ Error: {e}")
        print("   Make sure Redis is running: docker-compose up -d redis")


def seed_opensearch():
    """Seed warehouse locations in OpenSearch"""
    print("\n📦 OpenSearch (localhost:9200)")
    print("-" * 50)
    
    try:
        client = OpenSearch(
            hosts=[{"host": OPENSEARCH_CONFIG["host"], "port": OPENSEARCH_CONFIG["port"]}],
            use_ssl=False,
            verify_certs=False
        )
        
        # Delete index if exists
        try:
            client.indices.delete(index="warehouses")
            print("   🗑️  Deleted old warehouses index")
        except:
            pass
        
        # Create index with geo_point mapping
        client.indices.create(
            index="warehouses",
            body={
                "mappings": {
                    "properties": {
                        "id": {"type": "keyword"},
                        "city": {"type": "text"},
                        "location": {"type": "geo_point"}
                    }
                }
            }
        )
        
        # Add warehouses
        for wh_id, lat, lon, city in WAREHOUSES:
            client.index(
                index="warehouses",
                id=wh_id,
                body={
                    "id": wh_id,
                    "location": {"lat": lat, "lon": lon},
                    "city": city
                },
                refresh=True
            )
            print(f"   ✅ {wh_id}: ({lat}, {lon}) - {city}")
        
        print(f"   ✅ {len(WAREHOUSES)} warehouses indexed")
        
    except Exception as e:
        print(f"   ❌ Error: {e}")
        print("   Make sure OpenSearch is running: docker-compose up -d opensearch")


def verify_data():
    """Quick verification that data is correct"""
    print("\n🔍 VERIFICATION")
    print("-" * 50)
    
    # Test Redis
    try:
        r = redis.Redis(**REDIS_CONFIG, decode_responses=True)
        total_keys = len(list(r.scan_iter("wh_*")))
        print(f"   ✅ Redis: {total_keys} inventory keys")
    except Exception as e:
        print(f"   ❌ Redis: {e}")
    
    # Test OpenSearch geo-query (simulate what the app does)
    try:
        client = OpenSearch(
            hosts=[{"host": OPENSEARCH_CONFIG["host"], "port": OPENSEARCH_CONFIG["port"]}],
            use_ssl=False,
            verify_certs=False
        )
        
        # Simulate: User at LNMIIT (26.94, 75.84) - find nearest warehouses
        test_lat, test_lon = 26.94, 75.84
        query = {
            "size": 5,
            "sort": [
                {"_geo_distance": {"location": {"lat": test_lat, "lon": test_lon}, "order": "asc", "unit": "km"}}
            ]
        }
        res = client.search(index="warehouses", body=query)
        hits = res['hits']['hits']
        
        print(f"\n   📍 Nearest warehouses to LNMIIT test location ({test_lat}, {test_lon}):")
        for hit in hits[:3]:
            wh_id = hit['_source']['id']
            city = hit['_source']['city']
            dist = hit['sort'][0]
            product_count = len(INVENTORY.get(wh_id, {}))
            print(f"      {city} ({wh_id}): {dist:.1f} km — {product_count} products")
        
    except Exception as e:
        print(f"   ❌ OpenSearch: {e}")


if __name__ == "__main__":
    print("\n" + "=" * 60)
    print("🌱 LOCAL SEEDER - Rapid Delivery Service")
    print("=" * 60)
    print("Target: Docker containers (localhost)")
    
    seed_postgres()
    seed_redis()
    seed_opensearch()
    verify_data()
    
    print("\n" + "=" * 60)
    print("✅ Local seeding complete!")
    print("=" * 60)
    
    print("\n📍 Test locations for Flutter app:")
    print("   LNMIIT Campus:   26.9400, 75.8400  (3 warehouses within 15km)")
    print("   Raja Park:       26.9050, 75.8200  (4 warehouses within 15km)")
    print("   Ajmer:           26.4500, 74.6400  (too far, no delivery)")
    
    print("\n🧪 Multi-warehouse test scenarios:")
    print("   • Paneer → ONLY at Malviya Nagar (forces W-2)")
    print("   • Coffee → ONLY at LNMIIT (forces W-3)")
    print("   • Chicken → ONLY at Amer (forces W-4)")
    print("   • Apple → At Central + Malviya + LNMIIT + Amer (flexible)")
    
    print("\n🚀 Next: flutter run -d chrome --web-browser-flag \"--disable-web-security\"")
