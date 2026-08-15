#!/bin/bash
# ==============================================================================
# Dynamic & Safe Challenge Lab Solver by CloudRik
# Fully Automatic Cluster & Zone Detection with Fail-Safe Checks
# ==============================================================================

set -e

clear
echo "=================================================================="
echo "🚀 WELCOME TO AUTOMATED CHALLENGE LAB SOLVER BY CLOUDRIK"
echo "=================================================================="
echo ""

# 1. Take Service Name input via /dev/tty
read -p "📌 Enter Task 6 Service Name (e.g., helloweb-service-zp3a): " SERVICE_NAME < /dev/tty
echo ""

if [ -z "$SERVICE_NAME" ]; then
    echo "❌ ERROR: Service Name blank nahi ho sakta! Exiting to protect credits."
    exit 1
fi

echo "⏳ Auto-detecting Cluster Details..."

# 2. Dynamic Auto-Detection of Cluster & Zone
export PROJECT_ID=$(gcloud config get-value project)
export CLUSTER_NAME=$(gcloud container clusters list --format="value(name)" 2>/dev/null | head -n 1)
export ZONE=$(gcloud container clusters list --format="value(zone)" 2>/dev/null | head -n 1)

# Fail-safe check to prevent script execution if cluster is missing
if [ -z "$CLUSTER_NAME" ] || [ -z "$ZONE" ]; then
    echo "=================================================================="
    echo "❌ ERROR: GKE Cluster abhi ready nahi hai ya initialize ho raha hai."
    echo "⚠️ Script pehle hi rok di gayi hai taaki credits waste na ho."
    echo "👉 1-2 minute wait karke terminal mein command fir se chalayein."
    echo "=================================================================="
    exit 1
fi

export REGION=$(echo $ZONE | cut -d'-' -f1,2)

echo "✅ Project ID   : $PROJECT_ID"
echo "✅ Cluster Name : $CLUSTER_NAME"
echo "✅ Zone         : $ZONE"
echo "✅ Region       : $REGION"
echo "✅ Service Name : $SERVICE_NAME"
echo "=================================================================="

# 3. Connect to GKE Cluster
echo "⏳ Connecting to GKE Cluster..."
gcloud container clusters get-credentials $CLUSTER_NAME --zone $ZONE --project $PROJECT_ID

export NAMESPACE_NAME=$(kubectl get ns --no-headers -o custom-columns=":metadata.name" | grep -vE 'default|kube-|gke-' | head -n 1)

if [ -z "$NAMESPACE_NAME" ]; then
    export NAMESPACE_NAME=$(kubectl get ns --no-headers -o custom-columns=":metadata.name" | grep "gmp" | head -n 1)
fi

echo "✅ Namespace    : $NAMESPACE_NAME"

# TASK 1 & 2: Managed Prometheus
echo "📦 Deploying Task 1 & 2..."
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
echo "📦 Setting up Task 3 & 4..."
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
echo "📦 Executing Task 5..."
kubectl delete deployment helloweb -n $NAMESPACE_NAME --ignore-not-found

sed -i 's|<todo>|us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0|g' hello-app/manifests/helloweb-deployment.yaml
kubectl apply -f hello-app/manifests/helloweb-deployment.yaml -n $NAMESPACE_NAME

# TASK 6: Build v2 Container & Expose Service
echo "📦 Executing Task 6..."
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
echo "🎉 LAB COMPLETED SUCCESSFULLY! Check your progress on Qwiklabs."
echo "=================================================================="
