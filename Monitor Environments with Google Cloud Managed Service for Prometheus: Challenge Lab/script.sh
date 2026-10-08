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
echo "${CYAN}${BOLD}   GCP MANAGED PROMETHEUS CHALLENGE LAB         ${RESET}"
echo "${CYAN}${BOLD}=================================================${RESET}"
echo

# ===============================
# ENVIRONMENT DETECTION
# ===============================
PROJECT=$(gcloud config get-value project 2>/dev/null)

# Zone detect karo
ZONE=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-zone])" 2>/dev/null)

if [ -z "$ZONE" ]; then
  echo "${RED}Could not auto-detect zone.${RESET}"
  read -p "Enter your zone (e.g., us-east4-b): " ZONE
fi

# Verify zone matches lab requirement
echo "${BLUE}Project: ${WHITE}$PROJECT${RESET}"
echo "${BLUE}Zone:    ${WHITE}$ZONE${RESET}"
echo

# ===============================
# TASK 1: Create GKE cluster
# ===============================
echo "${MAGENTA}${BOLD}Task 1: Creating GKE cluster with Managed Prometheus${RESET}"

if gcloud container clusters describe gmp-cluster --zone=$ZONE &>/dev/null; then
  echo "${YELLOW}Cluster already exists, skipping creation${RESET}"
else
  gcloud container clusters create gmp-cluster \
    --num-nodes=3 \
    --zone=$ZONE \
    --enable-managed-prometheus \
    --quiet
fi

echo "${GREEN}Cluster ready${RESET}"
echo

echo "${YELLOW}${BOLD}Fetching cluster credentials${RESET}"
gcloud container clusters get-credentials gmp-cluster --zone=$ZONE
echo "${GREEN}Credentials retrieved${RESET}"
echo

# ===============================
# TASK 2: Create namespace + Apply manifests
# ===============================
echo "${CYAN}${BOLD}Task 2: Creating gmp-test namespace${RESET}"

if kubectl get ns gmp-test &>/dev/null; then
  echo "${YELLOW}Namespace already exists, skipping${RESET}"
else
  kubectl create ns gmp-test
fi
echo "${GREEN}Namespace ready${RESET}"
echo

# Apply setup manifests
echo "${CYAN}${BOLD}Task 2: Applying setup manifests${RESET}"
kubectl -n gmp-test apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/prometheus-engine/v0.4.3-gke.0/manifests/setup.yaml
echo "${GREEN}Setup applied${RESET}"
echo

echo "${CYAN}${BOLD}Task 2: Applying operator manifests${RESET}"
kubectl -n gmp-test apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/prometheus-engine/v0.4.3-gke.0/manifests/operator.yaml
echo "${GREEN}Operator applied${RESET}"
echo

# ===============================
# TASK 3: Deploy example application
# ===============================
echo "${YELLOW}${BOLD}Task 3: Deploying example application${RESET}"
kubectl -n gmp-test apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/prometheus-engine/v0.4.3-gke.0/examples/example-app.yaml
echo "${GREEN}Example app deployed${RESET}"
echo

# Wait for pods
echo "${YELLOW}Waiting for pods to be Ready...${RESET}"
kubectl -n gmp-test wait --for=condition=Ready pods --all --timeout=300s 2>/dev/null || true

echo "${YELLOW}Pods status:${RESET}"
kubectl -n gmp-test get pods
echo

# ===============================
# TASK 4: Filter exported metrics
# ===============================
echo "${RED}${BOLD}Task 4: Filtering exported metrics${RESET}"

# Patch operator config
kubectl patch operatorconfig config -n gmp-public --type='json' -p='[
  {"op": "add", "path": "/collection", "value": {"filter": {"matchOneOf": ["{job=\"prom-example\"}", "{__name__=~\"job:.+\"}"]}}}
]' 2>/dev/null || echo "${YELLOW}Operator config patch skipped${RESET}"
echo

# Create op-config.yaml
echo "${GREEN}${BOLD}Task 4: Generating op-config.yaml${RESET}"
cat > op-config.yaml <<'EOF_END'
apiVersion: monitoring.googleapis.com/v1alpha1
collection:
  filter:
    matchOneOf:
    - '{job="prom-example"}'
    - '{__name__=~"job:.+"}'
kind: OperatorConfig
metadata:
  annotations:
    components.gke.io/layer: addon
  labels:
    addonmanager.kubernetes.io/mode: Reconcile
  name: config
  namespace: gmp-public
EOF_END
echo "${GREEN}op-config.yaml created${RESET}"
echo

# Upload to Cloud Storage
echo "${CYAN}${BOLD}Task 4: Uploading config to Cloud Storage${RESET}"
gcloud storage buckets create gs://$PROJECT --project=$PROJECT 2>/dev/null || echo "${YELLOW}Bucket already exists${RESET}"
gcloud storage cp op-config.yaml gs://$PROJECT/
gcloud storage buckets add-iam-policy-binding gs://$PROJECT \
  --member=allUsers \
  --role=roles/storage.objectViewer \
  --quiet
echo "${GREEN}Config uploaded and public read enabled${RESET}"
echo

# Create prom-example-config.yaml
echo "${MAGENTA}${BOLD}Task 4: Generating prom-example-config.yaml${RESET}"
cat > prom-example-config.yaml <<EOF
apiVersion: monitoring.googleapis.com/v1alpha1
kind: PodMonitoring
metadata:
  labels:
    app.kubernetes.io/name: prom-example
  name: prom-example
  namespace: gmp-test
spec:
  endpoints:
  - interval: 60s
    port: metrics
  selector:
    matchLabels:
      app: prom-example
EOF
echo "${GREEN}prom-example-config.yaml created${RESET}"
echo

# Upload prom-example-config
echo "${BLUE}${BOLD}Task 4: Uploading prom-example-config${RESET}"
gcloud storage cp prom-example-config.yaml gs://$PROJECT/
gcloud storage buckets add-iam-policy-binding gs://$PROJECT \
  --member=allUsers \
  --role=roles/storage.objectViewer \
  --quiet
echo "${GREEN}Uploaded${RESET}"
echo

# ===============================
# VERIFICATION
# ===============================
echo "${CYAN}${BOLD}=================================================${RESET}"
echo "${CYAN}${BOLD}   VERIFICATION${RESET}"
echo "${CYAN}${BOLD}=================================================${RESET}"
echo

echo "${YELLOW}Cluster status:${RESET}"
gcloud container clusters list --filter="name:gmp-cluster" --format="table(name,status,zone)"
echo

echo "${YELLOW}Pods in gmp-test:${RESET}"
kubectl get pods -n gmp-test
echo

echo "${YELLOW}Storage bucket contents:${RESET}"
gcloud storage ls gs://$PROJECT/
echo

echo "${CYAN}${BOLD}=================================================${RESET}"
echo "${CYAN}${BOLD}   AUTOMATED SETUP COMPLETED${RESET}"
echo "${CYAN}${BOLD}=================================================${RESET}"
echo
echo "${WHITE}Now click Check my progress in the lab for:${RESET}"
echo "  - Task 1 (Deploy GKE cluster)"
echo "  - Task 2 (Deploy managed collection)"
echo "  - Task 3 (Deploy example application)"
echo "  - Task 4 (Filter exported metrics)"
echo
