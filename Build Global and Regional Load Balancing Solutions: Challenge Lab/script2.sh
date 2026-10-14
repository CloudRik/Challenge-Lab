
#!/bin/bash
# GSP539 - Build Global and Regional Load Balancing Solutions
# Complete single-file script for a fresh Google Skills Boost lab.
# Creates resources when missing; does not delete existing resources.

set -Eeuo pipefail
trap 'echo "ERROR at line $LINENO. Read the error above; do not rerun blindly."; exit 1' ERR

PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != "(unset)" ]] || {
  echo "ERROR: Start the lab and select its project first."
  exit 1
}

read -rp "Enter Region A: " REGION_A
read -rp "Enter Region B: " REGION_B
[[ -n "$REGION_A" && -n "$REGION_B" && "$REGION_A" != "$REGION_B" ]] || {
  echo "ERROR: Enter two different regions."
  exit 1
}

NETWORK="lb-network"
echo "Project=$PROJECT_ID | Region A=$REGION_A | Region B=$REGION_B"
gcloud config set project "$PROJECT_ID" --quiet

# ---------- HELPERS ----------
network_exists() {
  gcloud compute networks describe "$NETWORK" >/dev/null 2>&1
}
subnet_in_region() {
  gcloud compute networks subnets list \
    --format='value(name,region.basename(),network.basename(),purpose)' |
  awk -F '\t' -v r="$1" -v n="$NETWORK" \
    '$2==r && $3==n && $4!="REGIONAL_MANAGED_PROXY" {print $1; exit}'
}
ensure_backend_subnet() {
  local region="$1" cidr="$2" name
  name="$(subnet_in_region "$region")"
  if [[ -z "$name" ]]; then
    name="backend-${region}"
    gcloud compute networks subnets create "$name" \
      --network="$NETWORK" --region="$region" --range="$cidr"
  fi
  printf '%s' "$name"
}
ensure_firewall() {
  local name="$1"; shift
  if ! gcloud compute firewall-rules describe "$name" >/dev/null 2>&1; then
    gcloud compute firewall-rules create "$name" "$@"
  else
    echo "Firewall already exists: $name"
  fi
}
ensure_global_template() {
  local name="$1" tags="$2" startup="$3"
  if ! gcloud compute instance-templates describe "$name" >/dev/null 2>&1; then
    gcloud compute instance-templates create "$name" \
      --machine-type=e2-medium \
      --network="$NETWORK" \
      --tags="$tags" \
      --metadata=startup-script="$startup"
  else
    echo "Instance template already exists: $name"
  fi
}
ensure_regional_mig() {
  local name="$1" region="$2" template="$3" size="$4"
  if ! gcloud compute instance-groups managed describe "$name" \
    --region="$region" >/dev/null 2>&1; then
    gcloud compute instance-groups managed create "$name" \
      --region="$region" --template="$template" --size="$size"
  else
    echo "MIG already exists: $name in $region"
  fi
}

# ---------- NETWORK ----------
if ! network_exists; then
  gcloud compute networks create "$NETWORK" --subnet-mode=custom
fi

SUBNET_A="$(ensure_backend_subnet "$REGION_A" "10.10.1.0/24")"
SUBNET_B="$(ensure_backend_subnet "$REGION_B" "10.10.2.0/24")"
echo "Backend subnet A=$SUBNET_A | B=$SUBNET_B"

# The internal proxy load balancer requires an ACTIVE proxy-only subnet
# in Region B and the same VPC network.
PROXY_SUBNET="$(
  gcloud compute networks subnets list \
    --format='value(name,region.basename(),network.basename(),purpose,role)' |
  awk -F '\t' -v r="$REGION_B" -v n="$NETWORK" \
    '$2==r && $3==n && $4=="REGIONAL_MANAGED_PROXY" && $5=="ACTIVE" {print $1; exit}'
)"

if [[ -z "$PROXY_SUBNET" ]]; then
  if gcloud compute networks subnets describe proxy-only-subnet \
    --region="$REGION_B" >/dev/null 2>&1; then
    echo "ERROR: proxy-only-subnet exists but is not detected as ACTIVE."
    echo "Inspect that subnet in Cloud Console before continuing."
    exit 1
  fi
  gcloud compute networks subnets create proxy-only-subnet \
    --network="$NETWORK" \
    --region="$REGION_B" \
    --range=10.129.0.0/23 \
    --purpose=REGIONAL_MANAGED_PROXY \
    --role=ACTIVE
fi

# ---------- INSTANCE TEMPLATES ----------
ensure_global_template \
  "template-proxy-internal" \
  "tag-proxy-internal" \
  '#!/bin/bash
apt-get update
apt-get install -y nginx
echo "proxy-internal" > /var/www/html/index.html'

ensure_global_template \
  "template-alb-api" \
  "http-server" \
  '#!/bin/bash
apt-get update
apt-get install -y nginx
echo "Hello from $(hostname)" > /var/www/html/index.html'

# ---------- TASK 1.1: REGIONAL MIG + FIREWALLS ----------
echo "=== TASK 1.1: Internal MIG and firewall rules ==="

ensure_regional_mig \
  "mig-proxy-internal" "$REGION_B" "template-proxy-internal" 2

gcloud compute instance-groups managed set-named-ports \
  mig-proxy-internal --region="$REGION_B" --named-ports=tcp80:80

ensure_firewall "fw-allow-proxy-health-check" \
  --network="$NETWORK" \
  --direction=INGRESS --action=ALLOW \
  --rules=tcp:80 \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --target-tags=tag-proxy-internal

ensure_firewall "fw-allow-proxy-only-subnet" \
  --network="$NETWORK" \
  --direction=INGRESS --action=ALLOW \
  --rules=tcp:80 \
  --source-ranges=10.129.0.0/23 \
  --target-tags=tag-proxy-internal

# ---------- TASK 1.2: INTERNAL PROXY NETWORK LOAD BALANCER ----------
echo "=== TASK 1.2: Internal proxy NLB ==="

if ! gcloud compute health-checks describe tcp-check-proxy \
  --region="$REGION_B" >/dev/null 2>&1; then
  gcloud compute health-checks create tcp tcp-check-proxy \
    --region="$REGION_B" --port=80
fi

if ! gcloud compute addresses describe ip-internal-proxy \
  --region="$REGION_B" >/dev/null 2>&1; then
  gcloud compute addresses create ip-internal-proxy \
    --region="$REGION_B" \
    --subnet="$SUBNET_B" \
    --purpose=SHARED_LOADBALANCER_VIP
fi

if ! gcloud compute backend-services describe service-proxy-internal \
  --region="$REGION_B" >/dev/null 2>&1; then
  gcloud compute backend-services create service-proxy-internal \
    --region="$REGION_B" \
    --load-balancing-scheme=INTERNAL_MANAGED \
    --protocol=TCP \
    --health-checks=tcp-check-proxy \
    --health-checks-region="$REGION_B"
fi

if ! gcloud compute backend-services describe service-proxy-internal \
  --region="$REGION_B" --format=json | grep -q 'mig-proxy-internal'; then
  gcloud compute backend-services add-backend service-proxy-internal \
    --region="$REGION_B" \
    --instance-group=mig-proxy-internal \
    --instance-group-region="$REGION_B"
fi

if ! gcloud compute target-tcp-proxies describe proxy-internal \
  --region="$REGION_B" >/dev/null 2>&1; then
  gcloud compute target-tcp-proxies create proxy-internal \
    --region="$REGION_B" \
    --backend-service=service-proxy-internal
fi

if ! gcloud compute forwarding-rules describe rule-internal-proxy \
  --region="$REGION_B" >/dev/null 2>&1; then
  gcloud compute forwarding-rules create rule-internal-proxy \
    --region="$REGION_B" \
    --load-balancing-scheme=INTERNAL_MANAGED \
    --network="$NETWORK" \
    --subnet="$SUBNET_B" \
    --address=ip-internal-proxy \
    --target-tcp-proxy=proxy-internal \
    --target-tcp-proxy-region="$REGION_B" \
    --ports=110
fi

# ---------- TASK 1.3: CLIENT VM ----------
echo "=== TASK 1.3: Client VM ==="

ZONE_B="$(gcloud compute zones list \
  --filter="region:($REGION_B) AND status=UP" \
  --format='value(name)' | head -n 1)"
[[ -n "$ZONE_B" ]] || { echo "ERROR: No available zone in $REGION_B"; exit 1; }

if ! gcloud compute instances describe vm-client-internal \
  --zone="$ZONE_B" >/dev/null 2>&1; then
  gcloud compute instances create vm-client-internal \
    --zone="$ZONE_B" \
    --machine-type=e2-micro \
    --network="$NETWORK" \
    --subnet="$SUBNET_B" \
    --tags=allow-ssh
fi

ensure_firewall "fw-allow-ssh-client" \
  --network="$NETWORK" \
  --direction=INGRESS --action=ALLOW \
  --rules=tcp:22 \
  --source-ranges=35.235.240.0/20 \
  --target-tags=allow-ssh

# ---------- TASK 2.1: TWO REGIONAL MIGS ----------
echo "=== TASK 2.1: Global ALB backend MIGs ==="

ensure_regional_mig "mig-alb-api-a" "$REGION_A" "template-alb-api" 1
gcloud compute instance-groups managed set-named-ports \
  mig-alb-api-a --region="$REGION_A" --named-ports=http80:80

ensure_regional_mig "mig-alb-api-b" "$REGION_B" "template-alb-api" 1
gcloud compute instance-groups managed set-named-ports \
  mig-alb-api-b --region="$REGION_B" --named-ports=http80:80

# ---------- TASK 2.2: GLOBAL BACKEND SERVICE ----------
echo "=== TASK 2.2: Global backend service ==="

if ! gcloud compute health-checks describe http-check-alb \
  --global >/dev/null 2>&1; then
  gcloud compute health-checks create http http-check-alb \
    --port=80 --global
fi

if ! gcloud compute backend-services describe service-alb-global \
  --global >/dev/null 2>&1; then
  gcloud compute backend-services create service-alb-global \
    --protocol=HTTP \
    --health-checks=http-check-alb \
    --global
fi

if ! gcloud compute backend-services describe service-alb-global \
  --global --format=json | grep -q 'mig-alb-api-a'; then
  gcloud compute backend-services add-backend service-alb-global \
    --global \
    --instance-group=mig-alb-api-a \
    --instance-group-region="$REGION_A" \
    --balancing-mode=RATE \
    --max-rate-per-instance=1
fi

if ! gcloud compute backend-services describe service-alb-global \
  --global --format=json | grep -q 'mig-alb-api-b'; then
  gcloud compute backend-services add-backend service-alb-global \
    --global \
    --instance-group=mig-alb-api-b \
    --instance-group-region="$REGION_B" \
    --balancing-mode=RATE \
    --max-rate-per-instance=1
fi

# ---------- TASK 2.3: GLOBAL HTTPS FRONTEND ----------
echo "=== TASK 2.3: Global HTTPS frontend ==="

if ! gcloud compute ssl-certificates describe cert-self-signed \
  --global >/dev/null 2>&1; then
  openssl genrsa -out key.pem 2048
  openssl req -new -x509 -key key.pem -out cert.pem \
    -days 1 -subj "/CN=example.com"
  gcloud compute ssl-certificates create cert-self-signed \
    --certificate=cert.pem --private-key=key.pem --global
fi

if ! gcloud compute addresses describe ip-alb-global \
  --global >/dev/null 2>&1; then
  gcloud compute addresses create ip-alb-global --global
fi

if ! gcloud compute url-maps describe map-alb-global \
  --global >/dev/null 2>&1; then
  gcloud compute url-maps create map-alb-global \
    --default-service=service-alb-global --global
fi

if ! gcloud compute target-https-proxies describe https-proxy-alb-global \
  --global >/dev/null 2>&1; then
  gcloud compute target-https-proxies create https-proxy-alb-global \
    --url-map=map-alb-global \
    --ssl-certificates=cert-self-signed \
    --global
fi

if ! gcloud compute forwarding-rules describe rule-alb-global-https \
  --global >/dev/null 2>&1; then
  gcloud compute forwarding-rules create rule-alb-global-https \
    --global \
    --target-https-proxy=https-proxy-alb-global \
    --address=ip-alb-global \
    --ports=443
fi

# ---------- TASK 2.4: GLOBAL HEALTH-CHECK FIREWALL ----------
ensure_firewall "fw-allow-health-check-and-proxy" \
  --network="$NETWORK" \
  --direction=INGRESS --action=ALLOW \
  --rules=tcp:80 \
  --source-ranges=130.211.0.0/22,35.191.0.0/16

# ---------- SUMMARY ----------
echo
echo "=== RESOURCE SETUP FINISHED ==="
echo "Project: $PROJECT_ID"
echo "Internal load balancer IP:"
gcloud compute addresses describe ip-internal-proxy \
  --region="$REGION_B" --format='value(address)'
echo "Global HTTPS load balancer IP:"
gcloud compute addresses describe ip-alb-global \
  --global --format='value(address)'
echo
echo "Wait a few minutes for VM startup and health checks."
echo "This message confirms commands finished, not that every lab checker passed."
echo "Use Check my progress in the lab for the actual score."
