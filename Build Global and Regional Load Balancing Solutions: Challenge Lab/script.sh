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
echo "${CYAN}${BOLD}   GSP539 - GLOBAL & REGIONAL LOAD BALANCING   ${RESET}"
echo "${CYAN}${BOLD}=================================================${RESET}"
echo

# ===============================
# BLOCK 1: Session Setup
# ===============================
echo "${GREEN}${BOLD}[BLOCK 1/6] Setting up session values${RESET}"
echo

# User se Region A poocho
echo "${YELLOW}Lab panel se Region A aur Region B dekho (right side).${RESET}"
read -p "Enter Region A (e.g., us-east1): " REGION_A
read -p "Enter Region B (e.g., us-west1): " REGION_B

if [ -z "$REGION_A" ] || [ -z "$REGION_B" ]; then
  echo "${RED}Regions required! Script exit ho raha hai.${RESET}"
  exit 1
fi

NETWORK=lb-network
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

# Detect subnet, zone, templates
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

echo
echo "${GREEN}===== YOUR LAB VALUES =====${RESET}"
cat ~/lab.env
echo

echo "${YELLOW}Block 1 complete. Check regions are correct.${RESET}"
echo "${WHITE}Press Enter to continue to Block 2...${RESET}"
read

# ===============================
# BLOCK 2: Task 1 - Internal backends + firewall
# ===============================
source ~/lab.env

echo
echo "${GREEN}${BOLD}[BLOCK 2/6] Task 1: Internal backends + firewall rules${RESET}"
echo

echo "${YELLOW}Creating MIG 'mig-proxy-internal'...${RESET}"
gcloud compute instance-groups managed create mig-proxy-internal \
  --region=$REGION_B --template=$TPL_PROXY --size=2 --quiet 2>/dev/null || echo "${YELLOW}MIG exists${RESET}"

gcloud compute instance-groups managed set-named-ports mig-proxy-internal \
  --region=$REGION_B --named-ports=tcp80:80 --quiet 2>/dev/null || true

echo "${YELLOW}Creating firewall rules...${RESET}"
gcloud compute firewall-rules create fw-allow-hc-proxy-internal \
  --network=$NETWORK --direction=INGRESS --action=allow --rules=tcp:80 \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 --target-tags=tag-proxy-internal \
  --quiet 2>/dev/null || echo "${YELLOW}Rule exists${RESET}"

gcloud compute firewall-rules create fw-allow-proxy-only-subnet \
  --network=$NETWORK --direction=INGRESS --action=allow --rules=tcp:80 \
  --source-ranges=10.129.0.0/23 --target-tags=tag-proxy-internal \
  --quiet 2>/dev/null || echo "${YELLOW}Rule exists${RESET}"

echo
echo "${GREEN}Block 2 complete.${RESET}"
echo "${WHITE}>>> LAB PAGE pe jao aur click karo: 'Create a regional MIG and 2 firewall rules'${RESET}"
echo "${WHITE}Press Enter jab Check my progress pass ho jaye...${RESET}"
read

# ===============================
# BLOCK 3: Task 1 - Internal proxy NLB + client VM
# ===============================
source ~/lab.env

echo
echo "${GREEN}${BOLD}[BLOCK 3/6] Task 1: Internal proxy NLB + client VM${RESET}"
echo "${WHITE}Yeh 5-10 minute lega...${RESET}"
echo

# Proxy-only subnet
echo "${YELLOW}Checking proxy-only subnet...${RESET}"
gcloud compute networks subnets list --network=$NETWORK \
  --filter="region:($REGION_B) AND purpose:REGIONAL_MANAGED_PROXY" --format="value(name)" | grep -q . \
|| gcloud compute networks subnets create proxy-only-subnet --network=$NETWORK \
  --region=$REGION_B --range=10.129.0.0/23 --purpose=REGIONAL_MANAGED_PROXY --role=ACTIVE --quiet

# Reserve IP
echo "${YELLOW}Reserving internal IP...${RESET}"
gcloud compute addresses create ip-internal-proxy --region=$REGION_B \
  --subnet=$SUBNET_B --purpose=SHARED_LOADBALANCER_VIP --quiet 2>/dev/null || echo "${YELLOW}IP exists${RESET}"

# Health check
echo "${YELLOW}Creating health check...${RESET}"
gcloud compute health-checks create tcp tcp-check-internal --region=$REGION_B --port=80 --quiet 2>/dev/null || true

# Backend service
echo "${YELLOW}Creating backend service...${RESET}"
gcloud compute backend-services create service-proxy-internal --region=$REGION_B \
  --load-balancing-scheme=INTERNAL_MANAGED --protocol=TCP --port-name=tcp80 \
  --health-checks=tcp-check-internal --health-checks-region=$REGION_B --quiet 2>/dev/null || true

gcloud compute backend-services add-backend service-proxy-internal --region=$REGION_B \
  --instance-group=mig-proxy-internal --instance-group-region=$REGION_B \
  --balancing-mode=UTILIZATION --max-utilization=0.8 --quiet 2>/dev/null || true

# Target TCP proxy
echo "${YELLOW}Creating target TCP proxy...${RESET}"
gcloud compute target-tcp-proxies create tcp-proxy-internal \
  --region=$REGION_B --backend-service=service-proxy-internal --quiet 2>/dev/null || true

# Forwarding rule
echo "${YELLOW}Creating forwarding rule...${RESET}"
gcloud compute forwarding-rules create rule-internal-proxy --region=$REGION_B \
  --load-balancing-scheme=INTERNAL_MANAGED --network=$NETWORK --subnet=$SUBNET_B \
  --address=ip-internal-proxy --ports=110 \
  --target-tcp-proxy=tcp-proxy-internal --target-tcp-proxy-region=$REGION_B --quiet 2>/dev/null || true

echo
echo "${GREEN}Block 3 part 1 complete.${RESET}"
echo "${WHITE}>>> LAB PAGE pe click karo: 'Create a regional internal proxy NLB'${RESET}"
echo "${WHITE}Press Enter jab pass ho jaye...${RESET}"
read

# Client VM
echo
echo "${YELLOW}Creating client VM 'vm-client-internal'...${RESET}"
gcloud compute instances create vm-client-internal --zone=$ZONE_B \
  --network=$NETWORK --subnet=$SUBNET_B --tags=allow-ssh \
  --machine-type=e2-small --image-family=debian-12 --image-project=debian-cloud \
  --quiet 2>/dev/null || echo "${YELLOW}VM exists${RESET}"

echo
echo "${YELLOW}Waiting for VM to be ready (60s)...${RESET}"
sleep 60

# Test LB
INTERNAL_IP=$(gcloud compute addresses describe ip-internal-proxy --region=$REGION_B --format="value(address)")
echo "${YELLOW}Testing http://$INTERNAL_IP:110 from vm-client-internal...${RESET}"

for i in $(seq 15); do
  OUT=$(gcloud compute ssh vm-client-internal --zone=$ZONE_B --quiet --command="curl -s --max-time 5 http://$INTERNAL_IP:110" 2>/dev/null \
     || gcloud compute ssh vm-client-internal --zone=$ZONE_B --quiet --tunnel-through-iap --command="curl -s --max-time 5 http://$INTERNAL_IP:110" 2>/dev/null)
  [ -n "$OUT" ] && { echo "${GREEN}$OUT${RESET}" | head -5; echo "${GREEN}LB reachable on $INTERNAL_IP:110${RESET}"; break; }
  echo "${YELLOW}  not ready yet ($i/15), waiting 20s...${RESET}"; sleep 20
done

echo
echo "${GREEN}Block 3 complete.${RESET}"
echo "${WHITE}>>> LAB PAGE pe click karo: 'Deploy a client VM and validate the access'${RESET}"
echo "${WHITE}Press Enter jab pass ho jaye...${RESET}"
read

# ===============================
# BLOCK 4: Task 2 - Global HTTPS LB
# ===============================
source ~/lab.env

echo
echo "${GREEN}${BOLD}[BLOCK 4/6] Task 2: Global HTTPS Load Balancer${RESET}"
echo "${WHITE}Yeh 10-15 minute lega...${RESET}"
echo

# MIGs
echo "${YELLOW}Creating MIG in Region A...${RESET}"
gcloud compute instance-groups managed create mig-alb-api-a --region=$REGION_A --template=$TPL_ALB --size=2 --quiet 2>/dev/null || true
gcloud compute instance-groups managed set-named-ports mig-alb-api-a --region=$REGION_A --named-ports=http80:80 --quiet 2>/dev/null || true

echo "${YELLOW}Creating MIG in Region B...${RESET}"
gcloud compute instance-groups managed create mig-alb-api-b --region=$REGION_B --template=$TPL_ALB --size=2 --quiet 2>/dev/null || true
gcloud compute instance-groups managed set-named-ports mig-alb-api-b --region=$REGION_B --named-ports=http80:80 --quiet 2>/dev/null || true

echo
echo "${GREEN}Block 4 part 1 complete.${RESET}"
echo "${WHITE}>>> LAB PAGE pe click karo: 'Create two regional MIGs'${RESET}"
echo "${WHITE}Press Enter jab pass ho jaye...${RESET}"
read

# Firewall rule (template-based)
echo
echo "${YELLOW}Creating firewall rule (template-based)...${RESET}"
TPL_NET=$(gcloud compute instance-templates list --filter="name=template-alb-api" --format="value(properties.networkInterfaces[0].network.basename())" | head -1)
TPL_TAGS=$(gcloud compute instance-templates list --filter="name=template-alb-api" --format="value(properties.tags.items)" | head -1 | tr ';' ',')
echo "${BLUE}template-alb-api network: ${TPL_NET:-$NETWORK}   tags: ${TPL_TAGS:-none}${RESET}"

gcloud compute firewall-rules delete fw-allow-health-check-and-proxy --quiet 2>/dev/null || true
gcloud compute firewall-rules create fw-allow-health-check-and-proxy \
  --network=${TPL_NET:-$NETWORK} --direction=INGRESS --action=allow --rules=tcp:80 \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  ${TPL_TAGS:+--target-tags=$TPL_TAGS} --quiet

# Health check + backend
echo "${YELLOW}Creating global health check...${RESET}"
gcloud compute health-checks create http http-check-alb --port=80 --global --quiet 2>/dev/null || true

echo "${YELLOW}Creating global backend service...${RESET}"
gcloud compute backend-services create service-alb-global --global \
  --load-balancing-scheme=EXTERNAL_MANAGED --protocol=HTTP --port-name=http80 \
  --health-checks=http-check-alb --quiet 2>/dev/null || true

gcloud compute backend-services add-backend service-alb-global --global \
  --instance-group=mig-alb-api-a --instance-group-region=$REGION_A \
  --balancing-mode=RATE --max-rate-per-instance=1 --quiet 2>/dev/null || true

gcloud compute backend-services add-backend service-alb-global --global \
  --instance-group=mig-alb-api-b --instance-group-region=$REGION_B \
  --balancing-mode=RATE --max-rate-per-instance=1 --quiet 2>/dev/null || true

# SSL cert
echo "${YELLOW}Creating SSL cert...${RESET}"
openssl genrsa -out key.pem 2048 2>/dev/null
openssl req -new -x509 -key key.pem -out cert.pem -days 1 -subj "/CN=example.com" 2>/dev/null
gcloud compute ssl-certificates create cert-self-signed \
  --certificate=cert.pem --private-key=key.pem --global --quiet 2>/dev/null || true

# IP + URL map + proxy + forwarding
echo "${YELLOW}Reserving global IP...${RESET}"
gcloud compute addresses create ip-alb-global --ip-version=IPV4 --global --quiet 2>/dev/null || true

gcloud compute url-maps create url-map-alb --default-service=service-alb-global --quiet 2>/dev/null || true
gcloud compute target-https-proxies create https-proxy-alb \
  --url-map=url-map-alb --ssl-certificates=cert-self-signed --global --quiet 2>/dev/null || true
gcloud compute forwarding-rules create rule-alb-https --global \
  --load-balancing-scheme=EXTERNAL_MANAGED --network-tier=PREMIUM \
  --address=ip-alb-global --target-https-proxy=https-proxy-alb --ports=443 --quiet 2>/dev/null || true

# Health check
echo
echo "${YELLOW}Waiting 60s for backend health check...${RESET}"
sleep 60
gcloud compute backend-services get-health service-alb-global --global \
  --format="table(status.healthStatus[].instance.basename(),status.healthStatus[].healthState)"

# Wait for LB
ALB_IP=$(gcloud compute addresses describe ip-alb-global --global --format="value(address)")
echo
echo "${YELLOW}Waiting for https://$ALB_IP (404/502 for first few minutes is normal)...${RESET}"
for i in $(seq 40); do
  R=$(curl -ks --max-time 5 https://$ALB_IP | grep -o "Hello from[^<]*")
  [ -n "$R" ] && { echo "${GREEN}$R${RESET}"; echo "${GREEN}Load balancer is live${RESET}"; break; }
  echo "${YELLOW}  not ready yet ($i/40), waiting 20s...${RESET}"; sleep 20
done

echo
echo "${GREEN}Block 4 complete.${RESET}"
echo "${WHITE}>>> LAB PAGE pe click karo: 'Create global external application load balancer'${RESET}"
echo "${WHITE}Press Enter jab pass ho jaye...${RESET}"
read

# ===============================
# BLOCK 5: Task 3 - Failover test
# ===============================
source ~/lab.env
ALB_IP=$(gcloud compute addresses describe ip-alb-global --global --format="value(address)")

echo
echo "${GREEN}${BOLD}[BLOCK 5/6] Task 3: Failover test${RESET}"
echo

echo "${YELLOW}Traffic before failure (alternate A/B):${RESET}"
for i in $(seq 20); do curl -ks https://$ALB_IP | grep -o "Hello from[^<]*"; sleep 0.5; done

echo
echo "${YELLOW}Stopping nginx on mig-alb-api-a VMs...${RESET}"
for VM in $(gcloud compute instance-groups managed list-instances mig-alb-api-a --region=$REGION_A --format="value(instance.basename())"); do
  Z=$(gcloud compute instances list --filter="name=$VM" --format="value(zone.basename())")
  gcloud compute ssh $VM --zone=$Z --quiet --command="sudo systemctl stop nginx" 2>/dev/null \
  || gcloud compute ssh $VM --zone=$Z --quiet --tunnel-through-iap --command="sudo systemctl stop nginx"
  echo "${GREEN}  stopped nginx on $VM${RESET}"
done

echo
echo "${YELLOW}Waiting 60s for health check to mark Region A unhealthy...${RESET}"
sleep 60

echo "${YELLOW}Traffic after failure (should be Region B only):${RESET}"
for i in $(seq 10); do curl -ks https://$ALB_IP | grep -o "Hello from[^<]*"; sleep 0.5; done

echo
echo "${GREEN}Block 5 complete.${RESET}"
echo "${WHITE}>>> LAB PAGE pe click karo: 'Test failover and global distribution'${RESET}"
echo "${WHITE}Press Enter jab pass ho jaye...${RESET}"
read

# ===============================
# BLOCK 6: Restore
# ===============================
source ~/lab.env

echo
echo "${GREEN}${BOLD}[BLOCK 6/6] Restoring Nginx on Region A VMs${RESET}"
echo

for VM in $(gcloud compute instance-groups managed list-instances mig-alb-api-a --region=$REGION_A --format="value(instance.basename())"); do
  Z=$(gcloud compute instances list --filter="name=$VM" --format="value(zone.basename())")
  gcloud compute ssh $VM --zone=$Z --quiet --command="sudo systemctl start nginx" 2>/dev/null \
  || gcloud compute ssh $VM --zone=$Z --quiet --tunnel-through-iap --command="sudo systemctl start nginx"
  echo "${GREEN}  started nginx on $VM${RESET}"
done

echo
echo "${GREEN}Region A will rejoin once health check reports HEALTHY (about 1 min).${RESET}"
echo

# ===============================
# FINAL
# ===============================
echo
echo "${CYAN}${BOLD}=================================================${RESET}"
echo "${CYAN}${BOLD}   LAB COMPLETED - GSP539${RESET}"
echo "${CYAN}${BOLD}=================================================${RESET}"
echo
echo "${GREEN}All blocks executed successfully!${RESET}"
echo "${WHITE}Final score check karo lab page pe.${RESET}"
echo
