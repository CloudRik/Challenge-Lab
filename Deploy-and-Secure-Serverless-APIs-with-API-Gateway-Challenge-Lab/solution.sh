```bash
#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# ARC109 - Deploy and Secure Serverless APIs with API Gateway
# Full Automation for Tasks 1, 2 and 3
#
# IMPORTANT:
# Qwiklabs enables the required APIs automatically.
# DO NOT use "gcloud services enable" with the student account.
#
# This script waits for the lab APIs to become available before
# starting the actual lab tasks.
# ============================================================

trap 'printf "\n❌ Automation failed at line %s.\n" "$LINENO" >&2' ERR

REGION="us-east1"

FUNCTION_NAME="gcfunction"
FUNCTION_ENTRY="helloHttp"

API_ID="gcfunction-api"
API_CONFIG="gcfunction-api"
GATEWAY_ID="gcfunction-api"
DISPLAY_NAME="gcfunction API"

TOPIC_NAME="demo-topic"
DEFAULT_SUBSCRIPTION="demo-topic-sub"

# ------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------

log() {
  printf '\n🔹 %s\n' "$1"
}

ok() {
  printf '✅ %s\n' "$1"
}

fail() {
  printf '❌ %s\n' "$1" >&2
  exit 1
}

# ------------------------------------------------------------
# Start
# ------------------------------------------------------------

printf '\n'
printf '%s\n' '============================================================'
printf '%s\n' '      🚀 ARC109 LAB AUTOMATION - STARTING 🚀'
printf '%s\n' '============================================================'
printf '\n'

command -v gcloud >/dev/null 2>&1 || \
  fail 'gcloud CLI was not found. Run this in Google Cloud Shell.'

command -v curl >/dev/null 2>&1 || \
  fail 'curl was not found.'

# ------------------------------------------------------------
# Detect Qwiklabs project automatically
# ------------------------------------------------------------

PROJECT_ID="$(
  gcloud config get-value project 2>/dev/null |
  tr -d '\r' |
  xargs || true
)"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  read -r -p '👉 Enter your Google Cloud Project ID: ' PROJECT_ID

  [[ -n "$PROJECT_ID" ]] || \
    fail 'Project ID cannot be empty.'

  gcloud config set project "$PROJECT_ID" >/dev/null
fi

# Make sure gcloud is using the correct project.
gcloud config set project "$PROJECT_ID" >/dev/null

PROJECT_NUMBER="$(
  gcloud projects describe "$PROJECT_ID" \
    --format='value(projectNumber)'
)"

[[ -n "$PROJECT_NUMBER" ]] || \
  fail 'Could not determine the project number.'

COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

printf 'Project ID     : %s\n' "$PROJECT_ID"
printf 'Project Number : %s\n' "$PROJECT_NUMBER"
printf 'Region         : %s\n' "$REGION"
printf 'Backend SA     : %s\n' "$COMPUTE_SA"

# ============================================================
# WAIT FOR LAB APIs
# ============================================================
#
# IMPORTANT:
# Do NOT enable APIs manually.
#
# The original script checked only once and exited when
# api-gateway.googleapis.com was not ready yet.
#
# This version waits and checks repeatedly.
# ============================================================

log 'Waiting for Qwiklabs lab APIs to become available'

REQUIRED_SERVICES=(
  "cloudfunctions.googleapis.com"
  "cloudbuild.googleapis.com"
  "artifactregistry.googleapis.com"
  "run.googleapis.com"
  "api-gateway.googleapis.com"
  "servicemanagement.googleapis.com"
  "servicecontrol.googleapis.com"
  "pubsub.googleapis.com"
)

MAX_API_CHECKS=36
API_CHECK_INTERVAL=10

MISSING_SERVICES=()

for attempt in $(seq 1 "$MAX_API_CHECKS"); do

  ENABLED_SERVICES="$(
    gcloud services list \
      --enabled \
      --project="$PROJECT_ID" \
      --format='value(config.name)' 2>/dev/null || true
  )"

  MISSING_SERVICES=()

  for service in "${REQUIRED_SERVICES[@]}"; do
    if ! printf '%s\n' "$ENABLED_SERVICES" | grep -qx "$service"; then
      MISSING_SERVICES+=("$service")
    fi
  done

  if (( ${#MISSING_SERVICES[@]} == 0 )); then
    ok 'All required lab APIs are enabled.'
    break
  fi

  printf '\n⏳ Lab API setup is still in progress...'
  printf ' (%s/%s)\n' "$attempt" "$MAX_API_CHECKS"

  printf '   Still waiting for:\n'
  printf '   - %s\n' "${MISSING_SERVICES[@]}"

  if (( attempt < MAX_API_CHECKS )); then
    sleep "$API_CHECK_INTERVAL"
  fi

done

if (( ${#MISSING_SERVICES[@]} > 0 )); then
  printf '\n'
  printf '%s\n' '============================================================'
  printf '%s\n' '❌ LAB API SETUP DID NOT FINISH IN TIME'
  printf '%s\n' '============================================================'
  printf '\nStill missing:\n'
  printf '   - %s\n' "${MISSING_SERVICES[@]}"
  printf '\n'
  printf '%s\n' 'The lab normally enables these APIs automatically.'
  printf '%s\n' 'Do NOT run gcloud services enable with the student account.'
  printf '%s\n' 'Restart the lab if the setup is stuck.'
  printf '\n'
  exit 1
fi

# ------------------------------------------------------------
# Temporary working directory
# ------------------------------------------------------------

WORKDIR="$(mktemp -d)"

cleanup() {
  rm -rf "$WORKDIR"
}

trap cleanup EXIT

# ============================================================
# TASK 1
# Create Cloud Run Function (2nd Gen)
# ============================================================

log 'Task 1 - Deploying Cloud Run function'

cat > "$WORKDIR/package.json" <<'PKG1'
{
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0"
  }
}
PKG1

cat > "$WORKDIR/index.js" <<'JS1'
const functions = require('@google-cloud/functions-framework');

functions.http('helloHttp', (req, res) => {
  res.status(200).send('Hello World!');
});
JS1

gcloud functions deploy "$FUNCTION_NAME" \
  --gen2 \
  --runtime=nodejs22 \
  --region="$REGION" \
  --source="$WORKDIR" \
  --entry-point="$FUNCTION_ENTRY" \
  --trigger-http \
  --allow-unauthenticated \
  --project="$PROJECT_ID" \
  --quiet

# ------------------------------------------------------------
# Get deployed Cloud Run function URL
# ------------------------------------------------------------

FUNCTION_URL="$(
  gcloud functions describe "$FUNCTION_NAME" \
    --gen2 \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format='value(serviceConfig.uri)'
)"

[[ -n "$FUNCTION_URL" ]] || \
  fail 'Could not determine the deployed function URL.'

ok "Cloud Run function deployed: $FUNCTION_URL"

# ============================================================
# TASK 2
# Create API Gateway
# ============================================================

log 'Task 2 - Building OpenAPI specification'

cat > "$WORKDIR/openapispec.yaml" <<EOF2
swagger: '2.0'
info:
  title: gcfunction API
  description: Sample API on API Gateway with a Google Cloud Run functions backend
  version: 1.0.0
schemes:
  - https
produces:
  - application/json
x-google-backend:
  address: ${FUNCTION_URL}
paths:
  /gcfunction:
    get:
      summary: gcfunction
      operationId: gcfunction
      responses:
        '200':
          description: A successful response
          schema:
            type: string
EOF2

# ------------------------------------------------------------
# Create API
# ------------------------------------------------------------

log 'Checking API'

if gcloud api-gateway apis describe "$API_ID" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  ok "API $API_ID already exists; reusing it."

else

  gcloud api-gateway apis create "$API_ID" \
    --display-name="$DISPLAY_NAME" \
    --project="$PROJECT_ID" \
    --quiet

  ok "API $API_ID created."

fi

# ------------------------------------------------------------
# Create API Config
# ------------------------------------------------------------

log 'Checking API config'

if gcloud api-gateway api-configs describe "$API_CONFIG" \
    --api="$API_ID" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  ok "API config $API_CONFIG already exists; reusing it."

else

  log 'Creating API config - this may take several minutes'

  gcloud api-gateway api-configs create "$API_CONFIG" \
    --api="$API_ID" \
    --openapi-spec="$WORKDIR/openapispec.yaml" \
    --backend-auth-service-account="$COMPUTE_SA" \
    --project="$PROJECT_ID" \
    --quiet

  ok "API config $API_CONFIG created."

fi

# ------------------------------------------------------------
# Create API Gateway
# ------------------------------------------------------------

log 'Checking API Gateway'

if gcloud api-gateway gateways describe "$GATEWAY_ID" \
    --location="$REGION" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  ok "API Gateway $GATEWAY_ID already exists; reusing it."

else

  log 'Creating API Gateway - this may take several minutes'

  gcloud api-gateway gateways create "$GATEWAY_ID" \
    --api="$API_ID" \
    --api-config="$API_CONFIG" \
    --location="$REGION" \
    --display-name="$DISPLAY_NAME" \
    --project="$PROJECT_ID" \
    --quiet

  ok "API Gateway $GATEWAY_ID created."

fi

# ------------------------------------------------------------
# Wait for Gateway ACTIVE
# ------------------------------------------------------------

log 'Waiting for API Gateway to become ACTIVE'

GATEWAY_STATE=""

MAX_GATEWAY_CHECKS=40
GATEWAY_CHECK_INTERVAL=15

for attempt in $(seq 1 "$MAX_GATEWAY_CHECKS"); do

  GATEWAY_STATE="$(
    gcloud api-gateway gateways describe "$GATEWAY_ID" \
      --location="$REGION" \
      --project="$PROJECT_ID" \
      --format='value(state)' 2>/dev/null || true
  )"

  printf 'Gateway state: %s (check %s/%s)\n' \
    "${GATEWAY_STATE:-UNKNOWN}" \
    "$attempt" \
    "$MAX_GATEWAY_CHECKS"

  if [[ "$GATEWAY_STATE" == "ACTIVE" ]]; then
    break
  fi

  if (( attempt < MAX_GATEWAY_CHECKS )); then
    sleep "$GATEWAY_CHECK_INTERVAL"
  fi

done

[[ "$GATEWAY_STATE" == "ACTIVE" ]] || \
  fail 'API Gateway did not reach ACTIVE state in the expected time.'

ok 'API Gateway is ACTIVE.'

# ============================================================
# TASK 3
# Create Pub/Sub Topic + Default Subscription
# ============================================================

log 'Task 3 - Creating Pub/Sub topic'

# ------------------------------------------------------------
# Create topic
# ------------------------------------------------------------

if gcloud pubsub topics describe "$TOPIC_NAME" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  ok "Topic $TOPIC_NAME already exists; reusing it."

else

  gcloud pubsub topics create "$TOPIC_NAME" \
    --project="$PROJECT_ID" \
    --quiet

  ok "Topic $TOPIC_NAME created."

fi

# ------------------------------------------------------------
# Create default subscription
# ------------------------------------------------------------

if gcloud pubsub subscriptions describe "$DEFAULT_SUBSCRIPTION" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  ok "Subscription $DEFAULT_SUBSCRIPTION already exists; reusing it."

else

  gcloud pubsub subscriptions create "$DEFAULT_SUBSCRIPTION" \
    --topic="$TOPIC_NAME" \
    --project="$PROJECT_ID" \
    --quiet

  ok "Default subscription $DEFAULT_SUBSCRIPTION created."

fi

# ============================================================
# Update Cloud Run Function for Pub/Sub
# ============================================================

log 'Task 3 - Updating function to publish to Pub/Sub'

cat > "$WORKDIR/package.json" <<'PKG3'
{
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0",
    "@google-cloud/pubsub": "^3.4.1"
  }
}
PKG3

cat > "$WORKDIR/index.js" <<'JS3'
const {PubSub} = require('@google-cloud/pubsub');

const pubsub = new PubSub();
const topic = pubsub.topic('demo-topic');

const functions = require('@google-cloud/functions-framework');

functions.http('helloHttp', async (req, res) => {
  try {
    await topic.publishMessage({
      data: Buffer.from('Hello from Cloud Run functions!')
    });

    res.status(200).send('Message sent to Topic demo-topic!');
  } catch (error) {
    console.error('Pub/Sub publish failed:', error);
    res.status(500).send('Failed to publish message.');
  }
});
JS3

# ------------------------------------------------------------
# Redeploy function
# ------------------------------------------------------------

log 'Redeploying Cloud Run function with Pub/Sub code'

gcloud functions deploy "$FUNCTION_NAME" \
  --gen2 \
  --runtime=nodejs22 \
  --region="$REGION" \
  --source="$WORKDIR" \
  --entry-point="$FUNCTION_ENTRY" \
  --trigger-http \
  --allow-unauthenticated \
  --project="$PROJECT_ID" \
  --quiet

ok 'Function redeployed with Pub/Sub publishing code.'

# ============================================================
# Invoke API Gateway
# ============================================================

log 'Getting API Gateway hostname'

GATEWAY_HOST="$(
  gcloud api-gateway gateways describe "$GATEWAY_ID" \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    --format='value(defaultHostname)'
)"

[[ -n "$GATEWAY_HOST" ]] || \
  fail 'Could not determine the API Gateway hostname.'

GATEWAY_URL="https://${GATEWAY_HOST}/gcfunction"

printf '\nGateway URL: %s\n' "$GATEWAY_URL"

# ------------------------------------------------------------
# Invoke Gateway repeatedly
# ------------------------------------------------------------

log 'Invoking API Gateway endpoint'

RESPONSE=""
SUCCESS=0

MAX_INVOKE_ATTEMPTS=20
INVOKE_INTERVAL=15

for attempt in $(seq 1 "$MAX_INVOKE_ATTEMPTS"); do

  RESPONSE="$(
    curl -fsS \
      --max-time 30 \
      "$GATEWAY_URL" 2>/dev/null || true
  )"

  if [[ "$RESPONSE" == *'Message sent to Topic demo-topic!'* ]]; then
    SUCCESS=1
    break
  fi

  printf '⏳ Gateway endpoint not ready yet (attempt %s/%s)\n' \
    "$attempt" \
    "$MAX_INVOKE_ATTEMPTS"

  if [[ -n "$RESPONSE" ]]; then
    printf '   Response: %s\n' "$RESPONSE"
  fi

  if (( attempt < MAX_INVOKE_ATTEMPTS )); then
    sleep "$INVOKE_INTERVAL"
  fi

done

if [[ "$SUCCESS" -ne 1 ]]; then

  printf '\n'
  printf '%s\n' '============================================================'
  printf '%s\n' '❌ API GATEWAY INVOCATION FAILED'
  printf '%s\n' '============================================================'
  printf '\nLast response:\n%s\n\n' "$RESPONSE"

  fail 'API Gateway invocation did not return the expected success message.'

fi

ok 'API Gateway successfully invoked the Pub/Sub backend.'

# ============================================================
# FINAL
# ============================================================

printf '\n'
printf '%s\n' '============================================================'
printf '%s\n' '            🎉 LAB AUTOMATION COMPLETED 🎉'
printf '%s\n' '============================================================'

printf '✅ Task 1: Cloud Run function deployed\n'
printf '✅ Task 2: API Gateway configured\n'
printf '✅ Task 3: Pub/Sub topic created\n'
printf '✅ Task 3: Default subscription created\n'
printf '✅ Task 3: Function updated and redeployed\n'
printf '✅ API Gateway invocation completed successfully\n'

printf '\n'
printf 'Project : %s\n' "$PROJECT_ID"
printf 'Region  : %s\n' "$REGION"
printf 'Function: %s\n' "$FUNCTION_NAME"
printf 'Topic   : %s\n' "$TOPIC_NAME"
printf 'Gateway : %s\n' "$GATEWAY_URL"

printf '\n'
printf '%s\n' '👉 Now click "Check my progress" on the lab page.'
printf '%s\n' '============================================================'
```
