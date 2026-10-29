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
echo "${ORANGE}${BOLD}        DEPLOYING GLOBAL EXTERNAL ALB (TASK 2)            ${RESET}"
echo "${MAGENTA}${BOLD}==========================================================${RESET}"

read -p "${BLUE}${BOLD}Enter Region A (e.g., us-east4): ${RESET}" REGION_A
read -p "${BLUE}${BOLD}Enter Region B (e.g., us-central1): ${RESET}" REGION_B

echo "${YELLOW}▶ [STEP 1] Preparing global application template...${RESET}"
while [ -z "$(gcloud compute instance-templates list --filter='name:template-alb-api' --format='value(name)')" ]; do sleep 5; done
TEMPLATE_ALB_URI=$(gcloud compute instance-templates list --filter="name:template-alb-api" --format="value(selfLink)" | head -n 1)

echo "${YELLOW}▶ [STEP 2] Deploying Regional MIGs (Region A & B)...${RESET}"
gcloud compute instance-groups managed create mig-alb-api-a --template=$TEMPLATE_ALB_URI --region=$REGION_A --size=1 --quiet 2>/dev/null || true
gcloud compute instance-groups managed set-named-ports mig-alb-api-a --named-ports=http80:80 --region=$REGION_A --quiet 2>/dev/null || true
gcloud compute instance-groups managed create mig-alb-api-b --template=$TEMPLATE_ALB_URI --region=$REGION_B --size=1 --quiet 2>/dev/null || true
gcloud compute instance-groups managed set-named-ports mig-alb-api-b --named-ports=http80:80 --region=$REGION_B --quiet 2>/dev/null || true

echo "${YELLOW}▶ [STEP 3] Attaching global backend service with rate limiting...${RESET}"
gcloud compute health-checks create http http-check-alb --global --port=80 --quiet 2>/dev/null || true
gcloud compute backend-services create service-alb-global --global --protocol=HTTP --health-checks=http-check-alb --port-name=http80 --quiet 2>/dev/null || true
gcloud compute backend-services add-backend service-alb-global --global --instance-group=mig-alb-api-a --instance-group-region=$REGION_A --balancing-mode=RATE --max-rate-per-instance=1 --quiet 2>/dev/null || true
gcloud compute backend-services add-backend service-alb-global --global --instance-group=mig-alb-api-b --instance-group-region=$REGION_B --balancing-mode=RATE --max-rate-per-instance=1 --quiet 2>/dev/null || true

echo "${YELLOW}▶ [STEP 4] Generating self-signed SSL and reserving global IP...${RESET}"
openssl genrsa -out key.pem 2048 2>/dev/null
openssl req -new -x509 -key key.pem -out cert.pem -days 1 -subj "/CN=example.com" 2>/dev/null
gcloud compute ssl-certificates create cert-self-signed --certificate=cert.pem --private-key=key.pem --global --quiet 2>/dev/null || true
gcloud compute addresses create ip-alb-global --global --quiet 2>/dev/null || true

echo "${YELLOW}▶ [STEP 5] Wiring up Load Balancer frontend...${RESET}"
gcloud compute url-maps create url-map-alb --default-service=service-alb-global --quiet 2>/dev/null || true
gcloud compute target-https-proxies create https-proxy-alb --url-map=url-map-alb --ssl-certificates=cert-self-signed --quiet 2>/dev/null || true
gcloud compute forwarding-rules create https-forwarding-rule --global --target-https-proxy=https-proxy-alb --ports=443 --address=ip-alb-global --quiet 2>/dev/null || true

echo "${YELLOW}▶ [STEP 6] Enabling firewall rules for health checks...${RESET}"
ALB_NET_URI=$(gcloud compute instance-templates list --filter="name:template-alb-api" --format="value(properties.networkInterfaces[0].network)" | head -n 1)
ALB_NET_NAME=$(basename $ALB_NET_URI)
gcloud compute firewall-rules create fw-allow-health-check-and-proxy --network=$ALB_NET_NAME --action=allow --direction=ingress --source-ranges=130.211.0.0/22,35.191.0.0/16 --target-tags=tag-alb-api --rules=tcp:80 --quiet 2>/dev/null || true

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
echo "${YELLOW}${BOLD}✓ Stage 2 Complete! Please wait 2-3 minutes for propagation.${RESET}"
echo "${MAGENTA}${BOLD}==========================================================${RESET}"
