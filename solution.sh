#!/bin/bash
# ==============================================================================
# Qwiklabs/GCP Challenge Lab Interactive Automated Script
# Dynamic Region, Zone, Namespace & User Prompt for Service Name
# ==============================================================================

set -e

# Clear screen for clean interactive prompt
clear

echo "=================================================================="
echo "🚀 WELCOME TO AUTOMATED CHALLENGE LAB SOLVER"
echo "=================================================================="
echo ""
# Prompt user for input
read -p "📌 Enter the Service Name for Task 6 (e.g., helloweb-service-9xuc): " SERVICE_NAME
echo ""

if [ -z "$SERVICE_NAME" ]; then
    echo "⚠️  No Service Name provided! Exiting script to protect your credits."
    exit 1
fi

echo "✅ Service Name set to: $SERVICE_NAME"
echo "⏳ Starting lab setup..."
echo "=================================================================="

# 1. AUTO-DETECT ENVIRONMENT VARIABLES
export PROJECT_ID=$(gcloud config get-value project)
export CLUSTER_NAME=$(gcloud container clusters list --format="value(name)" | head -n 1)
export ZONE=$(gcloud container clusters list --format="value(zone)" | head -n 1)
export REGION=$(echo $ZONE | cut -d'-' -f1,2)
export NAMESPACE_NAME=$(kubectl get ns --no-headers -o custom-columns=":metadata.name" | grep -vE 'default|kube-|gke-' | head -n 1)

if [ -z "$NAMESPACE_NAME" ]; then
    export NAMESPACE_NAME=$(kubectl get ns --no-headers -o custom-columns=":metadata.name" | grep "gmp" | head -n 1)
fi

echo "✅ Project ID : $PROJECT_ID"
echo "✅ Cluster    : $CLUSTER_NAME"
echo "✅ Zone       : $ZONE"
echo "✅ Region     : $REGION"
echo "✅ Namespace  : $NAMESPACE_NAME"

# Connect to GKE Cluster
gcloud container clusters get-credentials $CLUSTER_NAME --zone $ZONE --project $PROJECT_ID

# TASK 1 & 2: Managed Prometheus Deployment
echo "📦 Task 1 & 2: Deploying Prometheus Test App..."
cat <<EOF > prometheus-app.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus-test
  template:
    metadata:
      labels:
        app: prometheus-test
    spec:
      containers:
      - name: prometheus-test
        image: prometheusoperator/prometheus-config-reloader:v0.67.0
        ports:
        - name: metrics
          containerPort: 1234
EOF

kubectl apply -f prometheus-app.yaml -n $NAMESPACE_NAME

# TASK 3 & 4: Manifest Download, Log Metric & Alert Policy
echo "📦 Task 3 & 4: Setting up Log Metric & Alerting Policy..."
gcloud storage cp -r gs://spls/gsp510/hello-app/ .

kubectl apply -f hello-app/manifests/helloweb-deployment.yaml -n $NAMESPACE_NAME || true

gcloud logging metrics create pod-image-errors \
    --description="Metric for pod image errors" \
    --log-filter='resource.type="k8s_pod" AND severity=ERROR' || true

cat <<EOF > alert-policy.json
{
  "displayName": "Pod Error Alert",
  "userLabels": {},
  "conditions": [
    {
      "displayName": "Log match condition",
      "conditionThreshold": {
        "filter": "resource.type=\"k8s_pod\" AND metric.type=\"logging.googleapis.com/user/pod-image-errors\"",
        "aggregations": [
          {
            "alignmentPeriod": "600s",
            "crossSeriesReducer": "REDUCE_SUM",
            "perSeriesAligner": "ALIGN_COUNT"
          }
        ],
        "comparison": "COMPARISON_GT",
        "thresholdValue": 0,
        "duration": "0s",
        "trigger": {
          "count": 1
        }
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "604800s"
  },
  "combiner": "OR",
  "enabled": true
}
EOF

gcloud alpha monitoring policies create --policy-from-file="alert-policy.json" || true

# TASK 5: Re-deploy App with Valid Image
echo "📦 Task 5: Updating image tag & re-deploying..."
kubectl delete deployment helloweb -n $NAMESPACE_NAME --ignore-not-found

sed -i 's|<todo>|us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0|g' hello-app/manifests/helloweb-deployment.yaml
kubectl apply -f hello-app/manifests/helloweb-deployment.yaml -n $NAMESPACE_NAME

# TASK 6: Build v2 Container & Expose Service
echo "📦 Task 6: Updating code, pushing v2 image & exposing service..."
sed -i 's/Version: 1.0.0/Version: 2.0.0/g' hello-app/main.go

# Auto-create Artifact Registry Repo if missing
gcloud artifacts repositories create demo-repo \
    --repository-format=docker \
    --location=$REGION \
    --description="Docker repository" || true

export IMAGE_TAG="$REGION-docker.pkg.dev/$PROJECT_ID/demo-repo/hello-app:v2"
gcloud builds submit hello-app --tag $IMAGE_TAG

kubectl set image deployment/helloweb helloweb=$IMAGE_TAG -n $NAMESPACE_NAME || kubectl set image deployment/helloweb hello-app=$IMAGE_TAG -n $NAMESPACE_NAME

# Expose service using user-provided variable
kubectl expose deployment helloweb \
    --name=$SERVICE_NAME \
    --type=LoadBalancer \
    --port=8080 \
    --target-port=8080 \
    -n $NAMESPACE_NAME || true

echo "=================================================================="
echo "🎉 SUCCESS! ALL TASKS COMPLETED. Click Check My Progress Buttons!"
echo "=================================================================="
