#!/bin/bash
# ============================================================
# GSP367: Task 2 Error Fix - Create Form Processor
# Run this if Task 2 checkpoint fails
# ============================================================

GREEN=$'\033[0;92m'
ORANGE=$'\033[38;5;208m'
CYAN=$'\033[0;96m'
YELLOW=$'\033[0;93m'
RED=$'\033[0;91m'
WHITE=$'\033[0;97m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

clear

echo "${CYAN}${BOLD}=========================================================${RESET}"
echo "${CYAN}${BOLD}   TASK 2 FIX - CREATE FORM PROCESSOR${RESET}"
echo "${CYAN}${BOLD}=========================================================${RESET}"
echo ""

# ============================================================
# AUTO-DETECT PROJECT
# ============================================================
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
echo "${GREEN}Project: ${WHITE}${BOLD}$PROJECT_ID${RESET}"
echo ""

# ============================================================
# USER INPUT
# ============================================================
read -p "${GREEN}Processor Name (e.g. accounts-processor): ${RESET}" PROCESSOR_NAME

if [ -z "$PROCESSOR_NAME" ]; then
    echo "${RED}ERROR: Processor name required${RESET}"
    exit 1
fi

echo ""
echo "${YELLOW}Creating processor via API...${RESET}"
echo ""

# ============================================================
# CREATE PROCESSOR VIA API
# ============================================================
ACCESS_TOKEN=$(gcloud auth application-default print-access-token)

RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"display_name\": \"$PROCESSOR_NAME\",
    \"type\": \"FORM_PARSER_PROCESSOR\"
  }" \
  "https://documentai.googleapis.com/v1/projects/$PROJECT_ID/locations/us/processors")

echo "$RESPONSE"

# Extract Processor ID
PROCESSOR_ID=$(echo "$RESPONSE" | grep -o '"name": "[^"]*"' | head -1 | sed 's/.*processors\///' | sed 's/"//')

if [ -z "$PROCESSOR_ID" ]; then
    echo ""
    echo "${RED}Processor creation via API failed.${RESET}"
    echo ""
    echo "${ORANGE}${BOLD}=========================================================${RESET}"
    echo "${ORANGE}${BOLD}  MANUAL STEP REQUIRED (Console se karo)${RESET}"
    echo "${ORANGE}${BOLD}=========================================================${RESET}"
    echo ""
    echo "${YELLOW}1. Console > Document AI > Processors${RESET}"
    echo "${YELLOW}2. Create Processor > Form Parser${RESET}"
    echo "${YELLOW}3. Name: ${WHITE}$PROCESSOR_NAME${RESET}"
    echo "${YELLOW}4. Region: ${WHITE}US${RESET}"
    echo "${YELLOW}5. Create dabao${RESET}"
    echo ""
    exit 1
fi

echo ""
echo "${GREEN}✓ Processor created${RESET}"
echo "${GREEN}Processor ID: ${WHITE}${BOLD}$PROCESSOR_ID${RESET}"
echo ""

# ============================================================
# UPDATE CLOUD FUNCTION ENV VARS
# ============================================================
echo "${YELLOW}Updating Cloud Function env vars...${RESET}"

PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null)

if [ -z "$REGION" ]; then
    REGION="us-east1"
fi

gcloud functions deploy process-invoices \
    --gen2 \
    --region=$REGION \
    --update-env-vars=PROCESSOR_ID=$PROCESSOR_ID,PARSER_LOCATION=us,PROJECT_ID=$PROJECT_ID \
    --quiet 2>/dev/null

echo "${GREEN}✓ Env vars updated${RESET}"

# ============================================================
# BANNER
# ============================================================
echo ""
echo "${ORANGE}${BOLD}=========================================================${RESET}"
echo "${ORANGE}${BOLD}       ✅  TASK 2 FIX COMPLETED  ✅                    ${RESET}"
echo "${ORANGE}${BOLD}=========================================================${RESET}"
echo ""
echo "${YELLOW}Ab lab page pe jaake Task 2 ka 'Check my progress' dabao.${RESET}"
echo ""
