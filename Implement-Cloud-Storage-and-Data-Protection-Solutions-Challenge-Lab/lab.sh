#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# Google Cloud Storage Challenge Lab Automation
# ============================================================

# ------------------------------------------------------------
# Error handler
# ------------------------------------------------------------

trap 'echo; echo "❌ Script failed at line $LINENO"; echo "Command: $BASH_COMMAND"; exit 1' ERR

# ------------------------------------------------------------
# Functions
# ------------------------------------------------------------

die() {
    echo
    echo "❌ $1"
    exit 1
}

prompt() {
    local message="$1"
    local __resultvar="$2"
    local value=""

    if [[ -t 0 ]]; then
        read -r -p "$message" value
    elif [[ -e /dev/tty ]]; then
        read -r -p "$message" value < /dev/tty
    else
        die "Interactive terminal (/dev/tty) is not available."
    fi

    printf -v "$__resultvar" '%s' "$value"
}

confirm() {
    local message="$1"
    local answer=""

    if [[ -t 0 ]]; then
        read -r -p "$message" answer
    elif [[ -e /dev/tty ]]; then
        read -r -p "$message" answer < /dev/tty
    else
        return 1
    fi

    [[ "$answer" =~ ^[Yy]$ ]]
}

# ------------------------------------------------------------
# Start
# ------------------------------------------------------------

echo
echo "============================================================"
echo " Google Cloud Storage Challenge Lab Automation"
echo "============================================================"
echo

# ------------------------------------------------------------
# 1. Check gcloud
# ------------------------------------------------------------

echo "Checking Google Cloud CLI..."

command -v gcloud >/dev/null 2>&1 || \
    die "gcloud CLI is not installed."

echo "✅ gcloud CLI found."

# ------------------------------------------------------------
# 2. Get user inputs
# ------------------------------------------------------------

echo
echo "============================================================"
echo " USER INPUT"
echo "============================================================"
echo

prompt "Enter Project ID: " PROJECT_ID
prompt "Enter Region (example: us-west1): " REGION
prompt "Enter Bucket1 name: " BUCKET1
prompt "Enter Bucket2 name: " BUCKET2
prompt "Enter Bucket3 name: " BUCKET3

# Remove accidental gs:// prefix
PROJECT_ID="${PROJECT_ID#gs://}"
BUCKET1="${BUCKET1#gs://}"
BUCKET2="${BUCKET2#gs://}"
BUCKET3="${BUCKET3#gs://}"

# Remove accidental trailing slash
BUCKET1="${BUCKET1%/}"
BUCKET2="${BUCKET2%/}"
BUCKET3="${BUCKET3%/}"

# ------------------------------------------------------------
# 3. Validate inputs
# ------------------------------------------------------------

[[ -n "$PROJECT_ID" ]] || die "Project ID cannot be empty."
[[ -n "$REGION" ]] || die "Region cannot be empty."
[[ -n "$BUCKET1" ]] || die "Bucket1 name cannot be empty."
[[ -n "$BUCKET2" ]] || die "Bucket2 name cannot be empty."
[[ -n "$BUCKET3" ]] || die "Bucket3 name cannot be empty."

# ------------------------------------------------------------
# 4. Display configuration
# ------------------------------------------------------------

echo
echo "============================================================"
echo " Configuration"
echo "============================================================"
echo
echo "Project ID : $PROJECT_ID"
echo "Region     : $REGION"
echo "Bucket1    : $BUCKET1"
echo "Bucket2    : $BUCKET2"
echo "Bucket3    : $BUCKET3"
echo

if ! confirm "Continue with these values? [y/N]: "; then
    echo
    echo "❌ Cancelled."
    exit 0
fi

# ------------------------------------------------------------
# 5. Check authentication
# ------------------------------------------------------------

echo
echo "============================================================"
echo " Checking Authentication"
echo "============================================================"
echo

ACTIVE_ACCOUNT="$(
    gcloud auth list \
        --filter=status:ACTIVE \
        --format="value(account)" 2>/dev/null \
        | head -n 1
)"

[[ -n "$ACTIVE_ACCOUNT" ]] || \
    die "No active Google Cloud account found."

echo "✅ Active account: $ACTIVE_ACCOUNT"

# ------------------------------------------------------------
# 6. Set project
# ------------------------------------------------------------

echo
echo "============================================================"
echo " Setting Project"
echo "============================================================"
echo

gcloud config set project "$PROJECT_ID"

echo "✅ Project set to: $PROJECT_ID"

# ------------------------------------------------------------
# 7. Set region
# ------------------------------------------------------------

echo
echo "============================================================"
echo " Setting Region"
echo "============================================================"
echo

gcloud config set compute/region "$REGION"

echo "✅ Region set to: $REGION"

# ============================================================
# TASK 1
# Create Bucket1 with NEARLINE
# ============================================================

echo
echo "============================================================"
echo " TASK 1 - Bucket1 / NEARLINE"
echo "============================================================"
echo

if gcloud storage buckets describe "gs://$BUCKET1" >/dev/null 2>&1; then

    echo "ℹ️ Bucket1 already exists."
    echo "Updating default storage class to NEARLINE..."

    gcloud storage buckets update \
        "gs://$BUCKET1" \
        --default-storage-class=NEARLINE

    echo "✅ Bucket1 updated to NEARLINE."

else

    echo "Creating Bucket1..."

    gcloud storage buckets create \
        "gs://$BUCKET1" \
        --project="$PROJECT_ID" \
        --location="$REGION" \
        --default-storage-class=NEARLINE

    echo "✅ Bucket1 created with NEARLINE."
fi

# ------------------------------------------------------------
# Verify Task 1
# ------------------------------------------------------------

BUCKET1_CLASS="$(
    gcloud storage buckets describe \
        "gs://$BUCKET1" \
        --format="value(storageClass)"
)"

if [[ "$BUCKET1_CLASS" != "NEARLINE" ]]; then
    die "Task 1 verification failed. Bucket1 storage class is: $BUCKET1_CLASS"
fi

echo "✅ Task 1 verification passed."

# ============================================================
# TASK 2
# Update sample.txt in Bucket2
# ============================================================

echo
echo "============================================================"
echo " TASK 2 - Update sample.txt in Bucket2"
echo "============================================================"
echo

# Check Bucket2
if ! gcloud storage buckets describe "gs://$BUCKET2" >/dev/null 2>&1; then
    die "Bucket2 does not exist: gs://$BUCKET2"
fi

echo "✅ Bucket2 exists."

EXPECTED_CONTENT="This is an example of editing the file content for cloud storage object"

# Create temporary file safely
TMP_FILE="$(mktemp)"

cleanup() {
    rm -f "$TMP_FILE"
}

trap cleanup EXIT

printf '%s\n' "$EXPECTED_CONTENT" > "$TMP_FILE"

echo "Uploading sample.txt..."

gcloud storage cp \
    "$TMP_FILE" \
    "gs://$BUCKET2/sample.txt"

echo "✅ sample.txt uploaded."

# Verify content
ACTUAL_CONTENT="$(
    gcloud storage cat \
        "gs://$BUCKET2/sample.txt"
)"

if [[ "$ACTUAL_CONTENT" != "$EXPECTED_CONTENT" ]]; then

    echo
    echo "❌ Task 2 verification failed."
    echo
    echo "Expected:"
    printf '%s\n' "$EXPECTED_CONTENT"
    echo
    echo "Actual:"
    printf '%s\n' "$ACTUAL_CONTENT"

    exit 1
fi

echo "✅ Task 2 content verified."

# ============================================================
# TASK 3
# Change Bucket3 to ARCHIVE
# ============================================================

echo
echo "============================================================"
echo " TASK 3 - Bucket3 / ARCHIVE"
echo "============================================================"
echo

# Check Bucket3
if ! gcloud storage buckets describe "gs://$BUCKET3" >/dev/null 2>&1; then
    die "Bucket3 does not exist: gs://$BUCKET3"
fi

echo "✅ Bucket3 exists."
echo "Updating default storage class to ARCHIVE..."

gcloud storage buckets update \
    "gs://$BUCKET3" \
    --default-storage-class=ARCHIVE

echo "✅ Bucket3 updated to ARCHIVE."

# ------------------------------------------------------------
# Verify Task 3
# ------------------------------------------------------------

BUCKET3_CLASS="$(
    gcloud storage buckets describe \
        "gs://$BUCKET3" \
        --format="value(storageClass)"
)"

if [[ "$BUCKET3_CLASS" != "ARCHIVE" ]]; then
    die "Task 3 verification failed. Bucket3 storage class is: $BUCKET3_CLASS"
fi

echo "✅ Task 3 verification passed."

# ============================================================
# FINAL VERIFICATION
# ============================================================

echo
echo "============================================================"
echo " FINAL VERIFICATION"
echo "============================================================"
echo

echo "Project:"
echo "  $PROJECT_ID"

echo
echo "Region:"
echo "  $REGION"

echo
echo "Bucket1:"
echo "  gs://$BUCKET1"
echo "  Storage class: $BUCKET1_CLASS"

echo
echo "Bucket2:"
echo "  gs://$BUCKET2/sample.txt"
echo "  Content:"
gcloud storage cat "gs://$BUCKET2/sample.txt"

echo
echo "Bucket3:"
echo "  gs://$BUCKET3"
echo "  Storage class: $BUCKET3_CLASS"

echo
echo "============================================================"
echo " ✅ ALL TASKS COMPLETED SUCCESSFULLY"
echo "============================================================"
echo
