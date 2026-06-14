# 🚀 Rapid Delivery Service - Deployment Guide

## 📋 Quick Start

### Local Development (Docker)
```powershell
cd local
docker-compose -f docker-compose-local.yaml up -d --build
python seed_local.py
cd ../rapid_delivery_app
flutter run -d chrome --web-browser-flag "--disable-web-security"
```

### AWS Production
```powershell
cd terraform-files
terraform init && terraform apply --auto-approve
./generate_flutter_config.ps1
python ../seed_aws.py
```

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      FLUTTER APP (Web/Mobile)                    │
└──────────────────────────────┬──────────────────────────────────┘
                               │ HTTP
                               ▼
┌──────────────────────────────────────────────────────────────────┐
│                        NGINX (Port 80)                           │
│         /availability/* → :8000    /order/* → :8001              │
└──────────────────────────────────────────────────────────────────┘
        │                        │                       │
        ▼                        ▼                       ▼
┌───────────────┐       ┌───────────────┐       ┌───────────────┐
│ Availability  │       │    Order      │       │  Fulfillment  │
│   Service     │       │   Service     │       │    Worker     │
│   :8000       │       │   :8001       │       │  (background) │
└───────┬───────┘       └───────┬───────┘       └───────┬───────┘
        │                       │                       │
        ▼                       ▼                       ▼
┌───────────────┐       ┌───────────────┐       ┌───────────────┐
│  OpenSearch   │       │   PostgreSQL  │       │     Redis     │
│ (Geo-location)│       │   (Orders)    │       │  (Inventory)  │
└───────────────┘       └───────────────┘       └───────────────┘
```

---

## 🔧 Service Details

| Service | Port | Purpose | Database |
|---------|------|---------|----------|
| **Availability** | 8000 | Stock check, warehouse search, inventory CRUD | Redis + OpenSearch |
| **Order** | 8001 | Place orders, order history | PostgreSQL |
| **Fulfillment** | - | Background order processing, stock updates | PostgreSQL + Redis |

### How They Work Together

1. **Buyer searches products** → Availability service queries OpenSearch for nearest warehouse, Redis for stock
2. **Buyer places order** → Order service saves to PostgreSQL with status `PENDING`
3. **Worker processes order** → Fulfillment worker polls DB, updates status to `COMPLETED`, decrements Redis stock
4. **Manager updates inventory** → Availability service updates Redis directly

---

## 📦 Local Setup (Docker)

### Prerequisites
- Docker Desktop running
- Python 3.9+
- Flutter SDK

### Step 1: Start Services
```powershell
cd d:\Rapid_Delivery_Service\local
docker-compose -f docker-compose-local.yaml up -d --build
```

### Step 2: Seed Data
```powershell
python seed_local.py
```

### Step 3: Run Flutter
```powershell
cd rapid_delivery_app
flutter run -d chrome --web-browser-flag "--disable-web-security"
```

### Verify Services
```powershell
curl http://localhost:8000/                    # Availability health
curl http://localhost:8001/                    # Order health
curl http://localhost:8000/warehouses          # List warehouses
curl "http://localhost:8000/availability?item_id=apple&lat=26.9&lon=75.8"
```

---

## ☁️ AWS Deployment

### Prerequisites
- AWS CLI configured (`aws configure`)
- Terraform installed
- SSH key: `ssh-keygen -t rsa -b 4096 -f terraform-files/k3s-key`

### Step 1: Deploy Infrastructure
```powershell
cd terraform-files
terraform init
terraform apply --auto-approve
```

**Creates (FREE TIER eligible):**
- 2 × EC2 t3.micro (API + Worker)
- RDS PostgreSQL t3.micro
- ElastiCache Redis t2.micro
- OpenSearch t3.small
- SQS Queue

### Step 2: Update Flutter Config
```powershell
./generate_flutter_config.ps1
```

### Step 3: Seed AWS
```powershell
python ../seed_aws.py
```

### Step 4: Verify
```powershell
$API_IP = terraform output -raw api_server_ip
curl http://${API_IP}:30001/
curl http://${API_IP}:30002/
```

---

## 🔄 Update Workflow

### Update Service Code
```powershell
# 1. Edit code
code availability-service/main.py

# 2. Rebuild local
cd local
docker-compose -f docker-compose-local.yaml build availability-service
docker-compose -f docker-compose-local.yaml up -d availability-service

# --- OR for AWS ---

# 2. Build and push to ECR
docker build -t availability:v2 ../availability-service
aws ecr get-login-password | docker login --username AWS --password-stdin <ECR_URL>
docker tag availability:v2 <ECR_URL>/availability:latest
docker push <ECR_URL>/availability:latest

# 3. Restart on EC2
ssh -i k3s-key ubuntu@<API_IP> "kubectl rollout restart deployment/availability-app"
```

### GitHub Actions CI/CD
Push to `main` branch triggers automatic build and deploy.

**Required Secrets:**
- `AWS_ACCOUNT_ID`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
- `EC2_API_HOST`, `EC2_SSH_KEY`

**Required Variables:**
- `AWS_REGION` (e.g., `us-east-1`)
- `DEPLOY_ENABLED` = `true`

---

## 🐛 Troubleshooting

### Container Issues
```powershell
docker logs rapid_availability    # Check logs
docker logs rapid_order
docker logs rapid_fulfillment
docker-compose -f docker-compose-local.yaml restart <service>
```

### Database Reset
```powershell
docker-compose -f docker-compose-local.yaml down -v  # Delete volumes
docker-compose -f docker-compose-local.yaml up -d
python seed_local.py
```

### Flutter CORS Issues
Always run with:
```powershell
flutter run -d chrome --web-browser-flag "--disable-web-security"
```

### EC2 Pods Not Running
```bash
ssh -i k3s-key ubuntu@<IP>
kubectl get pods
kubectl logs -l app=availability
sudo tail -f /var/log/cloud-init-output.log
```

---

## 🎓 GitHub Student Developer Pack Deployment

To host this project online and reduce your costs to zero using the **GitHub Student Developer Pack**, you can leverage the cloud credits and free tools it provides.

### 🎁 What the Pack Offers for This Project

1. **DigitalOcean**: $200 in platform credit for 1 year. This is the **best option** for hosting your Dockerized backend stack (Postgres, Redis, OpenSearch, and API services) on a single Virtual Machine (Droplet) without worrying about strict free-tier resource limits.
2. **Microsoft Azure**: $100 in credit plus free access to select services.
3. **Heroku**: $13/month in credits for 12 months.
4. **Namecheap / Name.com**: Free 1-year domain registration (e.g., `.me`, `.tech`, `.live`).
5. **Frontend Hosting**: Tools like **GitHub Pages**, **Vercel**, or **Netlify** offer generous free tiers for hosting your built Flutter Web app.

### 🚀 Step-by-Step Guide (using DigitalOcean)

Since the project relies heavily on Docker Compose, deploying onto a DigitalOcean Virtual Machine using the $200 credit is the most straightforward path.

#### Step 1: Claim Your Pack & Free Domain
1. Go to [education.github.com/pack](https://education.github.com/pack) and verify your student status.
2. Claim your **DigitalOcean $200 credit**.
3. Claim a free domain via **Namecheap** or **Name.com** from the pack dashboard.

#### Step 2: Set Up the DigitalOcean Server (Backend)
1. Log into DigitalOcean and create a new **Droplet** (Ubuntu 22.04 or 24.04).
2. Choose a Droplet size with at least **4GB RAM** (around $24/month). *At base rate, this is approximately 8.3 months on a $200 credit (theoretical maximum); actual duration can be lower with bandwidth, backups, and snapshots, so monitor billing regularly.*
3. SSH into your new Droplet:
   `ssh root@<YOUR_DROPLET_IP>`
4. Install Docker and Docker Compose on the Droplet.
5. Clone your repository:
   `git clone https://github.com/YOUR_USERNAME/Rapid_Delivery_Service.git`
6. Navigate to the project directory and start the stack:
   ```bash
   cd Rapid_Delivery_Service/local
   docker-compose -f docker-compose-local.yaml up -d --build
   ```
7. Seed the database on the server:
   `python3 seed_local.py`
8. Check that your APIs are running by making a test request to `http://<YOUR_DROPLET_IP>:8000` and `8001`.

#### Step 3: Host the Frontend (Flutter Web app)
1. On your local machine, navigate to the `rapid_delivery_app` directory.
2. Build with your domain-backed API URLs (no manual Dart edits needed):
   ```bash
   flutter build web \
     --dart-define=USE_AWS_BACKEND=true \
     --dart-define=AVAILABILITY_BASE_URL=https://api.yourdomain.com \
     --dart-define=ORDER_BASE_URL=https://api.yourdomain.com/order
   ```
   - `AVAILABILITY_BASE_URL` should be the API root origin (no `/availability` suffix).
   - `ORDER_BASE_URL` must include `/order` (the app appends endpoints like `/orders` to this base).
   - App routing behavior: availability calls become `https://api.yourdomain.com/availability/...`; order calls become `https://api.yourdomain.com/order/...`.
3. If you prefer default local endpoints, you can still build with:
   `flutter build web`
4. The compiled frontend will be in the `build/web` folder.
5. Deploy this folder for **free** using GitHub Pages, Vercel, or Netlify. For example, using the Netlify CLI:
   `npx netlify deploy --dir=build/web --prod`

#### Step 4: Link Your Free Domain & Secure with SSL
1. Go to your domain provider (Namecheap/Name.com).
2. Create DNS records:
   - `A` record: `api` → `<YOUR_DROPLET_IP>`
   - `A` record or `CNAME` for root domain (`@`) → your frontend host target
3. On your backend server, install Nginx + Certbot:
   ```bash
   sudo apt update
   sudo apt install -y nginx certbot python3-certbot-nginx
   ```
4. Configure Nginx reverse proxy for `api.yourdomain.com` and route:
   - `/availability/*` → `localhost:8000`
   - `/order/*` → `localhost:8001`
   - Minimal Nginx server block:
   ```nginx
   server {
     listen 80;
     server_name api.yourdomain.com;

     location /availability/ {
       # Strip /availability prefix before forwarding to service root
       rewrite ^/availability/(.*)$ /$1 break;
       proxy_pass http://127.0.0.1:8000;
     }

     location /order/ {
       # Strip /order prefix before forwarding to order service root
       rewrite ^/order/(.*)$ /$1 break;
       proxy_pass http://127.0.0.1:8001;
     }

     # Optional default route; remove this block if you prefer strict 404 on unmatched paths
     location / {
       proxy_pass http://127.0.0.1:8000;
     }
   }
   ```
5. Enable HTTPS:
   ```bash
   sudo certbot --nginx -d api.yourdomain.com
   ```
6. In your frontend hosting provider (Netlify/Vercel/GitHub Pages), attach `yourdomain.com` as the custom domain.

---

## 💰 AWS Costs

### Free Tier (12 months)
| Resource | Free | Cost |
|----------|------|------|
| 2× EC2 t3.micro | 750 hrs/mo each | $0 |
| RDS t3.micro | 750 hrs/mo | $0 |
| ElastiCache t2.micro | 750 hrs/mo | $0 |
| OpenSearch t3.small | 750 hrs/mo | $0 |
| **Total** | | **~$1/mo** |

### After Free Tier: ~$67/month

### Cleanup
```powershell
cd terraform-files
terraform destroy --auto-approve
```

---

## 📊 Testing & Validation

### API Tests
```powershell
# Check availability
curl "http://localhost:8000/availability?item_id=apple&lat=26.9&lon=75.8"

# Place order
curl -X POST http://localhost:8001/orders `
  -H "Content-Type: application/json" `
  -d '{"customer_id":"test","items":[{"item_id":"apple","warehouse_id":"wh_lnmiit","quantity":2}]}'

# Check order history
curl http://localhost:8001/orders/test
```

### Load Testing
```powershell
# Install hey (HTTP load generator)
# Run 100 requests, 10 concurrent
hey -n 100 -c 10 "http://localhost:8000/availability?item_id=apple&lat=26.9&lon=75.8"
```

---

## 🎯 Feature Checklist

### ✅ Implemented
- [x] Product catalog with categories
- [x] Location-based warehouse selection
- [x] Real-time stock checking
- [x] Cart management & checkout
- [x] Order placement & history
- [x] Manager inventory CRUD
- [x] Role-based UI (Buyer/Manager)
- [x] Demo mode for both roles

### 🔜 Roadmap
- [ ] Push notifications
- [ ] Payment gateway
- [ ] Live order tracking
- [ ] Multiple addresses
- [ ] Promo codes

---

## 📝 Quick Reference

```powershell
# Local Docker
cd local && docker-compose -f docker-compose-local.yaml up -d --build
docker-compose -f docker-compose-local.yaml logs -f
docker-compose -f docker-compose-local.yaml down

# Flutter
flutter run -d chrome --web-browser-flag "--disable-web-security"

# SSH to AWS
ssh -i terraform-files/k3s-key ubuntu@<IP>
kubectl get pods -A
kubectl logs -l app=availability

# Terraform
terraform plan
terraform apply --auto-approve
terraform output
terraform destroy --auto-approve
```
