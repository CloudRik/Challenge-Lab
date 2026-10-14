
#!/bin/bash
# GSP539 - Build Global and Regional Load Balancing Solutions
# Current lab: Region A=us-east1, Region B=us-west1
# Uses existing lb-network and backend/proxy subnets.

set -Eeuo pipefail
trap 'echo "FAILED at line $LINENO. Script stopped; inspect the error above."' ERR

PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
REGION_A="us-east1"
REGION_B="us-west1"
NETWORK="lb-network"
SUBNET_A="lb-backend-subnet-region-a"
SUBNET_B="lb-backend-subnet-region-b"
PROXY_SUBNET="proxy-subnet-internal"

[[ -n "$PROJECT_ID" && "$PROJECT_ID" != "(unset)" ]] || {
  echo "ERROR: Start the Skills Boost lab first."
  exit 1
}

gcloud config set project "$PROJECT_ID" --quiet
echo "Project=$PROJECT_ID | A=$REGION_A | B=$REGION_B"

# Verify the lab network and required subnets.
gcloud compute networks describe "$NETWORK" >/dev/null
gcloud compute networks subnets describe "$SUBNET_A" --region="$REGION_A" >/dev/null
gcloud compute networks subnets describe "$SUBNET_B" --region="$REGION_B" >/dev/null
gcloud compute networks subnets describe "$PROXY_SUBNET" --region="$REGION_B" >/dev/null

# Create a template only when missing. Templates are global resources.
ensure_template() {
  local name="$1" subnet="$2" tags="$3" startup="$4"
  if ! gcloud compute instance-templates describe "$name" >/dev/null 2>&1; then
    gcloud compute instance-templates create "$name" \
      --machine-type=e2-medium \
      --network="$NETWORK" \
      --subnet="$subnet" \
      --tags="$tags" \
      --metadata=startup-script="$startup"
  else
    echo "Keeping existing template: $name"
  fi
}

ensure_mig() {
  local name="$1" region="$2" template="$3" size="$4"
  if ! gcloud compute instance-groups managed describe "$name" \
    --region="$region" >/dev/null 2>&1; then
    gcloud compute instance-groups managed create "$name" \
      --region="$region" --template="$template" --size="$size"
  else
    echo "Keeping existing MIG: $name ($region)"
  fi
}

ensure_firewall() {
  local name="$1"; shift
  if ! gcloud compute firewall-rules describe "$name" >/dev/null 2>&1; then
    gcloud compute firewall-rules create "$name" "$@"
  else
    echo "Keeping existing firewall: $name"
  fi
}

# Templates
ensure_template "template-proxy-internal" "$SUBNET_B" \
  "tag-proxy-internal" \
  '#!/bin/bash
apt-get update
apt-get install -y nginx
echo proxy-internal > /var/www/html/index.html'

ensure_template "template-alb-api-a" "$SUBNET_A" \
  "http-server" \
  '#!/bin/bash
apt-get update
apt-get install -y nginx
echo "Hello from $(hostname)" > /var/www/html/index.html'

ensure_template "template-alb-api-b" "$SUBNET_B" \
  "http-server" \
  '#!/bin/bash
apt-get update
apt-get install -y nginx
echo "Hello from $(hostname)" > /var/www/html/index.html'

# TASK 1.1: Internal MIG, named port and firewall rules
echo "=== TASK 1.1 ==="
ensure_mig "mig-proxy-internal" "$REGION_B" "template-proxy-internal" 2

gcloud compute instance-groups managed set-named-ports mig-proxy-internal \
  --region="$REGION_B" --named-ports=tcp80:80

ensure_firewall "fw-allow-proxy-health-check" \
  --network="$NETWORK" --direction=INGRESS --action=ALLOW \
  --rules=tcp:80 \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --target-tags=tag-proxy-internal

ensure_firewall "fw-allow-proxy-only-subnet" \
  --network="$NETWORK" --direction=INGRESS --action=ALLOW \
  --rules=tcp:80 --source-ranges=10.129.0.0/23 \
  --target-tags=tag-proxy-internal

# TASK 1.2: Regional internal proxy NLB
echo "=== TASK 1.2 ==="
if ! gcloud compute health-checks describe tcp-check-proxy \
  --region="$REGION_B" >/dev/null 2>&1; then
  gcloud compute health-checks create tcp tcp-check-proxy \
    --region="$REGION_B" --port=80
fi

if ! gcloud compute addresses describe ip-internal-proxy \
  --region="$REGION_B" >/dev/null 2>&1; then
  gcloud compute addresses create ip-internal-proxy \
    --region="$REGION_B" --subnet="$SUBNET_B" \
    --purpose=SHARED_LOADBALANCER_VIP
fi

if ! gcloud compute backend-services describe service-proxy-internal \
  --region="$REGION_B" >/dev/null 2>&1; then
  gcloud compute backend-services create service-proxy-internal \
    --region="$REGION_B" --load-balancing-scheme=INTERNAL_MANAGED \
    --protocol=TCP --health-checks=tcp-check-proxy \
    --health-checks-region="$REGION_B"
fi

if ! gcloud compute backend-services describe service-proxy-internal \
  --region="$REGION_B" --format=json | grep -q 'mig-proxy-internal'; then
  gcloud compute backend-services add-backend service-proxy-internal \
    --region="$REGION_B" --instance-group=mig-proxy-internal \
    --instance-group-region="$REGION_B"
fi

if ! gcloud compute target-tcp-proxies describe proxy-internal \
  --region="$REGION_B" >/dev/null 2>&1; then
  gcloud compute target-tcp-proxies create proxy-internal \
    --region="$REGION_B" --backend-service=service-proxy-internal
fi

if ! gcloud compute forwarding-rules describe rule-internal-proxy \
  --region="$REGION_B" >/dev/null 2>&1; then
  gcloud compute forwarding-rules create rule-internal-proxy \
    --region="$REGION_B" --load-balancing-scheme=INTERNAL_MANAGED \
    --network="$NETWORK" --subnet="$SUBNET_B" \
    --address=ip-internal-proxy \
    --target-tcp-proxy=proxy-internal \
    --target-tcp-proxy-region="$REGION_B" --ports=110
fi

# TASK 1.3: Client VM
ZONE_B="$(gcloud compute zones list \
  --filter="region:($REGION_B) AND status=UP" \
  --format='value(name)' | head -n 1)"
[[ -n "$ZONE_B" ]] || { echo "No available zone in $REGION_B"; exit 1; }

if ! gcloud compute instances describe vm-client-internal \
  --zone="$ZONE_B" >/dev/null 2>&1; then
  gcloud compute instances create vm-client-internal \
    --zone="$ZONE_B" --machine-type=e2-micro \
    --network="$NETWORK" --subnet="$SUBNET_B" --tags=allow-ssh
fi

# TASK 2.1: Two regional MIGs
echo "=== TASK 2.1 ==="
ensure_mig "mig-alb-api-a" "$REGION_A" "template-alb-api-a" 1
gcloud compute instance-groups managed set-named-ports mig-alb-api-a \
  --region="$REGION_A" --named-ports=http80:80

ensure_mig "mig-alb-api-b" "$REGION_B" "template-alb-api-b" 1
gcloud compute instance-groups managed set-named-ports mig-alb-api-b \
  --region="$REGION_B" --named-ports=http80:80

# TASK 2.2: Global backend service
echo "=== TASK 2.2 ==="
if ! gcloud compute health-checks describe http-check-alb \
  --global >/dev/null 2>&1; then
  gcloud compute health-checks create http http-check-alb --port=80 --global
fi

if ! gcloud compute backend-services describe service-alb-global \
  --global >/dev/null 2>&1; then
  gcloud compute backend-services create service-alb-global \
    --protocol=HTTP --health-checks=http-check-alb --global
fi

if ! gcloud compute backend-services describe service-alb-global \
  --global --format=json | grep -q 'mig-alb-api-a'; then
  gcloud compute backend-services add-backend service-alb-global \
    --global --instance-group=mig-alb-api-a \
    --instance-group-region="$REGION_A" \
    --balancing-mode=RATE --max-rate-per-instance=1
fi

if ! gcloud compute backend-services describe service-alb-global \
  --global --format=json | grep -q 'mig-alb-api-b'; then
  gcloud compute backend-services add-backend service-alb-global \
    --global --instance-group=mig-alb-api-b \
    --instance-group-region="$REGION_B" \
    --balancing-mode=RATE --max-rate-per-instance=1
fi

# TASK 2.3: Global HTTPS frontend
echo "=== TASK 2.3 ==="
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
    --url-map=map-alb-global --ssl-certificates=cert-self-signed --global
fi

if ! gcloud compute forwarding-rules describe rule-alb-global-https \
  --global >/dev/null 2>&1; then
  gcloud compute forwarding-rules create rule-alb-global-https \
    --global --target-https-proxy=https-proxy-alb-global \
    --address=ip-alb-global --ports=443
fi

# TASK 2.4: Health-check firewall
ensure_firewall "fw-allow-health-check-and-proxy" \
  --network="$NETWORK" --direction=INGRESS --action=ALLOW \
  --rules=tcp:80 --source-ranges=130.211.0.0/22,35.191.0.0/16

echo
echo "Setup commands completed. This does NOT guarantee full lab score."
echo "Internal VIP:"
gcloud compute addresses describe ip-internal-proxy \
  --region="$REGION_B" --format='value(address)'
echo "Global HTTPS IP:"
gcloud compute addresses describe ip-alb-global \
  --global --format='value(address)'
echo "Wait for health checks, validate the client VM and complete Task 3."
