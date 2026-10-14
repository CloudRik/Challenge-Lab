#!/bin/bash
# Build Global and Regional Load Balancing - FULL V7 - Auto Create Missing Resources
# Region A: us-west1, Region B: us-east4
set +e

YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
export PROJECT_ID=$(gcloud config get-value project)

read -p "Enter Region A [default: us-west1]: " REGION_A
REGION_A=${REGION_A:-us-west1}
read -p "Enter Region B [default: us-east4]: " REGION_B
REGION_B=${REGION_B:-us-east4}

ZONE_A="${REGION_A}-a"
ZONE_B="${REGION_B}-a"
echo -e "${YELLOW}Using A=$REGION_A ($ZONE_A) | B=$REGION_B ($ZONE_B)${NC}"

NETWORK="default"
PROXY_SUBNET=$(gcloud compute networks subnets list --filter="purpose=REGIONAL_MANAGED_PROXY" --format="value(name)" | head -n1)
[ -z "$PROXY_SUBNET" ] && PROXY_SUBNET="proxy-subnet-internal"
CLIENT_SUBNET=$(gcloud compute networks subnets list --filter="region:$REGION_B AND purpose!=REGIONAL_MANAGED_PROXY" --format="value(name)" | head -n1)
[ -z "$CLIENT_SUBNET" ] && CLIENT_SUBNET="default"

echo "Network=$NETWORK Client=$CLIENT_SUBNET Proxy=$PROXY_SUBNET"

gcloud config set project $PROJECT_ID -q
gcloud config set compute/region $REGION_B -q

# --- FIX 1: Agar template exist nahi karta to khud banao ---
check_template() {
  if ! gcloud compute instance-templates describe $1 --quiet 2>/dev/null; then
    echo "Template $1 not found, creating it..."
    if [[ $1 == *"proxy-internal"* ]]; then
      gcloud compute instance-templates create $1 --machine-type=e2-medium --network=$NETWORK --tags=tag-proxy-internal,allow-ssh --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install -y nginx
echo "proxy-internal" > /var/www/html/index.html
' --region=$REGION_B 2>/dev/null || gcloud compute instance-templates create $1 --machine-type=e2-medium --network=$NETWORK --tags=tag-proxy-internal --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install -y nginx' 
    else
      gcloud compute instance-templates create $1 --machine-type=e2-medium --network=$NETWORK --tags=allow-ssh,http-server --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install -y nginx
HOSTNAME=$(hostname)
echo "Hello from $HOSTNAME" > /var/www/html/index.html
' --region=$REGION_A 2>/dev/null || gcloud compute instance-templates create $1 --machine-type=e2-medium --network=$NETWORK --tags=allow-ssh --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install -y nginx'
    fi
  fi
}

check_template template-proxy-internal
check_template template-alb-api

sleep 10

# --- TASK 1.1: MIG + Firewall ---
echo -e "${YELLOW}TASK 1.1 MIG + 2 Firewall${NC}"
gcloud compute instance-groups managed delete mig-proxy-internal --region=$REGION_B -q 2>/dev/null; sleep 5
gcloud compute instance-groups managed create mig-proxy-internal --template=template-proxy-internal --size=2 --region=$REGION_B
gcloud compute instance-groups managed set-named-ports mig-proxy-internal --region=$REGION_B --named-ports=tcp80:80

gcloud compute firewall-rules delete fw-allow-proxy-health-check -q 2>/dev/null
gcloud compute firewall-rules create fw-allow-proxy-health-check --network=$NETWORK --allow=tcp:80 --source-ranges=130.211.0.0/22,35.191.0.0/16 --target-tags=tag-proxy-internal

gcloud compute firewall-rules delete fw-allow-proxy-only-subnet -q 2>/dev/null
gcloud compute firewall-rules create fw-allow-proxy-only-subnet --network=$NETWORK --allow=tcp:80 --source-ranges=10.129.0.0/23 --target-tags=tag-proxy-internal

# --- TASK 1.2: Internal Proxy NLB ---
echo -e "${YELLOW}TASK 1.2 Internal Proxy NLB${NC}"
gcloud compute addresses delete ip-internal-proxy --region=$REGION_B -q 2>/dev/null
# FIX: IP ko CLIENT subnet me banao, proxy me nahi
gcloud compute addresses create ip-internal-proxy --region=$REGION_B --subnet=$CLIENT_SUBNET --purpose=SHARED_LOADBALANCER_VIP

gcloud compute health-checks create tcp tcp-check-proxy --port=80 --region=$REGION_B 2>/dev/null
gcloud compute backend-services delete service-proxy-internal --region=$REGION_B -q 2>/dev/null
gcloud compute backend-services create service-proxy-internal --load-balancing-scheme=INTERNAL_MANAGED --protocol=TCP --health-checks=tcp-check-proxy --health-checks-region=$REGION_B --region=$REGION_B
gcloud compute backend-services add-backend service-proxy-internal --instance-group=mig-proxy-internal --instance-group-region=$REGION_B --region=$REGION_B

gcloud compute target-tcp-proxies delete proxy-internal --region=$REGION_B -q 2>/dev/null
gcloud compute target-tcp-proxies create proxy-internal --backend-service=service-proxy-internal --region=$REGION_B

gcloud compute forwarding-rules delete rule-internal-proxy --region=$REGION_B -q 2>/dev/null
gcloud compute forwarding-rules create rule-internal-proxy --region=$REGION_B --load-balancing-scheme=INTERNAL_MANAGED --network=$NETWORK --subnet=$CLIENT_SUBNET --address=ip-internal-proxy --target-tcp-proxy=proxy-internal --target-tcp-proxy-region=$REGION_B --ports=110

# --- TASK 1.3: Client VM ---
gcloud compute instances delete vm-client-internal --zone=$ZONE_B -q 2>/dev/null
gcloud compute instances create vm-client-internal --zone=$ZONE_B --machine-type=e2-micro --network-interface=network=$NETWORK,subnet=$CLIENT_SUBNET --tags=allow-ssh

# --- TASK 2.1: Two MIGs ---
echo -e "${YELLOW}TASK 2.1 Global Backends${NC}"
gcloud compute instance-groups managed delete mig-alb-api-a --region=$REGION_A -q 2>/dev/null
gcloud compute instance-groups managed create mig-alb-api-a --template=template-alb-api --size=1 --region=$REGION_A
gcloud compute instance-groups managed set-named-ports mig-alb-api-a --region=$REGION_A --named-ports=http80:80

gcloud compute instance-groups managed delete mig-alb-api-b --region=$REGION_B -q 2>/dev/null
gcloud compute instance-groups managed create mig-alb-api-b --template=template-alb-api --size=1 --region=$REGION_B
gcloud compute instance-groups managed set-named-ports mig-alb-api-b --region=$REGION_B --named-ports=http80:80

# --- TASK 2.2: Backend Components ---
gcloud compute health-checks create http http-check-alb --port=80 --global 2>/dev/null
gcloud compute backend-services create service-alb-global --protocol=HTTP --health-checks=http-check-alb --global 2>/dev/null
gcloud compute backend-services add-backend service-alb-global --instance-group=mig-alb-api-a --instance-group-region=$REGION_A --balancing-mode=RATE --max-rate-per-instance=1 --global 2>/dev/null
gcloud compute backend-services add-backend service-alb-global --instance-group=mig-alb-api-b --instance-group-region=$REGION_B --balancing-mode=RATE --max-rate-per-instance=1 --global 2>/dev/null

# --- TASK 2.3: Frontend ---
echo "Creating SSL cert..."
rm -f key.pem cert.pem
openssl genrsa -out key.pem 2048 2>/dev/null
openssl req -new -x509 -key key.pem -out cert.pem -days 1 -subj "/CN=example.com" 2>/dev/null
gcloud compute ssl-certificates create cert-self-signed --certificate=cert.pem --private-key=key.pem --global 2>/dev/null

gcloud compute addresses create ip-alb-global --global 2>/dev/null
gcloud compute url-maps create map-alb-global --default-service=service-alb-global --global 2>/dev/null
gcloud compute target-https-proxies create https-proxy-alb-global --url-map=map-alb-global --ssl-certificates=cert-self-signed --global 2>/dev/null
gcloud compute forwarding-rules create rule-alb-global-https --global --target-https-proxy=https-proxy-alb-global --address=ip-alb-global --ports=443 2>/dev/null

# --- TASK 2.4: Firewall ---
gcloud compute firewall-rules create fw-allow-health-check-and-proxy --network=$NETWORK --allow=tcp:80 --source-ranges=130.211.0.0/22,35.191.0.0/16 2>/dev/null

echo -e "${GREEN}All Tasks Created! Wait 3 mins then Check Progress. For Task 3 failover, run: sudo systemctl stop nginx inside mig-alb-api-a VM${NC}"
