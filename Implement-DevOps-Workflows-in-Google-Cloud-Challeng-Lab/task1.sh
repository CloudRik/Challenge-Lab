#!/bin/bash
# ============================================================
# Implement DevOps Workflows in Google Cloud: Challenge Lab
# TASK 1 ONLY - Create Lab Resources
# ============================================================

# ======================
# COLORS
# ======================
BOLD=$(tput bold)
RESET=$(tput sgr0)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
WHITE=$(tput setaf 7)
RED=$(tput setaf 1)
ORANGE="\033[38;5;208m"
BG_CYAN=$(tput setab 6)

# ======================
# HEADER
# ======================
clear
echo "${BG_CYAN}${BOLD}${WHITE}==================================================${RESET}"
echo "${BG_CYAN}${BOLD}${WHITE}   >>  TASK 1: CREATE LAB RESOURCES  <<            ${RESET}"
echo "${BG_CYAN}${BOLD}${WHITE}==================================================${RESET}"
echo ""

# ======================
# STEP 1: SET VARIABLES
# ======================
echo "${ORANGE}${BOLD}[STEP 1] Setting variables...${RESET}"

export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
export REGION=europe-west1
export ZONE=europe-west1-b
gcloud config set compute/region $REGION
gcloud config set compute/zone $ZONE
export GIT_SERVER_IP=$(gcloud compute instances describe git-server \
    --zone=$ZONE \
    --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

echo "${GREEN}[OK] PROJECT_ID: $PROJECT_ID${RESET}"
echo "${GREEN}[OK] PROJECT_NUMBER: $PROJECT_NUMBER${RESET}"
echo "${GREEN}[OK] REGION: $REGION${RESET}"
echo "${GREEN}[OK] ZONE: $ZONE${RESET}"
echo "${GREEN}[OK] GIT_SERVER_IP: $GIT_SERVER_IP${RESET}"
echo ""

# ======================
# STEP 2: ENABLE APIs
# ======================
echo "${ORANGE}${BOLD}[STEP 2] Enabling APIs...${RESET}"
gcloud services enable container.googleapis.com \
    cloudbuild.googleapis.com
echo "${GREEN}[OK] APIs enabled${RESET}"
echo ""

# ======================
# STEP 3: ADD KUBERNETES DEVELOPER ROLE
# ======================
echo "${ORANGE}${BOLD}[STEP 3] Adding Kubernetes Developer role to Cloud Build SA...${RESET}"
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member=serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com \
    --role="roles/container.developer" --condition=None >/dev/null 2>&1
echo "${GREEN}[OK] Role added${RESET}"
echo ""

# ======================
# STEP 4: CONFIGURE GIT
# ======================
echo "${ORANGE}${BOLD}[STEP 4] Configuring Git...${RESET}"
git config --global user.name "Student"
git config --global user.email "student@qwiklabs.net"
echo "${GREEN}[OK] Git configured${RESET}"
echo ""

# ======================
# STEP 5: CREATE ARTIFACT REGISTRY
# ======================
echo "${ORANGE}${BOLD}[STEP 5] Creating Artifact Registry repository...${RESET}"
gcloud artifacts repositories create my-repository \
    --repository-format=docker \
    --location=$REGION 2>/dev/null || echo "[!] Repo may already exist"
echo "${GREEN}[OK] Artifact Registry ready${RESET}"
echo ""

# ======================
# STEP 6: CREATE GKE CLUSTER
# ======================
echo "${ORANGE}${BOLD}[STEP 6] Creating GKE cluster (3-5 min, please wait)...${RESET}"
gcloud container clusters create hello-cluster \
    --zone=$ZONE \
    --num-nodes=3 \
    --release-channel=regular \
    --enable-autoscaling \
    --min-nodes=2 \
    --max-nodes=6 \
    --cluster-version=1.29
echo "${GREEN}[OK] GKE cluster created${RESET}"
echo ""

# ======================
# STEP 7: GET GKE CREDENTIALS
# ======================
echo "${ORANGE}${BOLD}[STEP 7] Getting GKE credentials...${RESET}"
gcloud container clusters get-credentials hello-cluster --zone=$ZONE
echo "${GREEN}[OK] Credentials fetched${RESET}"
echo ""

# ======================
# STEP 8: CREATE NAMESPACES
# ======================
echo "${ORANGE}${BOLD}[STEP 8] Creating prod and dev namespaces...${RESET}"
kubectl create namespace prod 2>/dev/null || echo "[!] prod already exists"
kubectl create namespace dev 2>/dev/null || echo "[!] dev already exists"
echo "${GREEN}[OK] Namespaces created${RESET}"
echo ""

# ======================
# VERIFY
# ======================
echo "${ORANGE}${BOLD}[VERIFY] Checking resources...${RESET}"
echo ""
echo "--- GKE Cluster ---"
gcloud container clusters list --zone=$ZONE
echo ""
echo "--- Namespaces ---"
kubectl get namespaces
echo ""
echo "--- Artifact Registry ---"
gcloud artifacts repositories list --location=$REGION
echo ""

# ======================
# COMPLETION
# ======================
echo "${BG_CYAN}${BOLD}${WHITE}==================================================${RESET}"
echo "${BG_CYAN}${BOLD}${WHITE}     ***  TASK 1 COMPLETE!  ***                    ${RESET}"
echo "${BG_CYAN}${BOLD}${WHITE}==================================================${RESET}"
echo ""
echo "${YELLOW}Ab lab panel mein Task 1 ke saamne 'Check my progress' click karo.${RESET}"
echo ""
