# 🧪 TESTING GUIDE - Rapid Delivery Service

## Quick Reference

| Environment | Availability API | Order API |
|-------------|-----------------|-----------|
| **Local** | http://localhost:8000 | http://localhost:8001 |
| **AWS** | http://[EC2_IP]:30001 | http://[EC2_IP]:30002 |

---

## 1️⃣ LOCAL TESTING (Docker)

### Start Services
```powershell
cd d:\Rapid_Delivery_Service
docker-compose up -d
```

### Seed Database
```powershell
python seed.py
```

### Verify Services Running
```powershell
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Expected output:
```
NAMES                  STATUS          PORTS
availability-service   Up X minutes    0.0.0.0:8000->8000/tcp
order-service          Up X minutes    0.0.0.0:8001->8001/tcp
fulfillment-worker     Up X minutes
postgres               Up X minutes    0.0.0.0:5432->5432/tcp
redis                  Up X minutes    0.0.0.0:6379->6379/tcp
opensearch             Up X minutes    0.0.0.0:9200->9200/tcp
rapid_prometheus       Up X minutes    0.0.0.0:9090->9090/tcp
rapid_grafana          Up X minutes    0.0.0.0:3000->3000/tcp
```

### API Tests

**Test 1: Availability Health Check**
```powershell
curl http://localhost:8000/
# Expected: {"status":"healthy","service":"availability-service"}
```

**Test 2: Stock Check (Near LNMIIT - should find stock)**
```powershell
curl "http://localhost:8000/availability?item_id=apple&lat=26.94&lon=75.84"
# Expected: {"available":true,"warehouse_id":"wh_rajapark","distance_km":4.5,"quantity":50}
```

**Test 3: Stock Check (Far location - no delivery)**
```powershell
curl "http://localhost:8000/availability?item_id=apple&lat=26.45&lon=74.64"
# Expected: {"available":false,"message":"No stock or no delivery in your area"}
```

**Test 4: Order Health Check**
```powershell
curl http://localhost:8001/
# Expected: {"status":"healthy","service":"order-service"}
```

**Test 5: Place Order**
```powershell
curl -Method POST -Uri "http://localhost:8001/orders" `
  -ContentType "application/json" `
  -Body '{"customer_id":"test_user","items":[{"item_id":"apple","warehouse_id":"wh_rajapark","quantity":2}]}'
# Expected: {"status":"success","order_id":"<uuid>","message":"Order placed successfully"}
```

**Test 6: Get Order History**
```powershell
curl http://localhost:8001/orders/test_user
# Expected: Array of orders with order_id, customer_id, status, items, created_at
```

**Test 7: Multi-Warehouse Order Placement**
```powershell
curl -Method POST -Uri "http://localhost:8001/orders" `
  -ContentType "application/json" `
  -Body '{"customer_id":"multi_user","items":[{"item_id":"apple","warehouse_id":"wh_rajapark","quantity":2},{"item_id":"paneer","warehouse_id":"wh_lnmiit","quantity":1}]}'
# Expected: Success message with "is_multi_warehouse": true and multiple "sub_orders".
```

**Test 8: Demand Prediction API**
```powershell
curl http://localhost:8000/metrics/demand
# Expected: JSON with restock_needed, high_demand_items, and imbalanced_items.
```

### Flutter App Test
```powershell
cd rapid_delivery_app
flutter run -d chrome
```

**Test Flow:**
1. ✅ Location picker opens → Select "📍 LNMIIT Campus"
2. ✅ Products show stock levels (green/red badges)
3. ✅ Add items to cart
4. ✅ Place order → Should succeed
5. ✅ Check Orders tab → See real order history

### Stop Local Services
```powershell
docker-compose down
```

---

## 2️⃣ AWS TESTING

### Prerequisites
- Terraform applied successfully
- EC2 instances initialized (wait 5-7 min after terraform apply)

### Get AWS Endpoints
```powershell
cd terraform-files
terraform output
```

### SSH into EC2 Instances
```powershell
# API Server
ssh -i k3s-key ubuntu@<API_SERVER_IP>

# Worker Server
ssh -i k3s-key ubuntu@<WORKER_SERVER_IP>
```

### Check Pods on EC2
```bash
# On API Server - should see 2 pods
kubectl get pods -A

# Expected:
# NAMESPACE   NAME                              READY   STATUS    
# default     availability-app-xxxxx            1/1     Running   
# default     order-app-xxxxx                   1/1     Running   

# On Worker Server - should see 1 pod
kubectl get pods -A

# Expected:
# NAMESPACE   NAME                              READY   STATUS    
# default     fulfillment-worker-xxxxx          1/1     Running   
```

### API Tests (from your laptop)
```powershell
$API_IP = "YOUR_API_SERVER_IP"

# Availability health
curl http://${API_IP}:30001/

# Stock check
curl "http://${API_IP}:30001/availability?item_id=apple&lat=26.94&lon=75.84"

# Order health
curl http://${API_IP}:30002/

# Place order
curl -Method POST -Uri "http://${API_IP}:30002/orders" `
  -ContentType "application/json" `
  -Body '{"customer_id":"mobile_user","items":[{"item_id":"apple","warehouse_id":"wh_rajapark","quantity":2}]}'

# Get orders
curl http://${API_IP}:30002/orders/mobile_user
```

### Flutter App Test with AWS
1. Edit `lib/aws_config.dart`:
   ```dart
   static const String apiServerIp = "YOUR_API_SERVER_IP";
   ```

2. Edit `lib/api_service.dart`:
   ```dart
   static const bool useAwsBackend = true;
   ```

3. Run app:
   ```powershell
   cd rapid_delivery_app
   flutter run -d chrome
   ```

---

## 3️⃣ DATABASE VERIFICATION

### Local PostgreSQL
```powershell
docker exec postgres psql -U postgres -c "SELECT * FROM orders LIMIT 5;"
docker exec postgres psql -U postgres -c "SELECT * FROM inventory LIMIT 10;"
```

### AWS RDS (from laptop)
```powershell
# Install psql if needed, then:
psql -h <RDS_ENDPOINT> -U postgres -d postgres -c "SELECT * FROM orders LIMIT 5;"
# Password: password123
```

### Check Warehouses in OpenSearch
```powershell
# Local
curl http://localhost:9200/warehouses/_search?pretty

# AWS (from EC2)
curl https://<OPENSEARCH_ENDPOINT>/warehouses/_search?pretty
```

---

## 4️⃣ TROUBLESHOOTING

### Issue: "Connection refused" locally
```powershell
# Check if containers are running
docker ps

# Restart if needed
docker-compose down
docker-compose up -d
```

### Issue: "No delivery available" everywhere
```powershell
# Re-seed the database
python seed.py

# Verify warehouses exist
curl http://localhost:9200/warehouses/_search?pretty
```

### Issue: AWS pods not running
```bash
# SSH into EC2
ssh -i k3s-key ubuntu@<IP>

# Check pod status
kubectl get pods -A

# View pod logs
kubectl logs -l app=availability --tail=50
kubectl logs -l app=order --tail=50

# Describe pod for errors
kubectl describe pod <pod-name>
```

### Issue: Order placement fails
```powershell
# Check order service logs
docker logs order-service --tail=30

# Verify database schema
docker exec postgres psql -U postgres -c "\d orders"
```

---

## 5️⃣ EXPECTED TEST RESULTS

| Test | Local Expected | AWS Expected |
|------|---------------|--------------|
| Availability health | ✅ healthy | ✅ healthy |
| Stock near LNMIIT | ✅ available, ~50 qty | ✅ available, ~50 qty |
| Stock far away | ❌ not available | ❌ not available |
| Order health | ✅ healthy | ✅ healthy |
| Place single order | ✅ success + order_id | ✅ success + order_id |
| Multi-warehouse order | ✅ splits into sub-orders | ✅ splits into sub-orders |
| Order history | ✅ returns orders | ✅ returns orders |
| Flutter cart | ✅ works | ✅ works |
| Flutter checkout | ✅ works | ✅ works |
| Grafana Dashboard | ✅ Loads with data | ✅ Loads with data |

---

## 6️⃣ PERFORMANCE BENCHMARKS just reference purposes

### Local Development PC Results (Feb 2026)

**Test Environment:**
- PC: Intel i7 (8 cores), 16GB RAM, SSD
- Docker Desktop: 6 containers (postgres, redis, opensearch, availability, order, fulfillment)
- All services running locally on same machine

#### Sequential Request Throughput

| Endpoint | Requests/sec | Avg Latency | Notes |
|----------|-------------|-------------|-------|
| `GET /availability` | **106 req/s** | ~10ms | Redis cache hit |
| `GET /products/{warehouse}` | **100 req/s** | ~10ms | Redis lookup |
| `POST /orders` | **17 req/s** | ~57ms | PostgreSQL + OpenSearch write |
| `GET /orders/{customer}` | **83 req/s** | ~12ms | OpenSearch query |

#### Concurrent User Capacity (Local)

| Concurrent Users | Read Operations | Write Operations |
|-----------------|-----------------|------------------|
| 10 | ✅ 100% success | ✅ 100% success |
| 25 | ✅ ~6.7 req/s total | ✅ Stable |
| 50 | ✅ Handles well | ⚠️ Some queuing |

**Local Capacity Summary:**
- **Read-heavy workload:** ~100 concurrent users
- **Write-heavy workload:** ~15-20 concurrent users placing orders
- **Mixed typical usage:** ~30-50 concurrent active users

---

### AWS EC2 Performance Estimates

> ⚠️ Estimates based on typical FastAPI + PostgreSQL benchmarks. Actual results depend on network, DB configuration, and workload.

#### Single Instance Performance

| Instance Type | vCPU | RAM | Read Ops/sec | Write Ops/sec | Est. Concurrent Users | Cost/hr |
|--------------|------|-----|--------------|---------------|----------------------|---------|
| **t3.micro** | 2 | 1GB | ~80-120 | ~10-15 | 15-25 | $0.0104 |
| **t3.small** | 2 | 2GB | ~150-250 | ~20-35 | 30-50 | $0.0208 |
| **t3.medium** | 2 | 4GB | ~250-400 | ~35-60 | 50-80 | $0.0416 |
| **t3.large** | 2 | 8GB | ~400-600 | ~60-100 | 80-150 | $0.0832 |

#### Horizontal Scaling (Load Balanced)

**t3.micro Instances:**
| Instances | Read Ops/sec | Write Ops/sec | Est. Concurrent Users | Monthly Cost |
|-----------|-------------|---------------|----------------------|--------------|
| 1 | ~100 | ~12 | 20 | ~$7.50 |
| 2 | ~180 | ~22 | 35 | ~$15 |
| 3 | ~250 | ~30 | 50 | ~$22.50 |
| 4 | ~300 | ~35 | 60 | ~$30 |
| 5 | ~350 | ~40 | 70 | ~$37.50 |

**t3.small Instances:**
| Instances | Read Ops/sec | Write Ops/sec | Est. Concurrent Users | Monthly Cost |
|-----------|-------------|---------------|----------------------|--------------|
| 1 | ~200 | ~25 | 40 | ~$15 |
| 2 | ~380 | ~45 | 75 | ~$30 |
| 3 | ~540 | ~65 | 110 | ~$45 |
| 4 | ~680 | ~80 | 140 | ~$60 |
| 5 | ~800 | ~95 | 170 | ~$75 |

**t3.large Instances:**
| Instances | Read Ops/sec | Write Ops/sec | Est. Concurrent Users | Monthly Cost |
|-----------|-------------|---------------|----------------------|--------------|
| 1 | ~500 | ~80 | 120 | ~$60 |
| 2 | ~950 | ~150 | 230 | ~$120 |
| 3 | ~1350 | ~210 | 340 | ~$180 |
| 4 | ~1700 | ~260 | 440 | ~$240 |
| 5 | ~2000 | ~300 | 520 | ~$300 |

#### Scaling Bottlenecks

| Component | Bottleneck Point | Solution |
|-----------|-----------------|----------|
| **PostgreSQL** | ~500 writes/sec | RDS Multi-AZ, Read Replicas |
| **OpenSearch** | ~1000 writes/sec | Managed OpenSearch cluster |
| **Redis** | ~50,000 ops/sec | ElastiCache cluster |
| **Network** | ~1 Gbps | Enhanced networking |

#### Recommended Configurations

| Use Case | Instances | Type | Database | Est. Cost/month |
|----------|-----------|------|----------|-----------------|
| **Development** | 1 | t3.micro | Local Docker | ~$7 |
| **Startup MVP** | 2 | t3.small | RDS db.t3.micro | ~$50 |
| **Small Business** | 3 | t3.small | RDS db.t3.small | ~$100 |
| **Growing** | 3 | t3.medium | RDS db.t3.medium | ~$200 |
| **Production** | 5+ | t3.large | RDS + ElastiCache | ~$500+ |

---

## 7️⃣ FLUTTER APP TESTING

### UI Components to Verify

| Component | Expected Behavior |
|-----------|------------------|
| **Banner Carousel** | Auto-scrolling promo banners at top |
| **Category Chips** | Horizontal scroll, highlight on select |
| **Product Cards** | Discount badge, best seller tag, ADD button |
| **Cart Bottom Bar** | Sticky bar showing items & total |
| **Delivery Address Bar** | Shows location + "10 min" badge |
| **Search** | Filters products in real-time |

### Test Flow - Buyer
1. Open app → Role Selection screen appears
2. Click "Continue as Demo User"
3. Location sheet opens → Select "LNMIIT Campus"
4. Home screen loads with:
   - Delivery address bar at top
   - Promo banners
   - Category chips (All, Fruits, Dairy, etc.)
   - Product grid with stock levels
5. Filter by category → Grid updates
6. Search "apple" → Shows matching products
7. Add items → Cart bar appears at bottom
8. Tap "View Cart" → Cart screen opens
9. Place order → Success dialog
10. Check Order History → Order visible

### Test Flow - Manager
1. Click "I'm a Warehouse Manager"
2. Enter warehouse details
3. View dashboard with stats
4. Open inventory screen
5. Search/filter products
6. Update stock levels
7. Subscribe to notifications

### Categories to Test
- `all` - Shows all products
- `fruits` - Apple, Banana, Orange, Grapes
- `dairy` - Milk, Eggs, Curd, Paneer
- `snacks` - Chips, Cookies, Namkeen
- `beverages` - Cola, Water, Juice
- `bakery` - Bread, Cake
- `grocery` - Rice, Oil, Flour
- `frozen` - Ice Cream

---

## 8️⃣ MONITORING & OBSERVABILITY TESTING

### Prometheus Metrics
```powershell
# Open in browser:
http://localhost:9090

# Query to test:
inventory_stock_level
```
*Expected: List of current stock levels for each item in each warehouse, updating every 30 seconds.*

### Grafana Dashboards
```powershell
# Open in browser:
http://localhost:3000

# Login credentials:
Username: admin
Password: rapid123 (or value of GRAFANA_PASSWORD)
```
*Expected Flow:*
1. Navigate to "Dashboards" > "Rapid Delivery Service".
2. Verify all 17 panels load without errors.
3. Check "Business Overview" for total orders.
4. Check "Warehouse Inventory" heatmap.

