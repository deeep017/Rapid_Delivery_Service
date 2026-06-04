#!/bin/bash
set -e

echo "=========================================="
echo "K3S WORKER NODE - Joins Master Cluster"
echo "=========================================="

# 0. Swap
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# 1. Install dependencies
apt-get update
apt-get install -y curl unzip docker.io

systemctl enable docker
systemctl start docker

# 2. Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# 3. Wait for Master and get token
echo "Waiting for K3s master to save token to SSM..."

MAX_RETRIES=30
RETRY_COUNT=0
K3S_TOKEN=""

while [ -z "$K3S_TOKEN" ] && [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    echo "Attempt $((RETRY_COUNT + 1))/$MAX_RETRIES: Getting K3s token from SSM..."
    K3S_TOKEN=$(aws ssm get-parameter \
        --name "/rapid-delivery-local/k3s-token" \
        --with-decryption \
        --query "Parameter.Value" \
        --output text \
        --region ${AWS_REGION} 2>/dev/null || echo "")
    
    if [ -z "$K3S_TOKEN" ]; then
        echo "Token not ready yet, waiting 30 seconds..."
        sleep 30
        RETRY_COUNT=$((RETRY_COUNT + 1))
    fi
done

if [ -z "$K3S_TOKEN" ]; then
    echo "ERROR: Could not get K3s token from SSM after $MAX_RETRIES attempts"
    exit 1
fi

K3S_MASTER_IP=$(aws ssm get-parameter \
    --name "/rapid-delivery-local/k3s-master-ip" \
    --query "Parameter.Value" \
    --output text \
    --region ${AWS_REGION})

echo "Got K3s token and master IP: $K3S_MASTER_IP"

# 4. Install K3s AGENT (Worker Node)
mkdir -p /etc/rancher/k3s
cat <<EOF > /etc/rancher/k3s/config.yaml
---
node-label:
  - "node-role=worker"
kubelet-arg:
  - "max-pods=10"
  - "eviction-hard=memory.available<100Mi"
  - "eviction-soft=memory.available<200Mi"
  - "eviction-soft-grace-period=memory.available=30s"
EOF

curl -sfL https://get.k3s.io | K3S_URL="https://$K3S_MASTER_IP:6443" K3S_TOKEN="$K3S_TOKEN" sh -

echo "Waiting for agent to connect to master..."
sleep 30

# 5. Login to ECR (for image pulls)
aws ecr get-login-password --region ${AWS_REGION} \
 | docker login --username AWS \
 --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

echo "✅ K3s Worker Node Ready!"
echo "Worker has joined the cluster as an agent node."
echo "Pods will be scheduled here by the master."
