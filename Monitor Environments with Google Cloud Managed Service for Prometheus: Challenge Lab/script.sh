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
echo "${CYAN}${BOLD}=========================================${RESET}"
echo "${CYAN}${BOLD}   GCP MANAGED PROMETHEUS CHALLENGE LAB  ${RESET}"
echo "${CYAN}${BOLD}=========================================${RESET}"
echo

# Step 1: Detect project and zone
echo "${GREEN}${BOLD}Step 1: Detecting project and zone${RESET}"
export PROJECT=$(gcloud config get-value project 2>/dev/null)
export ZONE=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
echo "${BLUE}Project: ${WHITE}$PROJECT${RESET}"
echo "${BLUE}Zone:    ${WHITE}$ZONE${RESET}"
echo

# Step 2: Create GKE cluster with managed Prometheus
echo "${MAGENTA}${BOLD}Step 2: Creating GKE cluster with Managed Prometheus${RESET}"
gcloud container clusters create gmp-cluster \
  --num-nodes=3 \
  --zone=$ZONE \
  --enable-managed-prometheus \
  --quiet
echo "${GREEN}Cluster created${RESET}"
echo

# Step 3: Get credentials
echo "${YELLOW}${BOLD}Step 3: Fetching cluster credentials${RESET}"
gcloud container clusters get-credentials gmp-cluster --zone=$ZONE
echo "${GREEN}Credentials retrieved${RESET}"
echo

# Step 4: Create gmp-test namespace
echo "${CYAN}${BOLD}Step 4: Creating gmp-test namespace${RESET}"
kubectl create ns gmp-test
echo "${GREEN}Namespace created${RESET}"
echo

# Step 5: Apply setup manifests
echo "${BLUE}${BOLD}Step 5: Applying setup manifests${RESET}"
kubectl -n gmp-test apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/prometheus-engine/main/manifests/setup.yaml
echo "${GREEN}Setup applied${RESET}"
echo

# Step 6: Apply operator manifests
echo "${MAGENTA}${BOLD}Step 6: Applying operator manifests${RESET}"
kubectl -n gmp-test apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/prometheus-engine/main/manifests/operator.yaml
echo "${GREEN}Operator applied${RESET}"
echo

# Step 7: Deploy example application
echo "${YELLOW}${BOLD}Step 7: Deploying example application${RESET}"
kubectl -n gmp-test apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/prometheus-engine/main/examples/example-app.yaml
echo "${GREEN}Example app deployed${RESET}"
echo

# Step 8: Patch operator config
echo "${RED}${BOLD}Step 8: Patching operator config for metric filtering${RESET}"
kubectl patch operatorconfig config -n gmp-public --type='json' -p='[
  {"op": "add", "path": "/collection", "value": {"filter": {"matchOneOf": ["{job=\"prom-example\"}", "{__name__=~\"job:.+\"}"]}}}
]' 2>/dev/null || echo "${YELLOW}Operator config patch skipped (namespace may not exist yet)${RESET}"
echo

# Step 9: Create op-config.yaml
echo "${GREEN}${BOLD}Step 9: Generating op-config.yaml${RESET}"
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

# Step 10: Upload to Cloud Storage
echo "${CYAN}${BOLD}Step 10: Uploading config to Cloud Storage${RESET}"
gcloud storage buckets create gs://$PROJECT --project=$PROJECT 2>/dev/null || echo "${YELLOW}Bucket already exists${RESET}"
gcloud storage cp op-config.yaml gs://$PROJECT/
gcloud storage buckets add-iam-policy-binding gs://$PROJECT \
  --member=allUsers \
  --role=roles/storage.objectViewer \
  --quiet
echo "${GREEN}Config uploaded and public read enabled${RESET}"
echo

# Step 11: Create prom-example-config.yaml
echo "${MAGENTA}${BOLD}Step 11: Generating prom-example-config.yaml${RESET}"
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

# Step 12: Upload prom-example-config
echo "${BLUE}${BOLD}Step 12: Uploading prom-example-config to Cloud Storage${RESET}"
gcloud storage cp prom-example-config.yaml gs://$PROJECT/
gcloud storage buckets add-iam-policy-binding gs://$PROJECT \
  --member=allUsers \
  --role=roles/storage.objectViewer \
  --quiet
echo "${GREEN}Uploaded${RESET}"
echo

# Final verification
echo "${CYAN}${BOLD}=========================================${RESET}"
echo "${CYAN}${BOLD}   VERIFICATION${RESET}"
echo "${CYAN}${BOLD}=========================================${RESET}"
echo "${YELLOW}Cluster status:${RESET}"
gcloud container clusters list --filter="name:gmp-cluster" --format="table(name,status,zone)"
echo
echo "${YELLOW}Pods in gmp-test:${RESET}"
kubectl get pods -n gmp-test
echo
echo "${YELLOW}Storage bucket contents:${RESET}"
gcloud storage ls gs://$PROJECT/
echo
echo "${CYAN}${BOLD}=========================================${RESET}"
echo "${CYAN}${BOLD}   LAB SETUP COMPLETED${RESET}"
echo "${CYAN}${BOLD}=========================================${RESET}"
echo
