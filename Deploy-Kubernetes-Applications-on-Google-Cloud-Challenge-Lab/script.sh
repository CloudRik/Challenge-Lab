#!/bin/bash
# ============================================================
# Deploy Kubernetes Applications on Google Cloud: Challenge Lab
# Automated Script - Multi-User Portable
# ============================================================

set -e

# ---------- STEP 0: USER INPUTS ----------
echo "=============================================="
echo "  K8s Challenge Lab - Enter Your Details"
echo "=============================================="
echo ""

# Auto-detect project
DETECTED_PROJECT=$(gcloud config get-value project 2>/dev/null)
read -p "Enter Your Project ID [${DETECTED_PROJECT}]: " INPUT_PROJECT
PROJECT_ID=${INPUT_PROJECT:-$DETECTED_PROJECT}

read -p "Enter Your Region [europe-west4]: " INPUT_REGION
REGION=${INPUT_REGION:-europe-west4}

read -p "Enter Your Zone [europe-west4-a]: " INPUT_ZONE
ZONE=${INPUT_ZONE:-europe-west4-a}

read -p "Enter Your Repository Name [valkyrie-repo]: " INPUT_REPO
REPO_NAME=${INPUT_REPO:-valkyrie-repo}

read -p "Enter Your Docker Image Name [valkyrie-app]: " INPUT_IMAGE
IMAGE_NAME=${INPUT_IMAGE:-valkyrie-app}

read -p "Enter Your Image Tag [v0.0.2]: " INPUT_TAG
IMAGE_TAG=${INPUT_TAG:-v0.0.2}

read -p "Enter Your GKE Cluster Name [valkyrie-dev]: " INPUT_CLUSTER
CLUSTER_NAME=${INPUT_CLUSTER:-valkyrie-dev}

echo ""
echo "=============================================="
echo "📋 Summary:"
echo "Project ID   : $PROJECT_ID"
echo "Region       : $REGION"
echo "Zone         : $ZONE"
echo "Repo Name    : $REPO_NAME"
echo "Image Name   : $IMAGE_NAME"
echo "Image Tag    : $IMAGE_TAG"
echo "Cluster Name : $CLUSTER_NAME"
echo "=============================================="
read -p "Proceed? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
  echo "❌ Cancelled"
  exit 1
fi

# ---------- SETUP ----------
gcloud config set project "$PROJECT_ID"
gcloud config set compute/region "$REGION"
gcloud config set compute/zone "$ZONE"

# ============================================================
# TASK 1: Create Docker image and store the Dockerfile (25 pts)
# ============================================================
echo ""
echo "========== TASK 1: Docker Image & Dockerfile =========="

# Run lab's tracking script
echo "🔧 Running lab tracking script..."
source <(gcloud storage cat gs://spls/gsp318/script.sh) 2>/dev/null || true

# Download source code
echo ""
echo "📥 Downloading valkyrie-app source..."
gcloud storage cp gs://spls/gsp318/valkyrie-app.tgz .
tar -xzf valkyrie-app.tgz
cd valkyrie-app

# Create Dockerfile
echo ""
echo "📝 Creating Dockerfile..."
cat > Dockerfile <<'EOF'
FROM golang:1.10
WORKDIR /go/src/app
COPY source .
RUN go install -v
ENTRYPOINT ["app", "-single=true", "-port=8080"]
EOF

echo "✅ Dockerfile created:"
cat Dockerfile

# Build Docker image
echo ""
echo "🔨 Building Docker image ${IMAGE_NAME}:${IMAGE_TAG}..."
docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .

# Verify
echo ""
echo "🔍 Verifying Docker image..."
docker images | grep ${IMAGE_NAME}

echo ""
echo "✅ TASK 1 COMPLETE - Lab panel mein Task 1 'Check my progress' click karo"

# ============================================================
# TASK 2: Test the created Docker image (0 pts, informational)
# ============================================================
echo ""
echo "========== TASK 2: Test Docker Image =========="

echo "🚀 Running container in background (port 8080)..."
docker run -d -p 8080:8080 ${IMAGE_NAME}:${IMAGE_TAG}

sleep 3

echo ""
echo "🔍 Testing container..."
curl -s http://localhost:8080 | head -20 || echo "Container running, test manually via Web Preview"

echo ""
echo "✅ TASK 2 COMPLETE - Lab panel mein Task 2 'Check my progress' click karo"

# ============================================================
# TASK 3: Push Docker image to Artifact Registry (25 pts)
# ============================================================
echo ""
echo "========== TASK 3: Push to Artifact Registry =========="

# Create Artifact Registry repo
echo "📦 Creating Artifact Registry repository..."
gcloud artifacts repositories create ${REPO_NAME} \
  --repository-format=docker \
  --location=${REGION} \
  --description="Docker repository for valkyrie" \
  --project=${PROJECT_ID} 2>/dev/null || echo "ℹ️  Repo exists, continuing..."

# Configure Docker auth
echo ""
echo "🔐 Configuring Docker authentication..."
gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

# Re-tag image
echo ""
echo "🏷️  Re-tagging image..."
docker tag ${IMAGE_NAME}:${IMAGE_TAG} \
  ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${IMAGE_NAME}:${IMAGE_TAG}

# Push
echo ""
echo "⬆️  Pushing image to Artifact Registry..."
docker push ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${IMAGE_NAME}:${IMAGE_TAG}

echo ""
echo "✅ TASK 3 COMPLETE - Lab panel mein Task 3 'Check my progress' click karo"

# ============================================================
# TASK 4: Create and expose deployment in Kubernetes (50 pts)
# ============================================================
echo ""
echo "========== TASK 4: Deploy to Kubernetes =========="

# Go back to valkyrie-app dir
cd ~/valkyrie-app

# Get K8s credentials
echo "🔑 Getting GKE credentials for cluster ${CLUSTER_NAME}..."
gcloud container clusters get-credentials ${CLUSTER_NAME} \
  --zone=${ZONE} \
  --project=${PROJECT_ID}

# Update deployment.yaml
echo ""
echo "📝 Updating deployment.yaml with correct image path..."
if [ -f "k8s/deployment.yaml" ]; then
  sed -i "s|LOCATION-docker.pkg.dev/PROJECT-ID/REPOSITORY/IMAGE|${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${IMAGE_NAME}|g" k8s/deployment.yaml
  sed -i "s|IMAGE|${IMAGE_NAME}|g" k8s/deployment.yaml
  sed -i "s|TAG|${IMAGE_TAG}|g" k8s/deployment.yaml
  
  echo "--- deployment.yaml preview ---"
  cat k8s/deployment.yaml
else
  echo "⚠️  k8s/deployment.yaml not found"
fi

# Apply deployments
echo ""
echo "🚀 Applying Kubernetes deployments..."
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

# Wait for external IP
echo ""
echo "⏳ Waiting for external IP (30 seconds)..."
sleep 30

echo ""
echo "🔍 Checking pods and services..."
kubectl get pods
kubectl get services

echo ""
echo "=============================================="
echo "✅ ALL TASKS COMPLETE!"
echo "=============================================="
echo "1. Lab panel mein saare 'Check my progress' click karo"
echo "2. Web Preview se valkyrie-dev service check karo"
echo "=============================================="
