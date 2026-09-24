#!/bin/bash
clear

# ==============================================================================
# GSP343 CHALLENGE LAB MASTER SCRIPT
# ==============================================================================

GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
MAGENTA=$(tput setaf 5)
ORANGE=$(tput setaf 208)
WHITE=$(tput setaf 7)
BOLD=$(tput bold)
RESET=$(tput sgr0)

echo "${CYAN}${BOLD}>>> GSP343 CHALLENGE LAB MASTER SCRIPT <<<${RESET}"
echo ""

# ==============================================================================
# INTERACTIVE VARIABLE SETUP
# ==============================================================================
echo "${BOLD}${GREEN}--- LAB CONFIGURATION SETUP ---${RESET}"
echo ""

# 1. Zone Auto-Detection (no Enter confirmation)
AUTO_ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])" 2>/dev/null)
if [[ -n "$AUTO_ZONE" ]]; then
    echo -e "${GREEN}Default zone detected: ${CYAN}$AUTO_ZONE${RESET}"
    ZONE=$AUTO_ZONE
else
    echo -e "${WHITE}Look at the ${BOLD}'Challenge scenario'${RESET}${WHITE} section in your lab instructions.${RESET}"
    read -p "${GREEN}Zone (e.g., us-central1-a): ${RESET}" ZONE
fi

# 2. Cluster Name
read -p "${GREEN}Cluster Name: ${RESET}" CLUSTER_NAME

# 3. Node Pool Name
read -p "${GREEN}Node Pool Name: ${RESET}" POOL_NAME

# 4. Max Replicas
read -p "${GREEN}Max Replicas: ${RESET}" MAX_REPLICAS

echo ""
echo -e "${BOLD}${GREEN}Configuration saved. Starting deployment...${RESET}"
echo ""

export PROJECT_ID=$(gcloud config get-value project)
gcloud config set compute/zone $ZONE >/dev/null 2>&1

# ==============================================================================
# EXECUTION PHASE
# ==============================================================================

echo "${BOLD}${CYAN}[*] Task 1: Creating Cluster & Deploying App...${RESET}"
gcloud container clusters create $CLUSTER_NAME \
    --zone=$ZONE \
    --machine-type=e2-standard-2 \
    --num-nodes=2 \
    --release-channel=rapid \
    --quiet

kubectl create namespace dev
kubectl create namespace prod

git clone https://github.com/GoogleCloudPlatform/microservices-demo.git
cd microservices-demo
kubectl apply -f ./release/kubernetes-manifests.yaml --namespace dev

echo "${YELLOW}Waiting for deployments to initialize (~2-3 mins)...${RESET}"
kubectl wait --for=condition=Available deployment/frontend --namespace dev --timeout=300s

echo ""
echo "${BOLD}${MAGENTA}[*] Task 2: Creating Optimized Node Pool & Migrating Workloads...${RESET}"
gcloud container node-pools create $POOL_NAME \
    --cluster=$CLUSTER_NAME \
    --machine-type=custom-2-3584 \
    --num-nodes=2 \
    --zone=$ZONE \
    --quiet

echo "${YELLOW}Cordoning and draining default-pool...${RESET}"
for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool=default-pool -o=name); do
    kubectl cordon "$node" >/dev/null 2>&1
done

for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool=default-pool -o=name); do
    kubectl drain --force --ignore-daemonsets --delete-emptydir-data --grace-period=10 "$node" >/dev/null 2>&1
done

echo "${YELLOW}Deleting default-pool...${RESET}"
gcloud container node-pools delete default-pool --cluster=$CLUSTER_NAME --zone=$ZONE --quiet

echo ""
echo "${BOLD}${CYAN}[*] Task 3: Applying Frontend Update (PDB & Image)...${RESET}"
kubectl create poddisruptionbudget onlineboutique-frontend-pdb \
    --selector app=frontend \
    --min-available 1 \
    --namespace dev

kubectl patch deployment frontend -n dev --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/image", "value":"gcr.io/qwiklabs-resources/onlineboutique-frontend:v2.1"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/imagePullPolicy", "value":"Always"}
]'
sleep 5

echo ""
echo "${BOLD}${MAGENTA}[*] Task 4: Autoscaling Frontend, Cluster, and Recommendation Service...${RESET}"
kubectl autoscale deployment frontend \
    --cpu-percent=50 \
    --min=1 \
    --max=$MAX_REPLICAS \
    --namespace dev

gcloud beta container clusters update $CLUSTER_NAME \
    --enable-autoscaling \
    --min-nodes 1 \
    --max-nodes 6 \
    --zone=$ZONE \
    --quiet

kubectl autoscale deployment recommendationservice \
    --cpu-percent=50 \
    --min=1 \
    --max=5 \
    --namespace dev

echo ""
echo "${BOLD}${ORANGE}====================================================================${RESET}"
echo "${BOLD}${ORANGE}>>> ALL TASKS COMPLETE! CLICK 'CHECK MY PROGRESS' NOW <<<${RESET}"
echo "${BOLD}${ORANGE}====================================================================${RESET}"
