#!/bin/bash
clear

# Define color variables
BLACK=`tput setaf 0`
RED=`tput setaf 1`
GREEN=`tput setaf 2`
YELLOW=`tput setaf 3`
BLUE=`tput setaf 4`
MAGENTA=`tput setaf 5`
CYAN=`tput setaf 6`
WHITE=`tput setaf 7`

BG_BLACK=`tput setab 0`
BG_RED=`tput setab 1`
BG_GREEN=`tput setab 2`
BG_YELLOW=`tput setab 3`
BG_BLUE=`tput setab 4`
BG_MAGENTA=`tput setab 5`
BG_CYAN=`tput setab 6`
BG_WHITE=`tput setab 7`

BOLD=`tput bold`
RESET=`tput sgr0`

echo "${CYAN}${BOLD}=======================================================${RESET}"
echo "${MAGENTA}${BOLD}               POWERED BY ARCADESUITE                  ${RESET}"
echo "${CYAN}${BOLD}=======================================================${RESET}"

#----------------------------------------------------start--------------------------------------------------#

echo "${YELLOW}${BOLD}Please provide the required details:${RESET}"
echo

echo -n "${CYAN}${BOLD}Enter Repository Name (e.g., valkyrie-docker): ${RESET}"
read REPO
echo -n "${MAGENTA}${BOLD}Enter Docker Image Name (e.g., valkyrie-dev): ${RESET}"
read DCKR_IMG
echo -n "${YELLOW}${BOLD}Enter Tag Name (e.g., v0.0.2): ${RESET}"
read TAG
echo -n "${GREEN}${BOLD}Enter Zone (e.g., us-east1-d): ${RESET}"
read ZONE

export REPO="$REPO"
export DCKR_IMG="$DCKR_IMG"
export TAG="$TAG"
export ZONE="$ZONE"

export PROJECT_ID=$(gcloud config get-value project)
export REGION="${ZONE%-*}"

echo
echo "${GREEN}${BOLD}Starting Deployment Process...${RESET}"
echo

# Step 1: Sourcing setup script...
echo "${MAGENTA}${BOLD}Sourcing setup script...${RESET}"
source <(gsutil cat gs://cloud-training/gsp318/marking/setup_marking_v2.sh)

# Step 2: Downloading and extracting application...
echo "${GREEN}${BOLD}Downloading and extracting application...${RESET}"
gsutil cp gs://spls/gsp318/valkyrie-app.tgz .
tar -xzf valkyrie-app.tgz
cd valkyrie-app

# Step 3: Creating Dockerfile...
echo "${YELLOW}${BOLD}Creating Dockerfile...${RESET}"
cat > Dockerfile <<EOF
FROM golang:1.10
WORKDIR /go/src/app
COPY source .
RUN go install -v
ENTRYPOINT ["app","-single=true","-port=8080"]
EOF

# Step 4: Building Docker image...
echo "${BLUE}${BOLD}Building Docker image...${RESET}"
docker build -t $DCKR_IMG:$TAG .

# Step 5: Executing Step 1 script...
echo "${MAGENTA}${BOLD}Executing Step 1 script...${RESET}"
cd ..
./step1_v2.sh

# Step 6: Running Docker container...
echo "${CYAN}${BOLD}Running Docker container...${RESET}"
cd valkyrie-app
docker run -d -p 8080:8080 $DCKR_IMG:$TAG

# Step 7: Executing Step 2 script...
echo "${MAGENTA}${BOLD}Executing Step 2 script...${RESET}"
cd ..
./step2_v2.sh

cd valkyrie-app

# Step 8: Creating Artifact Repository...
echo "${YELLOW}${BOLD}Creating Artifact Repository...${RESET}"
gcloud artifacts repositories create $REPO \
    --repository-format=docker \
    --location=$REGION \
    --description="awesome lab" \
    --async

# Step 9: Configuring Docker authentication...
echo "${BLUE}${BOLD}Configuring Docker authentication...${RESET}"
gcloud auth configure-docker $REGION-docker.pkg.dev --quiet

sleep 30

# Step 10: Tagging and pushing Docker image...
echo "${CYAN}${BOLD}Tagging and pushing Docker image...${RESET}"

Image_ID=$(docker images --format='{{.ID}}' | head -n 1)

docker tag $Image_ID $REGION-docker.pkg.dev/$PROJECT_ID/$REPO/$DCKR_IMG:$TAG

docker push $REGION-docker.pkg.dev/$PROJECT_ID/$REPO/$DCKR_IMG:$TAG

# Step 11: Updating Kubernetes deployment...
echo "${GREEN}${BOLD}Updating Kubernetes deployment...${RESET}"
sed -i s#IMAGE_HERE#$REGION-docker.pkg.dev/$PROJECT_ID/$REPO/$DCKR_IMG:$TAG#g k8s/deployment.yaml

# Step 12: Configuring Kubernetes cluster...
echo "${YELLOW}${BOLD}Configuring Kubernetes cluster...${RESET}"
gcloud container clusters get-credentials valkyrie-dev --zone $ZONE

# Step 13: Deploying application to Kubernetes...
echo "${BLUE}${BOLD}Deploying application to Kubernetes...${RESET}"
kubectl create -f k8s/deployment.yaml
kubectl create -f k8s/service.yaml

echo ""

# Final Banner
echo "${GREEN}${BOLD}"
cat << "EOF"
  _____                      _      _       
 / ____|                    | |    | |      
| |     ___  _ __ ___  _ __ | | ___| |_ ___ 
| |    / _ \| '_ ` _ \| '_ \| |/ _ \ __/ _ \
| |___| (_) | | | | | | |_) | |  __/ ||  __/
 \_____\___/|_| |_| |_| .__/|_|\___|\__\___|
                      | |                    
                      |_|                    
EOF
echo "${RESET}"
echo "${MAGENTA}${BOLD}=======================================================${RESET}"
echo "${CYAN}${BOLD}               POWERED BY ARCADESUITE                  ${RESET}"
echo "${MAGENTA}${BOLD}=======================================================${RESET}"
echo "${GREEN}${BOLD}             LAB COMPLETED SUCCESSFULLY!               ${RESET}"
echo "${MAGENTA}${BOLD}=======================================================${RESET}"
echo ""

cd ~
remove_files() {
    for file in *; do
        if [[ "$file" == gsp* || "$file" == arc* || "$file" == shell* ]]; then
            if [[ -f "$file" ]]; then
                rm "$file"
                echo "File removed: $file"
            fi
        fi
    done
}
remove_files
