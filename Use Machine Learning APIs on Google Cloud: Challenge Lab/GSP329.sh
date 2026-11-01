#!/bin/bash

# ===============================================================
# ArcadeSuite - Integrate with Machine Learning APIs Challenge Lab
# ===============================================================

# -------------------- Color Definitions --------------------
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'

BOLD='\033[1m'
UNDERLINE='\033[4m'
RESET='\033[0m'

BG_GREEN='\033[42m'
BG_BLUE='\033[44m'
BG_RED='\033[41m'

clear

# -------------------- Banner --------------------
echo -e "${BG_BLUE}${WHITE}${BOLD}==============================================================${RESET}"
echo -e "${BG_BLUE}${WHITE}${BOLD}      ARCADESUITE - INITIATING EXECUTION                       ${RESET}"
echo -e "${BG_BLUE}${WHITE}${BOLD} Integrate with Machine Learning APIs Challenge Lab           ${RESET}"
echo -e "${BG_BLUE}${WHITE}${BOLD}==============================================================${RESET}"
echo

# -------------------- Input Section --------------------
echo -e "${CYAN}${BOLD}Enter the required lab parameters:${RESET}"
echo

read -p "Enter LANGUAGE (example: en): " LANGUAGE
read -p "Enter LOCALE (example: en_US): " LOCALE
read -p "Enter BIGQUERY_ROLE (example: roles/bigquery.admin): " BIGQUERY_ROLE
read -p "Enter CLOUD_STORAGE_ROLE (example: roles/storage.admin): " CLOUD_STORAGE_ROLE

echo
echo -e "${YELLOW}${BOLD}Using Configuration:${RESET}"
echo -e "${GREEN}Language           : ${LANGUAGE}${RESET}"
echo -e "${GREEN}Locale             : ${LOCALE}${RESET}"
echo -e "${GREEN}BigQuery Role      : ${BIGQUERY_ROLE}${RESET}"
echo -e "${GREEN}Cloud Storage Role : ${CLOUD_STORAGE_ROLE}${RESET}"
echo

# -------------------- Project Info --------------------
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [[ -z "$PROJECT_ID" ]]; then
    echo -e "${RED}${BOLD}Error: No active Google Cloud project found.${RESET}"
    exit 1
fi

echo -e "${GREEN}Project ID: ${PROJECT_ID}${RESET}"
echo

# -------------------- Service Account Creation --------------------
echo -e "${MAGENTA}${BOLD}Creating Service Account...${RESET}"

gcloud iam service-accounts create sample-sa \
    --display-name="Sample Service Account" 2>/dev/null

# -------------------- Assign Roles --------------------
echo -e "${MAGENTA}${BOLD}Assigning IAM Roles...${RESET}"

SA="sample-sa@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA}" \
    --role="${BIGQUERY_ROLE}"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA}" \
    --role="${CLOUD_STORAGE_ROLE}"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA}" \
    --role="roles/serviceusage.serviceUsageConsumer"

echo -e "${GREEN}IAM roles assigned successfully.${RESET}"
echo

# -------------------- Wait for IAM Propagation --------------------
echo -e "${YELLOW}${BOLD}Waiting 120 seconds for IAM propagation...${RESET}"
for i in {120..1}; do
    printf "\r${CYAN}%3d seconds remaining...${RESET}" "$i"
    sleep 1
done
echo -e "\n${GREEN}IAM propagation complete.${RESET}"
echo

# -------------------- Create Service Account Key --------------------
echo -e "${MAGENTA}${BOLD}Creating Service Account Key...${RESET}"

gcloud iam service-accounts keys create sample-sa-key.json \
    --iam-account="${SA}"

export GOOGLE_APPLICATION_CREDENTIALS="${PWD}/sample-sa-key.json"

echo -e "${GREEN}Credentials exported:${RESET} ${GOOGLE_APPLICATION_CREDENTIALS}"
echo

# -------------------- Download Python Script --------------------
echo -e "${MAGENTA}${BOLD}Downloading Analysis Script...${RESET}"

wget -q -O analyze-images-v2.py \
"https://raw.githubusercontent.com/guys-in-the-cloud/cloud-skill-boosts/main/Challenge-labs/Integrate%20with%20Machine%20Learning%20APIs%3A%20Challenge%20Lab/analyze-images-v2.py"

echo -e "${GREEN}Script downloaded successfully.${RESET}"
echo

# -------------------- Update Locale --------------------
echo -e "${MAGENTA}${BOLD}Updating Locale to ${LOCALE}...${RESET}"

sed -i "s/'en'/'${LOCALE}'/g" analyze-images-v2.py

echo -e "${GREEN}Locale updated successfully.${RESET}"
echo

# -------------------- Run Analysis --------------------
echo -e "${MAGENTA}${BOLD}Running Image Analysis...${RESET}"

python3 analyze-images-v2.py
python3 analyze-images-v2.py "$PROJECT_ID" "$PROJECT_ID"

echo -e "${GREEN}Image analysis completed.${RESET}"
echo

# -------------------- BigQuery Results --------------------
echo -e "${MAGENTA}${BOLD}Querying BigQuery Results...${RESET}"

bq query --use_legacy_sql=false \
"SELECT locale, COUNT(locale) AS lcount
 FROM image_classification_dataset.image_text_detail
 GROUP BY locale
 ORDER BY lcount DESC"

echo

# -------------------- Lab Complete Banner --------------------
echo -e "${BG_GREEN}${BLACK}${BOLD}==============================================================${RESET}"
echo -e "${BG_GREEN}${BLACK}${BOLD}                                                              ${RESET}"
echo -e "${BG_GREEN}${BLACK}${BOLD}              🎉  LAB COMPLETED SUCCESSFULLY!  🎉              ${RESET}"
echo -e "${BG_GREEN}${BLACK}${BOLD}                                                              ${RESET}"
echo -e "${BG_GREEN}${BLACK}${BOLD}==============================================================${RESET}"
echo
echo -e "${CYAN}${BOLD}Tasks Completed:${RESET}"
echo -e "${GREEN}✓${RESET} Service account created"
echo -e "${GREEN}✓${RESET} IAM roles assigned"
echo -e "${GREEN}✓${RESET} Service account key generated"
echo -e "${GREEN}✓${RESET} Image analysis script downloaded"
echo -e "${GREEN}✓${RESET} Machine Learning API analysis executed"
echo -e "${GREEN}✓${RESET} BigQuery results displayed"
echo
echo -e "${MAGENTA}${BOLD}==============================================================${RESET}"
echo -e "${CYAN}${BOLD}              Powered by ArcadeSuite                          ${RESET}"
echo -e "${CYAN}${BOLD}         Your Partner in Cloud & Tech Learning                ${RESET}"
echo -e "${MAGENTA}${BOLD}==============================================================${RESET}"
echo
echo -e "${YELLOW}${BOLD}Thank you for using ArcadeSuite! Keep learning, keep growing.${RESET}"
echo

# -------------------- Cleanup --------------------
rm -f -- "$0"
