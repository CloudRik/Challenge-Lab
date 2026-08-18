#!/usr/bin/env bash
set -Eeuo pipefail

# ARC102 - Store, Process, and Manage Data on Google Cloud - Command Line
# Automated setup: bucket -> Pub/Sub topic -> 1st-gen Cloud Function -> test upload
#
# Usage:
#   bash arc102-automation.sh
# or:
#   curl -fsSL <RAW_GITHUB_URL> | bash

log()  { printf '\n\033[1;36m[+] %s\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33m[!] %s\033[0m\n' "$*"; }
die()  { printf '\n\033[1;31m[ERROR] %s\033[0m\n' "$*" >&2; exit 1; }

trap 'die "Command failed at line $LINENO: $BASH_COMMAND"' ERR

command -v gcloud >/dev/null 2>&1 || die "gcloud CLI is required."
command -v curl >/dev/null 2>&1 || die "curl is required."

# curl | bash needs prompts to read from the terminal, not from curl's pipe.
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

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  PROJECT_ID="$(ask "Google Cloud Project ID")"
fi
[[ "$PROJECT_ID" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]] || die "Invalid project ID: $PROJECT_ID"
gcloud config set project "$PROJECT_ID" >/dev/null

REGION="$(ask "Region" "us-east1")"
BUCKET_NAME="$(ask "Bucket name" "wild-bucket-${PROJECT_ID}")"
TOPIC_NAME="$(ask "Pub/Sub topic name" "wild-topic-645")"
FUNCTION_NAME="$(ask "Cloud Function name" "wild-thumbnail-creator")"

[[ "$BUCKET_NAME" =~ ^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$ ]] || die "Invalid bucket name: $BUCKET_NAME"
[[ "$TOPIC_NAME" =~ ^[A-Za-z][A-Za-z0-9._~-]{2,254}$ ]] || die "Invalid Pub/Sub topic name: $TOPIC_NAME"
[[ "$FUNCTION_NAME" =~ ^[A-Za-z][A-Za-z0-9_-]{0,62}$ ]] || die "Invalid function name: $FUNCTION_NAME"

log "Using project: $PROJECT_ID"
log "Region: $REGION"
log "Bucket: $BUCKET_NAME"
log "Topic: $TOPIC_NAME"
log "Function: $FUNCTION_NAME"

log "Enabling required APIs"
gcloud services enable \
  storage.googleapis.com \
  pubsub.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  --project="$PROJECT_ID"

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

log "Creating bucket (if it does not already exist)"
if gcloud storage buckets describe "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
  warn "Bucket already exists; leaving it unchanged."
else
  gcloud storage buckets create "gs://${BUCKET_NAME}" \
    --location="$REGION" \
    --project="$PROJECT_ID"
fi

log "Creating Pub/Sub topic (if it does not already exist)"
if gcloud pubsub topics describe "$TOPIC_NAME" --project="$PROJECT_ID" >/dev/null 2>&1; then
  warn "Topic already exists; leaving it unchanged."
else
  gcloud pubsub topics create "$TOPIC_NAME" --project="$PROJECT_ID"
fi

log "Preparing Cloud Function source"
cat > "${WORKDIR}/index.js" <<EOF
/* globals exports, require */
//jshint strict: false
//jshint esversion: 6
"use strict";
const crc32 = require("fast-crc32c");
const { Storage } = require('@google-cloud/storage');
const gcs = new Storage();
const { PubSub } = require('@google-cloud/pubsub');
const imagemagick = require("imagemagick-stream");

exports.thumbnail = (event, context) => {
  const fileName = event.name;
  const bucketName = event.bucket;
  const size = "64x64"
  const bucket = gcs.bucket(bucketName);
  const topicName = "${TOPIC_NAME}";
  const pubsub = new PubSub();
  if ( fileName.search("64x64_thumbnail") == -1 ){
    // doesn't have a thumbnail, get the filename extension
    var filename_split = fileName.split('.');
    var filename_ext = filename_split[filename_split.length - 1];
    var filename_without_ext = fileName.substring(0, fileName.length - filename_ext.length );
    if (filename_ext.toLowerCase() == 'png' || filename_ext.toLowerCase() == 'jpg'){
      // only support png and jpg at this point
      console.log(\`Processing Original: gs://\${bucketName}/\${fileName}\`);
      const gcsObject = bucket.file(fileName);
      let newFilename = filename_without_ext + size + '_thumbnail.' + filename_ext;
      let gcsNewObject = bucket.file(newFilename);
      let srcStream = gcsObject.createReadStream();
      let dstStream = gcsNewObject.createWriteStream();
      let resize = imagemagick().resize(size).quality(90);
      srcStream.pipe(resize).pipe(dstStream);
      return new Promise((resolve, reject) => {
        dstStream
          .on("error", (err) => {
            console.log(\`Error: \${err}\`);
            reject(err);
          })
          .on("finish", () => {
            console.log(\`Success: \${fileName} → \${newFilename}\`);
              // set the content-type
              gcsNewObject.setMetadata(
              {
                contentType: 'image/'+ filename_ext.toLowerCase()
              }, function(err, apiResponse) {});
              pubsub
                .topic(topicName)
                .publisher()
                .publish(Buffer.from(newFilename))
                .then(messageId => {
                  console.log(\`Message \${messageId} published.\`);
                })
                .catch(err => {
                  console.error('ERROR:', err);
                });
          });
      });
    }
    else {
      console.log(\`gs://\${bucketName}/\${fileName} is not an image I can handle\`);
    }
  }
  else {
    console.log(\`gs://\${bucketName}/\${fileName} already has a thumbnail\`);
  }
};
EOF

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
    "node": "20"
  }
}
EOF

log "Deploying 1st-gen Cloud Function"
gcloud functions deploy "$FUNCTION_NAME" \
  --no-gen2 \
  --runtime=nodejs20 \
  --region="$REGION" \
  --entry-point=thumbnail \
  --trigger-bucket="$BUCKET_NAME" \
  --source="$WORKDIR" \
  --project="$PROJECT_ID"

log "Downloading test image"
curl -fsSL \
  "https://storage.googleapis.com/cloud-training/arc102/wildlife.jpg" \
  -o "${WORKDIR}/wildlife.jpg"

log "Uploading test image to trigger the function"
gcloud storage cp \
  "${WORKDIR}/wildlife.jpg" \
  "gs://${BUCKET_NAME}/wildlife.jpg" \
  --project="$PROJECT_ID"

log "Waiting for thumbnail creation"
for _ in {1..18}; do
  if gcloud storage ls "gs://${BUCKET_NAME}/wildlife64x64_thumbnail.jpg" \
      --project="$PROJECT_ID" >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

if gcloud storage ls "gs://${BUCKET_NAME}/wildlife64x64_thumbnail.jpg" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then
  log "SUCCESS: thumbnail created."
  printf '\nBucket objects:\n'
  gcloud storage ls "gs://${BUCKET_NAME}/" --project="$PROJECT_ID"
else
  warn "The function deployed and the test image was uploaded, but the thumbnail was not visible yet."
  warn "Check function logs; image processing can take a little longer."
  gcloud functions logs read "$FUNCTION_NAME" \
    --region="$REGION" \
    --gen1 \
    --limit=20 \
    --project="$PROJECT_ID" || true
fi

printf '\n\033[1;32mDone. Project=%s Region=%s Bucket=%s Topic=%s Function=%s\033[0m\n' \
  "$PROJECT_ID" "$REGION" "$BUCKET_NAME" "$TOPIC_NAME" "$FUNCTION_NAME"
