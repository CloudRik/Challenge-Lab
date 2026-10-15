#!/bin/bash
# Build Global and Regional Load Balancing - FULL V12 (FINAL FIXED)
set +e

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

YELLOW='\033[1;33m'; GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
export PROJECT_ID=$(gcloud config get-value project)

echo -e "\033[1;36m"
echo "============================================================"
echo "  🎮 LAB: Build Global & Regional Load Balancing Solutions"
echo "  🎬 Presented By ArcadeSuite"
echo "  📺 YouTube: @imasis-k8x"
echo "============================================================"
echo -e "\033[0m"

# ⚠️ Lab panel se EXACT copy karo
echo -e "${YELLOW}⚠️  Lab panel se Region A aur Region B EXACT copy karo${NC}"
read -p "Enter Region A (check lab panel): " REGION_A
while [ -z "$REGION_A" ]; do
  echo -e "${RED}Region A cannot be empty!${NC}"
  read -p "Enter Region A: " REGION_A
done

read -p "Enter Region B (check lab panel): " REGION_B
while [ -z "$REGION_B" ]; do
  echo -e "${RED}Region B cannot be empty!${NC}"
  read -p "Enter Region B: " REGION_B
done

echo ""
echo -e "${YELLOW}Using Region A = $REGION_A${NC}"
echo -e "${YELLOW}Using Region B = $REGION_B${NC}"
echo ""

read -p "Confirm? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
  echo "Aborting. Re-run with correct regions."
  exit 1
fi

ZONE_B=$(gcloud compute zones list --filter="region:($REGION_B)" --format="value(name)" | sort | head -1)
echo -e "${YELLOW}Zone B = $ZONE_B${NC}"

gcloud config set project $PROJECT_ID -q
gcloud config set compute/region $REGION_B -q

# ============================================================
# TASK 1 : Internal backends + firewall + NLB + client VM
# ============================================================
echo -e "${YELLOW}TASK 1 : Internal backends + firewall + NLB + client VM${NC}"
echo -e "\033[1;35m📺 YouTube: https://youtube.com/@imasis-k8x?si=lO3ixe-KbnN1nNBG\033[0m"

NETWORK=lb-network

# --- SUBNET_B: lb-network me dhundo ---
SUBNET_B=$(gcloud compute networks subnets list --network=$NETWORK \
  --filter="region:($REGION_B) AND purpose!=REGIONAL_MANAGED_PROXY" \
  --format="value(name)" | head -1)

if [ -z "$SUBNET_B" ]; then
  echo -e "${YELLOW}WARNING: lb-network me Region B ka subnet nahi mila. Default check...${NC}"
  SUBNET_B=$(gcloud compute networks subnets list --network=default \
    --filter="region:($REGION_B)" --format="value(name)" | head -1)
  NETWORK="default"
fi

if [ -z "$SUBNET_B" ]; then
  echo -e "${RED}ERROR: Koi bhi subnet nahi mila Region B me!${NC}"
  gcloud compute networks subnets list --format="value(name,region,network)"
  exit 1
fi

echo -e "${GREEN}SUBNET_B = $SUBNET_B${NC}"
echo -e "${GREEN}NETWORK = $NETWORK${NC}"

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

source ~/lab.env

# --- Block 2: internal backends + firewall rules ---
if gcloud compute instance-groups managed describe mig-proxy-internal --region=$REGION_B --quiet 2>/dev/null; then
  gcloud compute instance-groups managed delete mig-proxy-internal --region=$REGION_B -q
  sleep 5
fi
gcloud compute instance-groups managed create mig-proxy-internal \
  --region=$REGION_B --template=$TPL_PROXY --size=2
gcloud compute instance-groups managed set-named-ports mig-proxy-internal \
  --region=$REGION_B --named-ports=tcp80:80

gcloud compute firewall-rules delete fw-allow-hc-proxy-internal -q 2>/dev/null
gcloud compute firewall-rules create fw-allow-hc-proxy-internal \
  --network=$NETWORK --direction=INGRESS --action=allow --rules=tcp:80 \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 --target-tags=tag-proxy-internal

gcloud compute firewall-rules delete fw-allow-proxy-only-subnet -q 2>/dev/null
gcloud compute firewall-rules create fw-allow-proxy-only-subnet \
  --network=$NETWORK --direction=INGRESS --action=allow --rules=tcp:80 \
  --source-ranges=10.129.0.0/23 --target-tags=tag-proxy-internal

echo; echo ">>> Click Check my progress: Create a regional MIG and 2 firewall rules"

# --- Block 3: internal proxy LB + client VM ---
# Proxy-only subnet
gcloud compute networks subnets list --network=$NETWORK \
  --filter="region:($REGION_B) AND purpose:REGIONAL_MANAGED_PROXY" --format="value(name)" | grep -q . \
|| gcloud compute networks subnets create proxy-only-subnet --network=$NETWORK \
  --region=$REGION_B --range=10.129.0.0/23 --purpose=REGIONAL_MANAGED_PROXY --role=ACTIVE

# ============================================================
# 🔧 FIX: SAHI ORDER me delete karo (dependencies ke hisaab se)
# ============================================================
echo "Cleaning up existing resources in correct order..."

# 1) Forwarding rule pehle
gcloud compute forwarding-rules delete rule-internal-proxy --region=$REGION_B -q 2>/dev/null

# 2) TCP proxy
gcloud compute target-tcp-proxies delete tcp-proxy-internal --region=$REGION_B -q 2>/dev/null

# 3) Backend service
gcloud compute backend-services delete service-proxy-internal --region=$REGION_B -q 2>/dev/null

# 4) Health check
gcloud compute health-checks delete tcp-check-internal --region=$REGION_B -q 2>/dev/null

# 5) IP address
gcloud compute addresses delete ip-internal-proxy --region=$REGION_B -q 2>/dev/null

sleep 5

# ============================================================
# AB NAYA BANAO — SAHI ORDER me
# ============================================================
echo "Creating fresh resources..."

# 1) IP address
gcloud compute addresses create ip-internal-proxy --region=$REGION_B \
  --subnet=$SUBNET_B --purpose=SHARED_LOADBALANCER_VIP

# Verify
if gcloud compute addresses describe ip-internal-proxy --region=$REGION_B --quiet 2>/dev/null; then
  echo "[OK] ip-internal-proxy created"
  gcloud compute addresses describe ip-internal-proxy --region=$REGION_B \
    --format="value(address,purpose,subnetwork)"
else
  echo "[FAIL] ip-internal-proxy NOT created!"
  exit 1
fi

# 2) Health check
gcloud compute health-checks create tcp tcp-check-internal --region=$REGION_B --port=80

# 3) Backend service
gcloud compute backend-services create service-proxy-internal --region=$REGION_B \
  --load-balancing-scheme=INTERNAL_MANAGED --protocol=TCP --port-name=tcp80 \
  --health-checks=tcp-check-internal --health-checks-region=$REGION_B

# 4) Add backend
gcloud compute backend-services add-backend service-proxy-internal --region=$REGION_B \
  --instance-group=mig-proxy-internal --instance-group-region=$REGION_B \
  --balancing-mode=UTILIZATION --max-utilization=0.8

# 5) TCP proxy
gcloud compute target-tcp-proxies create tcp-proxy-internal \
  --region=$REGION_B --backend-service=service-proxy-internal

# 6) Forwarding rule
gcloud compute forwarding-rules create rule-internal-proxy --region=$REGION_B \
  --load-balancing-scheme=INTERNAL_MANAGED --network=$NETWORK --subnet=$SUBNET_B \
  --address=ip-internal-proxy --ports=110 \
  --target-tcp-proxy=tcp-proxy-internal --target-tcp-proxy-region=$REGION_B

echo; echo ">>> Click Check my progress: Create a regional internal proxy NLB"

# --- Client VM ---
gcloud compute instances delete vm-client-internal --zone=$ZONE_B -q 2>/dev/null
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
# TASK 2 : Global ALB
# ============================================================
echo -e "${YELLOW}TASK 2 : Global ALB (using default network)${NC}"
echo -e "\033[1;35m📺 YouTube: https://youtube.com/@imasis-k8x?si=lO3ixe-KbnN1nNBG\033[0m"
NETWORK="default"

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

echo ""
echo -e "\033[1;32m"
cat << "EOF"
  _____                      _      _       
 / ____|                    | |    | |      
| |     ___  _ __ ___  _ __ | | ___| |_ ___ 
| |    / _ \| '_ ` _ \| '_ \| |/ _ \ __/ _ \
| |___| (_) | | | | | | |_) | |  __/ ||  __/
 \_____\___/|_| |_| |_| .__/|_|\___|\__\___|
                      | |                    
                      |_|                    
EOF
echo -e "\033[0m"
echo -e "\033[1;33m🎉 ALL TASKS COMPLETED! 🎉\033[0m"
echo -e "\033[1;36m============================================================\033[0m"
echo -e "\033[1;32m🎬 Presented By ArcadeSuite\033[0m"
echo -e "\033[1;35m📺 YouTube: https://youtube.com/@imasis-k8x?si=lO3ixe-KbnN1nNBG\033[0m"
echo -e "\033[1;34m💻 GitHub:  https://github.com/CloudRik\033[0m"
echo -e "\033[1;33m🏆 Arcade Points: https://arcadesuite.pages.dev/\033[0m"
echo -e "\033[1;36m============================================================\033[0m"
echo -e "\033[1;33m⚠️  Please click 'Check my progress' for each task!\033[0m"
echo -e "\033[1;36m============================================================\033[0m"
echo ""
