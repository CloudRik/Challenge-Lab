#!/bin/bash

# Colors
CYAN='\033[0;96m'
GREEN='\033[0;92m'
YELLOW='\033[0;93m'
RED='\033[0;91m'
MAGENTA='\033[0;95m'
BLUE='\033[0;94m'
WHITE='\033[0;97m'
BOLD='\033[1m'
RESET='\033[0m'

clear
echo
echo "${CYAN}${BOLD}=================================================${RESET}"
echo "${CYAN}${BOLD}   SCALE OUT & UPDATE CONTAINERIZED APP (GSP354) ${RESET}"
echo "${CYAN}${BOLD}=================================================${RESET}"
echo

# ===============================
# UNIVERSAL ENVIRONMENT DETECTION
# ===============================
echo "${YELLOW}${BOLD}[1/6] Detecting environment...${RESET}"

# 1. Project ID auto-detect
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [ -z "$PROJECT_ID" ]; then
  read -p "Enter Project ID: " PROJECT_ID
fi

# 2. Zone auto-detect
ZONE=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-zone])" 2>/dev/null)

if [ -z "$ZONE" ]; then
  echo "${YELLOW}Zone not auto-detected.${RESET}"
  echo "${WHITE}Available zones:${RESET}"
  gcloud compute zones list --format="value(name)" | head -10
  read -p "Enter zone (e.g., us-central1-a): " ZONE
fi

# 3. Cluster name auto-detect
CLUSTER_NAME=$(gcloud container clusters list --format="value(name)" 2>/dev/null | head -1)

if [ -z "$CLUSTER_NAME" ]; then
  read -p "Enter GKE cluster name: " CLUSTER_NAME
fi

# 4. Lab-specific values (usually same across labs)
ARCHIVE_NAME="echo-web-v2.tar.gz"
APP_NAME="echo-app"
APP_VERSION="v2"
DEPLOYMENT_NAME="echo-app"
BUCKET="gs://$PROJECT_ID"

echo
echo "${CYAN}${BOLD}===== DETECTED VALUES =====${RESET}"
echo "${BLUE}Project:    ${WHITE}$PROJECT_ID${RESET}"
echo "${BLUE}Zone:       ${WHITE}$ZONE${RESET}"
echo "${BLUE}Cluster:    ${WHITE}$CLUSTER_NAME${RESET}"
echo "${BLUE}Archive:    ${WHITE}$ARCHIVE_NAME${RESET}"
echo "${BLUE}App:        ${WHITE}$APP_NAME:$APP_VERSION${RESET}"
echo "${BLUE}Bucket:     ${WHITE}$BUCKET${RESET}"
echo "${CYAN}${BOLD}===========================${RESET}"
echo

echo "${YELLOW}Press Enter to continue (Ctrl+C to cancel)...${RESET}"
read

# ===============================
# TASK 1: Build & Deploy Updated Application
# ===============================
echo
echo "${GREEN}${BOLD}[2/6] Task 1: Building Docker image with new tag${RESET}"

# Download archive
echo "${YELLOW}Downloading $ARCHIVE_NAME from $BUCKET...${RESET}"

if gsutil cp $BUCKET/$ARCHIVE_NAME . 2>/dev/null; then
  echo "${GREEN}Archive downloaded${RESET}"
else
  echo "${RED}Download failed. Trying alternative paths...${RESET}"
  gsutil ls $BUCKET/ | grep -i "echo"
  read -p "Enter exact archive name: " ARCHIVE_NAME
  gsutil cp $BUCKET/$ARCHIVE_NAME .
fi

# Extract
echo "${YELLOW}Extracting archive...${RESET}"
tar -xzf $ARCHIVE_NAME 2>/dev/null || unzip $ARCHIVE_NAME

# Find extracted directory
if [ -d "echo-web" ]; then
  cd echo-web
elif [ -d "echo-app" ]; then
  cd echo-app
else
  echo "${YELLOW}Finding extracted directory...${RESET}"
  EXTRACTED_DIR=$(ls -d */ 2>/dev/null | grep -E "echo|web|app" | head -1 | tr -d '/')
  if [ -n "$EXTRACTED_DIR" ]; then
    cd $EXTRACTED_DIR
  fi
fi

echo "${BLUE}Current directory: ${WHITE}$(pwd)${RESET}"

# Build Docker image
echo "${YELLOW}Building Docker image $APP_NAME:$APP_VERSION...${RESET}"
docker build -t $APP_NAME:$APP_VERSION . || {
  echo "${RED}Docker build failed. Check Dockerfile.${RESET}"
  ls -la
  exit 1
}

echo "${GREEN}Image built: $APP_NAME:$APP_VERSION${RESET}"
echo

echo "${WHITE}>>> LAB PAGE pe click karo: 'Build and deploy the updated application with a new tag'${RESET}"
echo "${WHITE}Press Enter when Check my progress passes...${RESET}"
read

# ===============================
# TASK 2: Push to Container Registry
# ===============================
echo
echo "${MAGENTA}${BOLD}[3/6] Task 2: Pushing image to gcr.io${RESET}"

# Tag for gcr.io
GCR_IMAGE="gcr.io/$PROJECT_ID/$APP_NAME:$APP_VERSION"
echo "${YELLOW}Tagging: $GCR_IMAGE${RESET}"
docker tag $APP_NAME:$APP_VERSION $GCR_IMAGE

# Configure Docker for gcr.io
echo "${YELLOW}Configuring Docker for gcr.io...${RESET}"
gcloud auth configure-docker --quiet 2>/dev/null

# Push
echo "${YELLOW}Pushing image...${RESET}"
docker push $GCR_IMAGE

echo "${GREEN}Image pushed: $GCR_IMAGE${RESET}"
echo

echo "${WHITE}>>> LAB PAGE pe click karo: 'Check that there is a tagged image in gcr.io for echo-app:v2'${RESET}"
echo "${WHITE}Press Enter when Check my progress passes...${RESET}"
read

# ===============================
# TASK 3: Scale out GKE cluster
# ===============================
echo
echo "${BLUE}${BOLD}[4/6] Task 3: Scaling out GKE cluster${RESET}"

# Get current cluster info
CURRENT_NODES=$(gcloud container clusters describe $CLUSTER_NAME \
  --zone=$ZONE --format="value(currentNodeCount)" 2>/dev/null)

echo "${BLUE}Current nodes: ${WHITE}$CURRENT_NODES${RESET}"

# Scale cluster
echo "${YELLOW}Scaling cluster to 3 nodes...${RESET}"
gcloud container clusters resize $CLUSTER_NAME \
  --num-nodes=3 \
  --zone=$ZONE \
  --quiet

echo "${GREEN}Cluster scaled to 3 nodes${RESET}"
echo

echo "${WHITE}>>> LAB PAGE pe click karo: 'Scale out the cluster'${RESET}"
echo "${WHITE}Press Enter when Check my progress passes...${RESET}"
read

# ===============================
# TASK 4: Update deployment
# ===============================
echo
echo "${MAGENTA}${BOLD}[5/6] Task 4: Updating deployment with new image${RESET}"

# Get cluster credentials
echo "${YELLOW}Fetching cluster credentials...${RESET}"
gcloud container clusters get-credentials $CLUSTER_NAME --zone=$ZONE --quiet

# Get current deployment name
CURRENT_DEPLOY=$(kubectl get deployments -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
echo "${BLUE}Current deployment: ${WHITE}$CURRENT_DEPLOY${RESET}"

# Update deployment image
echo "${YELLOW}Updating deployment image...${RESET}"
kubectl set image deployment/$CURRENT_DEPLOY \
  "*=$GCR_IMAGE" \
  --record=false

# Wait for rollout
echo "${YELLOW}Waiting for rollout...${RESET}"
kubectl rollout status deployment/$CURRENT_DEPLOY --timeout=300s

echo "${GREEN}Deployment updated${RESET}"
echo

echo "${WHITE}>>> LAB PAGE pe click karo: 'Update the deployment'${RESET}"
echo "${WHITE}Press Enter when Check my progress passes...${RESET}"
read

# ===============================
# VERIFICATION
# ===============================
echo
echo "${CYAN}${BOLD}[6/6] VERIFICATION${RESET}"
echo

echo "${YELLOW}Cluster status:${RESET}"
gcloud container clusters list --format="table(name,zone,currentNodeCount,status)"
echo

echo "${YELLOW}Pods:${RESET}"
kubectl get pods
echo

echo "${YELLOW}Deployments:${RESET}"
kubectl get deployments
echo

echo "${YELLOW}Services:${RESET}"
kubectl get services
echo

echo "${YELLOW}Container Registry images:${RESET}"
gcloud container images list --repository=gcr.io/$PROJECT_ID
echo

echo "${YELLOW}Image details:${RESET}"
gcloud container images describe $GCR_IMAGE --format="value(image_summary.digest)" 2>/dev/null
echo

# ===============================
# FINAL
# ===============================
echo
echo "${CYAN}${BOLD}=================================================${RESET}"
echo "${CYAN}${BOLD}   LAB COMPLETED - GSP354${RESET}"
echo "${CYAN}${BOLD}=================================================${RESET}"
echo
echo "${GREEN}All tasks executed successfully!${RESET}"
echo "${WHITE}Final score check karo lab page pe.${RESET}"
echo
echo "${YELLOW}Service URL ke liye:${RESET}"
kubectl get services -o wide
echo
