#!/bin/bash
# ============================================================
# Lab: Build a Secure Google Cloud Network (Challenge Lab)
# Auto-script - Interactive Version
# Works for any user - no hardcoded values
# ============================================================

# Color variables
BLACK=`tput setaf 0`
RED=`tput setaf 1`
GREEN=`tput setaf 2`
YELLOW=`tput setaf 3`
BLUE=`tput setaf 4`
MAGENTA=`tput setaf 5`
CYAN=`tput setaf 6`
WHITE=`tput setaf 7`

BG_BLACK=`tput setab 0`
BG_RED=`tput setab 1`
BG_GREEN=`tput setab 2`
BG_YELLOW=`tput setab 3`
BG_BLUE=`tput setab 4`
BG_MAGENTA=`tput setab 5`
BG_CYAN=`tput setab 6`
BG_WHITE=`tput setab 7`

BOLD=`tput bold`
RESET=`tput sgr0`

# Orange color for input prompts
ORANGE=`tput setaf 208`

# ============================================================
# USER INPUT SECTION (Orange prompts)
# ============================================================
echo -e "\n${BG_BLUE}${WHITE}${BOLD} CONFIGURATION ${RESET} ${BLUE}${BOLD}Please enter the required environment variables:${RESET}\n"

read -p "${ORANGE}${BOLD}Enter SSH IAP network tag: ${RESET}" IAP_NET_TAG
read -p "${ORANGE}${BOLD}Enter SSH internal network tag: ${RESET}" INT_NET_TAG
read -p "${ORANGE}${BOLD}Enter HTTP network tag: ${RESET}" HTTP_NET_TAG
read -p "${ORANGE}${BOLD}Enter ZONE: ${RESET}" ZONE

export IAP_NET_TAG
export INT_NET_TAG
export HTTP_NET_TAG
export ZONE

# Validate inputs
if [ -z "$IAP_NET_TAG" ] || [ -z "$INT_NET_TAG" ] || [ -z "$HTTP_NET_TAG" ] || [ -z "$ZONE" ]; then
    echo -e "\n${BG_RED}${WHITE}${BOLD} ERROR ${RESET} ${RED}One or more variables were left empty. Aborting script.${RESET}\n"
    exit 1
fi

# ============================================================
# TASK EXECUTION
# ============================================================
echo -e "\n${BG_CYAN}${BLACK}${BOLD} INFO ${RESET} ${CYAN}${BOLD}Starting GCP Network & Firewall Configuration...${RESET}\n"

echo "${CYAN}[1/8]${RESET} Deleting overly permissive firewall rule (open-access)..."
gcloud compute firewall-rules delete open-access --quiet 2>/dev/null || echo "${YELLOW}  (open-access rule not found, skipping)${RESET}"

echo "${CYAN}[2/8]${RESET} Starting bastion instance..."
gcloud compute instances start bastion --project=$DEVSHELL_PROJECT_ID --zone=$ZONE --quiet

echo "${CYAN}[3/8]${RESET} Creating ssh-ingress firewall rule (IAP)..."
gcloud compute firewall-rules create ssh-ingress --allow=tcp:22 --source-ranges 35.235.240.0/20 --target-tags $IAP_NET_TAG --network acme-vpc --quiet

echo "${CYAN}[4/8]${RESET} Adding IAP network tag to bastion instance..."
gcloud compute instances add-tags bastion --tags=$IAP_NET_TAG --zone=$ZONE

echo "${CYAN}[5/8]${RESET} Creating http-ingress firewall rule..."
gcloud compute firewall-rules create http-ingress --allow=tcp:80 --source-ranges 0.0.0.0/0 --target-tags $HTTP_NET_TAG --network acme-vpc --quiet

echo "${CYAN}[6/8]${RESET} Adding HTTP network tag to juice-shop instance..."
gcloud compute instances add-tags juice-shop --tags=$HTTP_NET_TAG --zone=$ZONE

echo "${CYAN}[7/8]${RESET} Creating internal-ssh-ingress rule..."
gcloud compute firewall-rules delete internal-ssh-ingress --quiet 2>/dev/null

gcloud compute firewall-rules create internal-ssh-ingress --allow=tcp:22 --source-ranges 192.168.10.0/24 --target-tags $INT_NET_TAG --network acme-vpc --quiet

echo "${CYAN}[8/8]${RESET} Adding internal SSH tag to juice-shop instance..."
gcloud compute instances add-tags juice-shop --tags=$INT_NET_TAG --zone=$ZONE

# ============================================================
# PART 2: Task 5 fix (internal-ssh-ingress with dynamic CIDR)
# ============================================================
echo -e "\n${YELLOW}⏳ Applying Task 5 fix (dynamic management subnet CIDR)...${RESET}"

MGMT_CIDR=$(gcloud compute networks subnets list \
  --filter="name=acme-mgmt-subnet" \
  --format="value(ipCidrRange)" | head -n 1)

if [ -n "$MGMT_CIDR" ]; then
    echo "${CYAN}Detected acme-mgmt-subnet CIDR: $MGMT_CIDR${RESET}"
    gcloud compute firewall-rules delete internal-ssh-ingress --quiet 2>/dev/null
    gcloud compute firewall-rules create internal-ssh-ingress \
        --network=acme-vpc \
        --allow=tcp:22 \
        --source-ranges="$MGMT_CIDR" \
        --target-tags="$INT_NET_TAG" --quiet
    echo "${GREEN}✓ internal-ssh-ingress recreated with correct CIDR${RESET}"
else
    echo "${YELLOW}⚠ Could not detect acme-mgmt-subnet CIDR. Skipping Task 5 fix.${RESET}"
fi

# ============================================================
# WAIT FOR STABILIZATION
# ============================================================
echo -e "\n${YELLOW}⏳ Waiting 30 seconds for network interfaces to stabilize...${RESET}"
sleep 30

# ============================================================
# SSH CHAIN: bastion -> juice-shop
# ============================================================
echo -e "\n${CYAN}Setting up SSH chain (bastion -> juice-shop)...${RESET}"

cat > prepare_disk.sh <<'EOF_END'
export ZONE=$(gcloud compute instances list juice-shop --format 'csv[no-heading](zone)')
gcloud compute ssh juice-shop --internal-ip --zone=$ZONE --quiet
EOF_END

gcloud compute scp prepare_disk.sh bastion:/tmp --project=$DEVSHELL_PROJECT_ID --zone=$ZONE --quiet

gcloud compute ssh bastion --project=$DEVSHELL_PROJECT_ID --zone=$ZONE --quiet --command="bash /tmp/prepare_disk.sh"

# ============================================================
# LAB COMPLETION BANNER
# ============================================================
echo ""
echo -e "${BG_GREEN}${WHITE}${BOLD}                                                    ${RESET}"
echo -e "${BG_GREEN}${WHITE}${BOLD}          ✅  LAB COMPLETED SUCCESSFULLY  ✅          ${RESET}"
echo -e "${BG_GREEN}${WHITE}${BOLD}                                                    ${RESET}"
echo ""
echo -e "${GREEN}${BOLD}All tasks executed.${RESET}"
echo -e "${YELLOW}Ab lab page pe jaake har 'Check my progress' button click karo.${RESET}"
echo -e "${YELLOW}Agar koi checkpoint fail ho toh bata dena.${RESET}"
echo ""
echo -e "${CYAN}${BOLD}Thank you!${RESET}"
echo ""
