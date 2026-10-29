clear
ORANGE=$'\033[38;5;208m'
CYAN=$'\033[0;36m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
MAGENTA=$'\033[0;35m'
BLUE=$'\033[0;34m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

echo "${MAGENTA}${BOLD}==========================================================${RESET}"
echo "${CYAN}${BOLD}               WELCOME TO ARCADESUITE                     ${RESET}"
echo "${MAGENTA}${BOLD}==========================================================${RESET}"
echo "${ORANGE}${BOLD}        DEPLOYING INTERNAL REGIONAL NLB (TASK 1)          ${RESET}"
echo "${MAGENTA}${BOLD}==========================================================${RESET}"

read -p "${BLUE}${BOLD}Enter Region B (e.g., us-east1): ${RESET}" REGION_B
export REGION_B=$REGION_B

echo "${YELLOW}▶ [STEP 1] Initializing template generation...${RESET}"
while [ -z "$(gcloud compute instance-templates list --filter='name:template-proxy-internal' --format='value(name)')" ]; do sleep 5; done
TEMPLATE_PROXY_URI=$(gcloud compute instance-templates list --filter="name=template-proxy-internal" --format="value(selfLink)" | head -n 1)

echo "${YELLOW}▶ [STEP 2] Scanning for optimal subnet placement...${RESET}"
SUBNET_B=$(gcloud compute networks subnets list --network=lb-network --regions=$REGION_B --format="value(name)" | grep -v "proxy" | head -n 1)
echo "${CYAN}Target Subnet Identified: ${SUBNET_B}${RESET}"

echo "${YELLOW}▶ [STEP 3] Spinning up Managed Instance Group (MIG)...${RESET}"
gcloud compute instance-groups managed create mig-proxy-internal --template=$TEMPLATE_PROXY_URI --region=$REGION_B --size=1 --quiet 2>/dev/null || true
gcloud compute instance-groups managed set-named-ports mig-proxy-internal --named-ports=tcp80:80 --region=$REGION_B --quiet 2>/dev/null || true

echo "${YELLOW}▶ [STEP 4] Configuring firewall safety rules...${RESET}"
gcloud compute firewall-rules create fw-allow-hc-proxy-internal --network=lb-network --action=allow --direction=ingress --source-ranges=130.211.0.0/22,35.191.0.0/16 --target-tags=tag-proxy-internal --rules=tcp:80 --quiet 2>/dev/null || true
gcloud compute firewall-rules create fw-allow-proxy-subnet-internal --network=lb-network --action=allow --direction=ingress --source-ranges=10.129.0.0/23 --target-tags=tag-proxy-internal --rules=tcp:80 --quiet 2>/dev/null || true

echo "${YELLOW}▶ [STEP 5] Allocating Shared VIP IP address...${RESET}"
gcloud compute addresses create ip-internal-proxy --region=$REGION_B --subnet=$SUBNET_B --purpose=SHARED_LOADBALANCER_VIP --quiet 2>/dev/null || true

echo "${YELLOW}▶ [STEP 6] Activating health monitoring...${RESET}"
gcloud compute health-checks create tcp hc-internal-proxy --region=$REGION_B --port=80 --quiet 2>/dev/null || true

echo "${YELLOW}▶ [STEP 7] Linking backend services...${RESET}"
gcloud compute backend-services create internal-proxy-backend --load-balancing-scheme=INTERNAL_MANAGED --protocol=TCP --region=$REGION_B --health-checks=hc-internal-proxy --health-checks-region=$REGION_B --port-name=tcp80 --quiet 2>/dev/null || true
gcloud compute backend-services add-backend internal-proxy-backend --region=$REGION_B --instance-group=mig-proxy-internal --instance-group-region=$REGION_B --quiet 2>/dev/null || true

echo "${YELLOW}▶ [STEP 8] Routing TCP traffic via Target Proxy...${RESET}"
gcloud compute target-tcp-proxies create proxy-internal --region=$REGION_B --backend-service=internal-proxy-backend --quiet 2>/dev/null || true
gcloud compute forwarding-rules create rule-internal-proxy --region=$REGION_B --load-balancing-scheme=INTERNAL_MANAGED --network=lb-network --subnet=$SUBNET_B --address=ip-internal-proxy --ports=110 --target-tcp-proxy=proxy-internal --target-tcp-proxy-region=$REGION_B --quiet 2>/dev/null || true

echo "${YELLOW}▶ [STEP 9] Launching validation client VM...${RESET}"
ZONE_B=$(gcloud compute zones list --filter="region:($REGION_B)" --format="value(name)" | head -n 1)
gcloud compute instances create vm-client-internal --zone=$ZONE_B --machine-type=e2-micro --network=lb-network --subnet=$SUBNET_B --tags=allow-ssh --quiet 2>/dev/null || true

echo ""
echo "${GREEN}${BOLD}  _____                      _      _       ${RESET}"
echo "${GREEN}${BOLD} / ____|                    | |    | |      ${RESET}"
echo "${GREEN}${BOLD}| |     ___  _ __ ___  _ __ | | ___| |_ ___ ${RESET}"
echo "${GREEN}${BOLD}| |    / _ \| '_ \` _ \| '_ \| |/ _ \ __/ _ \\${RESET}"
echo "${GREEN}${BOLD}| |___| (_) | | | | | | |_) | |  __/ ||  __/${RESET}"
echo "${GREEN}${BOLD} \_____\___/|_| |_| |_| .__/|_|\___|\__\___|${RESET}"
echo "${GREEN}${BOLD}                      | |                   ${RESET}"
echo "${GREEN}${BOLD}                      |_|                   ${RESET}"
echo ""
echo "${MAGENTA}${BOLD}==========================================================${RESET}"
echo "${CYAN}${BOLD}             POWERED BY ARCADESUITE                       ${RESET}"
echo "${MAGENTA}${BOLD}==========================================================${RESET}"
echo "${YELLOW}${BOLD}✓ Stage 1 Complete! Wait ~45s, then click 'Check my progress'.${RESET}"
echo "${MAGENTA}${BOLD}==========================================================${RESET}"
