#!/usr/bin/env bash

set -Eeuo pipefail

trap 'echo; echo "❌ ERROR at line $LINENO"; echo "Command: $BASH_COMMAND"; exit 1' ERR

# ============================================================
# Google Cloud Storage Challenge Lab
# Task-name based automation
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
        die "Interactive terminal is not available."
    fi

    printf -v "$variable" '%s' "$value"
}

clean_bucket() {
    local value="$1"
    value="${value#gs://}"
    value="${value%/}"
    printf '%s' "$value"
}

normalize_task() {
    tr '[:upper:]' '[:lower:]' <<< "$1"
}

detect_task() {
    local input
    input="$(normalize_task "$1")"

    # --------------------------------------------------------
    # CREATE BUCKET TYPES
    # --------------------------------------------------------

    if [[ "$input" == *"coldline"* && "$input" == *"bucket"* ]]; then
        echo "CREATE_COLDLINE"
        return
    fi

    if [[ "$input" == *"nearline"* && "$input" == *"bucket"* ]]; then
        echo "CREATE_NEARLINE"
        return
    fi

    if [[ "$input" == *"create a bucket"* ||
          "$input" == *"create a cloud storage bucket"* ]]; then
        echo "CREATE_STANDARD"
        return
    fi

    # --------------------------------------------------------
    # ARCHIVE
    # IMPORTANT: Check this BEFORE sample.txt/update matching.
    # --------------------------------------------------------

    if [[ "$input" == *"archive"* &&
          "$input" == *"storage class"* ]]; then
        echo "ARCHIVE_BUCKET3"
        return
    fi

    # --------------------------------------------------------
    # RETENTION POLICY
    # --------------------------------------------------------

    if [[ "$input" == *"retention policy"* ]]; then
        echo "RETENTION_30S"
        return
    fi

    # --------------------------------------------------------
    # PUBLIC OBJECT
    # --------------------------------------------------------

    if [[ "$input" == *"publish cloud storage files to web"* ||
          "$input" == *"publicly available"* ||
          "$input" == *"all users read permission"* ]]; then
        echo "PUBLIC_OBJECT"
        return
    fi

    # --------------------------------------------------------
    # UPDATE sample.txt
    # STRICT MATCHING
    # --------------------------------------------------------

    if [[ "$input" == *"update the file content of cloud storage object"* ||
          "$input" == *"edit the file contents of sample.txt"* ||
          ( "$input" == *"sample.txt"* && "$input" == *"edit"* ) ]]; then
        echo "UPDATE_SAMPLE_TXT"
        return
    fi

    # --------------------------------------------------------
    # ADD FILE TO BUCKET3
    # --------------------------------------------------------

    if [[ "$input" == *"add a file to the bucket"* ||
          "$input" == *"add an object into the precreated bucket"* ]]; then
        echo "UPLOAD_TO_BUCKET3"
        return
    fi

    # --------------------------------------------------------
    # LABEL BUCKET3
    # --------------------------------------------------------

    if [[ "$input" == *"add labels to cloud storage bucket"* ||
          "$input" == *"add labels"* ]]; then
        echo "LABEL_BUCKET3"
        return
    fi

    echo "UNKNOWN"
}

run_task() {
    local task_number="$1"
    local task_type="$2"

    echo
    echo "============================================================"
    echo " TASK $task_number -> $task_type"
    echo "============================================================"
    echo

    case "$task_type" in

        # ====================================================
        # CREATE STANDARD BUCKET
        # ====================================================

        CREATE_STANDARD)

            echo "Creating Bucket1 with STANDARD storage class..."

            if gcloud storage buckets describe \
                "gs://$BUCKET1" >/dev/null 2>&1; then

                echo "ℹ️ Bucket1 already exists."
                echo "✅ Leaving it as-is."

            else
                gcloud storage buckets create \
                    "gs://$BUCKET1" \
                    --project="$PROJECT_ID" \
                    --location="$REGION" \
                    --default-storage-class=STANDARD

                echo "✅ Bucket1 created."
            fi
            ;;

        # ====================================================
        # CREATE NEARLINE BUCKET
        # ====================================================

        CREATE_NEARLINE)

            echo "Creating Bucket1 with NEARLINE storage class..."

            if gcloud storage buckets describe \
                "gs://$BUCKET1" >/dev/null 2>&1; then

                echo "ℹ️ Bucket1 already exists."

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

        # ====================================================
        # CREATE COLDLINE BUCKET
        # ====================================================

        CREATE_COLDLINE)

            echo "Creating Bucket1 with COLDLINE storage class..."

            if gcloud storage buckets describe \
                "gs://$BUCKET1" >/dev/null 2>&1; then

                echo "ℹ️ Bucket1 already exists."

                gcloud storage buckets update \
                    "gs://$BUCKET1" \
                    --default-storage-class=COLDLINE

            else

                gcloud storage buckets create \
                    "gs://$BUCKET1" \
                    --project="$PROJECT_ID" \
                    --location="$REGION" \
                    --default-storage-class=COLDLINE
            fi

            echo "✅ Bucket1 configured as COLDLINE."
            ;;

        # ====================================================
        # RETENTION POLICY - 30 SECONDS
        # ====================================================

        RETENTION_30S)

            echo "Setting 30-second retention policy on Bucket2..."

            if ! gcloud storage buckets describe \
                "gs://$BUCKET2" >/dev/null 2>&1; then
                die "Bucket2 does not exist: gs://$BUCKET2"
            fi

            gcloud storage buckets update \
                "gs://$BUCKET2" \
                --retention-period=30s

            echo "✅ Bucket2 retention policy set to 30 seconds."
            ;;

        # ====================================================
        # UPDATE sample.txt
        # ====================================================

        UPDATE_SAMPLE_TXT)

            echo "Updating sample.txt in Bucket2..."

            if ! gcloud storage buckets describe \
                "gs://$BUCKET2" >/dev/null 2>&1; then
                die "Bucket2 does not exist: gs://$BUCKET2"
            fi

            EXPECTED_CONTENT="This is an example of editing the file content for cloud storage object"

            TMP_FILE="$(mktemp)"
            printf '%s\n' "$EXPECTED_CONTENT" > "$TMP_FILE"

            gcloud storage cp \
                "$TMP_FILE" \
                "gs://$BUCKET2/sample.txt"

            rm -f "$TMP_FILE"

            ACTUAL_CONTENT="$(
                gcloud storage cat \
                    "gs://$BUCKET2/sample.txt"
            )"

            if [[ "$ACTUAL_CONTENT" != "$EXPECTED_CONTENT" ]]; then
                die "Bucket2 sample.txt verification failed."
            fi

            echo "✅ sample.txt updated successfully."
            ;;

        # ====================================================
        # PUBLIC OBJECT
        # ====================================================

        PUBLIC_OBJECT)

            echo "Finding object in Bucket2..."

            if ! gcloud storage buckets describe \
                "gs://$BUCKET2" >/dev/null 2>&1; then
                die "Bucket2 does not exist: gs://$BUCKET2"
            fi

            mapfile -t OBJECTS < <(
                gcloud storage ls "gs://$BUCKET2/" 2>/dev/null
            )

            if [[ ${#OBJECTS[@]} -eq 0 ]]; then
                die "No object found in Bucket2."
            fi

            if [[ ${#OBJECTS[@]} -gt 1 ]]; then
                echo "Objects found:"
                printf '  %s\n' "${OBJECTS[@]}"
                die "More than one object exists; automatic selection would be unsafe."
            fi

            OBJECT_URL="${OBJECTS[0]}"

            echo "Object detected:"
            echo "  $OBJECT_URL"

            gcloud storage objects update \
                "$OBJECT_URL" \
                --add-acl-grant=entity=allUsers,role=READER

            echo "✅ Object is publicly readable."
            ;;

        # ====================================================
        # ADD FILE TO BUCKET3
        # ====================================================

        UPLOAD_TO_BUCKET3)

            echo "Adding a file to Bucket3..."

            if ! gcloud storage buckets describe \
                "gs://$BUCKET3" >/dev/null 2>&1; then
                die "Bucket3 does not exist: gs://$BUCKET3"
            fi

            TEMP_UPLOAD="$(mktemp --suffix=.txt)"

            printf '%s\n' \
                "Google Cloud Storage Challenge Lab object" \
                > "$TEMP_UPLOAD"

            gcloud storage cp \
                "$TEMP_UPLOAD" \
                "gs://$BUCKET3/challenge-lab.txt"

            rm -f "$TEMP_UPLOAD"

            echo "✅ challenge-lab.txt uploaded to Bucket3."
            ;;

        # ====================================================
        # ARCHIVE BUCKET3
        # ====================================================

        ARCHIVE_BUCKET3)

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

        # ====================================================
        # LABEL BUCKET3
        # ====================================================

        LABEL_BUCKET3)

            echo "Adding label to Bucket3..."

            if ! gcloud storage buckets describe \
                "gs://$BUCKET3" >/dev/null 2>&1; then
                die "Bucket3 does not exist: gs://$BUCKET3"
            fi

            echo
            echo "The lab requires a bucket label."
            echo "Enter the label key/value shown or required by your lab."
            echo

            prompt "Label key: " LABEL_KEY
            prompt "Label value: " LABEL_VALUE

            [[ -n "$LABEL_KEY" ]] || die "Label key cannot be empty."
            [[ -n "$LABEL_VALUE" ]] || die "Label value cannot be empty."

            gcloud storage buckets update \
                "gs://$BUCKET3" \
                --update-labels="${LABEL_KEY}=${LABEL_VALUE}"

            echo "✅ Bucket3 label added."
            ;;

        *)
            die "Unsupported task type: $task_type"
            ;;
    esac
}

# ============================================================
# START
# ============================================================

echo
echo "============================================================"
echo " Google Cloud Storage Challenge Lab Automation"
echo "============================================================"
echo

command -v gcloud >/dev/null 2>&1 || \
    die "gcloud CLI is not installed."

echo "✅ gcloud CLI found."

# ============================================================
# USER INPUT
# ============================================================

echo
echo "============================================================"
echo " LAB INFORMATION"
echo "============================================================"
echo

prompt "Enter Project ID: " PROJECT_ID
prompt "Enter Region: " REGION
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

# ============================================================
# TASK NAMES
# ============================================================

echo
echo "============================================================"
echo " TASK NAMES"
echo "============================================================"
echo
echo "Copy the exact Task 1 / Task 2 / Task 3 titles from the lab."
echo

prompt "Enter Task 1 name: " TASK1_NAME
prompt "Enter Task 2 name: " TASK2_NAME
prompt "Enter Task 3 name: " TASK3_NAME

TASK1_TYPE="$(detect_task "$TASK1_NAME")"
TASK2_TYPE="$(detect_task "$TASK2_NAME")"
TASK3_TYPE="$(detect_task "$TASK3_NAME")"

echo
echo "Detected operations:"
echo "  Task 1 -> $TASK1_TYPE"
echo "  Task 2 -> $TASK2_TYPE"
echo "  Task 3 -> $TASK3_TYPE"
echo

[[ "$TASK1_TYPE" != "UNKNOWN" ]] || \
    die "Could not identify Task 1: $TASK1_NAME"

[[ "$TASK2_TYPE" != "UNKNOWN" ]] || \
    die "Could not identify Task 2: $TASK2_NAME"

[[ "$TASK3_TYPE" != "UNKNOWN" ]] || \
    die "Could not identify Task 3: $TASK3_NAME"

# ============================================================
# AUTH
# ============================================================

echo
echo "============================================================"
echo " AUTHENTICATION"
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

echo "✅ Account: $ACTIVE_ACCOUNT"

# ============================================================
# CONFIG
# ============================================================

echo
echo "Setting project and region..."

gcloud config set project "$PROJECT_ID" >/dev/null
gcloud config set compute/region "$REGION" >/dev/null

echo "✅ Project and region configured."

# ============================================================
# RUN
# ============================================================

run_task 1 "$TASK1_TYPE"
run_task 2 "$TASK2_TYPE"
run_task 3 "$TASK3_TYPE"

# ============================================================
# DONE
# ============================================================

echo
echo "============================================================"
echo " ✅ SCRIPT COMPLETED SUCCESSFULLY"
echo "============================================================"
echo
echo "Now click 'Check my progress' for Task 1, Task 2 and Task 3."
echo
