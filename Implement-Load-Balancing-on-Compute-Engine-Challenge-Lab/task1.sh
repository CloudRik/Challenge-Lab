#!/bin/bash
# ============================================================
# Lab: Implement Load Balancing on Compute Engine (Challenge Lab)
# Task 1: Create multiple web server instances
# Interactive Script - Works for any user
# ============================================================

# Colors
ORANGE=$'\033[38;5;208m'
GREEN=$'\033[0;92m'
CYAN=$'\033[0;96m'
YELLOW=$'\033[0;93m'
RED=$'\033[0;91m'
WHITE=$'\033[0;97m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

clear

# ============================================================
# HEADER
# ============================================================
echo "${CYAN}${BOLD}=========================================================${RESET}"
echo "${CYAN}${BOLD}   TASK 1: CREATE MULTIPLE WEB SERVER INSTANCES${RESET}"
echo "${CYAN}${BOLD}=========================================================${RESET}"
echo ""

# ============================================================
# USER INPUT SECTION
# ============================================================
echo "${ORANGE}${BOLD}Please enter the required values:${RESET}"
echo ""

read -p "${ORANGE}${BOLD}Enter Your Region (e.g. us-central1): ${RESET}" REGION
read -p "${ORANGE}${BOLD}Enter Your Zone (e.g. us-central1-a): ${RESET}" ZONE
read -p "${ORANGE}${BOLD}Enter image-family (e.g. debian-12): ${RESET}" IMAGE_FAMILY
read -p "${ORANGE}${BOLD}Enter image-project (default: debian-cloud): ${RESET}" IMAGE_PROJECT

# Default image-project if empty
IMAGE_PROJECT=${IMAGE_PROJECT:-debian-cloud}

# Validate
if [ -z "$REGION" ] || [ -z "$ZONE" ] || [ -z "$IMAGE_FAMILY" ]; then
    echo "${RED}${BOLD}ERROR: One or more values are empty. Aborting.${RESET}"
    exit 1
fi

# Set defaults
gcloud config set compute/region $REGION --quiet
gcloud config set compute/zone $ZONE --quiet

echo ""
echo "${GREEN}Region: ${WHITE}${BOLD}$REGION${RESET}"
echo "${GREEN}Zone: ${WHITE}${BOLD}$ZONE${RESET}"
echo "${GREEN}Image Family: ${WHITE}${BOLD}$IMAGE_FAMILY${RESET}"
echo "${GREEN}Image Project: ${WHITE}${BOLD}$IMAGE_PROJECT${RESET}"
echo ""

# ============================================================
# CREATE WEB SERVERS
# ============================================================
echo "${CYAN}${BOLD}Creating 3 web server instances...${RESET}"
echo ""

create_web_server() {
    local server_name=$1
    
    echo "${CYAN}  -> Creating $server_name in $ZONE...${RESET}"
    
    gcloud compute instances create $server_name \
      --zone=$ZONE \
      --tags=network-lb-tag \
      --machine-type=e2-small \
      --image-family=$IMAGE_FAMILY \
      --image-project=$IMAGE_PROJECT \
      --metadata=startup-script="#!/bin/bash
apt-get update
apt-get install apache2 -y
service apache2 restart
echo '<h3>Web Server: $server_name</h3>' | tee /var/www/html/index.html" \
      --quiet
    
    echo "${GREEN}  ✓ $server_name created${RESET}"
    echo ""
}

create_web_server web1
create_web_server web2
create_web_server web3

# ============================================================
# FIREWALL RULE
# ============================================================
echo "${CYAN}${BOLD}Creating firewall rule www-firewall-network-lb...${RESET}"

gcloud compute firewall-rules create www-firewall-network-lb \
    --target-tags network-lb-tag \
    --allow tcp:80 --quiet

echo "${GREEN}✓ Firewall rule created${RESET}"
echo ""

# ============================================================
# BANNER
# ============================================================
echo ""
echo "${GREEN}${BOLD}=========================================================${RESET}"
echo "${GREEN}${BOLD}       ✅  TASK 1 COMPLETED SUCCESSFULLY  ✅          ${RESET}"
echo "${GREEN}${BOLD}=========================================================${RESET}"
echo ""
echo "${YELLOW}Ab lab page pe jaake 'Check my progress' button dabao.${RESET}"
echo ""
echo "${CYAN}${BOLD}Thank you!${RESET}"
echo ""
