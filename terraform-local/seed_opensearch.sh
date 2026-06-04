#!/bin/bash
# Seed Local OpenSearch with Warehouse Data
# Run this AFTER the EC2 instance is fully initialized

set -e

echo "Seeding OpenSearch with Warehouse Data"

# Create warehouses index with geo_point mapping
echo "Creating warehouses index..."
curl -X PUT "http://localhost:9200/warehouses" -H 'Content-Type: application/json' -d '{
  "mappings": {
    "properties": {
      "name": {"type": "text"},
      "address": {"type": "text"},
      "location": {"type": "geo_point"},
      "inventory": {
        "type": "nested",
        "properties": {
          "product_id": {"type": "keyword"},
          "product_name": {"type": "text"},
          "quantity": {"type": "integer"},
          "price": {"type": "float"}
        }
      }
    }
  }
}'

echo ""
echo "Adding sample warehouses..."

# Warehouse 1: New York
curl -X POST "http://localhost:9200/warehouses/_doc/1" -H 'Content-Type: application/json' -d '{
  "name": "NYC Warehouse",
  "address": "123 Broadway, New York, NY 10001",
  "location": {"lat": 40.7128, "lon": -74.0060},
  "inventory": [
    {"product_id": "LAPTOP-001", "product_name": "MacBook Pro 14", "quantity": 50, "price": 1999.99},
    {"product_id": "PHONE-001", "product_name": "iPhone 15 Pro", "quantity": 100, "price": 999.99},
    {"product_id": "TABLET-001", "product_name": "iPad Pro 12.9", "quantity": 75, "price": 1099.99}
  ]
}'

# Warehouse 2: Los Angeles
curl -X POST "http://localhost:9200/warehouses/_doc/2" -H 'Content-Type: application/json' -d '{
  "name": "LA Distribution Center",
  "address": "456 Sunset Blvd, Los Angeles, CA 90028",
  "location": {"lat": 34.0522, "lon": -118.2437},
  "inventory": [
    {"product_id": "LAPTOP-001", "product_name": "MacBook Pro 14", "quantity": 30, "price": 1999.99},
    {"product_id": "WATCH-001", "product_name": "Apple Watch Ultra", "quantity": 200, "price": 799.99},
    {"product_id": "HEADPHONE-001", "product_name": "AirPods Max", "quantity": 150, "price": 549.99}
  ]
}'

# Warehouse 3: Chicago
curl -X POST "http://localhost:9200/warehouses/_doc/3" -H 'Content-Type: application/json' -d '{
  "name": "Chicago Hub",
  "address": "789 Michigan Ave, Chicago, IL 60611",
  "location": {"lat": 41.8781, "lon": -87.6298},
  "inventory": [
    {"product_id": "PHONE-001", "product_name": "iPhone 15 Pro", "quantity": 80, "price": 999.99},
    {"product_id": "TABLET-001", "product_name": "iPad Pro 12.9", "quantity": 60, "price": 1099.99},
    {"product_id": "ACCESSORY-001", "product_name": "MagSafe Charger", "quantity": 500, "price": 39.99}
  ]
}'

# Warehouse 4: Seattle
curl -X POST "http://localhost:9200/warehouses/_doc/4" -H 'Content-Type: application/json' -d '{
  "name": "Seattle Fulfillment Center",
  "address": "321 Pike St, Seattle, WA 98101",
  "location": {"lat": 47.6062, "lon": -122.3321},
  "inventory": [
    {"product_id": "LAPTOP-002", "product_name": "Dell XPS 15", "quantity": 40, "price": 1499.99},
    {"product_id": "MONITOR-001", "product_name": "LG UltraWide 34", "quantity": 25, "price": 699.99},
    {"product_id": "KEYBOARD-001", "product_name": "Logitech MX Keys", "quantity": 100, "price": 99.99}
  ]
}'

# Warehouse 5: Miami
curl -X POST "http://localhost:9200/warehouses/_doc/5" -H 'Content-Type: application/json' -d '{
  "name": "Miami Warehouse",
  "address": "555 Ocean Drive, Miami, FL 33139",
  "location": {"lat": 25.7617, "lon": -80.1918},
  "inventory": [
    {"product_id": "PHONE-002", "product_name": "Samsung Galaxy S24", "quantity": 90, "price": 899.99},
    {"product_id": "TABLET-002", "product_name": "Samsung Galaxy Tab S9", "quantity": 45, "price": 849.99},
    {"product_id": "EARBUDS-001", "product_name": "Galaxy Buds Pro", "quantity": 200, "price": 199.99}
  ]
}'

echo ""
echo "=========================================="
echo "✅ OpenSearch seeded successfully!"
echo "========================================"
echo ""
echo "Verify with: curl http://localhost:9200/warehouses/_search?pretty"
