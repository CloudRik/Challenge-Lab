#!/bin/bash
# ============================================================
#  Challenge Lab — Build Global and Regional Load Balancing
#  Task 1 + Task 2 | Sahi Fixed Script
# ============================================================

run_safe() {
  "$@" 2>/dev/null && echo "  ✅ Done" || echo "  ⚠️ Skipped (already exists)"
}

echo "=========================================="
echo "  Lab Setup — Sirf Region Daalo"
echo "=========================================="
echo ""

read -p "Region A (lab panel se, e.g., us-east4): " REGION_A
read -p "Region B (lab panel se, e.g., europe-west1): " REGION_B

# Fixed names (jo lab mein diye hain)
MIG_T1="mig-proxy-internal"
TEMPLATE_T1="template-proxy-internal"
TAG_T1="tag-proxy-internal"
IP_T1="ip-internal-proxy"
RULE_T1="rule-internal-proxy"
BACKEND_T1="web-backend-service"
HC_T1="tcp-health-check"
FWD_PORT="110"

MIG_A="mig-alb-api-a"
MIG_B="mig-alb-api-b"
TEMPLATE_T2="template-alb-api"
HC_T2="http-check-alb"
BACKEND_T2="service-alb-global"
IP_T2="ip-alb-global"
CERT_T2="cert-self-signed"

echo ""
echo "Region A = $REGION_A"
echo "Region B = $REGION_B"
echo "Baaki saare naam lab ke hisaab se set hain."
read -p "ENTER to continue (Ctrl+C to cancel)..."
echo ""

# ============================================================
#  TASK 1 — Firewalls + Static IP + Template + MIG
# ============================================================
echo ">>> TASK 1: Firewall Rules + Static IP"

run_safe gcloud compute firewall-rules create fw-allow-health-check \
  --network=default --action=allow --direction=ingress \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --target-tags=$TAG_T1 --rules=tcp:80 --quiet

run_safe gcloud compute firewall-rules create fw-allow-proxy-only-subnet \
  --network=default --action=allow --direction=ingress \
  --source-ranges=10.129.0.0/23 \
  --target-tags=$TAG_T1 --rules=tcp:80 --quiet

run_safe gcloud compute addresses create $IP_T1 \
  --region=$REGION_B --subnet=default \
  --purpose=SHARED_LOADBALANCER_VIP --quiet

echo ">>> TASK 1: Instance Template"
run_safe gcloud compute instance-templates create $TEMPLATE_T1 \
  --network=default --subnet=default \
  --region=$REGION_B \
  --tags=$TAG_T1 \
  --machine-type=e2-medium \
  --image-family=debian-12 --image-project=debian-cloud \
  --metadata=startup-script='#! /bin/bash
  apt-get update
  apt-get install -y nginx
  service nginx restart' --quiet

echo ">>> TASK 1: Regional MIG"
run_safe gcloud compute instance-groups managed create $MIG_T1 \
  --template=$TEMPLATE_T1 --size=1 --region=$REGION_B --quiet

run_safe gcloud compute instance-groups managed set-named-ports $MIG_T1 \
  --named-ports=tcp80:80 --region=$REGION_B --quiet

echo ">>> TASK 1: Regional TCP Health Check"
run_safe gcloud compute health-checks create tcp $HC_T1 \
  --region=$REGION_B --port=80 --quiet

echo ">>> TASK 1: Regional Backend Service"
run_safe gcloud compute backend-services create $BACKEND_T1 \
  --load-balancing-scheme=INTERNAL_MANAGED \
  --protocol=TCP --region=$REGION_B \
  --health-checks=$HC_T1 --health-checks-region=$REGION_B --quiet

run_safe gcloud compute backend-services add-backend $BACKEND_T1 \
  --instance-group=$MIG_T1 \
  --instance-group-region=$REGION_B \
  --region=$REGION_B --quiet

echo ">>> TASK 1: Forwarding Rule (Port $FWD_PORT)"
run_safe gcloud compute forwarding-rules create $RULE_T1 \
  --load-balancing-scheme=INTERNAL_MANAGED \
  --network=default --subnet=default \
  --region=$REGION_B --address=$IP_T1 \
  --ports=$FWD_PORT \
  --backend-service=$BACKEND_T1 --quiet

echo ">>> TASK 1: Client VM"
run_safe gcloud compute instances create vm-client-internal \
  --zone=${REGION_B}-a \
  --machine-type=e2-micro \
  --image-family=debian-12 --image-project=debian-cloud \
  --tags=allow-ssh --quiet

# ============================================================
#  TASK 2 — Template + 2 MIGs + Global ALB + HTTPS
# ============================================================
echo ">>> TASK 2: Instance Template"
run_safe gcloud compute instance-templates create $TEMPLATE_T2 \
  --network=default --subnet=default \
  --region=$REGION_A \
  --tags=http-server \
  --machine-type=e2-medium \
  --image-family=debian-12 --image-project=debian-cloud \
  --metadata=startup-script='#! /bin/bash
  apt-get update
  apt-get install -y nginx
  service nginx restart' --quiet

echo ">>> TASK 2: MIG Region A"
run_safe gcloud compute instance-groups managed create $MIG_A \
  --template=$TEMPLATE_T2 --size=2 --region=$REGION_A --quiet
run_safe gcloud compute instance-groups managed set-named-ports $MIG_A \
  --named-ports=http80:80 --region=$REGION_A --quiet

echo ">>> TASK 2: MIG Region B"
run_safe gcloud compute instance-groups managed create $MIG_B \
  --template=$TEMPLATE_T2 --size=2 --region=$REGION_B --quiet
run_safe gcloud compute instance-groups managed set-named-ports $MIG_B \
  --named-ports=http80:80 --region=$REGION_B --quiet

echo ">>> TASK 2: Firewall for Global ALB"
run_safe gcloud compute firewall-rules create fw-allow-health-check-and-proxy \
  --network=default --action=allow --direction=ingress \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --target-tags=http-server --rules=tcp:80 --quiet

echo ">>> TASK 2: Global HTTP Health Check"
run_safe gcloud compute health-checks create http $HC_T2 \
  --port=80 --global --quiet

echo ">>> TASK 2: Global Backend Service"
run_safe gcloud compute backend-services create $BACKEND_T2 \
  --load-balancing-scheme=EXTERNAL_MANAGED \
  --protocol=HTTP --global \
  --health-checks=$HC_T2 --quiet

echo ">>> TASK 2: Add both MIGs to backend"
run_safe gcloud compute backend-services add-backend $BACKEND_T2 \
  --instance-group=$MIG_A --instance-group-region=$REGION_A \
  --balancing-mode=RATE --max-rate-per-instance=1 --global --quiet

run_safe gcloud compute backend-services add-backend $BACKEND_T2 \
  --instance-group=$MIG_B --instance-group-region=$REGION_B \
  --balancing-mode=RATE --max-rate-per-instance=1 --global --quiet

echo ">>> TASK 2: Global Static IP"
run_safe gcloud compute addresses create $IP_T2 --global --quiet

echo ">>> TASK 2: SSL Certificate"
openssl genrsa -out key.pem 2048
openssl req -new -x509 -key key.pem -out cert.pem -days 1 -subj "/CN=example.com"

run_safe gcloud compute ssl-certificates create $CERT_T2 \
  --certificate=cert.pem --private-key=key.pem --global --quiet

echo ">>> TASK 2: URL Map"
run_safe gcloud compute url-maps create web-map-https \
  --default-service=$BACKEND_T2 --quiet

echo ">>> TASK 2: HTTPS Proxy"
run_safe gcloud compute target-https-proxies create https-proxy \
  --url-map=web-map-https --ssl-certificates=$CERT_T2 --quiet

echo ">>> TASK 2: Forwarding Rule HTTPS (Port 443)"
run_safe gcloud compute forwarding-rules create https-content-rule \
  --address=$IP_T2 --global \
  --target-https-proxy=https-proxy --ports=443 --quiet

echo ""
echo "=========================================="
echo "  ✅ Full Setup Complete!"
echo "=========================================="
echo ""
echo "Ab lab panel mein 'Check my progress' click karo:"
echo "  1. Task 1 ke liye"
echo "  2. Task 2 ke liye"
echo ""
echo "Agar score na aaye to browser refresh karo ya incognito use karo."
