#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# ARC102 - Store, Process, and Manage Data on Google Cloud
# Automated setup:
#
#   Bucket
#      ↓
#   Pub/Sub Topic
#      ↓
#   1st-gen Cloud Function
#      ↓
#   Cloud Storage trigger
#      ↓
#   Thumbnail creation
#      ↓
#   Verification
#
# Usage:
#   bash arc102-automation.sh
#
# Or:
#   curl -fsSL <RAW_GITHUB_URL> | bash
# ============================================================


# ------------------------------------------------------------
# Output helpers
# ------------------------------------------------------------

log() {
  printf '\n\033[1;36m[+] %s\033[0m\n' "$*"
}

warn() {
  printf '\n\033[1;33m[!] %s\033[0m\n' "$*"
}

die() {
  printf '\n\033[1;31m[ERROR] %s\033[0m\n' "$*" >&2
  exit 1
}


# ------------------------------------------------------------
# Error trap
# ------------------------------------------------------------

trap 'die "Command failed at line $LINENO: $BASH_COMMAND"' ERR


# ------------------------------------------------------------
# Prerequisites
# ------------------------------------------------------------

command -v gcloud >/dev/null 2>&1 \
  || die "gcloud CLI is required."

command -v curl >/dev/null 2>&1 \
  || die "curl is required."


# ------------------------------------------------------------
# Interactive input
# Works with:
#   bash script.sh
#   curl | bash
# ------------------------------------------------------------

if [[ -t 0 ]]; then
  ASK_FD="/dev/stdin"
elif [[ -r /dev/tty ]]; then
  ASK_FD="/dev/tty"
else
  die "Interactive terminal not available. Run this script from a terminal."
fi


ask() {
  local prompt="$1"
  local default="${2:-}"
  local value

  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " value < "$ASK_FD"
    printf '%s' "${value:-$default}"
  else
    read -r -p "$prompt: " value < "$ASK_FD"
    printf '%s' "$value"
  fi
}


# ------------------------------------------------------------
# Collect project
# ------------------------------------------------------------

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  PROJECT_ID="$(ask "Google Cloud Project ID")"
fi

[[ "$PROJECT_ID" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]] \
  || die "Invalid project ID: $PROJECT_ID"

gcloud config set project "$PROJECT_ID" >/dev/null


# ------------------------------------------------------------
# Collect lab values
# ------------------------------------------------------------

REGION="$(ask "Region" "us-east1")"

BUCKET_NAME="$(ask \
  "Bucket name" \
  "wild-bucket-${PROJECT_ID}")"

TOPIC_NAME="$(ask \
  "Pub/Sub topic name" \
  "wild-topic-645")"

FUNCTION_NAME="$(ask \
  "Cloud Function name" \
  "wild-thumbnail-creator")"


# ------------------------------------------------------------
# Validate names
# ------------------------------------------------------------

[[ "$BUCKET_NAME" =~ ^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$ ]] \
  || die "Invalid bucket name: $BUCKET_NAME"

[[ "$TOPIC_NAME" =~ ^[A-Za-z][A-Za-z0-9._~-]{2,254}$ ]] \
  || die "Invalid Pub/Sub topic name: $TOPIC_NAME"

[[ "$FUNCTION_NAME" =~ ^[A-Za-z][A-Za-z0-9_-]{0,62}$ ]] \
  || die "Invalid function name: $FUNCTION_NAME"


# ------------------------------------------------------------
# Display configuration
# ------------------------------------------------------------

log "Using project: $PROJECT_ID"
log "Region: $REGION"
log "Bucket: $BUCKET_NAME"
log "Topic: $TOPIC_NAME"
log "Function: $FUNCTION_NAME"


# ------------------------------------------------------------
# Enable required APIs
# ------------------------------------------------------------

log "Enabling required APIs"

gcloud services enable \
  storage.googleapis.com \
  pubsub.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  --project="$PROJECT_ID"


# ------------------------------------------------------------
# Ensure Cloud Functions service identity exists
# ------------------------------------------------------------

log "Ensuring Cloud Functions service identity exists"

gcloud beta services identity create \
  --service=cloudfunctions.googleapis.com \
  --project="$PROJECT_ID" \
  >/dev/null 2>&1 || true


# ------------------------------------------------------------
# Get project number
# ------------------------------------------------------------

PROJECT_NUMBER="$(
  gcloud projects describe "$PROJECT_ID" \
    --format="value(projectNumber)"
)"

[[ -n "$PROJECT_NUMBER" ]] \
  || die "Unable to determine project number."


# ------------------------------------------------------------
# Cloud Functions service agent
# ------------------------------------------------------------

CF_SERVICE_AGENT="service-${PROJECT_NUMBER}@gcf-admin-robot.iam.gserviceaccount.com"

log "Cloud Functions service agent:"
printf '%s\n' "$CF_SERVICE_AGENT"


# ------------------------------------------------------------
# Artifact Registry permissions
#
# Fixes:
#   403 Failed to create 1st Gen function
#   artifactregistry.repositories.list
#   artifactregistry.repositories.get
# ------------------------------------------------------------

log "Configuring Artifact Registry access"

IAM_READY="false"

for attempt in {1..8}; do

  if gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member="serviceAccount:${CF_SERVICE_AGENT}" \
      --role="roles/artifactregistry.reader" \
      --quiet \
      >/dev/null 2>&1; then

    IAM_READY="true"

    log "Artifact Registry Reader permission configured."

    break
  fi

  warn "Artifact Registry IAM not ready yet."
  warn "Retrying IAM configuration (${attempt}/8)..."

  sleep 10

done


if [[ "$IAM_READY" != "true" ]]; then
  die "Could not configure Artifact Registry Reader permission for Cloud Functions service agent."
fi


# ------------------------------------------------------------
# IAM propagation wait
# ------------------------------------------------------------

log "Waiting for IAM propagation"

sleep 15


# ------------------------------------------------------------
# Temporary working directory
# ------------------------------------------------------------

WORKDIR="$(mktemp -d)"

cleanup() {
  rm -rf "$WORKDIR"
}

trap cleanup EXIT


# ------------------------------------------------------------
# Create bucket
# ------------------------------------------------------------

log "Creating bucket"

if gcloud storage buckets describe \
    "gs://${BUCKET_NAME}" \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1; then

  warn "Bucket already exists; leaving it unchanged."

else

  gcloud storage buckets create \
    "gs://${BUCKET_NAME}" \
    --location="$REGION" \
    --project="$PROJECT_ID"

fi


# ------------------------------------------------------------
# Create Pub/Sub topic
# ------------------------------------------------------------

log "Creating Pub/Sub topic"

if gcloud pubsub topics describe \
    "$TOPIC_NAME" \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1; then

  warn "Topic already exists; leaving it unchanged."

else

  gcloud pubsub topics create \
    "$TOPIC_NAME" \
    --project="$PROJECT_ID"

fi


# ------------------------------------------------------------
# Prepare Cloud Function source
# ------------------------------------------------------------

log "Preparing Cloud Function source"


cat > "${WORKDIR}/index.js" <<EOF
/* globals exports, require */

//jshint strict: false
//jshint esversion: 6

"use strict";

const { Storage } = require("@google-cloud/storage");
const { PubSub } = require("@google-cloud/pubsub");
const imagemagick = require("imagemagick-stream");

const gcs = new Storage();

exports.thumbnail = (event, context) => {

  const fileName = event.name;
  const bucketName = event.bucket;
  const size = "64x64";

  const bucket = gcs.bucket(bucketName);

  const topicName = "${TOPIC_NAME}";
  const pubsub = new PubSub();


  // Ignore files that already contain a thumbnail.
  if (fileName.search("64x64_thumbnail") === -1) {

    var filename_split = fileName.split(".");

    var filename_ext =
      filename_split[filename_split.length - 1];

    var filename_without_ext =
      fileName.substring(
        0,
        fileName.length - filename_ext.length
      );


    // Only JPG and PNG are supported.
    if (
      filename_ext.toLowerCase() === "png" ||
      filename_ext.toLowerCase() === "jpg"
    ) {

      console.log(
        \`Processing Original: gs://\${bucketName}/\${fileName}\`
      );


      const gcsObject =
        bucket.file(fileName);


      let newFilename =
        filename_without_ext +
        size +
        "_thumbnail." +
        filename_ext;


      let gcsNewObject =
        bucket.file(newFilename);


      let srcStream =
        gcsObject.createReadStream();


      let dstStream =
        gcsNewObject.createWriteStream();


      let resize =
        imagemagick()
          .resize(size)
          .quality(90);


      srcStream
        .pipe(resize)
        .pipe(dstStream);


      return new Promise((resolve, reject) => {

        dstStream

          .on("error", (err) => {

            console.log(
              \`Error: \${err}\`
            );

            reject(err);

          })


          .on("finish", () => {

            console.log(
              \`Success: \${fileName} → \${newFilename}\`
            );


            // Set content type.
            gcsNewObject.setMetadata(
              {
                contentType:
                  "image/" +
                  filename_ext.toLowerCase()
              },
              function(err, apiResponse) {}
            );


            // ------------------------------------------------
            // Pub/Sub
            //
            // IMPORTANT:
            // Do NOT use:
            // .publisher()
            //
            // Use publishMessage().
            // ------------------------------------------------

            pubsub
              .topic(topicName)
              .publishMessage({
                data: Buffer.from(newFilename)
              })

              .then((messageId) => {

                console.log(
                  \`Message \${messageId} published.\`
                );

                resolve();

              })

              .catch((err) => {

                console.error(
                  "Pub/Sub ERROR:",
                  err
                );

                // Thumbnail has already been created.
                resolve();

              });

          });

      });


    } else {

      console.log(
        \`gs://\${bucketName}/\${fileName} is not an image I can handle\`
      );

    }


  } else {

    console.log(
      \`gs://\${bucketName}/\${fileName} already has a thumbnail\`
    );

  }

};
EOF


# ------------------------------------------------------------
# package.json
# ------------------------------------------------------------

cat > "${WORKDIR}/package.json" <<'EOF'
{
  "name": "thumbnails",
  "version": "1.0.0",
  "description": "Create Thumbnail of uploaded image",
  "scripts": {
    "start": "node index.js"
  },
  "dependencies": {
    "@google-cloud/pubsub": "^2.0.0",
    "@google-cloud/storage": "^5.0.0",
    "fast-crc32c": "1.0.4",
    "imagemagick-stream": "4.1.1"
  },
  "devDependencies": {},
  "engines": {
    "node": "22"
  }
}
EOF


# ------------------------------------------------------------
# Deploy function
# ------------------------------------------------------------

log "Deploying 1st-gen Cloud Function"

DEPLOYED="false"

for attempt in {1..3}; do

  if gcloud functions deploy "$FUNCTION_NAME" \
      --no-gen2 \
      --runtime=nodejs22 \
      --region="$REGION" \
      --entry-point=thumbnail \
      --trigger-bucket="$BUCKET_NAME" \
      --source="$WORKDIR" \
      --project="$PROJECT_ID"; then

    DEPLOYED="true"

    break

  fi


  warn "Function deployment failed."
  warn "Waiting for IAM/API propagation..."

  sleep 20

done


if [[ "$DEPLOYED" != "true" ]]; then
  die "Cloud Function deployment failed after multiple attempts."
fi


# ------------------------------------------------------------
# Download test image
# ------------------------------------------------------------

log "Downloading test image"

curl -fsSL \
  "https://storage.googleapis.com/cloud-training/arc102/wildlife.jpg" \
  -o "${WORKDIR}/wildlife.jpg"


# ------------------------------------------------------------
# Upload test image
# ------------------------------------------------------------

log "Uploading test image to trigger the function"

gcloud storage cp \
  "${WORKDIR}/wildlife.jpg" \
  "gs://${BUCKET_NAME}/wildlife.jpg" \
  --project="$PROJECT_ID"


# ------------------------------------------------------------
# Thumbnail verification
#
# wildlife.jpg
#       ↓
# wildlife.64x64_thumbnail.jpg
# ------------------------------------------------------------

THUMBNAIL="gs://${BUCKET_NAME}/wildlife.64x64_thumbnail.jpg"

log "Waiting for thumbnail creation"

THUMBNAIL_CREATED="false"


for attempt in {1..30}; do

  if gcloud storage ls \
      "$THUMBNAIL" \
      --project="$PROJECT_ID" \
      >/dev/null 2>&1; then

    THUMBNAIL_CREATED="true"

    break

  fi

  printf '.'

  sleep 5

done

printf '\n'


# ------------------------------------------------------------
# SUCCESS
# ------------------------------------------------------------

if [[ "$THUMBNAIL_CREATED" == "true" ]]; then

  printf '\n'
  printf '\033[1;32m============================================================\033[0m\n'
  printf '\033[1;32m                                                            \033[0m\n'
  printf '\033[1;32m                  LAB SUCCESSFUL                            \033[0m\n'
  printf '\033[1;32m                                                            \033[0m\n'
  printf '\033[1;32m============================================================\033[0m\n'
  printf '\n'

  log "Thumbnail successfully created."


  printf '\033[1;36mProject   :\033[0m %s\n' "$PROJECT_ID"
  printf '\033[1;36mRegion    :\033[0m %s\n' "$REGION"
  printf '\033[1;36mBucket    :\033[0m %s\n' "$BUCKET_NAME"
  printf '\033[1;36mTopic     :\033[0m %s\n' "$TOPIC_NAME"
  printf '\033[1;36mFunction  :\033[0m %s\n' "$FUNCTION_NAME"
  printf '\033[1;36mThumbnail :\033[0m %s\n' "$THUMBNAIL"


  printf '\nBucket objects:\n'

  gcloud storage ls \
    "gs://${BUCKET_NAME}/" \
    --project="$PROJECT_ID"


  printf '\n'

  printf '\033[1;32m============================================================\033[0m\n'
  printf '\033[1;32m                 AUTOMATION COMPLETE                        \033[0m\n'
  printf '\033[1;32m============================================================\033[0m\n'
  printf '\n'


# ------------------------------------------------------------
# FAILURE
# ------------------------------------------------------------

else

  warn "Thumbnail was not visible after waiting."

  warn "Checking Cloud Function logs..."


  gcloud functions logs read \
    "$FUNCTION_NAME" \
    --region="$REGION" \
    --no-gen2 \
    --limit=50 \
    --project="$PROJECT_ID" \
    || true


  printf '\n'

  printf '\033[1;31m============================================================\033[0m\n'
  printf '\033[1;31m                                                            \033[0m\n'
  printf '\033[1;31m              LAB VERIFICATION FAILED                       \033[0m\n'
  printf '\033[1;31m                                                            \033[0m\n'
  printf '\033[1;31m============================================================\033[0m\n'
  printf '\n'

  die "Thumbnail verification failed. Check the logs above."

fi
