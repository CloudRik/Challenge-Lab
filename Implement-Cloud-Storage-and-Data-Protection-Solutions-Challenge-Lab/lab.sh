#!/usr/bin/env bash

set -Eeuo pipefail

trap 'echo; echo "❌ ERROR at line $LINENO"; echo "Command: $BASH_COMMAND"; exit 1' ERR

# ============================================================
# Google Cloud Storage Challenge Lab - Universal Automation
# Supports known task variants for the random-assignment lab.
# ============================================================

die() {
    echo
    echo "❌ $1"
    exit 1
}

prompt() {
    local message="$1"
    local variable="$2"
    local value=""

    if [[ -t 0 ]]; then
        read -r -p "$message" value
    elif [[ -e /dev/tty ]]; then
        read -r -p "$message" value < /dev/tty
    else
        die "Interactive terminal (/dev/tty) is not available."
    fi

    printf -v "$variable" '%s' "$value"
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
# Helper: clean bucket name
# ------------------------------------------------------------

clean_bucket() {
    local value="$1"
    value="${value#gs://}"
    value="${value%/}"
    printf '%s' "$value"
}

# ------------------------------------------------------------
# Task menu
# ------------------------------------------------------------

show_task_menu() {
    echo
    echo "============================================================"
    echo " AVAILABLE TASK VARIANTS"
    echo "============================================================"
    echo
    echo "  1) Create Bucket1 - STANDARD"
    echo "  2) Create Bucket1 - NEARLINE"
    echo "  3) Update sample.txt in Bucket2"
    echo "  4) Publish Bucket2 object to web"
    echo "  5) Change Bucket3 default class to ARCHIVE"
    echo "  6) Add labels to Bucket3"
    echo
}

# ============================================================
# START
# ============================================================

echo
echo "============================================================"
echo " Google Cloud Storage Challenge Lab Automation"
echo "============================================================"
echo

# ------------------------------------------------------------
# Check gcloud
# ------------------------------------------------------------

command -v gcloud >/dev/null 2>&1 || \
    die "gcloud CLI is not installed."

echo "✅ gcloud CLI found."

# ------------------------------------------------------------
# User inputs
# ------------------------------------------------------------

echo
echo "============================================================"
echo " BASIC LAB INFORMATION"
echo "============================================================"
echo

prompt "Enter Project ID: " PROJECT_ID
prompt "Enter Region (example: us-east4): " REGION
prompt "Enter Bucket1 name: " BUCKET1
prompt "Enter Bucket2 name: " BUCKET2
prompt "Enter Bucket3 name: " BUCKET3

PROJECT_ID="${PROJECT_ID#gs://}"

BUCKET1="$(clean_bucket "$BUCKET1")"
BUCKET2="$(clean_bucket "$BUCKET2")"
BUCKET3="$(clean_bucket "$BUCKET3")"

[[ -n "$PROJECT_ID" ]] || die "Project ID cannot be empty."
[[ -n "$REGION" ]] || die "Region cannot be empty."
[[ -n "$BUCKET1" ]] || die "Bucket1 cannot be empty."
[[ -n "$BUCKET2" ]] || die "Bucket2 cannot be empty."
[[ -n "$BUCKET3" ]] || die "Bucket3 cannot be empty."

# ------------------------------------------------------------
# Select assigned task variants
# ------------------------------------------------------------

show_task_menu

prompt "Enter Task 1 variant number: " TASK1
prompt "Enter Task 2 variant number: " TASK2
prompt "Enter Task 3 variant number: " TASK3

case "$TASK1" in
    1|2) ;;
    *) die "Invalid Task 1 variant. Use 1 or 2." ;;
esac

case "$TASK2" in
    3|4) ;;
    *) die "Invalid Task 2 variant. Use 3 or 4." ;;
esac

case "$TASK3" in
    5|6) ;;
    *) die "Invalid Task 3 variant. Use 5 or 6." ;;
esac

# ------------------------------------------------------------
# Show configuration
# ------------------------------------------------------------

echo
echo "============================================================"
echo " CONFIGURATION"
echo "============================================================"
echo
echo "Project ID : $PROJECT_ID"
echo "Region     : $REGION"
echo "Bucket1    : $BUCKET1"
echo "Bucket2    : $BUCKET2"
echo "Bucket3    : $BUCKET3"
echo
echo "Task 1     : Variant $TASK1"
echo "Task 2     : Variant $TASK2"
echo "Task 3     : Variant $TASK3"
echo

if ! confirm "Continue with these values? [y/N]: "; then
    echo "❌ Cancelled."
    exit 0
fi

# ============================================================
# AUTHENTICATION
# ============================================================

echo
echo "============================================================"
echo " CHECKING AUTHENTICATION"
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

# ============================================================
# PROJECT
# ============================================================

echo
echo "============================================================"
echo " SETTING PROJECT"
echo "============================================================"
echo

gcloud config set project "$PROJECT_ID"

echo "✅ Project: $PROJECT_ID"

# ============================================================
# REGION
# ============================================================

echo
echo "============================================================"
echo " SETTING REGION"
echo "============================================================"
echo

gcloud config set compute/region "$REGION"

echo "✅ Region: $REGION"

# ============================================================
# TASK 1
# ============================================================

echo
echo "============================================================"
echo " TASK 1"
echo "============================================================"
echo

case "$TASK1" in

    1)
        echo "Creating Bucket1 with STANDARD storage class..."

        if gcloud storage buckets describe "gs://$BUCKET1" \
            >/dev/null 2>&1; then

            echo "ℹ️ Bucket1 already exists."
            echo "Leaving existing storage class unchanged."

        else
            gcloud storage buckets create \
                "gs://$BUCKET1" \
                --project="$PROJECT_ID" \
                --location="$REGION"

            echo "✅ Bucket1 created."
        fi
        ;;

    2)
        echo "Creating Bucket1 with NEARLINE storage class..."

        if gcloud storage buckets describe "gs://$BUCKET1" \
            >/dev/null 2>&1; then

            echo "ℹ️ Bucket1 already exists."
            echo "Updating default storage class to NEARLINE..."

            gcloud storage buckets update \
                "gs://$BUCKET1" \
                --default-storage-class=NEARLINE

        else

            gcloud storage buckets create \
                "gs://$BUCKET1" \
                --project="$PROJECT_ID" \
                --location="$REGION" \
                --default-storage-class=NEARLINE
        fi

        echo "✅ Bucket1 configured as NEARLINE."
        ;;
esac

# ============================================================
# TASK 2
# ============================================================

echo
echo "============================================================"
echo " TASK 2"
echo "============================================================"
echo

case "$TASK2" in

    # --------------------------------------------------------
    # Variant 3: Update sample.txt
    # --------------------------------------------------------

    3)

        echo "Updating sample.txt in Bucket2..."

        if ! gcloud storage buckets describe \
            "gs://$BUCKET2" >/dev/null 2>&1; then

            die "Bucket2 does not exist: gs://$BUCKET2"
        fi

        EXPECTED_CONTENT="This is an example of editing the file content for cloud storage object"

        TMP_FILE="$(mktemp)"

        cleanup_task2() {
            rm -f "$TMP_FILE"
        }

        trap cleanup_task2 EXIT

        printf '%s\n' "$EXPECTED_CONTENT" > "$TMP_FILE"

        gcloud storage cp \
            "$TMP_FILE" \
            "gs://$BUCKET2/sample.txt"

        ACTUAL_CONTENT="$(
            gcloud storage cat \
                "gs://$BUCKET2/sample.txt"
        )"

        if [[ "$ACTUAL_CONTENT" != "$EXPECTED_CONTENT" ]]; then
            die "Bucket2 sample.txt content verification failed."
        fi

        rm -f "$TMP_FILE"

        trap - EXIT

        echo "✅ sample.txt updated successfully."
        ;;

    # --------------------------------------------------------
    # Variant 4: Public object
    # --------------------------------------------------------

    4)

        echo "Making Bucket2 object publicly readable..."

        if ! gcloud storage buckets describe \
            "gs://$BUCKET2" >/dev/null 2>&1; then

            die "Bucket2 does not exist: gs://$BUCKET2"
        fi

        prompt "Enter object name inside Bucket2: " OBJECT_NAME

        [[ -n "$OBJECT_NAME" ]] || \
            die "Object name cannot be empty."

        OBJECT_NAME="${OBJECT_NAME#/}"

        if ! gcloud storage ls \
            "gs://$BUCKET2/$OBJECT_NAME" >/dev/null 2>&1; then

            die "Object not found: gs://$BUCKET2/$OBJECT_NAME"
        fi

        gcloud storage objects update \
            "gs://$BUCKET2/$OBJECT_NAME" \
            --add-acl-grant=entity=allUsers,role=READER

        echo
        echo "✅ Object is now publicly readable:"
        echo "   gs://$BUCKET2/$OBJECT_NAME"
        ;;
esac

# ============================================================
# TASK 3
# ============================================================

echo
echo "============================================================"
echo " TASK 3"
echo "============================================================"
echo

case "$TASK3" in

    # --------------------------------------------------------
    # Variant 5: ARCHIVE
    # --------------------------------------------------------

    5)

        echo "Changing Bucket3 default storage class to ARCHIVE..."

        if ! gcloud storage buckets describe \
            "gs://$BUCKET3" >/dev/null 2>&1; then

            die "Bucket3 does not exist: gs://$BUCKET3"
        fi

        gcloud storage buckets update \
            "gs://$BUCKET3" \
            --default-storage-class=ARCHIVE

        echo "✅ Bucket3 configured as ARCHIVE."
        ;;

    # --------------------------------------------------------
    # Variant 6: Labels
    # --------------------------------------------------------

    6)

        echo "Adding label to Bucket3..."

        if ! gcloud storage buckets describe \
            "gs://$BUCKET3" >/dev/null 2>&1; then

            die "Bucket3 does not exist: gs://$BUCKET3"
        fi

        echo
        echo "Enter the label exactly as required by your lab."
        echo "Example: environment=lab"
        echo

        prompt "Label key: " LABEL_KEY
        prompt "Label value: " LABEL_VALUE

        [[ -n "$LABEL_KEY" ]] || \
            die "Label key cannot be empty."

        [[ -n "$LABEL_VALUE" ]] || \
            die "Label value cannot be empty."

        gcloud storage buckets update \
            "gs://$BUCKET3" \
            --update-labels="${LABEL_KEY}=${LABEL_VALUE}"

        echo "✅ Label added to Bucket3."
        ;;

esac

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

gcloud storage buckets describe \
    "gs://$BUCKET1" \
    --format="value(storageClass)" 2>/dev/null \
    || true

echo
echo "Bucket2:"
echo "  gs://$BUCKET2"

if [[ "$TASK2" == "3" ]]; then
    echo "  sample.txt:"
    gcloud storage cat "gs://$BUCKET2/sample.txt"
fi

if [[ "$TASK2" == "4" ]]; then
    echo "  Public object configured."
fi

echo
echo "Bucket3:"
echo "  gs://$BUCKET3"

if [[ "$TASK3" == "5" ]]; then
    gcloud storage buckets describe \
        "gs://$BUCKET3" \
        --format="value(storageClass)"
fi

if [[ "$TASK3" == "6" ]]; then
    echo "  Labels:"
    gcloud storage buckets describe \
        "gs://$BUCKET3" \
        --format="value(labels)"
fi

echo
echo "============================================================"
echo " ✅ SCRIPT COMPLETED"
echo "============================================================"
echo
echo "Now click 'Check my progress' for each lab task."
echo
