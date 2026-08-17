#!/usr/bin/env bash

set -Eeuo pipefail

trap 'echo; echo "❌ Script failed at line $LINENO. Command: $BASH_COMMAND"; exit 1' ERR

echo "===================================================="
echo " Google Cloud Storage Challenge Lab Automation"
echo "===================================================="
echo

# ----------------------------------------------------
# 1. USER INPUTS
# ----------------------------------------------------

read -rp "Enter Project ID: " PROJECT_ID
read -rp "Enter Region (example: us-west1): " REGION
read -rp "Enter Bucket1 name: " BUCKET1
read -rp "Enter Bucket2 name: " BUCKET2
read -rp "Enter Bucket3 name: " BUCKET3

# Remove accidental gs:// prefix if user pasted it.
PROJECT_ID="${PROJECT_ID#gs://}"
BUCKET1="${BUCKET1#gs://}"
BUCKET2="${BUCKET2#gs://}"
BUCKET3="${BUCKET3#gs://}"

echo
echo "----------------------------------------------------"
echo "Checking required commands..."
echo "----------------------------------------------------"

command -v gcloud >/dev/null 2>&1 || {
    echo "❌ gcloud CLI is not installed."
    exit 1
}

# ----------------------------------------------------
# 2. CHECK AUTHENTICATION
# ----------------------------------------------------

echo
echo "----------------------------------------------------"
echo "Checking Google Cloud authentication..."
echo "----------------------------------------------------"

if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    echo "❌ No active Google Cloud account found."
    echo "Please authenticate first."
    exit 1
fi

ACTIVE_ACCOUNT="$(gcloud auth list \
    --filter=status:ACTIVE \
    --format='value(account)' | head -n 1)"

echo "✅ Active account: $ACTIVE_ACCOUNT"

# ----------------------------------------------------
# 3. SET PROJECT
# ----------------------------------------------------

echo
echo "----------------------------------------------------"
echo "Setting project..."
echo "----------------------------------------------------"

gcloud config set project "$PROJECT_ID"

# ----------------------------------------------------
# 4. SET REGION
# ----------------------------------------------------

echo
echo "----------------------------------------------------"
echo "Setting region..."
echo "----------------------------------------------------"

gcloud config set compute/region "$REGION"

# ----------------------------------------------------
# 5. DISPLAY CONFIGURATION
# ----------------------------------------------------

echo
echo "===================================================="
echo "Configuration"
echo "===================================================="
echo "Project ID : $PROJECT_ID"
echo "Region     : $REGION"
echo "Bucket1    : $BUCKET1"
echo "Bucket2    : $BUCKET2"
echo "Bucket3    : $BUCKET3"
echo "===================================================="
echo

read -rp "Continue with these values? [y/N]: " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "❌ Cancelled."
    exit 0
fi

# ----------------------------------------------------
# TASK 1
# Create Bucket1 with NEARLINE storage class
# ----------------------------------------------------

echo
echo "===================================================="
echo "TASK 1"
echo "Creating/updating Bucket1 with NEARLINE..."
echo "===================================================="

if gcloud storage buckets describe "gs://$BUCKET1" >/dev/null 2>&1; then

    echo "ℹ️ Bucket1 already exists."

    gcloud storage buckets update \
        "gs://$BUCKET1" \
        --default-storage-class=NEARLINE

    echo "✅ Bucket1 default storage class set to NEARLINE."

else

    gcloud storage buckets create \
        "gs://$BUCKET1" \
        --project="$PROJECT_ID" \
        --location="$REGION" \
        --default-storage-class=NEARLINE

    echo "✅ Bucket1 created with NEARLINE storage class."
fi

# ----------------------------------------------------
# TASK 2
# Update sample.txt in Bucket2
# ----------------------------------------------------

echo
echo "===================================================="
echo "TASK 2"
echo "Updating sample.txt in Bucket2..."
echo "===================================================="

# Check Bucket2 exists.
if ! gcloud storage buckets describe "gs://$BUCKET2" >/dev/null 2>&1; then
    echo "❌ Bucket2 does not exist:"
    echo "   gs://$BUCKET2"
    exit 1
fi

# Create exact required content.
TMP_FILE="$(mktemp)"

printf '%s\n' \
"This is an example of editing the file content for cloud storage object" \
> "$TMP_FILE"

# Upload using the SAME object name: sample.txt
gcloud storage cp \
    "$TMP_FILE" \
    "gs://$BUCKET2/sample.txt"

rm -f "$TMP_FILE"

echo "✅ sample.txt uploaded to Bucket2."

# Verify exact content.
EXPECTED_CONTENT="This is an example of editing the file content for cloud storage object"
ACTUAL_CONTENT="$(gcloud storage cat "gs://$BUCKET2/sample.txt")"

if [[ "$ACTUAL_CONTENT" != "$EXPECTED_CONTENT" ]]; then
    echo "❌ Task 2 verification failed."
    echo "Expected:"
    echo "$EXPECTED_CONTENT"
    echo
    echo "Actual:"
    echo "$ACTUAL_CONTENT"
    exit 1
fi

echo "✅ Task 2 content verified."

# ----------------------------------------------------
# TASK 3
# Change Bucket3 storage class to ARCHIVE
# ----------------------------------------------------

echo
echo "===================================================="
echo "TASK 3"
echo "Changing Bucket3 storage class to ARCHIVE..."
echo "===================================================="

if ! gcloud storage buckets describe "gs://$BUCKET3" >/dev/null 2>&1; then
    echo "❌ Bucket3 does not exist:"
    echo "   gs://$BUCKET3"
    exit 1
fi

gcloud storage buckets update \
    "gs://$BUCKET3" \
    --default-storage-class=ARCHIVE

echo "✅ Bucket3 default storage class set to ARCHIVE."

# ----------------------------------------------------
# FINAL VERIFICATION
# ----------------------------------------------------

echo
echo "===================================================="
echo "FINAL VERIFICATION"
echo "===================================================="

echo
echo "Bucket1:"
gcloud storage buckets describe \
    "gs://$BUCKET1" \
    --format="value(name,location,storageClass)"

echo
echo "Bucket2 sample.txt:"
gcloud storage cat \
    "gs://$BUCKET2/sample.txt"

echo
echo "Bucket3:"
gcloud storage buckets describe \
    "gs://$BUCKET3" \
    --format="value(name,location,storageClass)"

echo
echo "===================================================="
echo "✅ ALL LAB TASKS COMPLETED SUCCESSFULLY"
echo "===================================================="
