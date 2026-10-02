#!/bin/bash
# ============================================================
# Deploy Kubernetes Applications on Google Cloud: Challenge Lab
# Automated Script - Multi-User Portable + Live Progress
# ============================================================

set -e

# ---------- HELPER FUNCTIONS ----------
spinner() {
  local pid=$1
  local msg="${2:-Working...}"
  local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local i=0
  while kill -0 $pid 2>/dev/null; do
    i=$(( (i+1) % 10 ))
    printf "\r${spin:$i:1}  ${msg}"
    sleep 0.1
  done
  printf "\r✅ ${msg} - Done!          \n"
}

countdown() {
  local secs=$1
  local msg="${2:-Waiting}"
  while [ $secs -gt 0 ]; do
    printf "\r⏳ ${msg}: ${secs}s remaining...   "
    sleep 1
    secs=$((secs-1))
  done
  printf "\r✅ ${msg} - Complete!          \n"
}

progress_wait() {
  local secs=$1
  local msg="${2:-Processing}"
  local elapsed=0
  while [ $elapsed -lt $secs ]; do
    printf "\r⏳ ${msg} (${elapsed}s / ${secs}s)..."
    sleep 5
    elapsed=$((elapsed+5))
  done
  printf "\r✅ ${msg} - Complete!          \n"
}

# ---------- STEP 0: USER INPUTS ----------
echo "=============================================="
echo "  K8s Challenge Lab - Enter Your Details"
echo "=============================================="
echo ""

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
echo ""
echo "🔧 Setting up gcloud config..."
gcloud config set project "$PROJECT_ID" 2>/dev/null
gcloud config set compute/region "$REGION" 2>/dev/null
gcloud config set compute/zone "$ZONE" 2>/dev/null
echo "✅ Config set complete"

# ============================================================
# TASK 1: Create Docker image and store the Dockerfile (25 pts)
# ============================================================
echo ""
echo "════════════════════════════════════════════"
echo "  TASK 1: Docker Image & Dockerfile (25 pts)"
echo "════════════════════════════════════════════"
echo ""

# Run lab's tracking script with spinner
echo "🔧 Running lab tracking script (this sets up cluster in background)..."
echo "⏳ This step takes 5-10 minutes. Please be patient!"
echo ""

(
  source <(gcloud storage cat gs://spls/gsp318/script.sh) > /tmp/tracking.log 2>&1
) &
TRACKING_PID=$!

# Show progress while waiting
elapsed=0
while kill -0 $TRACKING_PID 2>/dev/null; do
  spin_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  i=$((elapsed % 10))
  printf "\r${spin_chars:$i:1}  Tracking script running... (${elapsed}s elapsed)"
  sleep 2
  elapsed=$((elapsed+2))
done
wait $TRACKING_PID 2>/dev/null || true
printf "\r✅ Tracking script complete! (${elapsed}s total)          \n"
echo ""
echo "📄 Last few lines of tracking log:"
tail -5 /tmp/tracking.log 2>/dev/null || true

# Download source code
echo ""
echo "📥 Downloading valkyrie-app source..."
(
  gcloud storage cp gs://spls/gsp318/valkyrie-app.tgz . > /tmp/dl.log 2>&1
) &
spinner $! "Downloading valkyrie-app.tgz"

(
  tar -xzf valkyrie-app.tgz
) &
spinner $! "Extracting source code"

cd valkyrie-app
echo "✅ Source extracted to $(pwd)"

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
echo "✅ Dockerfile created"
echo ""
echo "--- Dockerfile content ---"
cat Dockerfile
echo "--------------------------"

# Build Docker image with spinner
echo ""
echo "🔨 Building Docker image ${IMAGE_NAME}:${IMAGE_TAG}..."
echo "⏳ This takes 1-2 minutes..."
docker build -t ${IMAGE_NAME}:${IMAGE_TAG} . > /tmp/docker-build.log 2>&1 &
BUILD_PID=$!

elapsed=0
while kill -0 $BUILD_PID 2>/dev/null; do
  spin_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  i=$((elapsed % 10))
  printf "\r${spin_chars:$i:1}  Docker build running... (${elapsed}s)"
  sleep 2
  elapsed=$((elapsed+2))
done
wait $BUILD_PID
printf "\r✅ Docker image built! (${elapsed}s)          \n"
echo ""
echo "--- Build output (last 5 lines) ---"
tail -5 /tmp/docker-build.log

# Verify
echo ""
echo "🔍 Verifying Docker image..."
docker images | grep ${IMAGE_NAME}
echo ""
echo "✅ TASK 1 COMPLETE - Lab panel mein Task 1 'Check my progress' click karo"

# ============================================================
# TASK 2: Test the created Docker image (no points, informational)
# ============================================================
echo ""
echo "════════════════════════════════════════════"
echo "  TASK 2: Test Docker Image"
echo "════════════════════════════════════════════"
echo ""

echo "🚀 Running container in background (port 8080)..."
docker run -d -p 8080:8080 ${IMAGE_NAME}:${IMAGE_TAG} > /dev/null 2>&1 || true
echo "✅ Container started"

countdown 3 "Waiting for container to boot"

echo ""
echo "🔍 Testing container response..."
curl -s http://localhost:8080 | head -10 || echo "Container running - use Web Preview to test"

echo ""
echo "✅ TASK 2 COMPLETE"

# ============================================================
# TASK 3: Push Docker image to Artifact Registry (25 pts)
# ============================================================
echo ""
echo "════════════════════════════════════════════"
echo "  TASK 3: Push to Artifact Registry (25 pts)"
echo "════════════════════════════════════════════"
echo ""

# Create Artifact Registry repo
echo "📦 Creating Artifact Registry repository..."
gcloud artifacts repositories create ${REPO_NAME} \
  --repository-format=docker \
  --location=${REGION} \
  --description="Docker repository for valkyrie" \
  --project=${PROJECT_ID} 2>/dev/null || echo "ℹ️  Repo exists, continuing..."
echo "✅ Repository ready: ${REPO_NAME}"

# Configure Docker auth
echo ""
echo "🔐 Configuring Docker authentication..."
gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet
echo "✅ Docker auth configured"

# Re-tag image
echo ""
echo "🏷️  Re-tagging image for Artifact Registry..."
docker tag ${IMAGE_NAME}:${IMAGE_TAG} \
  ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${IMAGE_NAME}:${IMAGE_TAG}
echo "✅ Image re-tagged"

# Push with progress
echo ""
echo "⬆️  Pushing image to Artifact Registry..."
echo "⏳ This takes 1-2 minutes..."
docker push ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${IMAGE_NAME}:${IMAGE_TAG} > /tmp/docker-push.log 2>&1 &
PUSH_PID=$!

elapsed=0
while kill -0 $PUSH_PID 2>/dev/null; do
  spin_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  i=$((elapsed % 10))
  printf "\r${spin_chars:$i:1}  Pushing to registry... (${elapsed}s)"
  sleep 2
  elapsed=$((elapsed+2))
done
wait $PUSH_PID
printf "\r✅ Image pushed! (${elapsed}s)          \n"
echo ""
echo "--- Push output (last 5 lines) ---"
tail -5 /tmp/docker-push.log

echo ""
echo "✅ TASK 3 COMPLETE - Lab panel mein Task 3 'Check my progress' click karo"

# ============================================================
# TASK 4: Create and expose deployment in Kubernetes (50 pts)
# ============================================================
echo ""
echo "════════════════════════════════════════════"
echo "  TASK 4: Deploy to Kubernetes (50 pts)"
echo "════════════════════════════════════════════"
echo ""

cd ~/valkyrie-app

# Get K8s credentials
echo "🔑 Getting GKE credentials for cluster ${CLUSTER_NAME}..."
gcloud container clusters get-credentials ${CLUSTER_NAME} \
  --zone=${ZONE} \
  --project=${PROJECT_ID} > /dev/null 2>&1 &
spinner $! "Fetching GKE credentials"
echo "✅ Credentials fetched"

# Update deployment.yaml
echo ""
echo "📝 Updating deployment.yaml with correct image path..."
if [ -f "k8s/deployment.yaml" ]; then
  sed -i "s|LOCATION-docker.pkg.dev/PROJECT-ID/REPOSITORY/IMAGE|${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${IMAGE_NAME}|g" k8s/deployment.yaml
  sed -i "s|IMAGE|${IMAGE_NAME}|g" k8s/deployment.yaml
  sed -i "s|TAG|${IMAGE_TAG}|g" k8s/deployment.yaml

  echo "--- deployment.yaml preview ---"
  cat k8s/deployment.yaml
  echo "-------------------------------"
else
  echo "⚠️  k8s/deployment.yaml not found"
fi

# Apply deployments
echo ""
echo "🚀 Applying Kubernetes deployments..."
kubectl apply -f k8s/deployment.yaml > /dev/null 2>&1 &
spinner $! "Applying deployment.yaml"

kubectl apply -f k8s/service.yaml > /dev/null 2>&1 &
spinner $! "Applying service.yaml"
echo "✅ Deployments applied"

# Wait for external IP with countdown
echo ""
countdown 30 "Waiting for external IP assignment"

echo ""
echo "🔍 Checking pods..."
kubectl get pods

echo ""
echo "🔍 Checking services..."
kubectl get services

echo ""
echo "=============================================="
echo "✅ ALL TASKS COMPLETE!"
echo "=============================================="
echo "1. Lab panel mein saare 'Check my progress' click karo"
echo "2. Web Preview se valkyrie-dev service check karo"
echo "=============================================="
