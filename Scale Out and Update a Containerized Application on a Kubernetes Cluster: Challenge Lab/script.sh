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
# ENVIRONMENT DETECTION (User Input)
# ===============================
echo "${YELLOW}${BOLD}Environment Setup${RESET}"
echo

# Project ID
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
  read -p "Enter Project ID: " PROJECT_ID
fi
echo "${BLUE}Project: ${WHITE}$PROJECT_ID${RESET}"

# Zone
ZONE=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-zone])" 2>/dev/null)
if [ -z "$ZONE" ]; then
  read -p "Enter Zone (e.g., us-central1-a): " ZONE
fi
echo "${BLUE}Zone: ${WHITE}$ZONE${RESET}"

# Cluster name (auto-detect from GKE)
CLUSTER_NAME=$(gcloud container clusters list --format="value(name)" 2>/dev/null | head -1)
if [ -z "$CLUSTER_NAME" ]; then
  echo "${YELLOW}No cluster found. Please enter cluster name:${RESET}"
  read -p "Cluster name (e.g., echo-web): " CLUSTER_NAME
fi
echo "${BLUE}Cluster: ${WHITE}$CLUSTER_NAME${RESET}"

# App details (from lab)
APP_NAME="echo-app"
APP_TAG="v2"
DEPLOYMENT_NAME="echo-web"
ARCHIVE_NAME="echo-web-v2.tar.gz"
BUCKET="gs://$PROJECT_ID"

echo "${BLUE}App: ${WHITE}$APP_NAME:$APP_TAG${RESET}"
echo "${BLUE}Deployment: ${WHITE}$DEPLOYMENT_NAME${RESET}"
echo

read -p "Press Enter to continue (Ctrl+C to cancel)..."

# ===============================
# TASK 1: Build Docker image with new tag
# ===============================
echo
echo "${GREEN}${BOLD}[TASK 1] Build and deploy updated application${RESET}"

# Download archive
echo "${YELLOW}Downloading $ARCHIVE_NAME from $BUCKET...${RESET}"
if ! gsutil cp $BUCKET/$ARCHIVE_NAME . 2>/dev/null; then
  echo "${RED}Archive not found at $BUCKET/$ARCHIVE_NAME${RESET}"
  echo "${YELLOW}Searching bucket contents...${RESET}"
  gsutil ls $BUCKET/ | head -10
  read -p "Enter exact archive name: " ARCHIVE_NAME
  gsutil cp $BUCKET/$ARCHIVE_NAME .
fi

# Extract
echo "${YELLOW}Extracting $ARCHIVE_NAME...${RESET}"
tar -xzf $ARCHIVE_NAME 2>/dev/null || unzip -o $ARCHIVE_NAME

# Find extracted directory
if [ -d "echo-web" ]; then
  cd echo-web
elif [ -d "echo-app" ]; then
  cd echo-app
else
  EXTRACTED_DIR=$(ls -d */ 2>/dev/null | grep -iE "echo|web|app" | head -1 | tr -d '/')
  [ -n "$EXTRACTED_DIR" ] && cd $EXTRACTED_DIR
fi

echo "${BLUE}Current dir: ${WHITE}$(pwd)${RESET}"

# Build Docker image
echo "${YELLOW}Building Docker image $APP_NAME:$APP_TAG...${RESET}"
docker build -t $APP_NAME:$APP_TAG . || {
  echo "${RED}Docker build failed${RESET}"
  exit 1
}

echo "${GREEN}Image built: $APP_NAME:$APP_TAG${RESET}"
echo

echo "${YELLOW}${BOLD}NOTE: Task 1 has NO Check my progress button — proceed directly.${RESET}"
echo "${WHITE}Press Enter to continue...${RESET}"
read

# ===============================
# TASK 2: Push to Container Registry
# ===============================
echo
echo "${MAGENTA}${BOLD}[TASK 2] Push image to gcr.io${RESET}"

GCR_IMAGE="gcr.io/$PROJECT_ID/$APP_NAME:$APP_TAG"
echo "${YELLOW}Tagging: $GCR_IMAGE${RESET}"
docker tag $APP_NAME:$APP_TAG $GCR_IMAGE

echo "${YELLOW}Configuring Docker for gcr.io...${RESET}"
gcloud auth configure-docker --quiet

echo "${YELLOW}Pushing image...${RESET}"
docker push $GCR_IMAGE

echo "${GREEN}Image pushed: $GCR_IMAGE${RESET}"
echo

echo "${WHITE}>>> LAB PAGE pe click karo: 'Check that there is a tagged image in gcr.io for echo-app:v2'${RESET}"
echo "${WHITE}Press Enter when Check my progress passes...${RESET}"
read

# ===============================
# TASK 3: Deploy updated application to K8s cluster
# ===============================
echo
echo "${BLUE}${BOLD}[TASK 3] Deploy updated application to Kubernetes${RESET}"

# Get cluster credentials
echo "${YELLOW}Fetching cluster credentials...${RESET}"
gcloud container clusters get-credentials $CLUSTER_NAME --zone=$ZONE

# Deploy the application
echo "${YELLOW}Creating deployment $DEPLOYMENT_NAME...${RESET}"

kubectl create deployment $DEPLOYMENT_NAME \
  --image=$GCR_IMAGE \
  --dry-run=client -o yaml | kubectl apply -f -

# Expose on port 80
echo "${YELLOW}Exposing deployment on port 80...${RESET}"
kubectl expose deployment $DEPLOYMENT_NAME \
  --type=LoadBalancer \
  --port=80 \
  --target-port=8080 \
  --dry-run=client -o yaml | kubectl apply -f -

echo "${GREEN}Deployment applied${RESET}"
echo

echo "${WHITE}>>> LAB PAGE pe click karo: 'Deploy the updated application version (v2) to the Kubernetes cluster'${RESET}"
echo "${WHITE}Press Enter when Check my progress passes...${RESET}"
read

# ===============================
# TASK 4: Scale out the application
# ===============================
echo
echo "${MAGENTA}${BOLD}[TASK 4] Scale out application to 2 replicas${RESET}"

echo "${YELLOW}Scaling $DEPLOYMENT_NAME to 2 replicas...${RESET}"
kubectl scale deployment $DEPLOYMENT_NAME --replicas=2

echo "${YELLOW}Waiting for rollout...${RESET}"
kubectl rollout status deployment/$DEPLOYMENT_NAME --timeout=300s

echo "${GREEN}Application scaled to 2 replicas${RESET}"
echo

echo "${WHITE}>>> LAB PAGE pe click karo: 'Scale out the kubernetes application so that it is running 2 replicas'${RESET}"
echo "${WHITE}Press Enter when Check my progress passes...${RESET}"
read

# ===============================
# TASK 5: Confirm application is running
# ===============================
echo
echo "${CYAN}${BOLD}[TASK 5] Verify the application is running${RESET}"

echo "${YELLOW}Waiting for external IP...${RESET}"
for i in $(seq 1 30); do
  EXTERNAL_IP=$(kubectl get service $DEPLOYMENT_NAME -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  if [ -n "$EXTERNAL_IP" ]; then
    break
  fi
  echo "  Waiting... ($i/30)"
  sleep 10
done

if [ -n "$EXTERNAL_IP" ]; then
  echo "${GREEN}External IP: $EXTERNAL_IP${RESET}"
  echo
  echo "${YELLOW}Testing application...${RESET}"
  curl -s http://$EXTERNAL_IP
  echo
else
  echo "${RED}External IP not assigned yet. Try again later.${RESET}"
fi
echo

echo "${WHITE}>>> LAB PAGE pe click karo: 'Verify your deployed application service is responding correctly'${RESET}"
echo "${WHITE}Press Enter when Check my progress passes...${RESET}"
read

# ===============================
# VERIFICATION
# ===============================
echo
echo "${CYAN}${BOLD}=== VERIFICATION ===${RESET}"
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

echo "${YELLOW}GCR images:${RESET}"
gcloud container images list --repository=gcr.io/$PROJECT_ID
echo

echo "${CYAN}${BOLD}=================================================${RESET}"
echo "${CYAN}${BOLD}   LAB COMPLETED - GSP354${RESET}"
echo "${CYAN}${BOLD}=================================================${RESET}"
echo
echo "${GREEN}All tasks executed successfully!${RESET}"
echo "${WHITE}Final score check karo lab page pe.${RESET}"
echo
