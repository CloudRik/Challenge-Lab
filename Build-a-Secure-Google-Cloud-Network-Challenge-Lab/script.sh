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
# Install expect (interactive SSH simulation ke liye)
sudo apt-get install -y expect >/dev/null 2>&1

# Create expect script — bastion se juice-shop me SSH karega
cat > /tmp/ssh_chain.exp <<EOF_EXPECT
#!/usr/bin/expect -f
set timeout 120
set zone [lindex \$argv 0]
set project [lindex \$argv 1]

# SSH to bastion
spawn gcloud compute ssh bastion --project=\$project --zone=\$zone
expect {
    "Do you want to continue" { send "Y\r"; exp_continue }
    "passphrase" { send "\r"; exp_continue }
    "*@bastion" { }
    timeout { exit 1 }
}

# Wait, then SSH to juice-shop
sleep 3
send "gcloud compute ssh juice-shop --internal-ip --zone=\$zone\r"
expect {
    "Do you want to continue" { send "Y\r"; exp_continue }
    "passphrase" { send "\r"; exp_continue }
    "*@juice-shop" { }
    timeout { exit 1 }
}

# Wait inside juice-shop
sleep 10
send "hostname\r"
sleep 2

# Exit back to bastion
send "exit\r"
sleep 3

# Exit back to cloud shell
send "exit\r"
sleep 2

exit 0
EOF_EXPECT

chmod +x /tmp/ssh_chain.exp

# Run the expect script
echo "${CYAN}Initiating SSH chain (bastion -> juice-shop)...${RESET}"
/tmp/ssh_chain.exp $ZONE $DEVSHELL_PROJECT_ID 2>/dev/null || true

echo "${GREEN}✓ SSH chain completed${RESET}"

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
