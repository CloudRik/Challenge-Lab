#!/bin/bash

# ============================================================
# Task 5 — Deploy Second Versions (Dev + Prod) — v2.0
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
echo -e "${MAGENTA}${BOLD}   🚀 Task 5 — Deploy Second Versions (v2.0)          ${RESET}"
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

IMAGE_V1="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/sample-app:v1.0"
IMAGE_V2="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/sample-app:v2.0"

echo ""
echo -e "${CYAN}🔹 Image v1: ${BOLD}$IMAGE_V1${RESET}"
echo -e "${CYAN}🔹 Image v2: ${BOLD}$IMAGE_V2${RESET}"
echo ""

# ---------- HELPER: Write new main.go ----------
write_main_go() {
  cat > ~/sample-app/main.go << 'EOF'
package main

import (
	"image"
	"image/color"
	"image/draw"
	"image/png"
	"net/http"
)

func blueHandler(w http.ResponseWriter, r *http.Request) {
	img := image.NewRGBA(image.Rect(0, 0, 100, 100))
	draw.Draw(img, img.Bounds(), &image.Uniform{color.RGBA{0, 0, 255, 255}}, image.ZP, draw.Src)
	w.Header().Set("Content-Type", "image/png")
	png.Encode(w, img)
}

func redHandler(w http.ResponseWriter, r *http.Request) {
	img := image.NewRGBA(image.Rect(0, 0, 100, 100))
	draw.Draw(img, img.Bounds(), &image.Uniform{color.RGBA{255, 0, 0, 255}}, image.ZP, draw.Src)
	w.Header().Set("Content-Type", "image/png")
	png.Encode(w, img)
}

func main() {
	http.HandleFunc("/blue", blueHandler)
	http.HandleFunc("/red", redHandler)
	http.ListenAndServe(":8080", nil)
}
EOF
}

# ---------- PART A: DEV ----------
echo -e "${CYAN}=====================================================${RESET}"
echo -e "${MAGENTA}${BOLD}   🧪 PART A — Deploy Dev v2.0                        ${RESET}"
echo -e "${CYAN}=====================================================${RESET}"

cd ~/sample-app

echo ""
echo -e "${CYAN}🔹 Step 5.A.1: Switching to 'dev' branch...${RESET}"
git checkout dev

echo ""
echo -e "${CYAN}🔹 Step 5.A.2: Updating main.go with redHandler...${RESET}"
write_main_go
echo -e "${GREEN}✅ main.go updated.${RESET}"

echo ""
echo -e "${CYAN}🔹 Step 5.A.3: Bumping version to v2.0 in cloudbuild-dev.yaml...${RESET}"
sed -i 's|:v1\.0|:v2.0|g' cloudbuild-dev.yaml
sed -i 's|v1\.0|v2.0|g' cloudbuild-dev.yaml
grep -i "v2.0\|_VERSION\|tag" cloudbuild-dev.yaml || echo -e "${YELLOW}⚠ Check version manually${RESET}"
echo -e "${GREEN}✅ cloudbuild-dev.yaml updated.${RESET}"

echo ""
echo -e "${CYAN}🔹 Step 5.A.4: Updating dev/deployment.yaml to v2.0...${RESET}"
sed -i 's|:v1\.0|:v2.0|g' dev/deployment.yaml
sed -i 's|v1\.0|v2.0|g' dev/deployment.yaml
grep "image:" dev/deployment.yaml
echo -e "${GREEN}✅ dev/deployment.yaml updated.${RESET}"

echo ""
echo -e "${CYAN}🔹 Step 5.A.5: Committing and pushing dev...${RESET}"
git add .
git commit -m "Deploy v2.0 on dev" || echo -e "${YELLOW}⚠ Nothing to commit.${RESET}"
git push --force http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/sample-app.git dev
echo -e "${GREEN}✅ Pushed to dev.${RESET}"

echo ""
echo -e "${CYAN}🔹 Step 5.A.6: Running Cloud Build for dev (v2.0)...${RESET}"
gcloud builds submit --config=cloudbuild-dev.yaml .
echo -e "${GREEN}✅ Dev v2.0 build submitted.${RESET}"

echo ""
echo -e "${CYAN}🔹 Step 5.A.7: Waiting for LoadBalancer propagation (30s)...${RESET}"
sleep 30
DEV_LB_IP=$(kubectl get service dev-deployment-service -n dev -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
echo -e "${GREEN}✅ Dev LB IP: $DEV_LB_IP${RESET}"

echo -e "${CYAN}🔹 Testing /red endpoint on dev...${RESET}"
curl -s -I http://${DEV_LB_IP}:8080/red | head -1

# ---------- PART B: PROD ----------
echo ""
echo -e "${CYAN}=====================================================${RESET}"
echo -e "${MAGENTA}${BOLD}   🏭 PART B — Deploy Prod v2.0                       ${RESET}"
echo -e "${CYAN}=====================================================${RESET}"

echo ""
echo -e "${CYAN}🔹 Step 5.B.1: Switching to 'master' branch...${RESET}"
git checkout master

echo ""
echo -e "${CYAN}🔹 Step 5.B.2: Updating main.go with redHandler...${RESET}"
write_main_go
echo -e "${GREEN}✅ main.go updated.${RESET}"

echo ""
echo -e "${CYAN}🔹 Step 5.B.3: Bumping version to v2.0 in cloudbuild.yaml...${RESET}"
sed -i 's|:v1\.0|:v2.0|g' cloudbuild.yaml
sed -i 's|v1\.0|v2.0|g' cloudbuild.yaml
grep -i "v2.0\|_VERSION\|tag" cloudbuild.yaml || echo -e "${YELLOW}⚠ Check version manually${RESET}"
echo -e "${GREEN}✅ cloudbuild.yaml updated.${RESET}"

echo ""
echo -e "${CYAN}🔹 Step 5.B.4: Updating prod/deployment.yaml to v2.0...${RESET}"
sed -i 's|:v1\.0|:v2.0|g' prod/deployment.yaml
sed -i 's|v1\.0|v2.0|g' prod/deployment.yaml
grep "image:" prod/deployment.yaml
echo -e "${GREEN}✅ prod/deployment.yaml updated.${RESET}"

echo ""
echo -e "${CYAN}🔹 Step 5.B.5: Committing and pushing master...${RESET}"
git add .
git commit -m "Deploy v2.0 on master" || echo -e "${YELLOW}⚠ Nothing to commit.${RESET}"
git push --force http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/sample-app.git master
echo -e "${GREEN}✅ Pushed to master.${RESET}"

echo ""
echo -e "${CYAN}🔹 Step 5.B.6: Running Cloud Build for prod (v2.0)...${RESET}"
gcloud builds submit --config=cloudbuild.yaml .
echo -e "${GREEN}✅ Prod v2.0 build submitted.${RESET}"

echo ""
echo -e "${CYAN}🔹 Step 5.B.7: Waiting for LoadBalancer propagation (30s)...${RESET}"
sleep 30
PROD_LB_IP=$(kubectl get service prod-deployment-service -n prod -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
echo -e "${GREEN}✅ Prod LB IP: $PROD_LB_IP${RESET}"

echo -e "${CYAN}🔹 Testing /red endpoint on prod...${RESET}"
curl -s -I http://${PROD_LB_IP}:8080/red | head -1

# ---------- FINAL ----------
echo ""
echo -e "${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════════╗"
echo "║   🎉  TASK 5 COMPLETED!  🎉                  ║"
echo "║                                              ║"
echo "║   Dev  IP : ${DEV_LB_IP:-pending}"
echo "║   Prod IP : ${PROD_LB_IP:-pending}"
echo "║                                              ║"
echo "║   👉 Go to lab page → Check my progress      ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${RESET}"
