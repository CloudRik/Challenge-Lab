#!/bin/bash

# ============================================================
# Task 2 + Task 3 — FIXED Version
# ============================================================

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
RED='\033[1;31m'
BOLD='\033[1m'
RESET='\033[0m'

clear

echo -e "${CYAN}=====================================================${RESET}"
echo -e "${MAGENTA}${BOLD}   🚀 Task 2 + 3 — Git Repo & Cloud Build Triggers   ${RESET}"
echo -e "${CYAN}=====================================================${RESET}"
echo ""

# ---------- INPUTS ----------
echo -e "${GREEN}${BOLD}👉 Please provide the values from your lab page:${RESET}"
echo ""
echo -e "${GREEN}   Enter REGION (e.g. us-central1): ${RESET}"
read REGION
echo -e "${GREEN}   Enter ZONE (e.g. us-central1-c): ${RESET}"
read ZONE
echo -e "${GREEN}   Enter Git Server IP (from Lab setup panel): ${RESET}"
read GIT_SERVER_IP

echo ""
echo -e "${YELLOW}🔍 Confirming values:${RESET}"
echo -e "   Region         : ${BOLD}$REGION${RESET}"
echo -e "   Zone           : ${BOLD}$ZONE${RESET}"
echo -e "   Git Server IP  : ${BOLD}$GIT_SERVER_IP${RESET}"
echo ""
echo -e "${YELLOW}✅ Confirm? (y/n): ${RESET}"
read CONFIRM

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo -e "${RED}❌ Aborted.${RESET}"
  exit 1
fi

export REGION ZONE GIT_SERVER_IP

# ---------- TASK 2 ----------
echo ""
echo -e "${CYAN}=====================================================${RESET}"
echo -e "${MAGENTA}${BOLD}   📦 TASK 2 — Connect to the Git repository         ${RESET}"
echo -e "${CYAN}=====================================================${RESET}"

# Clean previous broken attempt
echo ""
echo -e "${CYAN}🔹 Cleaning any previous attempt...${RESET}"
cd ~
rm -rf ~/sample-app 2>/dev/null
echo -e "${GREEN}✅ Cleaned.${RESET}"

# Step 2.1: Create folder FIRST, then copy
echo ""
echo -e "${CYAN}🔹 Step 2.1: Creating ~/sample-app and copying sample code...${RESET}"
mkdir -p ~/sample-app
gcloud storage cp -r gs://spls/gsp330/sample-app/* ~/sample-app/
echo -e "${GREEN}✅ Sample code copied.${RESET}"

# Verify files exist
if [ ! -f ~/sample-app/cloudbuild.yaml ]; then
  echo -e "${RED}❌ cloudbuild.yaml not found. Copy failed. Aborting.${RESET}"
  exit 1
fi

# Step 2.2: Replace placeholders
echo ""
echo -e "${CYAN}🔹 Step 2.2: Replacing placeholders in yaml files...${RESET}"
cd ~/sample-app
for file in cloudbuild-dev.yaml cloudbuild.yaml; do
  if [ -f "$file" ]; then
    sed -i "s/<your-region>/${REGION}/g" "$file"
    sed -i "s/<your-zone>/${ZONE}/g" "$file"
    sed -i "s/<version>/v1.0/g" "$file"
    echo -e "${GREEN}   ✅ Updated $file${RESET}"
  else
    echo -e "${YELLOW}   ⚠ $file not found, skipping${RESET}"
  fi
done

# Step 2.3: Init git repo & push master
echo ""
echo -e "${CYAN}🔹 Step 2.3: Initializing Git repo & pushing to master...${RESET}"
git init -q
git remote remove origin 2>/dev/null || true
git remote add origin http://${GIT_SERVER_IP}:3000/giteaadmin/sample-app.git
git branch -M master
git add .
git commit -q -m "initial commit"
git push -u http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/sample-app.git master
echo -e "${GREEN}✅ Pushed to master branch.${RESET}"

# Step 2.4: Create dev branch & push
echo ""
echo -e "${CYAN}🔹 Step 2.4: Creating 'dev' branch & pushing...${RESET}"
git checkout -b dev -q
git push -u http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/sample-app.git dev
echo -e "${GREEN}✅ Pushed to dev branch.${RESET}"

# Step 2.5: Verify
echo ""
echo -e "${CYAN}🔹 Step 2.5: Verifying branches...${RESET}"
git branch -a
echo -e "${GREEN}✅ Task 2 complete.${RESET}"

# ---------- TASK 3 ----------
echo ""
echo -e "${CYAN}=====================================================${RESET}"
echo -e "${MAGENTA}${BOLD}   ⚙️  TASK 3 — Create the Cloud Build Triggers       ${RESET}"
echo -e "${CYAN}=====================================================${RESET}"

export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')

# Note: Ab 2>/dev/null nahi hai, taaki error dikhe
echo ""
echo -e "${CYAN}🔹 Step 3.1: Creating trigger 'sample-app-prod-deploy'...${RESET}"
gcloud builds triggers create manual \
  --name="sample-app-prod-deploy" \
  --inline-config="cloudbuild.yaml" \
  --service-account="projects/${PROJECT_ID}/serviceAccounts/${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --region=${REGION} \
  --repo="http://${GIT_SERVER_IP}:3000/giteaadmin/sample-app" \
  --repo-type=GITHUB \
  --branch="master" \
  --build-config="cloudbuild.yaml" \
  --substitutions="_REGION=${REGION},_ZONE=${ZONE}"

echo ""
echo -e "${CYAN}🔹 Step 3.2: Creating trigger 'sample-app-dev-deploy'...${RESET}"
gcloud builds triggers create manual \
  --name="sample-app-dev-deploy" \
  --inline-config="cloudbuild-dev.yaml" \
  --service-account="projects/${PROJECT_ID}/serviceAccounts/${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --region=${REGION} \
  --repo="http://${GIT_SERVER_IP}:3000/giteaadmin/sample-app" \
  --repo-type=GITHUB \
  --branch="dev" \
  --build-config="cloudbuild-dev.yaml" \
  --substitutions="_REGION=${REGION},_ZONE=${ZONE}"

echo ""
echo -e "${CYAN}🔹 Step 3.3: Verifying triggers...${RESET}"
gcloud builds triggers list --region=${REGION}

echo ""
echo -e "${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════════╗"
echo "║   🎉  TASK 2 + 3 COMPLETED!  🎉              ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${RESET}"
