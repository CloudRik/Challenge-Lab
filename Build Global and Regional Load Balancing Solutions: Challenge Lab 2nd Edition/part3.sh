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
echo "${ORANGE}${BOLD}         SIMULATING REGIONAL FAILOVER (TASK 3)            ${RESET}"
echo "${MAGENTA}${BOLD}==========================================================${RESET}"

echo "${YELLOW}▶ [STEP 1] Waiting for Region A instances to initialize...${RESET}"
while [ -z "$(gcloud compute instances list --filter='name:mig-alb-api-a*' --format='value(name)')" ]; do 
    echo "${CYAN}Waiting for instance in Region A...${RESET}"
    sleep 5
done

INSTANCE=$(gcloud compute instances list --filter="name:mig-alb-api-a*" --format="value(name)" | head -n 1)
ZONE=$(gcloud compute instances list --filter="name:mig-alb-api-a*" --format="value(zone)" | awk -F/ '{print $NF}' | head -n 1)

echo "${BLUE}Target Instance Identified: ${INSTANCE} (Zone: ${ZONE})${RESET}"

echo "${YELLOW}▶ [STEP 2] Generating secure SSH credentials...${RESET}"
mkdir -p ~/.ssh
ssh-keygen -t rsa -f ~/.ssh/google_compute_engine -N "" -q <<< y >/dev/null 2>&1 || true

echo "${YELLOW}▶ [STEP 3] Simulating failure by stopping Nginx on Region A...${RESET}"
gcloud compute ssh "$INSTANCE" --zone="$ZONE" --quiet --command="sudo systemctl stop nginx"

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
echo "${YELLOW}${BOLD}✓ Failover simulated successfully! Wait 60s, then click 'Check my progress'.${RESET}"
echo "${MAGENTA}${BOLD}==========================================================${RESET}"
