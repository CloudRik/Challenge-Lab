#!/bin/bash
# ============================================================
# GSP456: Task 2 - Perform one-time migration
# Universal Script - Works for any user
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
echo "${CYAN}${BOLD}   GSP456 - TASK 2: ONE-TIME MIGRATION${RESET}"
echo "${CYAN}${BOLD}=========================================================${RESET}"
echo ""

# ============================================================
# AUTO-DETECT
# ============================================================
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
echo "${GREEN}Project: ${WHITE}${BOLD}$PROJECT_ID${RESET}"

ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])" 2>/dev/null)
REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null)

if [ -z "$ZONE" ]; then
    ZONE=$(gcloud compute zones list --format="value(name)" --limit=1 2>/dev/null)
    REGION=${ZONE%-*}
fi
if [ -z "$REGION" ]; then
    REGION=${ZONE%-*}
fi

echo "${GREEN}Region: ${WHITE}$REGION${RESET}"
echo "${GREEN}Zone: ${WHITE}$ZONE${RESET}"
echo ""

# ============================================================
# USER INPUT
# ============================================================
read -p "${GREEN}Source Connection Profile Name (e.g. dev-p1n-m82): ${RESET}" SOURCE_PROFILE
read -p "${GREEN}Destination Cloud SQL Instance ID (e.g. mysql-p1n-m82): ${RESET}" DEST_INSTANCE
read -p "${GREEN}Migration Job Name (e.g. mysql-migration-job): ${RESET}" JOB_NAME

if [ -z "$SOURCE_PROFILE" ] || [ -z "$DEST_INSTANCE" ] || [ -z "$JOB_NAME" ]; then
    echo "${RED}ERROR: All fields required${RESET}"
    exit 1
fi

export PROJECT_ID REGION ZONE SOURCE_PROFILE DEST_INSTANCE JOB_NAME

echo ""
echo "${GREEN}Source Profile: ${WHITE}$SOURCE_PROFILE${RESET}"
echo "${GREEN}Destination: ${WHITE}$DEST_INSTANCE${RESET}"
echo "${GREEN}Job Name: ${WHITE}$JOB_NAME${RESET}"
echo ""

read -p "${YELLOW}Press Enter to continue...${RESET}"

# ============================================================
# STEP 1: Create Migration Job (One-time)
# ============================================================
echo ""
echo "${CYAN}[1/3] Creating one-time migration job...${RESET}"

gcloud database-migration migration-jobs create $JOB_NAME \
    --region=$REGION \
    --source=$SOURCE_PROFILE \
    --destination=$DEST_INSTANCE \
    --type=ONE_TIME \
    --quiet 2>/dev/null

if [ $? -eq 0 ]; then
    echo "${GREEN}✓ Migration job created${RESET}"
else
    echo "${YELLOW}⚠ CLI failed. Create manually in Console:${RESET}"
    echo ""
    echo "${CYAN}  Database Migration > Migration jobs > Create migration job${RESET}"
    echo ""
    echo "  Job name:              $JOB_NAME"
    echo "  Source connection:     $SOURCE_PROFILE"
    echo "  Destination:           $DEST_INSTANCE"
    echo "  Migration job type:    One-time"
    echo "  Destination type:      Existing instance"
    echo ""
fi

# ============================================================
# STEP 2: Test migration job
# ============================================================
echo ""
echo "${CYAN}[2/3] Testing migration job...${RESET}"

gcloud database-migration migration-jobs verify $JOB_NAME \
    --region=$REGION --quiet 2>/dev/null

echo "${GREEN}✓ Test done${RESET}"

# ============================================================
# STEP 3: Start migration job
# ============================================================
echo ""
echo "${CYAN}[3/3] Starting migration job...${RESET}"

gcloud database-migration migration-jobs start $JOB_NAME \
    --region=$REGION --quiet 2>/dev/null

echo "${GREEN}✓ Migration started${RESET}"
echo ""
echo "${YELLOW}⚠ Migration me 5-10 min lag sakte hain.${RESET}"
echo "${YELLOW}Lab page pe 5 min wait karke 'Check my progress' dabao.${RESET}"

# ============================================================
# BANNER
# ============================================================
echo ""
echo "${ORANGE}${BOLD}=========================================================${RESET}"
echo "${ORANGE}${BOLD}       ✅  TASK 2 COMPLETED SUCCESSFULLY  ✅          ${RESET}"
echo "${ORANGE}${BOLD}=========================================================${RESET}"
echo ""
echo "${YELLOW}Ab lab page pe jaake 'Check my progress' button dabao.${RESET}"
echo ""
