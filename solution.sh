#!/bin/bash
# ==============================================================================
# Qwiklabs Interactive One-Liner Script
# Takes keyboard input safely via /dev/tty even with curl pipe!
# ==============================================================================

set -e

# Screen clean karke user se input mangenge
clear
echo "=================================================================="
echo "🚀 WELCOME TO AUTOMATED CHALLENGE LAB SOLVER BY CLOUDRIK"
echo "=================================================================="
echo ""

# /dev/tty ka use karke keyboard input read karenge
read -p "📌 Enter Task 6 Service Name (e.g., helloweb-service-9xuc): " SERVICE_NAME < /dev/tty
read -p "📌 Enter Lab Zone (e.g., us-west1-b): " ZONE < /dev/tty
echo ""

if [ -z "$SERVICE_NAME" ] || [ -z "$ZONE" ]; then
    echo "❌ Error: Inputs missing! Exiting script to protect your credits."
    exit 1
fi

echo "✅ Service Name : $SERVICE_NAME"
echo "✅ Zone         : $ZONE"
echo "⏳ Starting lab setup..."
echo "=================================================================="

# 1. ENVIRONMENT SETUP
export PROJECT_ID=$(gcloud config get-value project)
export CLUSTER_NAME=$(gcloud container clusters list --zone=$ZONE --format="value(name)" | head -n 1)
export REGION=$(echo $ZONE | cut -d'-' -f1,2)

echo "⏳ Connecting to GKE Cluster..."
gcloud container clusters get-credentials $CLUSTER_NAME --zone $ZONE --project $PROJECT_ID

export NAMESPACE_NAME=$(kubectl get ns --no-headers -o custom-columns=":metadata.name" | grep -vE 'default|kube-|gke-' | head -n 1)

if [ -z "$NAMESPACE_NAME" ]; then
    export NAMESPACE_NAME=$(kubectl get ns --no-headers -o custom-columns=":metadata.name" | grep "gmp" | head -n 1)
fi

echo "✅ Project ID : $PROJECT_ID"
echo "✅ Cluster    : $CLUSTER_NAME"
echo "✅ Region     : $REGION"
echo "✅ Namespace  : $NAMESPACE_NAME"

# TASK 1 & 2: Managed Prometheus
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

# TASK 3 & 4: Log Metric & Alert Policy
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

# TASK 5: Re-deploy App
echo "📦 Task 5: Updating image tag & re-deploying..."
kubectl delete deployment helloweb -n $NAMESPACE_NAME --ignore-not-found

sed -i 's|<todo>|us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0|g' hello-app/manifests/helloweb-deployment.yaml
kubectl apply -f hello-app/manifests/helloweb-deployment.yaml -n $NAMESPACE_NAME

# TASK 6: Build v2 Container & Expose Service
echo "📦 Task 6: Updating code, pushing v2 image & exposing service..."
sed -i 's/Version: 1.0.0/Version: 2.0.0/g' hello-app/main.go

gcloud artifacts repositories create demo-repo \
    --repository-format=docker \
    --location=$REGION \
    --description="Docker repository" || true

export IMAGE_TAG="$REGION-docker.pkg.dev/$PROJECT_ID/demo-repo/hello-app:v2"
gcloud builds submit hello-app --tag $IMAGE_TAG

kubectl set image deployment/helloweb helloweb=$IMAGE_TAG -n $NAMESPACE_NAME || kubectl set image deployment/helloweb hello-app=$IMAGE_TAG -n $NAMESPACE_NAME

kubectl expose deployment helloweb \
    --name=$SERVICE_NAME \
    --type=LoadBalancer \
    --port=8080 \
    --target-port=8080 \
    -n $NAMESPACE_NAME || true

echo "=================================================================="
echo "🎉 SUCCESS! ALL TASKS COMPLETED. Click Check My Progress Buttons!"
echo "=================================================================="
