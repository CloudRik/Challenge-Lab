#!/bin/bash

# =========================================================
#  Google Skills Boost - Challenge Lab Automation Script
#  Lab: Build Global and Regional Load Balancing Solutions
#  Version: Bulletproof (Skip if exists)
# =========================================================

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

# ---------- USER INPUTS ----------
echo -e "\n${YELLOW}[Lab Specific Inputs]${NC}"
echo -e "${YELLOW}Note: Region A aur Region B lab ke 'Start Lab' page pe diye hote hain.${NC}"

read -p "Enter Region A (e.g. us-east1): " REGION_A
read -p "Enter Region B (e.g. europe-west1): " REGION_B

# ---------- AUTO-DERIVE ZONES ----------
echo -e "\n${GREEN}[Auto-detecting zones from regions...]${NC}"
ZONE_A=$(gcloud compute zones list --filter="region:$REGION_A" --format="value(name)" | head -1)
ZONE_B=$(gcloud compute zones list --filter="region:$REGION_B" --format="value(name)" | head -1)

[[ -z "$ZONE_A" ]] && ZONE_A="${REGION_A}-b"
[[ -z "$ZONE_B" ]] && ZONE_B="${REGION_B}-b"

echo -e "✅ Zone A: $ZONE_A"
echo -e "✅ Zone B: $ZONE_B"

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
#  HELPER FUNCTION: Create if not exists
# =========================================================
create_if_not_exists() {
    local check_cmd="$1"
    local create_cmd="$2"
    local name="$3"
    
    if eval "$check_cmd" &>/dev/null; then
        echo -e "${YELLOW}⏭️  $name already exists, skipping...${NC}"
    else
        echo -e "${GREEN}➕ Creating $name...${NC}"
        eval "$create_cmd"
    fi
}

# =========================================================
#  TASK 1: Regional Internal Proxy NLB
# =========================================================
echo -e "\n${GREEN}========== TASK 1: Regional Internal Proxy NLB ==========${NC}"

# 1.1 VPC + Subnets
create_if_not_exists \
    "gcloud compute networks describe $VPC_NAME" \
    "gcloud compute networks create $VPC_NAME --subnet-mode=custom" \
    "VPC $VPC_NAME"

create_if_not_exists \
    "gcloud compute networks subnets describe $SUBNET_A --region=$REGION_A" \
    "gcloud compute networks subnets create $SUBNET_A --network=$VPC_NAME --region=$REGION_A --range=10.10.10.0/24" \
    "Subnet $SUBNET_A"

create_if_not_exists \
    "gcloud compute networks subnets describe $SUBNET_B --region=$REGION_B" \
    "gcloud compute networks subnets create $SUBNET_B --network=$VPC_NAME --region=$REGION_B --range=10.20.20.0/24" \
    "Subnet $SUBNET_B"

# 1.2 Instance Template
create_if_not_exists \
    "gcloud compute instance-templates describe template-proxy-internal" \
    "gcloud compute instance-templates create template-proxy-internal --network=$VPC_NAME --subnet=$SUBNET_B --region=$REGION_B --machine-type=e2-medium --image-family=debian-11 --image-project=debian-cloud --tags=tag-proxy-internal --metadata=startup-script='#! /bin/bash
apt-get update
apt-get install -y nginx
service nginx start'" \
    "Instance Template template-proxy-internal"

# 1.3 Regional MIG
create_if_not_exists \
    "gcloud compute instance-groups managed describe mig-proxy-internal --region=$REGION_B" \
    "gcloud compute instance-groups managed create mig-proxy-internal --template=template-proxy-internal --size=2 --region=$REGION_B" \
    "MIG mig-proxy-internal"

# Set named port (idempotent)
gcloud compute instance-groups managed set-named-ports mig-proxy-internal \
    --named-ports=tcp80:80 \
    --region=$REGION_B 2>/dev/null || true

# 1.4 Firewall Rules
create_if_not_exists \
    "gcloud compute firewall-rules describe fw-proxy-internal-hc" \
    "gcloud compute firewall-rules create fw-proxy-internal-hc --network=$VPC_NAME --allow=tcp:80 --source-ranges=130.211.0.0/22,35.191.0.0/16 --target-tags=tag-proxy-internal" \
    "Firewall fw-proxy-internal-hc"

create_if_not_exists \
    "gcloud compute firewall-rules describe fw-proxy-internal-subnet" \
    "gcloud compute firewall-rules create fw-proxy-internal-subnet --network=$VPC_NAME --allow=tcp:80 --source-ranges=10.129.0.0/23 --target-tags=tag-proxy-internal" \
    "Firewall fw-proxy-internal-subnet"

# 1.5 Internal Static IP
create_if_not_exists \
    "gcloud compute addresses describe ip-internal-proxy --region=$REGION_B" \
    "gcloud compute addresses create ip-internal-proxy --region=$REGION_B --subnet=$SUBNET_B --purpose=SHARED_LOADBALANCER_VIP" \
    "Static IP ip-internal-proxy"

INTERNAL_IP=$(gcloud compute addresses describe ip-internal-proxy \
    --region=$REGION_B --format="value(address)")
echo -e "✅ Internal IP: $INTERNAL_IP"

# Health Check
create_if_not_exists \
    "gcloud compute health-checks describe hc-proxy-internal --region=$REGION_B" \
    "gcloud compute health-checks create tcp hc-proxy-internal --port=80 --region=$REGION_B" \
    "Health Check hc-proxy-internal"

# Backend Service
create_if_not_exists \
    "gcloud compute backend-services describe service-proxy-internal --region=$REGION_B" \
    "gcloud compute backend-services create service-proxy-internal --load-balancing-scheme=INTERNAL_MANAGED --protocol=TCP --region=$REGION_B --health-checks=hc-proxy-internal" \
    "Backend Service service-proxy-internal"

# Add backend
gcloud compute backend-services add-backend service-proxy-internal \
    --instance-group=mig-proxy-internal \
    --instance-group-region=$REGION_B \
    --region=$REGION_B 2>/dev/null || true

# Target TCP Proxy
create_if_not_exists \
    "gcloud compute target-tcp-proxies describe proxy-internal-nlb --region=$REGION_B" \
    "gcloud compute target-tcp-proxies create proxy-internal-nlb --backend-service=service-proxy-internal --region=$REGION_B" \
    "Target TCP Proxy proxy-internal-nlb"

# Forwarding Rule
create_if_not_exists \
    "gcloud compute forwarding-rules describe rule-internal-proxy --region=$REGION_B" \
    "gcloud compute forwarding-rules create rule-internal-proxy --region=$REGION_B --load-balancing-scheme=INTERNAL_MANAGED --network=$VPC_NAME --subnet=$SUBNET_B --address=$INTERNAL_IP --ports=110 --target-tcp-proxy=proxy-internal-nlb" \
    "Forwarding Rule rule-internal-proxy"

# 1.6 Client VM
create_if_not_exists \
    "gcloud compute instances describe vm-client-internal --zone=$ZONE_B" \
    "gcloud compute instances create vm-client-internal --zone=$ZONE_B --network=$VPC_NAME --subnet=$SUBNET_B --machine-type=e2-medium --image-family=debian-11 --image-project=debian-cloud --tags=allow-ssh" \
    "Client VM vm-client-internal"

create_if_not_exists \
    "gcloud compute firewall-rules describe fw-allow-ssh" \
    "gcloud compute firewall-rules create fw-allow-ssh --network=$VPC_NAME --allow=tcp:22 --source-ranges=0.0.0.0/0 --target-tags=allow-ssh" \
    "Firewall fw-allow-ssh"

echo -e "${GREEN}✅ TASK 1 Completed!${NC}"

# =========================================================
#  TASK 2: Global External ALB
# =========================================================
echo -e "\n${GREEN}========== TASK 2: Global External ALB ==========${NC}"

# 2.1 Instance Template for ALB
create_if_not_exists \
    "gcloud compute instance-templates describe template-alb-api" \
    "gcloud compute instance-templates create template-alb-api --network=$VPC_NAME --machine-type=e2-medium --image-family=debian-11 --image-project=debian-cloud --tags=http-server --metadata=startup-script='#! /bin/bash
apt-get update
apt-get install -y nginx
service nginx start'" \
    "Instance Template template-alb-api"

# 2.2 Two MIGs
create_if_not_exists \
    "gcloud compute instance-groups managed describe mig-alb-api-a --region=$REGION_A" \
    "gcloud compute instance-groups managed create mig-alb-api-a --template=template-alb-api --size=2 --region=$REGION_A" \
    "MIG mig-alb-api-a"

gcloud compute instance-groups managed set-named-ports mig-alb-api-a \
    --named-ports=http80:80 \
    --region=$REGION_A 2>/dev/null || true

create_if_not_exists \
    "gcloud compute instance-groups managed describe mig-alb-api-b --region=$REGION_B" \
    "gcloud compute instance-groups managed create mig-alb-api-b --template=template-alb-api --size=2 --region=$REGION_B" \
    "MIG mig-alb-api-b"

gcloud compute instance-groups managed set-named-ports mig-alb-api-b \
    --named-ports=http80:80 \
    --region=$REGION_B 2>/dev/null || true

# 2.3 Health Check + Backend Service
create_if_not_exists \
    "gcloud compute health-checks describe http-check-alb --global" \
    "gcloud compute health-checks create http http-check-alb --port=80 --global" \
    "Health Check http-check-alb"

create_if_not_exists \
    "gcloud compute backend-services describe service-alb-global --global" \
    "gcloud compute backend-services create service-alb-global --load-balancing-scheme=EXTERNAL_MANAGED --protocol=HTTP --health-checks=http-check-alb --global" \
    "Backend Service service-alb-global"

gcloud compute backend-services add-backend service-alb-global \
    --instance-group=mig-alb-api-a \
    --instance-group-region=$REGION_A \
    --balancing-mode=RATE \
    --max-rate-per-instance=1 \
    --global 2>/dev/null || true

gcloud compute backend-services add-backend service-alb-global \
    --instance-group=mig-alb-api-b \
    --instance-group-region=$REGION_B \
    --balancing-mode=RATE \
    --max-rate-per-instance=1 \
    --global 2>/dev/null || true

# 2.4 SSL Certificate
if [[ ! -f key.pem ]]; then
    openssl genrsa -out key.pem 2048
fi
if [[ ! -f cert.pem ]]; then
    openssl req -new -x509 -key key.pem -out cert.pem -days 1 -subj "/CN=example.com"
fi

create_if_not_exists \
    "gcloud compute ssl-certificates describe cert-self-signed --global" \
    "gcloud compute ssl-certificates create cert-self-signed --certificate=cert.pem --private-key=key.pem --global" \
    "SSL Certificate cert-self-signed"

# 2.5 Global Static IP
create_if_not_exists \
    "gcloud compute addresses describe ip-alb-global --global" \
    "gcloud compute addresses create ip-alb-global --global" \
    "Global IP ip-alb-global"

ALB_IP=$(gcloud compute addresses describe ip-alb-global --global --format="value(address)")
echo -e "✅ Global ALB IP: $ALB_IP"

# 2.6 URL Map + HTTPS Proxy + Forwarding Rule
create_if_not_exists \
    "gcloud compute url-maps describe url-map-alb" \
    "gcloud compute url-maps create url-map-alb --default-service=service-alb-global" \
    "URL Map url-map-alb"

create_if_not_exists \
    "gcloud compute target-https-proxies describe https-proxy-alb" \
    "gcloud compute target-https-proxies create https-proxy-alb --ssl-certificates=cert-self-signed --url-map=url-map-alb" \
    "HTTPS Proxy https-proxy-alb"

create_if_not_exists \
    "gcloud compute forwarding-rules describe rule-alb-global --global" \
    "gcloud compute forwarding-rules create rule-alb-global --load-balancing-scheme=EXTERNAL_MANAGED --network-tier=PREMIUM --address=$ALB_IP --target-https-proxy=https-proxy-alb --global --ports=443" \
    "Forwarding Rule rule-alb-global"

# 2.7 Firewall
create_if_not_exists \
    "gcloud compute firewall-rules describe fw-allow-health-check-and-proxy" \
    "gcloud compute firewall-rules create fw-allow-health-check-and-proxy --network=$VPC_NAME --allow=tcp:80 --source-ranges=130.211.0.0/22,35.191.0.0/16 --target-tags=http-server" \
    "Firewall fw-allow-health-check-and-proxy"

echo -e "${GREEN}✅ TASK 2 Completed!${NC}"

# =========================================================
#  TASK 3: Test Info
# =========================================================
echo -e "\n${GREEN}========== TASK 3: Test Failover ==========${NC}"
echo -e "${YELLOW}Global ALB IP: $ALB_IP${NC}"
echo -e "${YELLOW}Internal NLB IP: $INTERNAL_IP${NC}"
echo ""
echo -e "${GREEN}Manual test commands:${NC}"
echo -e "1. ${YELLOW}while true; do curl -k -s https://$ALB_IP | grep 'Hello from'; sleep 0.5; done${NC}"
echo -e "2. SSH into mig-alb-api-a VM → ${YELLOW}sudo systemctl stop nginx${NC}"
echo ""

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  🎉 All Tasks Executed Successfully!  ${NC}"
echo -e "${GREEN}========================================${NC}"
