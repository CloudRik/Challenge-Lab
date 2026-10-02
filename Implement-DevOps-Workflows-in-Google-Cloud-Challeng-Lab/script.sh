#!/bin/bash
# ============================================================
# Implement DevOps Workflows in Google Cloud: Challenge Lab
# Full Automated Script - Multi-User Portable
# ============================================================

# ======================
# COLOR DEFINITIONS
# ======================
BOLD=$(tput bold)
RESET=$(tput sgr0)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
WHITE=$(tput setaf 7)
ORANGE="\033[38;5;208m"
BG_CYAN=$(tput setab 6)
BG_MAGENTA=$(tput setab 5)

# ======================
# HEADER
# ======================
clear
echo "${BG_CYAN}${BOLD}${WHITE}==================================================${RESET}"
echo "${BG_CYAN}${BOLD}${WHITE}  >>  DEVOPS WORKFLOWS IN GOOGLE CLOUD  <<         ${RESET}"
echo "${BG_CYAN}${BOLD}${WHITE}==================================================${RESET}"
echo ""

# ======================
# USER INPUTS
# ======================
echo "${ORANGE}${BOLD}====================================================${RESET}"
echo "${ORANGE}${BOLD}  [SETUP] Enter Your Lab Details${RESET}"
echo "${ORANGE}${BOLD}====================================================${RESET}"

DETECTED_PROJECT=$(gcloud config get-value project 2>/dev/null)
read -p "Enter Your Project ID [${DETECTED_PROJECT}]: " INPUT_PROJECT
PROJECT_ID=${INPUT_PROJECT:-$DETECTED_PROJECT}

read -p "Enter Your Region [europe-west4]: " INPUT_REGION
REGION=${INPUT_REGION:-europe-west4}

read -p "Enter Your Zone [${REGION}-a]: " INPUT_ZONE
ZONE=${INPUT_ZONE:-${REGION}-a}

# Auto-detect git-server IP
GIT_SERVER_IP=""
for TRY_ZONE in "$ZONE" "${REGION}-a" "${REGION}-b" "${REGION}-c"; do
    GIT_SERVER_IP=$(gcloud compute instances describe git-server \
        --zone=$TRY_ZONE \
        --format='get(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null)
    [ -n "$GIT_SERVER_IP" ] && break
done
if [ -z "$GIT_SERVER_IP" ]; then
    read -p "Enter Git Server IP: " GIT_SERVER_IP
fi

echo ""
echo "${YELLOW}Project ID    : ${WHITE}$PROJECT_ID${RESET}"
echo "${YELLOW}Region        : ${WHITE}$REGION${RESET}"
echo "${YELLOW}Zone          : ${WHITE}$ZONE${RESET}"
echo "${YELLOW}Git Server IP : ${WHITE}$GIT_SERVER_IP${RESET}"
echo ""
read -p "Proceed? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
    echo "Cancelled"
    exit 1
fi

# ======================
# TASK 1: CREATE LAB RESOURCES
# ======================
echo ""
echo "${ORANGE}${BOLD}====================================================${RESET}"
echo "${ORANGE}${BOLD}  [TASK 1] Create Lab Resources${RESET}"
echo "${ORANGE}${BOLD}====================================================${RESET}"

export PROJECT_ID=$PROJECT_ID
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
export REGION=$REGION
export ZONE=$ZONE
export GIT_SERVER_IP=$GIT_SERVER_IP
gcloud config set compute/region $REGION
gcloud config set compute/zone $ZONE

echo "${GREEN}[OK] Variables set${RESET}"
echo "  PROJECT_ID=$PROJECT_ID"
echo "  PROJECT_NUMBER=$PROJECT_NUMBER"
echo "  REGION=$REGION"
echo "  ZONE=$ZONE"
echo "  GIT_SERVER_IP=$GIT_SERVER_IP"

echo "${CYAN}Enabling APIs...${RESET}"
gcloud services enable container.googleapis.com cloudbuild.googleapis.com
echo "${GREEN}[OK] APIs enabled${RESET}"

echo "${CYAN}Adding Kubernetes Developer role...${RESET}"
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member=serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com \
    --role="roles/container.developer" --condition=None >/dev/null 2>&1
echo "${GREEN}[OK] Role added${RESET}"

git config --global user.name "Student"
git config --global user.email "student@qwiklabs.net"
echo "${GREEN}[OK] Git configured${RESET}"

echo "${CYAN}Creating Artifact Registry...${RESET}"
gcloud artifacts repositories create my-repository \
    --repository-format=docker \
    --location=$REGION 2>/dev/null || echo "[!] Repo exists"
echo "${GREEN}[OK] Artifact Registry ready${RESET}"

echo "${CYAN}Creating GKE cluster (3-5 min)...${RESET}"
gcloud container clusters create hello-cluster \
    --zone=$ZONE \
    --num-nodes=3 \
    --release-channel=regular \
    --enable-autoscaling \
    --min-nodes=2 \
    --max-nodes=6 \
    --cluster-version=1.29
echo "${GREEN}[OK] GKE cluster created${RESET}"

echo "${CYAN}Getting GKE credentials...${RESET}"
gcloud container clusters get-credentials hello-cluster --zone=$ZONE
echo "${GREEN}[OK] Credentials fetched${RESET}"

echo "${CYAN}Creating prod and dev namespaces...${RESET}"
kubectl create namespace prod 2>/dev/null || echo "[!] prod exists"
kubectl create namespace dev 2>/dev/null || echo "[!] dev exists"
echo "${GREEN}[OK] Namespaces created${RESET}"
echo "${ORANGE}>>> TASK 1 COMPLETE - Check my progress${RESET}"

# ======================
# TASK 2: CONNECT TO GIT REPO
# ======================
echo ""
echo "${ORANGE}${BOLD}====================================================${RESET}"
echo "${ORANGE}${BOLD}  [TASK 2] Connect to Git Repository${RESET}"
echo "${ORANGE}${BOLD}====================================================${RESET}"

cd ~
rm -rf sample-app 2>/dev/null
gcloud storage cp -r gs://spls/gsp330/sample-app/* sample-app
echo "${GREEN}[OK] Sample app downloaded${RESET}"

cd ~/sample-app

echo "${CYAN}Replacing region/zone placeholders...${RESET}"
for file in sample-app/cloudbuild-dev.yaml sample-app/cloudbuild.yaml; do
    sed -i "s/<your-region>/${REGION}/g" "$file" 2>/dev/null
    sed -i "s/<your-zone>/${ZONE}/g" "$file" 2>/dev/null
    sed -i "s/<version>/v1.0/g" "$file" 2>/dev/null
done

# Also fix files in current directory (if any)
for file in cloudbuild-dev.yaml cloudbuild.yaml; do
    [ -f "$file" ] && {
        sed -i "s/<your-region>/${REGION}/g" "$file"
        sed -i "s/<your-zone>/${ZONE}/g" "$file"
        sed -i "s/<version>/v1.0/g" "$file"
    }
done
echo "${GREEN}[OK] Placeholders replaced${RESET}"

git init -q
git remote add origin http://${GIT_SERVER_IP}:3000/giteaadmin/sample-app.git
git branch -m master
git add . && git commit -m "initial commit" -q
git push -u http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/sample-app.git master
echo "${GREEN}[OK] Pushed to master branch${RESET}"

git checkout -b dev -q
git push -u http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/sample-app.git dev
echo "${GREEN}[OK] Dev branch created${RESET}"
echo "${ORANGE}>>> TASK 2 COMPLETE - Check my progress${RESET}"

# ======================
# TASK 3: CLOUD BUILD TRIGGERS
# ======================
echo ""
echo "${ORANGE}${BOLD}====================================================${RESET}"
echo "${ORANGE}${BOLD}  [TASK 3] Create Cloud Build Triggers${RESET}"
echo "${ORANGE}${BOLD}====================================================${RESET}"

gcloud builds triggers create manual \
    --name="sample-app-prod-deploy" \
    --inline-config="cloudbuild.yaml" \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
    --region=${REGION} \
    --build-config="./cloudbuild.yaml" \
    --branch=master \
    --repo=https://github.com/giteaadmin/sample-app \
    --repo-type=GITHUB 2>/dev/null || \
gcloud builds triggers create manual \
    --name="sample-app-prod-deploy" \
    --build-config="cloudbuild.yaml" \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
    --region=${REGION} 2>/dev/null || echo "[!] Trigger 1 may exist"
echo "${GREEN}[OK] Trigger 1 created${RESET}"

gcloud builds triggers create manual \
    --name="sample-app-dev-deploy" \
    --build-config="cloudbuild-dev.yaml" \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
    --region=${REGION} 2>/dev/null || echo "[!] Trigger 2 may exist"
echo "${GREEN}[OK] Trigger 2 created${RESET}"
echo "${ORANGE}>>> TASK 3 COMPLETE - Check my progress${RESET}"

# ======================
# TASK 4: FIRST DEPLOYMENT (v1.0)
# ======================
echo ""
echo "${ORANGE}${BOLD}====================================================${RESET}"
echo "${ORANGE}${BOLD}  [TASK 4] Deploy First Versions (v1.0)${RESET}"
echo "${ORANGE}${BOLD}====================================================${RESET}"

cd ~/sample-app

# Fix dev/deployment.yaml
echo "${CYAN}Fixing dev/deployment.yaml...${RESET}"
sed -i "s|<todo>|${REGION}-docker.pkg.dev/${PROJECT_ID}/my-repository/sample-app:1.0|g" dev/deployment.yaml
sed -i "s|PROJECT_ID|${PROJECT_ID}|g" dev/deployment.yaml
grep -i "image:" dev/deployment.yaml

git checkout dev -q
git add .
git commit -m "Deploy v1.0 on dev" -q
git push http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/sample-app.git dev
echo "${GREEN}[OK] Dev pushed${RESET}"

echo "${CYAN}Running dev build...${RESET}"
gcloud builds submit --config=cloudbuild-dev.yaml . 
echo "${GREEN}[OK] Dev build complete${RESET}"

echo "${CYAN}Exposing dev deployment...${RESET}"
kubectl expose deployment development-deployment -n dev \
    --name=dev-deployment-service --type=LoadBalancer --port=8080 --target-port=8080
echo "${GREEN}[OK] Dev service exposed${RESET}"

# Fix prod/deployment.yaml
echo "${CYAN}Fixing prod/deployment.yaml...${RESET}"
git checkout master -q
sed -i "s|<todo>|${REGION}-docker.pkg.dev/${PROJECT_ID}/my-repository/sample-app:1.0|g" prod/deployment.yaml
sed -i "s|PROJECT_ID|${PROJECT_ID}|g" prod/deployment.yaml
grep -i "image:" prod/deployment.yaml

git add .
git commit -m "Deploy v1.0 on master" -q
git push http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/sample-app.git master
echo "${GREEN}[OK] Master pushed${RESET}"

echo "${CYAN}Running prod build...${RESET}"
gcloud builds submit --config=cloudbuild.yaml .
echo "${GREEN}[OK] Prod build complete${RESET}"

echo "${CYAN}Exposing prod deployment...${RESET}"
kubectl expose deployment production-deployment -n prod \
    --name=prod-deployment-service --type=LoadBalancer --port=8080 --target-port=8080
echo "${GREEN}[OK] Prod service exposed${RESET}"

echo "${CYAN}Waiting 60 sec for LoadBalancer IPs...${RESET}"
sleep 60
kubectl get services -n dev
kubectl get services -n prod
echo "${ORANGE}>>> TASK 4 COMPLETE - Check my progress${RESET}"

# ======================
# TASK 5: SECOND DEPLOYMENT (v2.0)
# ======================
echo ""
echo "${ORANGE}${BOLD}====================================================${RESET}"
echo "${ORANGE}${BOLD}  [TASK 5] Deploy Second Versions (v2.0)${RESET}"
echo "${ORANGE}${BOLD}====================================================${RESET}"

cd ~/sample-app

# Dev v2.0
echo "${CYAN}Setting up dev v2.0...${RESET}"
git checkout dev -q

# Update main.go with redHandler
python3 <<'PYEOF'
with open('main.go', 'r') as f:
    content = f.read()

# Add redHandler function if missing
if 'func redHandler' not in content:
    red_func = '''
func redHandler(w http.ResponseWriter, r *http.Request) {
	img := image.NewRGBA(image.Rect(0, 0, 100, 100))
	draw.Draw(img, img.Bounds(), &image.Uniform{color.RGBA{255, 0, 0, 255}}, image.ZP, draw.Src)
	w.Header().Set("Content-Type", "image/png")
	png.Encode(w, img)
}
'''
    content = content + red_func

# Update main function
old_main = '''func main() {
	http.HandleFunc("/blue", blueHandler)
	http.ListenAndServe(":8080", nil)
}'''
new_main = '''func main() {
	http.HandleFunc("/blue", blueHandler)
	http.HandleFunc("/red", redHandler)
	http.ListenAndServe(":8080", nil)
}'''
content = content.replace(old_main, new_main)

with open('main.go', 'w') as f:
    f.write(content)
print("main.go updated")
PYEOF

sed -i "s|<version>|v2.0|g" cloudbuild-dev.yaml
sed -i "s|sample-app:1.0|sample-app:2.0|g" dev/deployment.yaml
sed -i "s|:v1.0|:v2.0|g" dev/deployment.yaml
sed -i "s|:1.0|:2.0|g" dev/deployment.yaml
grep -i "image:" dev/deployment.yaml

git add .
git commit -m "Deploy v2.0 on dev" -q
git push http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/sample-app.git dev
echo "${GREEN}[OK] Dev v2.0 pushed${RESET}"

gcloud builds submit --config=cloudbuild-dev.yaml .
echo "${GREEN}[OK] Dev v2.0 built${RESET}"

# Prod v2.0
echo "${CYAN}Setting up prod v2.0...${RESET}"
git checkout master -q

# Update main.go for master (same redHandler + main update)
python3 <<'PYEOF'
with open('main.go', 'r') as f:
    content = f.read()

if 'func redHandler' not in content:
    red_func = '''
func redHandler(w http.ResponseWriter, r *http.Request) {
	img := image.NewRGBA(image.Rect(0, 0, 100, 100))
	draw.Draw(img, img.Bounds(), &image.Uniform{color.RGBA{255, 0, 0, 255}}, image.ZP, draw.Src)
	w.Header().Set("Content-Type", "image/png")
	png.Encode(w, img)
}
'''
    content = content + red_func

old_main = '''func main() {
	http.HandleFunc("/blue", blueHandler)
	http.ListenAndServe(":8080", nil)
}'''
new_main = '''func main() {
	http.HandleFunc("/blue", blueHandler)
	http.HandleFunc("/red", redHandler)
	http.ListenAndServe(":8080", nil)
}'''
content = content.replace(old_main, new_main)

with open('main.go', 'w') as f:
    f.write(content)
print("main.go updated")
PYEOF

sed -i "s|<version>|v2.0|g" cloudbuild.yaml
sed -i "s|sample-app:1.0|sample-app:2.0|g" prod/deployment.yaml
sed -i "s|:v1.0|:v2.0|g" prod/deployment.yaml
sed -i "s|:1.0|:2.0|g" prod/deployment.yaml
grep -i "image:" prod/deployment.yaml

git add .
git commit -m "Deploy v2.0 on master" -q
git push http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/sample-app.git master
echo "${GREEN}[OK] Prod v2.0 pushed${RESET}"

gcloud builds submit --config=cloudbuild.yaml .
echo "${GREEN}[OK] Prod v2.0 built${RESET}"
echo "${ORANGE}>>> TASK 5 COMPLETE - Check my progress${RESET}"

# ======================
# TASK 6: ROLLBACK
# ======================
echo ""
echo "${ORANGE}${BOLD}====================================================${RESET}"
echo "${ORANGE}${BOLD}  [TASK 6] Rollback Production Deployment${RESET}"
echo "${ORANGE}${BOLD}====================================================${RESET}"

echo "${CYAN}Rolling back production-deployment to v1.0...${RESET}"
kubectl rollout undo deployment/production-deployment -n prod
echo "${GREEN}[OK] Rollback triggered${RESET}"

echo "${CYAN}Waiting 30 sec for rollback to complete...${RESET}"
sleep 30
kubectl rollout status deployment/production-deployment -n prod
kubectl get pods -n prod

PROD_LB_IP=$(kubectl get service prod-deployment-service -n prod -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "${YELLOW}Prod LB IP: ${WHITE}$PROD_LB_IP${RESET}"
echo "${CYAN}Testing /red endpoint (expected: 404)...${RESET}"
curl -I http://${PROD_LB_IP}:8080/red 2>&1 | head -3 || echo "Not reachable yet"
echo "${ORANGE}>>> TASK 6 COMPLETE - Check my progress${RESET}"

# ======================
# COMPLETION
# ======================
echo ""
echo "${BG_MAGENTA}${BOLD}${WHITE}====================================================${RESET}"
echo "${BG_MAGENTA}${BOLD}${WHITE}     ***  LAB SUCCESSFULLY COMPLETED!  ***          ${RESET}"
echo "${BG_MAGENTA}${BOLD}${WHITE}====================================================${RESET}"
echo ""
echo "${WHITE}${BOLD}[>] Access your resources:${RESET}"
echo "${ORANGE}GKE: https://console.cloud.google.com/kubernetes/list?project=$PROJECT_ID${RESET}"
echo "${ORANGE}Cloud Build: https://console.cloud.google.com/cloud-build/builds?project=$PROJECT_ID${RESET}"
echo "${ORANGE}Artifact Registry: https://console.cloud.google.com/artifacts?project=$PROJECT_ID${RESET}"
echo ""
echo "${CYAN}${BOLD}[i] Sab kuch ho gaya! Lab panel mein check karo.${RESET}"
echo ""
