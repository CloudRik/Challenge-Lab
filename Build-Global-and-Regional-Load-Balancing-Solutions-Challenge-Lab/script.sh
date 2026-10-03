#!/bin/bash

# =========================================================
#  Google Skills Boost - Challenge Lab Automation Script
#  Lab: Build Global and Regional Load Balancing Solutions
# =========================================================

set -e  # Stop script on any error

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}============================================${NC}"
echo -e "${YELLOW}  Global & Regional Load Balancing Setup   ${NC}"
echo -e "${YELLOW}============================================${NC}\n"

# ---------- AUTO DETECT ----------
echo -e "${GREEN}[Auto-detecting environment...]${NC}"

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
    read -p "Project ID auto-detect nahi hua. Enter manually: " PROJECT_ID
    gcloud config set project $PROJECT_ID
fi
echo -e "✅ Project ID: $PROJECT_ID"

ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1)
USERNAME=$(echo $ACTIVE_ACCOUNT | cut -d'@' -f1)
echo -e "✅ Username: $USERNAME"

# ---------- USER INPUTS (Region A / Region B) ----------
# ---------- USER INPUTS (Sirf Regions) ----------
echo -e "\n${YELLOW}[Lab Specific Inputs]${NC}"
echo -e "${YELLOW}Note: Region A aur Region B lab ke 'Start Lab' page pe diye hote hain.${NC}"

read -p "Enter Region A (e.g. us-east1): " REGION_A
read -p "Enter Region B (e.g. europe-west1): " REGION_B

# Auto-derive zones from regions
echo -e "\n${GREEN}[Auto-detecting zones...]${NC}"
ZONE_A=$(gcloud compute zones list --filter="region:$REGION_A" --format="value(name)" | head -1)
ZONE_B=$(gcloud compute zones list --filter="region:$REGION_B" --format="value(name)" | head -1)

if [[ -z "$ZONE_A" || -z "$ZONE_B" ]]; then
    echo -e "${RED}❌ Zone auto-detect fail hua. Region names check karo.${NC}"
    exit 1
fi

echo -e "✅ Zone A: $ZONE_A"
echo -e "✅ Zone B: $ZONE_B"

# Derived variables
SUBNET_A="subnet-a"
SUBNET_B="subnet-b"
VPC_NAME="lb-network"

# ---------- CONFIRM ----------
echo -e "\n${GREEN}===== Configuration Summary =====${NC}"
echo "Project ID : $PROJECT_ID"
echo "Region A   : $REGION_A  (Zone: $ZONE_A)"
echo "Region B   : $REGION_B  (Zone: $ZONE_B)"
echo "Username   : $USERNAME"
echo "================================="

read -p "Proceed? (y/n): " CONFIRM
[[ "$CONFIRM" != "y" ]] && echo "Aborted." && exit 1

# =========================================================
#  TASK 1: Secure internal transaction processor (Regional Internal Proxy NLB)
# =========================================================
echo -e "\n${GREEN}========== TASK 1: Regional Internal Proxy NLB ==========${NC}"

# 1.1 Create VPC + Subnets
echo -e "${GREEN}[1.1] Creating VPC and Subnets...${NC}"
gcloud compute networks create $VPC_NAME --subnet-mode=custom

gcloud compute networks subnets create $SUBNET_A \
    --network=$VPC_NAME \
    --region=$REGION_A \
    --range=10.10.10.0/24

gcloud compute networks subnets create $SUBNET_B \
    --network=$VPC_NAME \
    --region=$REGION_B \
    --range=10.20.20.0/24

# 1.2 Create Instance Template + MIG in Region B
echo -e "${GREEN}[1.2] Creating Instance Template (template-proxy-internal)...${NC}"
gcloud compute instance-templates create template-proxy-internal \
    --network=$VPC_NAME \
    --subnet=$SUBNET_B \
    --region=$REGION_B \
    --machine-type=e2-medium \
    --image-family=debian-11 \
    --image-project=debian-cloud \
    --tags=tag-proxy-internal \
    --metadata=startup-script='#! /bin/bash
apt-get update
apt-get install -y nginx
service nginx start'

echo -e "${GREEN}[1.3] Creating Regional MIG (mig-proxy-internal) in Region B...${NC}"
gcloud compute instance-groups managed create mig-proxy-internal \
    --template=template-proxy-internal \
    --size=2 \
    --region=$REGION_B

gcloud compute instance-groups managed set-named-ports mig-proxy-internal \
    --named-ports=tcp80:80 \
    --region=$REGION_B

# 1.4 Firewall Rules
echo -e "${GREEN}[1.4] Creating Firewall Rules...${NC}"
gcloud compute firewall-rules create fw-proxy-internal-hc \
    --network=$VPC_NAME \
    --allow=tcp:80 \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --target-tags=tag-proxy-internal \
    --description="Health check for internal proxy NLB"

gcloud compute firewall-rules create fw-proxy-internal-subnet \
    --network=$VPC_NAME \
    --allow=tcp:80 \
    --source-ranges=10.129.0.0/23 \
    --target-tags=tag-proxy-internal \
    --description="Proxy-only subnet CIDR for internal proxy NLB"

# 1.5 Reserve Internal Static IP + Forwarding Rule
echo -e "${GREEN}[1.5] Creating Internal Static IP & Forwarding Rule...${NC}"
gcloud compute addresses create ip-internal-proxy \
    --region=$REGION_B \
    --subnet=$SUBNET_B \
    --purpose=SHARED_LOADBALANCER_VIP

INTERNAL_IP=$(gcloud compute addresses describe ip-internal-proxy \
    --region=$REGION_B --format="value(address)")

gcloud compute forwarding-rules create rule-internal-proxy \
    --region=$REGION_B \
    --load-balancing-scheme=INTERNAL_MANAGED \
    --network=$VPC_NAME \
    --subnet=$SUBNET_B \
    --address=$INTERNAL_IP \
    --ports=110 \
    --target-tcp-proxy=proxy-internal-nlb

gcloud compute target-tcp-proxies create proxy-internal-nlb \
    --backend-service=service-proxy-internal \
    --region=$REGION_B

gcloud compute backend-services create service-proxy-internal \
    --load-balancing-scheme=INTERNAL_MANAGED \
    --protocol=TCP \
    --region=$REGION_B \
    --health-checks=hc-proxy-internal

gcloud compute health-checks create tcp hc-proxy-internal \
    --port=80 \
    --region=$REGION_B

gcloud compute backend-services add-backend service-proxy-internal \
    --instance-group=mig-proxy-internal \
    --instance-group-region=$REGION_B \
    --region=$REGION_B

# 1.6 Client VM (vm-client-internal)
echo -e "${GREEN}[1.6] Creating Client VM (vm-client-internal)...${NC}"
gcloud compute instances create vm-client-internal \
    --zone=$ZONE_B \
    --network=$VPC_NAME \
    --subnet=$SUBNET_B \
    --machine-type=e2-medium \
    --image-family=debian-11 \
    --image-project=debian-cloud \
    --tags=allow-ssh

gcloud compute firewall-rules create fw-allow-ssh \
    --network=$VPC_NAME \
    --allow=tcp:22 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=allow-ssh \
    --description="Allow SSH to client VM"

echo -e "${GREEN}✅ TASK 1 Completed!${NC}"

# =========================================================
#  TASK 2: Global External Application Load Balancer
# =========================================================
echo -e "\n${GREEN}========== TASK 2: Global External ALB ==========${NC}"

# 2.1 Instance Template for ALB backends
echo -e "${GREEN}[2.1] Creating Instance Template (template-alb-api)...${NC}"
gcloud compute instance-templates create template-alb-api \
    --network=$VPC_NAME \
    --machine-type=e2-medium \
    --image-family=debian-11 \
    --image-project=debian-cloud \
    --tags=http-server \
    --metadata=startup-script='#! /bin/bash
apt-get update
apt-get install -y nginx
service nginx start'

# 2.2 Two Regional MIGs
echo -e "${GREEN}[2.2] Creating MIGs (mig-alb-api-a & mig-alb-api-b)...${NC}"
gcloud compute instance-groups managed create mig-alb-api-a \
    --template=template-alb-api \
    --size=2 \
    --region=$REGION_A

gcloud compute instance-groups managed set-named-ports mig-alb-api-a \
    --named-ports=http80:80 \
    --region=$REGION_A

gcloud compute instance-groups managed create mig-alb-api-b \
    --template=template-alb-api \
    --size=2 \
    --region=$REGION_B

gcloud compute instance-groups managed set-named-ports mig-alb-api-b \
    --named-ports=http80:80 \
    --region=$REGION_B

# 2.3 Global Health Check + Backend Service
echo -e "${GREEN}[2.3] Creating Global HTTP Health Check & Backend Service...${NC}"
gcloud compute health-checks create http http-check-alb \
    --port=80 \
    --global

gcloud compute backend-services create service-alb-global \
    --load-balancing-scheme=EXTERNAL_MANAGED \
    --protocol=HTTP \
    --health-checks=http-check-alb \
    --global

gcloud compute backend-services add-backend service-alb-global \
    --instance-group=mig-alb-api-a \
    --instance-group-region=$REGION_A \
    --balancing-mode=RATE \
    --max-rate-per-instance=1 \
    --global

gcloud compute backend-services add-backend service-alb-global \
    --instance-group=mig-alb-api-b \
    --instance-group-region=$REGION_B \
    --balancing-mode=RATE \
    --max-rate-per-instance=1 \
    --global

# 2.4 Self-signed SSL Certificate
echo -e "${GREEN}[2.4] Creating Self-signed SSL Certificate...${NC}"
openssl genrsa -out key.pem 2048
openssl req -new -x509 -key key.pem -out cert.pem -days 1 -subj "/CN=example.com"

gcloud compute ssl-certificates create cert-self-signed \
    --certificate=cert.pem \
    --private-key=key.pem \
    --global

# 2.5 Reserve Global Static IP
echo -e "${GREEN}[2.5] Reserving Global Static IP (ip-alb-global)...${NC}"
gcloud compute addresses create ip-alb-global --global
ALB_IP=$(gcloud compute addresses describe ip-alb-global --global --format="value(address)")
echo -e "✅ Global ALB IP: $ALB_IP"

# 2.6 HTTPS Frontend
echo -e "${GREEN}[2.6] Creating HTTPS Frontend (Port 443)...${NC}"
gcloud compute target-https-proxies create https-proxy-alb \
    --ssl-certificates=cert-self-signed \
    --url-map=url-map-alb

gcloud compute url-maps create url-map-alb \
    --default-service=service-alb-global

gcloud compute forwarding-rules create rule-alb-global \
    --load-balancing-scheme=EXTERNAL_MANAGED \
    --network-tier=PREMIUM \
    --address=$ALB_IP \
    --target-https-proxy=https-proxy-alb \
    --global \
    --ports=443

# 2.7 Firewall for ALB
echo -e "${GREEN}[2.7] Creating Firewall Rule (fw-allow-health-check-and-proxy)...${NC}"
gcloud compute firewall-rules create fw-allow-health-check-and-proxy \
    --network=$VPC_NAME \
    --allow=tcp:80 \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --target-tags=http-server \
    --description="Allow health check and proxy traffic to ALB backends"

echo -e "${GREEN}✅ TASK 2 Completed!${NC}"

# =========================================================
#  TASK 3: Test Failover and Global Distribution
# =========================================================
echo -e "\n${GREEN}========== TASK 3: Test Failover ==========${NC}"

echo -e "${YELLOW}Global ALB IP: $ALB_IP${NC}"
echo -e "${YELLOW}Internal NLB IP: $INTERNAL_IP${NC}"
echo ""
echo -e "${GREEN}Test commands (run manually in separate SSH sessions):${NC}"
echo -e "1. Global distribution test:"
echo -e "   ${YELLOW}while true; do curl -k -s https://$ALB_IP | grep 'Hello from'; sleep 0.5; done${NC}"
echo ""
echo -e "2. Simulate failover (SSH into mig-alb-api-a VM):"
echo -e "   ${YELLOW}sudo systemctl stop nginx${NC}"
echo ""

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  🎉 All Tasks Executed Successfully!  ${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}Ab Skills Boost pe 'Check my progress' click karo har task ke liye.${NC}"
