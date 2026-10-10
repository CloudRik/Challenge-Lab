#!/bin/bash

# Colors
CYAN='\033[0;96m'
GREEN='\033[0;92m'
YELLOW='\033[0;93m'
RED='\033[0;91m'
MAGENTA='\033[0;95m'
BLUE='\033[0;94m'
WHITE='\033[0;97m'
BOLD='\033[1m'
RESET='\033[0m'

clear
echo
echo "${CYAN}${BOLD}=================================================${RESET}"
echo "${CYAN}${BOLD}   GLOBAL & REGIONAL LOAD BALANCING LAB         ${RESET}"
echo "${CYAN}${BOLD}=================================================${RESET}"
echo

# ===============================
# ENVIRONMENT DETECTION
# ===============================
PROJECT=$(gcloud config get-value project 2>/dev/null)

if [ -z "$PROJECT" ]; then
  read -p "Enter your Project ID: " PROJECT
  gcloud config set project $PROJECT
fi

echo "${BLUE}Project: ${WHITE}$PROJECT${RESET}"
echo

# ===============================
# REGION INPUT (Auto-detect try karo)
# ===============================
echo "${YELLOW}${BOLD}Region Configuration${RESET}"
echo

# Default region detect karo
DEFAULT_REGION=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null)

if [ -z "$DEFAULT_REGION" ]; then
  DEFAULT_REGION="us-central1"
fi

# Available regions list dikhao
echo "${WHITE}Available regions (sample):${RESET}"
gcloud compute regions list --format="value(name)" 2>/dev/null | head -15
echo

# User se Region A poocho
echo "${YELLOW}Region A = pehla region (jahan MIG-A banega)${RESET}"
read -p "Enter Region A [default: $DEFAULT_REGION]: " REGION_A
REGION_A=${REGION_A:-$DEFAULT_REGION}

# User se Region B poocho
echo
echo "${YELLOW}Region B = dusra region (jahan MIG-B banega, internal proxy bhi yahin)${RESET}"
echo "${WHITE}Note: Region B alag hona chahiye Region A se (global load balancer ke liye)${RESET}"

# Suggest a different region
SUGGESTED_B="europe-west1"
if [ "$REGION_A" = "europe-west1" ]; then
  SUGGESTED_B="us-central1"
fi

read -p "Enter Region B [default: $SUGGESTED_B]: " REGION_B
REGION_B=${REGION_B:-$SUGGESTED_B}

# Verify different regions
if [ "$REGION_A" = "$REGION_B" ]; then
  echo "${RED}Warning: Region A aur Region B same hain! Global load balancer ke liye alag hone chahiye.${RESET}"
  read -p "Continue anyway? (y/n): " CONFIRM
  if [ "$CONFIRM" != "y" ]; then
    exit 1
  fi
fi

echo
echo "${GREEN}Region A: ${WHITE}$REGION_A${RESET}"
echo "${GREEN}Region B: ${WHITE}$REGION_B${RESET}"
echo

# ===============================
# TASK 1: Regional Internal Proxy NLB
# ===============================
echo "${GREEN}${BOLD}=================================================${RESET}"
echo "${GREEN}${BOLD}Task 1: Regional Internal Proxy NLB${RESET}"
echo "${GREEN}${BOLD}=================================================${RESET}"
echo

# 1a. Instance template
echo "${YELLOW}[1/9] Creating instance template 'template-proxy-internal'...${RESET}"
gcloud compute instance-templates create template-proxy-internal \
  --machine-type=e2-micro \
  --network=default \
  --tags=tag-proxy-internal \
  --image-family=debian-11 \
  --image-project=debian-cloud \
  --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install -y nginx
systemctl start nginx
systemctl enable nginx' \
  --quiet 2>/dev/null || echo "${YELLOW}Template already exists${RESET}"

# 1b. Regional MIG
echo "${YELLOW}[2/9] Creating regional MIG 'mig-proxy-internal' in $REGION_B...${RESET}"
gcloud compute instance-groups managed create mig-proxy-internal \
  --template=template-proxy-internal \
  --size=2 \
  --region=$REGION_B \
  --quiet 2>/dev/null || echo "${YELLOW}MIG already exists${RESET}"

gcloud compute instance-groups managed set-named-ports mig-proxy-internal \
  --named-ports=tcp80:80 \
  --region=$REGION_B \
  --quiet 2>/dev/null || true

# 1c. Proxy-only subnet
echo "${YELLOW}[3/9] Creating proxy-only subnet...${RESET}"
gcloud compute networks subnets describe proxy-only-subnet --region=$REGION_B &>/dev/null || \
gcloud compute networks subnets create proxy-only-subnet \
  --purpose=REGIONAL_MANAGED_PROXY \
  --role=ACTIVE \
  --region=$REGION_B \
  --network=default \
  --range=10.129.0.0/23 \
  --quiet

# 1d. Firewall rules
echo "${YELLOW}[4/9] Creating firewall rules...${RESET}"
gcloud compute firewall-rules create fw-health-check-internal \
  --network=default \
  --allow=tcp:80 \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --target-tags=tag-proxy-internal \
  --quiet 2>/dev/null || echo "${YELLOW}Rule exists${RESET}"

gcloud compute firewall-rules create fw-proxy-internal \
  --network=default \
  --allow=tcp:80 \
  --source-ranges=10.129.0.0/23 \
  --target-tags=tag-proxy-internal \
  --quiet 2>/dev/null || echo "${YELLOW}Rule exists${RESET}"

# 1e. Health check
echo "${YELLOW}[5/9] Creating health check...${RESET}"
gcloud compute health-checks create tcp hc-internal-proxy \
  --port=80 \
  --region=$REGION_B \
  --quiet 2>/dev/null || echo "${YELLOW}HC exists${RESET}"

# 1f. Backend service
echo "${YELLOW}[6/9] Creating backend service...${RESET}"
gcloud compute backend-services create bs-internal-proxy \
  --load-balancing-scheme=INTERNAL_MANAGED \
  --protocol=TCP \
  --health-checks=hc-internal-proxy \
  --region=$REGION_B \
  --quiet 2>/dev/null || echo "${YELLOW}BS exists${RESET}"

gcloud compute backend-services add-backend bs-internal-proxy \
  --instance-group=mig-proxy-internal \
  --instance-group-region=$REGION_B \
  --region=$REGION_B \
  --quiet 2>/dev/null || true

# 1g. Reserve static internal IP
echo "${YELLOW}[7/9] Reserving internal IP...${RESET}"
gcloud compute addresses create ip-internal-proxy \
  --region=$REGION_B \
  --subnet=default \
  --purpose=SHARED_LOADBALANCER_VIP \
  --quiet 2>/dev/null || echo "${YELLOW}IP exists${RESET}"

INTERNAL_IP=$(gcloud compute addresses describe ip-internal-proxy \
  --region=$REGION_B --format="value(address)" 2>/dev/null)
echo "${BLUE}Internal IP: ${WHITE}$INTERNAL_IP${RESET}"

# 1h. Target TCP proxy
echo "${YELLOW}[8/9] Creating target TCP proxy...${RESET}"
gcloud compute target-tcp-proxies create tcp-proxy-internal \
  --backend-service=bs-internal-proxy \
  --region=$REGION_B \
  --quiet 2>/dev/null || echo "${YELLOW}TCP proxy exists${RESET}"

# 1i. Forwarding rule
echo "${YELLOW}[9/9] Creating forwarding rule...${RESET}"
gcloud compute forwarding-rules create rule-internal-proxy \
  --load-balancing-scheme=INTERNAL_MANAGED \
  --network=default \
  --subnet=default \
  --address=$INTERNAL_IP \
  --ports=110 \
  --region=$REGION_B \
  --target-tcp-proxy=tcp-proxy-internal \
  --quiet 2>/dev/null || echo "${YELLOW}FR exists${RESET}"

echo "${GREEN}Task 1 complete${RESET}"
echo

# ===============================
# TASK 2: Global External ALB
# ===============================
echo "${MAGENTA}${BOLD}=================================================${RESET}"
echo "${MAGENTA}${BOLD}Task 2: Global External Application Load Balancer${RESET}"
echo "${MAGENTA}${BOLD}=================================================${RESET}"
echo

# 2a. Instance template
echo "${YELLOW}[1/9] Creating instance template 'template-alb-api'...${RESET}"
gcloud compute instance-templates create template-alb-api \
  --machine-type=e2-micro \
  --network=default \
  --tags=tag-allow-ssh \
  --image-family=debian-11 \
  --image-project=debian-cloud \
  --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install -y nginx
systemctl start nginx
systemctl enable nginx' \
  --quiet 2>/dev/null || echo "${YELLOW}Template exists${RESET}"

# 2b. MIG in Region A
echo "${YELLOW}[2/9] Creating MIG 'mig-alb-api-a' in $REGION_A...${RESET}"
gcloud compute instance-groups managed create mig-alb-api-a \
  --template=template-alb-api \
  --size=2 \
  --region=$REGION_A \
  --quiet 2>/dev/null || true

gcloud compute instance-groups managed set-named-ports mig-alb-api-a \
  --named-ports=http80:80 \
  --region=$REGION_A \
  --quiet 2>/dev/null || true

# 2c. MIG in Region B
echo "${YELLOW}[3/9] Creating MIG 'mig-alb-api-b' in $REGION_B...${RESET}"
gcloud compute instance-groups managed create mig-alb-api-b \
  --template=template-alb-api \
  --size=2 \
  --region=$REGION_B \
  --quiet 2>/dev/null || true

gcloud compute instance-groups managed set-named-ports mig-alb-api-b \
  --named-ports=http80:80 \
  --region=$REGION_B \
  --quiet 2>/dev/null || true

# 2d. Health check
echo "${YELLOW}[4/9] Creating health check...${RESET}"
gcloud compute health-checks create http http-check-alb \
  --port=80 \
  --global \
  --quiet 2>/dev/null || true

# 2e. Backend service
echo "${YELLOW}[5/9] Creating backend service 'service-alb-global'...${RESET}"
gcloud compute backend-services create service-alb-global \
  --load-balancing-scheme=EXTERNAL_MANAGED \
  --protocol=HTTP \
  --health-checks=http-check-alb \
  --global \
  --quiet 2>/dev/null || true

gcloud compute backend-services add-backend service-alb-global \
  --instance-group=mig-alb-api-a \
  --instance-group-region=$REGION_A \
  --balancing-mode=RATE \
  --max-rate-per-instance=1 \
  --global \
  --quiet 2>/dev/null || true

gcloud compute backend-services add-backend service-alb-global \
  --instance-group=mig-alb-api-b \
  --instance-group-region=$REGION_B \
  --balancing-mode=RATE \
  --max-rate-per-instance=1 \
  --global \
  --quiet 2>/dev/null || true

# 2f. SSL cert
echo "${YELLOW}[6/9] Creating self-signed SSL cert...${RESET}"
openssl genrsa -out key.pem 2048 2>/dev/null
openssl req -new -x509 -key key.pem -out cert.pem -days 1 -subj "/CN=example.com" 2>/dev/null

gcloud compute ssl-certificates create cert-self-signed \
  --certificate=cert.pem \
  --private-key=key.pem \
  --global \
  --quiet 2>/dev/null || true

# 2g. Reserve global static IP
echo "${YELLOW}[7/9] Reserving global static IP 'ip-alb-global'...${RESET}"
gcloud compute addresses create ip-alb-global --global --quiet 2>/dev/null || true

ALB_IP=$(gcloud compute addresses describe ip-alb-global \
  --global --format="value(address)" 2>/dev/null)
echo "${BLUE}ALB IP: ${WHITE}$ALB_IP${RESET}"

# 2h. URL map + HTTPS target proxy
echo "${YELLOW}[8/9] Creating URL map and HTTPS proxy...${RESET}"
gcloud compute url-maps create url-map-alb \
  --default-service=service-alb-global \
  --quiet 2>/dev/null || true

gcloud compute target-https-proxies create https-proxy-alb \
  --url-map=url-map-alb \
  --ssl-certificates=cert-self-signed \
  --quiet 2>/dev/null || true

# 2i. Forwarding rule
echo "${YELLOW}[9/9] Creating HTTPS forwarding rule...${RESET}"
gcloud compute forwarding-rules create fr-alb-https \
  --load-balancing-scheme=EXTERNAL_MANAGED \
  --network-tier=PREMIUM \
  --address=$ALB_IP \
  --target-https-proxy=https-proxy-alb \
  --global \
  --ports=443 \
  --quiet 2>/dev/null || true

# 2j. Firewall
echo "${YELLOW}Creating firewall 'fw-allow-health-check-and-proxy'...${RESET}"
gcloud compute firewall-rules create fw-allow-health-check-and-proxy \
  --network=default \
  --allow=tcp:80 \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --target-tags=tag-allow-ssh \
  --quiet 2>/dev/null || true

echo "${GREEN}Task 2 complete${RESET}"
echo

# ===============================
# VERIFICATION
# ===============================
echo "${CYAN}${BOLD}=================================================${RESET}"
echo "${CYAN}${BOLD}   VERIFICATION${RESET}"
echo "${CYAN}${BOLD}=================================================${RESET}"
echo

echo "${YELLOW}Internal Proxy IP:${RESET}"
echo "$INTERNAL_IP"
echo

echo "${YELLOW}External ALB IP:${RESET}"
echo "$ALB_IP"
echo

echo "${YELLOW}MIGs:${RESET}"
gcloud compute instance-groups managed list --format="table(name,region,size)"
echo

echo "${CYAN}${BOLD}=================================================${RESET}"
echo "${CYAN}${BOLD}   AUTOMATED SETUP COMPLETED${RESET}"
echo "${CYAN}${BOLD}=================================================${RESET}"
echo
echo "${WHITE}Now click Check my progress in the lab for:${RESET}"
echo "  - Task 1: Create a regional internal proxy NLB"
echo "  - Task 2: Create global external application load balancer"
echo "  - Task 3: Test failover and global distribution"
echo
echo "${YELLOW}${BOLD}For Task 3 (failover test):${RESET}"
echo "  1. curl -k https://$ALB_IP (repeat 4-5 times, should alternate A/B)"
echo "  2. SSH into mig-alb-api-a VM"
echo "  3. sudo systemctl stop nginx"
echo "  4. Observe failover in Load Balancing console"
echo
