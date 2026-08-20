#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# Google Skills - Develop Serverless Applications on Cloud Run
# Automated solution
# ============================================================

trap 'echo; echo "ERROR: Script failed near line $LINENO."; exit 1' ERR

echo "============================================================"
echo " Google Skills - Cloud Run Challenge Lab"
echo " Automated Solution"
echo "============================================================"
echo

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

command -v gcloud >/dev/null 2>&1 || {
  echo "ERROR: gcloud CLI is not installed."
  exit 1
}

command -v git >/dev/null 2>&1 || {
  echo "ERROR: git is not installed."
  exit 1
}

confirm() {
  local answer
  read -r -p "$1 [Y/n]: " answer
  answer="${answer:-Y}"

  case "$answer" in
    Y|y|yes|YES)
      ;;
    *)
      echo "Cancelled."
      exit 0
      ;;
  esac
}

service_exists() {
  local service="$1"

  gcloud run services describe "$service" \
    --region "$REGION" \
    --format="value(metadata.name)" \
    >/dev/null 2>&1
}

delete_service_if_exists() {
  local service="$1"

  if service_exists "$service"; then
    echo "Deleting existing Cloud Run service: $service"

    gcloud run services delete "$service" \
      --region "$REGION" \
      --quiet

    echo "Deleted: $service"
  else
    echo "Service does not exist, skipping delete: $service"
  fi
}

build_image() {
  local directory="$1"
  local image="$2"

  echo
  echo "------------------------------------------------------------"
  echo "Building image"
  echo "Directory : $directory"
  echo "Image     : $image"
  echo "------------------------------------------------------------"

  cd "$LAB_DIR/$directory"

  gcloud builds submit \
    --tag "$image"

  echo "Build successful: $image"
}

deploy_public() {
  local service="$1"
  local image="$2"

  echo
  echo "Deploying PUBLIC Cloud Run service: $service"

  gcloud run deploy "$service" \
    --image "$image" \
    --allow-unauthenticated \
    --region "$REGION" \
    --platform managed \
    --quiet
}

deploy_private() {
  local service="$1"
  local image="$2"
  local service_account="$3"

  echo
  echo "Deploying PRIVATE Cloud Run service: $service"

  gcloud run deploy "$service" \
    --image "$image" \
    --service-account "$service_account" \
    --region "$REGION" \
    --platform managed \
    --no-allow-unauthenticated \
    --quiet
}

get_service_url() {
  local service="$1"

  gcloud run services describe "$service" \
    --region "$REGION" \
    --platform managed \
    --format="value(status.url)"
}

# ------------------------------------------------------------
# Project / region
# ------------------------------------------------------------

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  PROJECT_ID="$(gcloud projects list \
    --filter="projectId:qwiklabs-gcp" \
    --format="value(projectId)" \
    --limit=1)"
fi

if [[ -z "$PROJECT_ID" ]]; then
  read -r -p "Enter your Google Cloud Project ID: " PROJECT_ID
fi

gcloud config set project "$PROJECT_ID" >/dev/null

echo
echo "Project: $PROJECT_ID"

read -r -p "Cloud Run region [us-east4]: " REGION
REGION="${REGION:-us-east4}"

gcloud config set run/region "$REGION" >/dev/null
gcloud config set run/platform managed >/dev/null

# ------------------------------------------------------------
# Lab-specific values
# ------------------------------------------------------------

echo
echo "============================================================"
echo " Enter the values shown by your lab"
echo "============================================================"
echo
echo "The numeric suffixes are intentionally NOT hardcoded."
echo

read -r -p "Public Billing Service name: " PUBLIC_BILLING_SERVICE
read -r -p "Staging Frontend Service name: " STAGING_FRONTEND_SERVICE
read -r -p "Private Billing Service name: " PRIVATE_BILLING_SERVICE
read -r -p "Billing Service Account ID: " BILLING_SA_ID
read -r -p "Production Billing Service name: " PROD_BILLING_SERVICE
read -r -p "Frontend Service Account ID: " FRONTEND_SA_ID
read -r -p "Production Frontend Service name: " PROD_FRONTEND_SERVICE

# Basic validation
for value_name in \
  PUBLIC_BILLING_SERVICE \
  STAGING_FRONTEND_SERVICE \
  PRIVATE_BILLING_SERVICE \
  BILLING_SA_ID \
  PROD_BILLING_SERVICE \
  FRONTEND_SA_ID \
  PROD_FRONTEND_SERVICE
do
  if [[ -z "${!value_name}" ]]; then
    echo "ERROR: $value_name cannot be empty."
    exit 1
  fi
done

BILLING_SA_EMAIL="${BILLING_SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
FRONTEND_SA_EMAIL="${FRONTEND_SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"

LAB_DIR="$HOME/pet-theory/lab07"

# ------------------------------------------------------------
# Confirmation
# ------------------------------------------------------------

echo
echo "============================================================"
echo " Configuration"
echo "============================================================"
echo "Project ID              : $PROJECT_ID"
echo "Region                  : $REGION"
echo "Public Billing          : $PUBLIC_BILLING_SERVICE"
echo "Staging Frontend        : $STAGING_FRONTEND_SERVICE"
echo "Private Billing         : $PRIVATE_BILLING_SERVICE"
echo "Billing Service Account : $BILLING_SA_ID"
echo "Production Billing      : $PROD_BILLING_SERVICE"
echo "Frontend Service Account: $FRONTEND_SA_ID"
echo "Production Frontend     : $PROD_FRONTEND_SERVICE"
echo "============================================================"
echo

confirm "Proceed with the complete lab automation?"

# ------------------------------------------------------------
# Provisioning
# ------------------------------------------------------------

echo
echo "============================================================"
echo " Provisioning lab environment"
echo "============================================================"

if [[ ! -d "$LAB_DIR/.git" ]]; then
  echo "Cloning pet-theory repository..."

  git clone \
    https://github.com/rosera/pet-theory.git \
    "$HOME/pet-theory"
else
  echo "pet-theory repository already exists."
fi

# ------------------------------------------------------------
# Task 1 - Public Billing Service
# ------------------------------------------------------------

echo
echo "============================================================"
echo " TASK 1 - Public Billing Service"
echo "============================================================"

build_image \
  "unit-api-billing" \
  "gcr.io/${PROJECT_ID}/billing-staging-api:0.1"

deploy_public \
  "$PUBLIC_BILLING_SERVICE" \
  "gcr.io/${PROJECT_ID}/billing-staging-api:0.1"

PUBLIC_BILLING_URL="$(get_service_url "$PUBLIC_BILLING_SERVICE")"

echo "Public Billing URL:"
echo "$PUBLIC_BILLING_URL"

echo "Testing public Billing endpoint..."
curl --fail --silent --show-error \
  "$PUBLIC_BILLING_URL"

echo
echo "Task 1 complete."

# ------------------------------------------------------------
# Task 2 - Staging Frontend
# ------------------------------------------------------------

echo
echo "============================================================"
echo " TASK 2 - Staging Frontend"
echo "============================================================"

build_image \
  "staging-frontend-billing" \
  "gcr.io/${PROJECT_ID}/frontend-staging:0.1"

deploy_public \
  "$STAGING_FRONTEND_SERVICE" \
  "gcr.io/${PROJECT_ID}/frontend-staging:0.1"

STAGING_FRONTEND_URL="$(get_service_url "$STAGING_FRONTEND_SERVICE")"

echo "Staging Frontend URL:"
echo "$STAGING_FRONTEND_URL"

echo "Testing staging frontend..."
curl --fail --silent --show-error \
  "$STAGING_FRONTEND_URL" \
  >/dev/null

echo "Task 2 complete."

# ------------------------------------------------------------
# Task 3 - Private Billing Service
# ------------------------------------------------------------

echo
echo "============================================================"
echo " TASK 3 - Private Billing Service"
echo "============================================================"

echo "Removing the previous public Billing Service..."

delete_service_if_exists "$PUBLIC_BILLING_SERVICE"

build_image \
  "staging-api-billing" \
  "gcr.io/${PROJECT_ID}/billing-staging-api:0.2"

deploy_private \
  "$PRIVATE_BILLING_SERVICE" \
  "gcr.io/${PROJECT_ID}/billing-staging-api:0.2" \
  "$BILLING_SA_EMAIL"

PRIVATE_BILLING_URL="$(get_service_url "$PRIVATE_BILLING_SERVICE")"

echo "Private Billing URL:"
echo "$PRIVATE_BILLING_URL"

echo "Testing authenticated private endpoint..."

curl --fail --silent --show-error \
  -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  "$PRIVATE_BILLING_URL"

echo
echo "Task 3 complete."

# ------------------------------------------------------------
# Task 4 - Billing Service Account
# ------------------------------------------------------------

echo
echo "============================================================"
echo " TASK 4 - Billing Service Account"
echo "============================================================"

if gcloud iam service-accounts describe "$BILLING_SA_EMAIL" \
  >/dev/null 2>&1; then

  echo "Billing Service Account already exists:"
  echo "$BILLING_SA_EMAIL"

else

  gcloud iam service-accounts create "$BILLING_SA_ID" \
    --display-name="Billing Service Cloud Run"

  echo "Created:"
  echo "$BILLING_SA_EMAIL"
fi

echo "Task 4 complete."

# ------------------------------------------------------------
# Task 5 - Production Billing Service
# ------------------------------------------------------------

echo
echo "============================================================"
echo " TASK 5 - Production Billing Service"
echo "============================================================"

build_image \
  "prod-api-billing" \
  "gcr.io/${PROJECT_ID}/billing-prod-api:0.1"

deploy_private \
  "$PROD_BILLING_SERVICE" \
  "gcr.io/${PROJECT_ID}/billing-prod-api:0.1" \
  "$BILLING_SA_EMAIL"

PROD_BILLING_URL="$(get_service_url "$PROD_BILLING_SERVICE")"

echo "Production Billing URL:"
echo "$PROD_BILLING_URL"

echo "Testing production Billing endpoint..."

curl --fail --silent --show-error \
  -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  "$PROD_BILLING_URL"

echo
echo "Task 5 complete."

# ------------------------------------------------------------
# Task 6 - Frontend Service Account
# ------------------------------------------------------------

echo
echo "============================================================"
echo " TASK 6 - Frontend Service Account"
echo "============================================================"

if gcloud iam service-accounts describe "$FRONTEND_SA_EMAIL" \
  >/dev/null 2>&1; then

  echo "Frontend Service Account already exists:"
  echo "$FRONTEND_SA_EMAIL"

else

  gcloud iam service-accounts create "$FRONTEND_SA_ID" \
    --display-name="Billing Service Cloud Run Invoker"

  echo "Created:"
  echo "$FRONTEND_SA_EMAIL"
fi

echo
echo "Granting run.invoker on Production Billing Service..."

gcloud run services add-iam-policy-binding \
  "$PROD_BILLING_SERVICE" \
  --region "$REGION" \
  --member="serviceAccount:${FRONTEND_SA_EMAIL}" \
  --role="roles/run.invoker" \
  --quiet

echo "Task 6 complete."

# ------------------------------------------------------------
# Task 7 - Production Frontend
# ------------------------------------------------------------

echo
echo "============================================================"
echo " TASK 7 - Production Frontend"
echo "============================================================"

build_image \
  "prod-frontend-billing" \
  "gcr.io/${PROJECT_ID}/frontend-prod:0.1"

deploy_public \
  "$PROD_FRONTEND_SERVICE" \
  "gcr.io/${PROJECT_ID}/frontend-prod:0.1"

# Update the frontend service to use the frontend SA.
gcloud run services update "$PROD_FRONTEND_SERVICE" \
  --service-account "$FRONTEND_SA_EMAIL" \
  --region "$REGION" \
  --quiet

PROD_FRONTEND_URL="$(get_service_url "$PROD_FRONTEND_SERVICE")"

echo
echo "============================================================"
echo " FINAL RESULT"
echo "============================================================"
echo
echo "Project:"
echo "$PROJECT_ID"
echo
echo "Production Frontend:"
echo "$PROD_FRONTEND_URL"
echo
echo "Production Billing:"
echo "$PROD_BILLING_URL"
echo
echo "Frontend Service Account:"
echo "$FRONTEND_SA_EMAIL"
echo
echo "Billing Service Account:"
echo "$BILLING_SA_EMAIL"
echo

echo "Testing production frontend..."

curl --fail --silent --show-error \
  "$PROD_FRONTEND_URL" \
  >/dev/null

echo
echo "============================================================"
echo " ALL AUTOMATED STEPS COMPLETED SUCCESSFULLY"
echo "============================================================"
echo
echo "Open the production frontend:"
echo "$PROD_FRONTEND_URL"
echo
