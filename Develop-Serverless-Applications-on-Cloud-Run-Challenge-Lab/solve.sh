#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Google Skills - Develop Serverless Applications on Cloud Run
# Challenge Lab - Automated Solution
#
# Safe order:
#   1. Public Billing
#   2. Staging Frontend
#   3. Private Billing (NO service account)
#   4. Create Billing Service Account
#   5. Production Billing (Billing SA attached)
#   6. Create Frontend SA + grant run.invoker
#   7. Production Frontend (Frontend SA attached)
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

command -v curl >/dev/null 2>&1 || {
  echo "ERROR: curl is not installed."
  exit 1
}

service_exists() {
  local service="$1"

  gcloud run services describe "$service" \
    --region "$REGION" \
    --platform managed \
    --format="value(metadata.name)" \
    >/dev/null 2>&1
}

delete_service_if_exists() {
  local service="$1"

  if service_exists "$service"; then
    echo "Deleting existing Cloud Run service: $service"
    gcloud run services delete "$service" \
      --region "$REGION" \
      --platform managed \
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

  if [[ ! -d "$LAB_DIR/$directory" ]]; then
    echo "ERROR: Source directory does not exist:"
    echo "       $LAB_DIR/$directory"
    exit 1
  fi

  (
    cd "$LAB_DIR/$directory"
    gcloud builds submit --tag "$image" --quiet
  )

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

# IMPORTANT:
# Task 3 happens BEFORE the Billing Service Account exists.
# Therefore this function intentionally has NO --service-account flag.
deploy_private() {
  local service="$1"
  local image="$2"

  echo
  echo "Deploying PRIVATE Cloud Run service: $service"

  gcloud run deploy "$service" \
    --image "$image" \
    --no-allow-unauthenticated \
    --region "$REGION" \
    --platform managed \
    --quiet
}

deploy_private_with_sa() {
  local service="$1"
  local image="$2"
  local service_account="$3"

  echo
  echo "Deploying PRIVATE Cloud Run service: $service"
  echo "Runtime service account: $service_account"

  gcloud run deploy "$service" \
    --image "$image" \
    --service-account "$service_account" \
    --no-allow-unauthenticated \
    --region "$REGION" \
    --platform managed \
    --quiet
}

get_service_url() {
  local service="$1"

  gcloud run services describe "$service" \
    --region "$REGION" \
    --platform managed \
    --format="value(status.url)"
}

wait_for_service() {
  local service="$1"

  echo "Waiting for Cloud Run service to become ready: $service"

  for _ in {1..30}; do
    if service_exists "$service"; then
      return 0
    fi
    sleep 2
  done

  echo "ERROR: Cloud Run service did not become ready: $service"
  exit 1
}

create_service_account_if_missing() {
  local sa_id="$1"
  local display_name="$2"
  local email="${sa_id}@${PROJECT_ID}.iam.gserviceaccount.com"

  if gcloud iam service-accounts describe "$email" \
      --project "$PROJECT_ID" \
      >/dev/null 2>&1; then
    echo "Service account already exists: $email"
  else
    echo "Creating service account: $email"

    gcloud iam service-accounts create "$sa_id" \
      --project "$PROJECT_ID" \
      --display-name="$display_name" \
      --quiet

    echo "Created: $email"
  fi
}

# ------------------------------------------------------------
# Project / region
# ------------------------------------------------------------

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  echo "No active gcloud project was found."
  read -r -p "Enter your Google Cloud Project ID: " PROJECT_ID
fi

if [[ -z "$PROJECT_ID" ]]; then
  echo "ERROR: Project ID cannot be empty."
  exit 1
fi

gcloud projects describe "$PROJECT_ID" >/dev/null

gcloud config set project "$PROJECT_ID" >/dev/null

echo
echo "Project: $PROJECT_ID"

read -r -p "Cloud Run region [us-east4]: " REGION
REGION="${REGION:-us-east4}"

if [[ ! "$REGION" =~ ^[a-z0-9-]+$ ]]; then
  echo "ERROR: Invalid region: $REGION"
  exit 1
fi

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
echo "Use the EXACT names/suffixes displayed in the lab."
echo "Do not add .run.app or the project ID."
echo

read -r -p "Public Billing Service name: " PUBLIC_BILLING_SERVICE
read -r -p "Staging Frontend Service name: " STAGING_FRONTEND_SERVICE
read -r -p "Private Billing Service name: " PRIVATE_BILLING_SERVICE
read -r -p "Billing Service Account ID: " BILLING_SA_ID
read -r -p "Production Billing Service name: " PROD_BILLING_SERVICE
read -r -p "Frontend Service Account ID: " FRONTEND_SA_ID
read -r -p "Production Frontend Service name: " PROD_FRONTEND_SERVICE

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

LAB_DIR="$HOME/pet-theory"
LAB_CODE_DIR="$LAB_DIR/lab07"

# ------------------------------------------------------------
# Confirmation
# ------------------------------------------------------------

echo
echo "============================================================"
echo " Configuration"
echo "============================================================"
echo "Project ID               : $PROJECT_ID"
echo "Region                   : $REGION"
echo "Lab directory            : $LAB_CODE_DIR"
echo "Public Billing           : $PUBLIC_BILLING_SERVICE"
echo "Staging Frontend         : $STAGING_FRONTEND_SERVICE"
echo "Private Billing          : $PRIVATE_BILLING_SERVICE"
echo "Billing Service Account  : $BILLING_SA_ID"
echo "Production Billing       : $PROD_BILLING_SERVICE"
echo "Frontend Service Account : $FRONTEND_SA_ID"
echo "Production Frontend      : $PROD_FRONTEND_SERVICE"
echo "============================================================"
echo

read -r -p "Proceed with the complete lab automation? [Y/n]: " answer
answer="${answer:-Y}"
case "$answer" in
  Y|y|yes|YES) ;;
  *) echo "Cancelled."; exit 0 ;;
esac

# ------------------------------------------------------------
# Provision repository
# ------------------------------------------------------------

echo
echo "============================================================"
echo " Provisioning lab environment"
echo "============================================================"

if [[ ! -d "$LAB_DIR/.git" ]]; then
  if [[ -e "$LAB_DIR" ]]; then
    echo "ERROR: $LAB_DIR exists but is not a git repository."
    echo "Move/remove that directory and run the script again."
    exit 1
  fi

  echo "Cloning pet-theory repository..."
  git clone https://github.com/rosera/pet-theory.git "$LAB_DIR"
else
  echo "pet-theory repository already exists."
fi

if [[ ! -d "$LAB_CODE_DIR" ]]; then
  echo "ERROR: Expected lab directory not found:"
  echo "       $LAB_CODE_DIR"
  echo
  echo "The pet-theory repository does not contain the expected lab07 path."
  exit 1
fi

# ============================================================
# TASK 1 - Public Billing Service
# ============================================================

echo
echo "============================================================"
echo " TASK 1 - Public Billing Service"
echo "============================================================"

build_image \
  "lab07/unit-api-billing" \
  "gcr.io/${PROJECT_ID}/billing-staging-api:0.1"

deploy_public \
  "$PUBLIC_BILLING_SERVICE" \
  "gcr.io/${PROJECT_ID}/billing-staging-api:0.1"

wait_for_service "$PUBLIC_BILLING_SERVICE"

PUBLIC_BILLING_URL="$(get_service_url "$PUBLIC_BILLING_SERVICE")"

echo "Public Billing URL:"
echo "$PUBLIC_BILLING_URL"

echo "Testing public Billing endpoint..."
curl --fail --silent --show-error \
  --retry 5 --retry-delay 2 \
  "$PUBLIC_BILLING_URL" >/dev/null

echo "Task 1 complete."

# ============================================================
# TASK 2 - Staging Frontend
# ============================================================

echo
echo "============================================================"
echo " TASK 2 - Staging Frontend"
echo "============================================================"

build_image \
  "lab07/staging-frontend-billing" \
  "gcr.io/${PROJECT_ID}/frontend-staging:0.1"

deploy_public \
  "$STAGING_FRONTEND_SERVICE" \
  "gcr.io/${PROJECT_ID}/frontend-staging:0.1"

wait_for_service "$STAGING_FRONTEND_SERVICE"

STAGING_FRONTEND_URL="$(get_service_url "$STAGING_FRONTEND_SERVICE")"

echo "Staging Frontend URL:"
echo "$STAGING_FRONTEND_URL"

echo "Testing staging frontend..."
curl --fail --silent --show-error \
  --retry 5 --retry-delay 2 \
  "$STAGING_FRONTEND_URL" >/dev/null

echo "Task 2 complete."

# ============================================================
# TASK 3 - Private Billing Service
# ============================================================

echo
echo "============================================================"
echo " TASK 3 - Private Billing Service"
echo "============================================================"

echo "Removing the previous public Billing Service..."
delete_service_if_exists "$PUBLIC_BILLING_SERVICE"

build_image \
  "lab07/staging-api-billing" \
  "gcr.io/${PROJECT_ID}/billing-staging-api:0.2"

# CRITICAL FIX:
# DO NOT attach BILLING_SA here.
# Task 4 creates billing-service-sa-* AFTER Task 3.
deploy_private \
  "$PRIVATE_BILLING_SERVICE" \
  "gcr.io/${PROJECT_ID}/billing-staging-api:0.2"

wait_for_service "$PRIVATE_BILLING_SERVICE"

PRIVATE_BILLING_URL="$(get_service_url "$PRIVATE_BILLING_SERVICE")"

echo "Private Billing URL:"
echo "$PRIVATE_BILLING_URL"

echo "Testing authenticated private endpoint..."
curl --fail --silent --show-error \
  --retry 5 --retry-delay 2 \
  -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  "$PRIVATE_BILLING_URL" >/dev/null

echo "Task 3 complete."

# ============================================================
# TASK 4 - Billing Service Account
# ============================================================

echo
echo "============================================================"
echo " TASK 4 - Billing Service Account"
echo "============================================================"

create_service_account_if_missing \
  "$BILLING_SA_ID" \
  "Billing Service Cloud Run"

echo "Task 4 complete."

# ============================================================
# TASK 5 - Production Billing Service
# ============================================================

echo
echo "============================================================"
echo " TASK 5 - Production Billing Service"
echo "============================================================"

# Verify the SA exists before using --service-account.
gcloud iam service-accounts describe "$BILLING_SA_EMAIL" \
  --project "$PROJECT_ID" >/dev/null

build_image \
  "lab07/prod-api-billing" \
  "gcr.io/${PROJECT_ID}/billing-prod-api:0.1"

# Task 5 requires authentication AND the Billing Service Account.
deploy_private_with_sa \
  "$PROD_BILLING_SERVICE" \
  "gcr.io/${PROJECT_ID}/billing-prod-api:0.1" \
  "$BILLING_SA_EMAIL"

wait_for_service "$PROD_BILLING_SERVICE"

PROD_BILLING_URL="$(get_service_url "$PROD_BILLING_SERVICE")"

echo "Production Billing URL:"
echo "$PROD_BILLING_URL"

echo "Testing production Billing endpoint..."
curl --fail --silent --show-error \
  --retry 5 --retry-delay 2 \
  -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  "$PROD_BILLING_URL" >/dev/null

echo "Task 5 complete."

# ============================================================
# TASK 6 - Frontend Service Account
# ============================================================

echo
echo "============================================================"
echo " TASK 6 - Frontend Service Account"
echo "============================================================"

create_service_account_if_missing \
  "$FRONTEND_SA_ID" \
  "Billing Service Cloud Run Invoker"

echo
echo "Granting roles/run.invoker on Production Billing Service..."

gcloud run services add-iam-policy-binding \
  "$PROD_BILLING_SERVICE" \
  --region "$REGION" \
  --platform managed \
  --member="serviceAccount:${FRONTEND_SA_EMAIL}" \
  --role="roles/run.invoker" \
  --quiet

echo "Task 6 complete."

# ============================================================
# TASK 7 - Production Frontend
# ============================================================

echo
echo "============================================================"
echo " TASK 7 - Production Frontend"
echo "============================================================"

# Verify the frontend SA exists before using it.
gcloud iam service-accounts describe "$FRONTEND_SA_EMAIL" \
  --project "$PROJECT_ID" >/dev/null

build_image \
  "lab07/prod-frontend-billing" \
  "gcr.io/${PROJECT_ID}/frontend-prod:0.1"

# Task 7 requires the frontend to remain PUBLIC while the
# frontend Cloud Run runtime uses the new Frontend SA.
# Attach the SA DURING deployment instead of deploying first
# and updating it afterward.
gcloud run deploy "$PROD_FRONTEND_SERVICE" \
  --image "gcr.io/${PROJECT_ID}/frontend-prod:0.1" \
  --service-account "$FRONTEND_SA_EMAIL" \
  --allow-unauthenticated \
  --region "$REGION" \
  --platform managed \
  --quiet

wait_for_service "$PROD_FRONTEND_SERVICE"

PROD_FRONTEND_URL="$(get_service_url "$PROD_FRONTEND_SERVICE")"

echo
echo "Testing production frontend..."
curl --fail --silent --show-error \
  --retry 5 --retry-delay 2 \
  "$PROD_FRONTEND_URL" >/dev/null

echo
echo "============================================================"
echo " ALL AUTOMATED STEPS COMPLETED SUCCESSFULLY"
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
echo "Open the production frontend:"
echo "$PROD_FRONTEND_URL"
echo
