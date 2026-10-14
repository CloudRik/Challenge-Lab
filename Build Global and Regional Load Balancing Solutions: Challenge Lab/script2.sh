#!/bin/bash
# Build Global and Regional Load Balancing - Universal Automated Script
# Input Based - No Hardcoded Project

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
set -e

echo -e "${YELLOW}=== Challenge Lab Automation - Load Balancing ===${NC}"

# --- INPUTS ---
export PROJECT_ID=$(gcloud config get-value project)
echo -e "Detected Project: ${GREEN}$PROJECT_ID${NC}"

read -p "Enter Region A [default: us-east4]: " REGION_A
REGION_A=${REGION_A:-us-east4}
read -p "Enter Region B [default: europe-west4]: " REGION_B
REGION_B=${REGION_B:-europe-west4}
read -p "Enter Zone for Region B VM [default: ${REGION_B}-a]: " ZONE_B
ZONE_B=${ZONE_B:-${REGION_B}-a}

read -p "Enter Zone for Region A VM [default: ${REGION_A}-a]: " ZONE_A
ZONE_A=${ZONE_A:-${REGION_A}-a}

echo -e "${GREEN}Using Region A: $REGION_A, Region B: $REGION_B${NC}"

# --- AUTO DISCOVER NETWORK ---
NETWORK=$(gcloud compute networks list --format="value(name)" | head -n1)
echo "Detected Network: $NETWORK"

# Proxy only subnet - CIDR 10.129.0.0/23 wala
PROXY_SUBNET=$(gcloud compute networks subnets list --regions=$REGION_B --filter="ipCidrRange=10.129.0.0/23" --format="value(name)" | head -n1)
if [ -z "$PROXY_SUBNET" ]; then
  PROXY_SUBNET=$(gcloud compute networks subnets list --filter="purpose:REGIONAL_MANAGED_PROXY" --format="value(name)" | head -n1)
fi
echo "Proxy Subnet: $PROXY_SUBNET"

# Normal subnet for client VM
CLIENT_SUBNET=$(gcloud compute networks subnets list --regions=$REGION_B --format="value(name)" --filter="purpose!=REGIONAL_MANAGED_PROXY" | head -n1)
echo "Client Subnet: $CLIENT_SUBNET"

gcloud config set project $PROJECT_ID
gcloud config set compute/region $REGION_B

# ================= TASK 1 =================
echo -e "${YELLOW}--- TASK 1: Internal Proxy NLB ---${NC}"

echo "Creating MIG mig-proxy-internal..."
gcloud compute instance-groups managed create mig-proxy-internal \
  --template=template-proxy-internal \
  --size=2 --region=$REGION_B || echo "MIG may already exist"

gcloud compute instance-groups managed set-named-ports mig-proxy-internal \
  --region=$REGION_B --named-ports=tcp80:80

echo "Creating Firewall Rules for proxy..."
gcloud compute firewall-rules create fw-allow-proxy-health-check \
  --network=$NETWORK --action=allow --direction=INGRESS \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --target-tags=tag-proxy-internal --rules=tcp:80 || true

gcloud compute firewall-rules create fw-allow-proxy-only-subnet \
  --network=$NETWORK --action=allow --direction=INGRESS \
  --source-ranges=10.129.0.0/23 \
  --target-tags=tag-proxy-internal --rules=tcp:80 || true

echo "Reserving Internal IP ip-internal-proxy..."
gcloud compute addresses create ip-internal-proxy \
  --region=$REGION_B --subnet=$PROXY_SUBNET --purpose=SHARED_LOADBALANCER_VIP || true

echo "Creating Backend Service, Target TCP Proxy, Forwarding Rule for Internal Proxy..."
gcloud compute health-checks create tcp tcp-check-proxy --port=80 --region=$REGION_B || true

gcloud compute backend-services create service-proxy-internal \
  --load-balancing-scheme=INTERNAL_MANAGED --protocol=TCP \
  --health-checks=tcp-check-proxy --health-checks-region=$REGION_B \
  --region=$REGION_B || true

gcloud compute backend-services add-backend service-proxy-internal \
  --instance-group=mig-proxy-internal --instance-group-region=$REGION_B \
  --region=$REGION_B || true

gcloud compute target-tcp-proxies create proxy-internal \
  --backend-service=service-proxy-internal --region=$REGION_B || true

gcloud compute forwarding-rules create rule-internal-proxy \
  --region=$REGION_B --load-balancing-scheme=INTERNAL_MANAGED \
  --network=$NETWORK --subnet=$CLIENT_SUBNET \
  --address=ip-internal-proxy --target-tcp-proxy=proxy-internal \
  --target-tcp-proxy-region=$REGION_B --ports=110 --ip-protocol=TCP || true

# ================= TASK 2 =================
echo -e "${YELLOW}--- TASK 2: Global External ALB ---${NC}"

echo "Creating MIGs mig-alb-api-a and mig-alb-api-b..."
gcloud compute instance-groups managed create mig-alb-api-a \
  --template=template-alb-api --size=1 --region=$REGION_A || true
gcloud compute instance-groups managed set-named-ports mig-alb-api-a \
  --region=$REGION_A --named-ports=http80:80 || true

gcloud compute instance-groups managed create mig-alb-api-b \
  --template=template-alb-api --size=1 --region=$REGION_B || true
gcloud compute instance-groups managed set-named-ports mig-alb-api-b \
  --region=$REGION_B --named-ports=http80:80 || true

echo "Creating Health Check and Backend Service..."
gcloud compute health-checks create http http-check-alb --port=80 --global || true
gcloud compute backend-services create service-alb-global \
  --protocol=HTTP --health-checks=http-check-alb --global || true

gcloud compute backend-services add-backend service-alb-global \
  --instance-group=mig-alb-api-a --instance-group-region=$REGION_A \
  --balancing-mode=RATE --max-rate-per-instance=1 --global || true

gcloud compute backend-services add-backend service-alb-global \
  --instance-group=mig-alb-api-b --instance-group-region=$REGION_B \
  --balancing-mode=RATE --max-rate-per-instance=1 --global || true

echo "Creating SSL Cert..."
openssl genrsa -out key.pem 2048
openssl req -new -x509 -key key.pem -out cert.pem -days 1 -subj "/CN=example.com"
gcloud compute ssl-certificates create cert-self-signed \
  --certificate=cert.pem --private-key=key.pem --global || true

echo "Creating Global IP and Frontend..."
gcloud compute addresses create ip-alb-global --global || true
gcloud compute url-maps create map-alb-global --default-service=service-alb-global --global || true
gcloud compute target-https-proxies create https-proxy-alb-global \
  --url-map=map-alb-global --ssl-certificates=cert-self-signed --global || true

gcloud compute forwarding-rules create rule-alb-global-https \
  --global --target-https-proxy=https-proxy-alb-global \
  --address=ip-alb-global --ports=443 || true

echo "Creating Firewall fw-allow-health-check-and-proxy..."
gcloud compute firewall-rules create fw-allow-health-check-and-proxy \
  --network=$NETWORK --action=allow --direction=INGRESS \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 --rules=tcp:80 || true

# ================= TASK 3 & VALIDATION VM =================
echo -e "${YELLOW}--- Creating Client VM for Validation ---${NC}"
gcloud compute instances create vm-client-internal \
  --zone=$ZONE_B --machine-type=e2-micro \
  --network-interface=network=$NETWORK,subnet=$CLIENT_SUBNET \
  --tags=allow-ssh --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install -y nginx
' || true

echo -e "${GREEN}=== ALL DONE ===${NC}"
echo "Ab skills.google pe jaake 'Check my progress' dabao"
echo "Region A: $REGION_A | Region B: $REGION_B | Project: $PROJECT_ID"
