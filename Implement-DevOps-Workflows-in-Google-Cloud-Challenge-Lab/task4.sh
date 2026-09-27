#!/bin/bash

# ============================================================
# Task 4 — Deploy First Versions (Dev + Prod)
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
echo -e "${MAGENTA}${BOLD}   🚀 Task 4 — Deploy First Versions (Dev + Prod)     ${RESET}"
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
echo -e "${GREEN}   Enter Artifact Repo Name (from Task 1, e.g. my-repository): ${RESET}"
read REPO_NAME

echo ""
echo -e "${YELLOW}🔍 Confirming values:${RESET}"
echo -e "   Region         : ${BOLD}$REGION${RESET}"
echo -e "   Zone           : ${BOLD}$ZONE${RESET}"
echo -e "   Git Server IP  : ${BOLD}$GIT_SERVER_IP${RESET}"
echo -e "   Repo Name      : ${BOLD}$REPO_NAME${RESET}"
echo ""
echo -e "${YELLOW}✅ Confirm? (y/n): ${RESET}"
read CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo -e "${RED}❌ Aborted.${RESET}"
  exit 1
fi

export REGION ZONE GIT_SERVER_IP REPO_NAME
export PROJECT_ID=$(gcloud config get-value project)

# Image base path (yahan actual project ID aata hai)
IMAGE_BASE="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/sample-app:v1.0"

echo ""
echo -e "${CYAN}🔹 Image path: ${BOLD}$IMAGE_BASE${RESET}"
echo ""

# ---------- PART A: DEV ----------
echo -e "${CYAN}=====================================================${RESET}"
echo -e "${MAGENTA}${BOLD}   🧪 PART A — Deploy Dev Version                     ${RESET}"
echo -e "${CYAN}=====================================================${RESET}"

cd ~/sample-app

echo ""
echo -e "${CYAN}🔹 Step 4.A.1: Switching to 'dev' branch...${RESET}"
git checkout dev

echo ""
echo -e "${CYAN}🔹 Step 4.A.2: Inspecting dev/deployment.yaml...${RESET}"
if [ ! -f dev/deployment.yaml ]; then
  echo -e "${RED}❌ dev/deployment.yaml not found. Aborting.${RESET}"
  exit 1
fi
echo -e "${YELLOW}--- Original dev/deployment.yaml (top 30 lines) ---${RESET}"
head -30 dev/deployment.yaml

echo ""
echo -e "${CYAN}🔹 Step 4.A.3: Replacing <todo> and <PROJECT_ID> in dev/deployment.yaml...${RESET}"
# <todo> replace karo image se
sed -i "s|<todo>|${IMAGE_BASE}|g" dev/deployment.yaml
# Agar <PROJECT_ID> literal hai to usko bhi replace karo
sed -i "s|<PROJECT_ID>|${PROJECT_ID}|g" dev/deployment.yaml
# Agar ${PROJECT_ID} literal hai to bhi
sed -i "s|\${PROJECT_ID}|${PROJECT_ID}|g" dev/deployment.yaml
sed -i "s|<your-project-id>|${PROJECT_ID}|g" dev/deployment.yaml

echo -e "${GREEN}✅ dev/deployment.yaml updated.${RESET}"
echo -e "${YELLOW}--- Updated dev/deployment.yaml (top 30 lines) ---${RESET}"
head -30 dev/deployment.yaml

echo ""
echo -e "${CYAN}🔹 Step 4.A.4: Committing and pushing dev branch...${RESET}"
git add .
git commit -m "Deploy v1.0 on dev" || echo -e "${YELLOW}⚠ Nothing to commit.${RESET}"
git push --force http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/sample-app.git dev
echo -e "${GREEN}✅ Pushed to dev.${RESET}"

echo ""
echo -e "${CYAN}🔹 Step 4.A.5: Running Cloud Build for dev...${RESET}"
gcloud builds submit --config=cloudbuild-dev.yaml .
echo -e "${GREEN}✅ Dev build submitted.${RESET}"

echo ""
echo -e "${CYAN}🔹 Step 4.A.6: Exposing dev-deployment as LoadBalancer...${RESET}"
kubectl expose deployment development-deployment \
  --name=dev-deployment-service \
  --type=LoadBalancer \
  --port=8080 \
  --target-port=8080 \
  --namespace=dev 2>/dev/null \
  || echo -e "${YELLOW}⚠ Service may already exist, continuing...${RESET}"

echo ""
echo -e "${CYAN}🔹 Step 4.A.7: Waiting for LoadBalancer IP (max 3 min)...${RESET}"
for i in {1..18}; do
  DEV_LB_IP=$(kubectl get service dev-deployment-service -n dev -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  if [ -n "$DEV_LB_IP" ]; then
    break
  fi
  echo -e "${YELLOW}   ...waiting ($i/18)${RESET}"
  sleep 10
done

if [ -z "$DEV_LB_IP" ]; then
  echo -e "${RED}❌ Dev LoadBalancer IP not assigned in time.${RESET}"
else
  echo -e "${GREEN}✅ Dev LoadBalancer IP: $DEV_LB_IP${RESET}"
  echo -e "${CYAN}🔹 Testing /blue endpoint...${RESET}"
  curl -s -I http://${DEV_LB_IP}:8080/blue | head -1
fi

# ---------- PART B: PROD ----------
echo ""
echo -e "${CYAN}=====================================================${RESET}"
echo -e "${MAGENTA}${BOLD}   🏭 PART B — Deploy Prod Version                    ${RESET}"
echo -e "${CYAN}=====================================================${RESET}"

echo ""
echo -e "${CYAN}🔹 Step 4.B.1: Switching to 'master' branch...${RESET}"
git checkout master

echo ""
echo -e "${CYAN}🔹 Step 4.B.2: Replacing <todo> and <PROJECT_ID> in prod/deployment.yaml...${RESET}"
if [ ! -f prod/deployment.yaml ]; then
  echo -e "${RED}❌ prod/deployment.yaml not found. Aborting.${RESET}"
  exit 1
fi
sed -i "s|<todo>|${IMAGE_BASE}|g" prod/deployment.yaml
sed -i "s|<PROJECT_ID>|${PROJECT_ID}|g" prod/deployment.yaml
sed -i "s|\${PROJECT_ID}|${PROJECT_ID}|g" prod/deployment.yaml
sed -i "s|<your-project-id>|${PROJECT_ID}|g" prod/deployment.yaml

echo -e "${GREEN}✅ prod/deployment.yaml updated.${RESET}"

echo ""
echo -e "${CYAN}🔹 Step 4.B.3: Committing and pushing master branch...${RESET}"
git add .
git commit -m "Deploy v1.0 on master" || echo -e "${YELLOW}⚠ Nothing to commit.${RESET}"
git push --force http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/sample-app.git master
echo -e "${GREEN}✅ Pushed to master.${RESET}"

echo ""
echo -e "${CYAN}🔹 Step 4.B.4: Running Cloud Build for prod...${RESET}"
gcloud builds submit --config=cloudbuild.yaml .
echo -e "${GREEN}✅ Prod build submitted.${RESET}"

echo ""
echo -e "${CYAN}🔹 Step 4.B.5: Exposing production-deployment as LoadBalancer...${RESET}"
kubectl expose deployment production-deployment \
  --name=prod-deployment-service \
  --type=LoadBalancer \
  --port=8080 \
  --target-port=8080 \
  --namespace=prod 2>/dev/null \
  || echo -e "${YELLOW}⚠ Service may already exist, continuing...${RESET}"

echo ""
echo -e "${CYAN}🔹 Step 4.B.6: Waiting for LoadBalancer IP (max 3 min)...${RESET}"
for i in {1..18}; do
  PROD_LB_IP=$(kubectl get service prod-deployment-service -n prod -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  if [ -n "$PROD_LB_IP" ]; then
    break
  fi
  echo -e "${YELLOW}   ...waiting ($i/18)${RESET}"
  sleep 10
done

if [ -z "$PROD_LB_IP" ]; then
  echo -e "${RED}❌ Prod LoadBalancer IP not assigned in time.${RESET}"
else
  echo -e "${GREEN}✅ Prod LoadBalancer IP: $PROD_LB_IP${RESET}"
  echo -e "${CYAN}🔹 Testing /blue endpoint...${RESET}"
  curl -s -I http://${PROD_LB_IP}:8080/blue | head -1
fi

# ---------- FINAL ----------
echo ""
echo -e "${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════════╗"
echo "║   🎉  TASK 4 COMPLETED!  🎉                  ║"
echo "║                                              ║"
echo "║   Dev  IP : ${DEV_LB_IP:-pending}"
echo "║   Prod IP : ${PROD_LB_IP:-pending}"
echo "║                                              ║"
echo "║   👉 Go to lab page → Check my progress      ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${RESET}"
