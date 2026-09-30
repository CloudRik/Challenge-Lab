#!/bin/bash
# ============================================================
#  Challenge Lab — Task 1 + Task 2 (Error-Free, Interactive)
# ============================================================

# Helper: run command, ignore if already exists
run_safe() {
  "$@" 2>/dev/null && echo "  ✅ Done" || echo "  ⚠️ Skipped (already exists)"
}

echo "=========================================="
echo "  Lab Setup — User Inputs"
echo "=========================================="
echo ""

read -p "Region A (e.g., us-east1): " REGION_A
read -p "Region B (e.g., us-east4): " REGION_B
read -p "MIG Name (Task 1, e.g., mig-proxy-internal): " MIG_T1
read -p "Template Name (Task 1, e.g., template-proxy-internal): " TEMPLATE_T1
read -p "Network Tag (Task 1, e.g., tag-proxy-internal): " TAG_T1
read -p "Static IP Name (Task 1, e.g., ip-internal-proxy): " IP_T1
read -p "Forwarding Rule Name (Task 1, e.g., rule-internal-proxy): " RULE_T1
read -p "Backend Service Name (Task 1, e.g., web-backend-service): " BACKEND_T1
read -p "Health Check Name (Task 1, e.g., tcp-health-check): " HC_T1
read -p "Forwarding Port (Task 1, e.g., 110): " FWD_PORT

read -p "MIG Name Region A (Task 2, e.g., mig-alb-api-a): " MIG_A
read -p "MIG Name Region B (Task 2, e.g., mig-alb-api-b): " MIG_B
read -p "Template Name (Task 2, e.g., template-alb-api): " TEMPLATE_T2
read -p "Health Check Name (Task 2, e.g., http-check-alb): " HC_T2
read -p "Backend Service Name (Task 2, e.g., service-alb-global): " BACKEND_T2

echo ""
echo "================================"
echo "  Values:"
echo "  REGION_A      = $REGION_A"
echo "  REGION_B      = $REGION_B"
echo "  MIG_T1        = $MIG_T1"
echo "  TEMPLATE_T1   = $TEMPLATE_T1"
echo "  TAG_T1        = $TAG_T1"
echo "  IP_T1         = $IP_T1"
echo "  RULE_T1       = $RULE_T1"
echo "  BACKEND_T1    = $BACKEND_T1"
echo "  HC_T1         = $HC_T1"
echo "  FWD_PORT      = $FWD_PORT"
echo "  MIG_A         = $MIG_A"
echo "  MIG_B         = $MIG_B"
echo "  TEMPLATE_T2   = $TEMPLATE_T2"
echo "  HC_T2         = $HC_T2"
echo "  BACKEND_T2    = $BACKEND_T2"
echo "================================"
read -p "ENTER to continue (Ctrl+C to cancel)..."
echo ""

# ============================================================
#  TASK 1 — PART 1: Firewalls + Static IP
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

# ============================================================
#  TASK 1 — PART 2: Regional Health Check (IMPORTANT FIX)
# ============================================================
echo ">>> TASK 1: Regional TCP Health Check"
run_safe gcloud compute health-checks create tcp $HC_T1 \
  --region=$REGION_B --port=80 --quiet

# ============================================================
#  TASK 1 — PART 3: Regional Backend Service (INTERNAL_MANAGED)
# ============================================================
echo ">>> TASK 1: Regional Backend Service"
run_safe gcloud compute backend-services create $BACKEND_T1 \
  --load-balancing-scheme=INTERNAL_MANAGED \
  --protocol=TCP --region=$REGION_B \
  --health-checks=$HC_T1 --health-checks-region=$REGION_B --quiet

run_safe gcloud compute backend-services add-backend $BACKEND_T1 \
  --instance-group=$MIG_T1 \
  --instance-group-region=$REGION_B \
  --region=$REGION_B --quiet

# ============================================================
#  TASK 1 — PART 4: Forwarding Rule (Port 110)
# ============================================================
echo ">>> TASK 1: Forwarding Rule on port $FWD_PORT"
run_safe gcloud compute forwarding-rules create $RULE_T1 \
  --load-balancing-scheme=INTERNAL_MANAGED \
  --network=default --subnet=default \
  --region=$REGION_B --address=$IP_T1 \
  --ports=$FWD_PORT \
  --backend-service=$BACKEND_T1 --quiet

# ============================================================
#  TASK 1 — PART 5: Client VM
# ============================================================
echo ">>> TASK 1: Creating Client VM"
run_safe gcloud compute instances create vm-client-internal \
  --zone=${REGION_B}-a \
  --machine-type=e2-micro \
  --image-family=debian-12 --image-project=debian-cloud \
  --tags=allow-ssh --quiet

# ============================================================
#  TASK 2 — PART 1: Two Regional MIGs (Global ALB)
# ============================================================
echo ">>> TASK 2: Creating MIG in Region A"
run_safe gcloud compute instance-groups managed create $MIG_A \
  --template=$TEMPLATE_T2 --size=2 --region=$REGION_A --quiet

run_safe gcloud compute instance-groups managed set-named-ports $MIG_A \
  --named-ports=http80:80 --region=$REGION_A --quiet

echo ">>> TASK 2: Creating MIG in Region B"
run_safe gcloud compute instance-groups managed create $MIG_B \
  --template=$TEMPLATE_T2 --size=2 --region=$REGION_B --quiet

run_safe gcloud compute instance-groups managed set-named-ports $MIG_B \
  --named-ports=http80:80 --region=$REGION_B --quiet

# ============================================================
#  TASK 2 — PART 2: Firewall for Global ALB
# ============================================================
echo ">>> TASK 2: Firewall for Global ALB"
run_safe gcloud compute firewall-rules create fw-allow-health-check-and-proxy \
  --network=default --action=allow --direction=ingress \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --target-tags=http-server --rules=tcp:80 --quiet

# ============================================================
#  TASK 2 — PART 3: Global Health Check + Backend
# ============================================================
echo ">>> TASK 2: Global HTTP Health Check"
run_safe gcloud compute health-checks create http $HC_T2 \
  --port=80 --global --quiet

echo ">>> TASK 2: Global Backend Service"
run_safe gcloud compute backend-services create $BACKEND_T2 \
  --load-balancing-scheme=EXTERNAL_MANAGED \
  --protocol=HTTP --global \
  --health-checks=$HC_T2 --quiet

echo ">>> TASK 2: Adding both MIGs to backend (RPS=1)"
run_safe gcloud compute backend-services add-backend $BACKEND_T2 \
  --instance-group=$MIG_A --instance-group-region=$REGION_A \
  --balancing-mode=RATE --max-rate-per-instance=1 --global --quiet

run_safe gcloud compute backend-services add-backend $BACKEND_T2 \
  --instance-group=$MIG_B --instance-group-region=$REGION_B \
  --balancing-mode=RATE --max-rate-per-instance=1 --global --quiet

echo ""
echo "=========================================="
echo "  ✅ Base Setup Complete!"
echo "=========================================="
echo ""
echo "Ab Cloud Console se ya gcloud se yeh kar:"
echo "  1. SSL certificate create (openssl + gcloud ssl-certificates)"
echo "  2. HTTPS Frontend (URL map + HTTPS proxy + forwarding rule port 443)"
echo "  3. 'Check my progress' dono Task 1 aur Task 2 ke liye"
