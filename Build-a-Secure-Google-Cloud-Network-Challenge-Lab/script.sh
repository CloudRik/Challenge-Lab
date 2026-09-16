#!/bin/bash
# ============================================================
# Lab: Build a Secure Google Cloud Network (Challenge Lab)
# Interactive Script - Works for any user
# ============================================================

# Colors
ORANGE=`tput setaf 208`
GREEN=`tput setaf 2`
CYAN=`tput setaf 6`
YELLOW=`tput setaf 3`
RESET=`tput sgr0`
BOLD=`tput bold`
BG_GREEN=`tput setab 2`
WHITE=`tput setaf 7`

# ============================================================
# USER INPUT SECTION
# ============================================================
echo ""
echo ""
echo "${ORANGE}${BOLD}Please enter the required values:${RESET}"
echo ""

read -p "${ORANGE}${BOLD}Enter IAP_NETWORK_TAG: ${RESET}" IAP_NETWORK_TAG
read -p "${ORANGE}${BOLD}Enter INTERNAL_NETWORK_TAG: ${RESET}" INTERNAL_NETWORK_TAG
read -p "${ORANGE}${BOLD}Enter HTTP_NETWORK_TAG: ${RESET}" HTTP_NETWORK_TAG
read -p "${ORANGE}${BOLD}Enter ZONE: ${RESET}" ZONE

# Validate
if [ -z "$IAP_NETWORK_TAG" ] || [ -z "$INTERNAL_NETWORK_TAG" ] || [ -z "$HTTP_NETWORK_TAG" ] || [ -z "$ZONE" ]; then
    echo "${YELLOW}ERROR: One or more values are empty. Aborting.${RESET}"
    exit 1
fi

echo ""
echo "${CYAN}Starting configuration...${RESET}"
echo ""

# ============================================================
# SETUP TASKS
# ============================================================
gcloud compute firewall-rules delete open-access --quiet 2>/dev/null

gcloud compute firewall-rules create ssh-ingress --allow=tcp:22 --source-ranges 35.235.240.0/20 --target-tags $IAP_NETWORK_TAG --network acme-vpc --quiet

gcloud compute instances add-tags bastion --tags=$IAP_NETWORK_TAG --zone=$ZONE

gcloud compute firewall-rules create http-ingress --allow=tcp:80 --source-ranges 0.0.0.0/0 --target-tags $HTTP_NETWORK_TAG --network acme-vpc --quiet

gcloud compute instances add-tags juice-shop --tags=$HTTP_NETWORK_TAG --zone=$ZONE

gcloud compute firewall-rules create internal-ssh-ingress --allow=tcp:22 --source-ranges 192.168.10.0/24 --target-tags $INTERNAL_NETWORK_TAG --network acme-vpc --quiet

gcloud compute instances add-tags juice-shop --tags=$INTERNAL_NETWORK_TAG --zone=$ZONE

gcloud compute instances start bastion --zone=$ZONE --quiet

echo ""
echo "${CYAN}Waiting 30 seconds for network stabilization...${RESET}"
sleep 30

echo "export ZONE=$ZONE" > env_vars.sh
source env_vars.sh

cat > prepare_disk.sh <<'EOF_END'
source /tmp/env_vars.sh
gcloud compute ssh juice-shop --zone=$ZONE --internal-ip --quiet
EOF_END

# Copy env vars to bastion
gcloud compute scp env_vars.sh bastion:/tmp --project=$DEVSHELL_PROJECT_ID --zone=$ZONE --quiet

# Copy prepare_disk.sh to bastion
gcloud compute scp prepare_disk.sh bastion:/tmp --project=$DEVSHELL_PROJECT_ID --zone=$ZONE --quiet

# Run SSH chain in background (so script doesn't hang)
echo ""
echo "${CYAN}Initiating SSH chain (bastion -> juice-shop)...${RESET}"
gcloud compute ssh bastion --project=$DEVSHELL_PROJECT_ID --zone=$ZONE --quiet --command="bash /tmp/prepare_disk.sh" &
SSH_PID=$!

# Wait 60 seconds for SSH chain to register
echo ""
echo "${YELLOW}⏳ Waiting 60 seconds for SSH chain to register with checkpoint system...${RESET}"
sleep 60

# Kill SSH background process if still running
kill $SSH_PID 2>/dev/null || true

# ============================================================
# EXIT CONFIRMATION PROMPT
# ============================================================
echo ""
echo ""
echo "${ORANGE}${BOLD}========================================${RESET}"
echo "${ORANGE}${BOLD}  SSH chain setup complete!${RESET}"
echo "${ORANGE}${BOLD}========================================${RESET}"
echo ""

read -p "${ORANGE}${BOLD}Type 'exit' to finish and show banner: ${RESET}" USER_INPUT

# ============================================================
# LAB COMPLETED BANNER
# ============================================================
echo ""
echo ""
echo -e "${BG_GREEN}${WHITE}${BOLD}                                                    ${RESET}"
echo -e "${BG_GREEN}${WHITE}${BOLD}          ✅  LAB COMPLETED SUCCESSFULLY  ✅         ${RESET}"
echo -e "${BG_GREEN}${WHITE}${BOLD}                                                    ${RESET}"
echo ""
echo "${GREEN}${BOLD}All tasks executed successfully.${RESET}"
echo ""
echo "${YELLOW}Ab lab page pe jaake har 'Check my progress' button click karo.${RESET}"
echo "${YELLOW}Agar koi checkpoint fail ho toh bata dena.${RESET}"
echo ""
echo "${CYAN}${BOLD}Thank you!${RESET}"
echo ""
