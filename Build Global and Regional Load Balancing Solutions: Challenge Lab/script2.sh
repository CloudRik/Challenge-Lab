#!/bin/bash
# Build Global and Regional Load Balancing - FULL V9
# Task 1 = naya code (lb-network) | Task 2 = purana code (default network)
set +e

YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
export PROJECT_ID=$(gcloud config get-value project)

# ============================================================
# USER INPUT
# ============================================================
read -p "Enter Region A [default: us-west1]: " REGION_A
REGION_A=${REGION_A:-us-west1}
read -p "Enter Region B [default: us-east4]: " REGION_B
REGION_B=${REGION_B:-us-east4}

ZONE_A="${REGION_A}-a"
ZONE_B="${REGION_B}-a"
echo -e "${YELLOW}Using A=$REGION_A ($ZONE_A) | B=$REGION_B ($ZONE_B)${NC}"

gcloud config set project $PROJECT_ID -q
gcloud config set compute/region $REGION_B -q

# ============================================================
# TASK 1 : NEW CODE (lb-network)
# ============================================================
echo -e "${YELLOW}TASK 1 (NEW) : Internal backends + firewall + NLB + client VM${NC}"

NETWORK=lb-network

# --- lab.env derive ---
[ -z "$REGION_B" ] && REGION_B=$(gcloud compute networks subnets list --network=$NETWORK --filter="purpose:REGIONAL_MANAGED_PROXY" --format="value(region.basename())" | head -1)
[ -z "$REGION_B" ] && REGION_B=$(gcloud compute instance-templates list --filter="name=template-proxy-internal" --format="value(region.basename())" | head -1)
[ -z "$REGION_A" ] && REGION_A=$(gcloud compute networks subnets list --network=$NETWORK --filter="NOT purpose:REGIONAL_MANAGED_PROXY" --format="value(region.basename())" | sort -u | grep -vx "$REGION_B" | head -1)
SUBNET_B=$(gcloud compute networks subnets list --network=$NETWORK --filter="region:($REGION_B) AND NOT purpose:REGIONAL_MANAGED_PROXY" --format="value(name)" | head -1)
ZONE_B=$(gcloud compute zones list --filter="region:($REGION_B)" --format="value(name)" | sort | head -1)
TPL_PROXY=$(gcloud compute instance-templates list --filter="name=template-proxy-internal" --format="value(selfLink)" | head -1)
TPL_ALB=$(gcloud compute instance-templates list --filter="name=template-alb-api" --format="value(selfLink)" | head -1)

cat > ~/lab.env <<EOF
export PROJECT_ID=$PROJECT_ID
export NETWORK=$NETWORK
export REGION_A=$REGION_A
export REGION_B=$REGION_B
export SUBNET_B=$SUBNET_B
export ZONE_B=$ZONE_B
export TPL_PROXY=$TPL_PROXY
export TPL_ALB=$TPL_ALB
EOF
echo; echo "===== YOUR LAB VALUES ====="; cat ~/lab.env

# --- Block 2: internal backends + firewall rules ---
source ~/lab.env

gcloud compute instance-groups managed create mig-proxy-internal \
  --region=$REGION_B --template=$TPL_PROXY --size=2
gcloud compute instance-groups managed set-named-ports mig-proxy-internal \
  --region=$REGION_B --named-ports=tcp80:80

gcloud compute firewall-rules create fw-allow-hc-proxy-internal \
  --network=$NETWORK --direction=INGRESS --action=allow --rules=tcp:80 \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 --target-tags=tag-proxy-internal

gcloud compute firewall-rules create fw-allow-proxy-only-subnet \
  --network=$NETWORK --direction=INGRESS --action=allow --rules=tcp:80 \
  --source-ranges=10.129.0.0/23 --target-tags=tag-proxy-internal

echo; echo ">>> Click Check my progress: Create a regional MIG and 2 firewall rules"

# --- Block 3: internal proxy LB + client VM ---
source ~/lab.env

gcloud compute networks subnets list --network=$NETWORK \
  --filter="region:($REGION_B) AND purpose:REGIONAL_MANAGED_PROXY" --format="value(name)" | grep -q . \
|| gcloud compute networks subnets create proxy-only-subnet --network=$NETWORK \
  --region=$REGION_B --range=10.129.0.0/23 --purpose=REGIONAL_MANAGED_PROXY --role=ACTIVE

gcloud compute addresses create ip-internal-proxy --region=$REGION_B \
  --subnet=$SUBNET_B --purpose=SHARED_LOADBALANCER_VIP

gcloud compute health-checks create tcp tcp-check-internal --region=$REGION_B --port=80

gcloud compute backend-services create service-proxy-internal --region=$REGION_B \
  --load-balancing-scheme=INTERNAL_MANAGED --protocol=TCP --port-name=tcp80 \
  --health-checks=tcp-check-internal --health-checks-region=$REGION_B
gcloud compute backend-services add-backend service-proxy-internal --region=$REGION_B \
  --instance-group=mig-proxy-internal --instance-group-region=$REGION_B \
  --balancing-mode=UTILIZATION --max-utilization=0.8

gcloud compute target-tcp-proxies create tcp-proxy-internal \
  --region=$REGION_B --backend-service=service-proxy-internal

gcloud compute forwarding-rules create rule-internal-proxy --region=$REGION_B \
  --load-balancing-scheme=INTERNAL_MANAGED --network=$NETWORK --subnet=$SUBNET_B \
  --address=ip-internal-proxy --ports=110 \
  --target-tcp-proxy=tcp-proxy-internal --target-tcp-proxy-region=$REGION_B

echo; echo ">>> Click Check my progress: Create a regional internal proxy NLB"

gcloud compute instances create vm-client-internal --zone=$ZONE_B \
  --network=$NETWORK --subnet=$SUBNET_B --tags=allow-ssh \
  --machine-type=e2-small --image-family=debian-12 --image-project=debian-cloud

INTERNAL_IP=$(gcloud compute addresses describe ip-internal-proxy --region=$REGION_B --format="value(address)")
echo "Testing http://$INTERNAL_IP:110 from vm-client-internal ..."
for i in $(seq 15); do
  OUT=$(gcloud compute ssh vm-client-internal --zone=$ZONE_B --quiet --command="curl -s --max-time 5 http://$INTERNAL_IP:110" 2>/dev/null \
     || gcloud compute ssh vm-client-internal --zone=$ZONE_B --quiet --tunnel-through-iap --command="curl -s --max-time 5 http://$INTERNAL_IP:110" 2>/dev/null)
  [ -n "$OUT" ] && { echo "$OUT" | head -5; echo "LB reachable on $INTERNAL_IP:110"; break; }
  echo "  not ready yet ($i/15), waiting 20s..."; sleep 20
done

echo; echo ">>> Click Check my progress: Deploy a client VM and validate the access"

# ============================================================
# TASK 2 : UNCHANGED CONTENT, but NETWORK = default (fix)
# ============================================================
echo -e "${YELLOW}TASK 2 : Global ALB (using default network)${NC}"

NETWORK="default"          # <-- FIX: Task 2 default network pe chalega

# --- Agar template exist nahi karta to khud banao ---
check_template() {
  if ! gcloud compute instance-templates describe $1 --quiet 2>/dev/null; then
    echo "Template $1 not found, creating it..."
    if [[ $1 == *"proxy-internal"* ]]; then
      gcloud compute instance-templates create $1 --machine-type=e2-medium --network=$NETWORK --tags=tag-proxy-internal,allow-ssh --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install -y nginx
echo "proxy-internal" > /var/www/html/index.html
'
    else
      gcloud compute instance-templates create $1 --machine-type=e2-medium --network=$NETWORK --tags=allow-ssh,http-server --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install -y nginx
HOSTNAME=$(hostname)
echo "Hello from $HOSTNAME" > /var/www/html/index.html
'
    fi
  fi
}

check_template template-proxy-internal
check_template template-alb-api

sleep 10

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

echo -e "${GREEN}All Tasks Created! Wait 3 mins then Check Progress.${NC}"
