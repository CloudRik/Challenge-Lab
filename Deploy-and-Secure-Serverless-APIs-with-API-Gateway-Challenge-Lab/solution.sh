#!/usr/bin/env bash
set -Eeuo pipefail

trap 'printf "\n❌ Automation failed at line %s.\n" "$LINENO" >&2' ERR

# ============================================================
# ARC109 - Deploy and Secure Serverless APIs with API Gateway
# Automated solution for Tasks 1, 2 and 3
# ============================================================

REGION="us-east1"
FUNCTION_NAME="gcfunction"
FUNCTION_ENTRY="helloHttp"
API_ID="gcfunction-api"
API_CONFIG="gcfunction-api"
GATEWAY_ID="gcfunction-api"
DISPLAY_NAME="gcfunction API"
TOPIC_NAME="demo-topic"
DEFAULT_SUBSCRIPTION="demo-topic-sub"

log()     { printf '\n🔹 %s\n' "$1"; }
ok()      { printf '✅ %s\n' "$1"; }
fail()    { printf '❌ %s\n' "$1" >&2; exit 1; }

printf '\n'
printf '%s\n' '============================================================'
printf '%s\n' '      🚀 ARC109 LAB AUTOMATION - STARTING 🚀'
printf '%s\n' '============================================================'
printf '\n'

command -v gcloud >/dev/null 2>&1 || fail 'gcloud CLI was not found. Run this in Google Cloud Shell.'
command -v curl   >/dev/null 2>&1 || fail 'curl was not found.'

# Detect the lab project automatically.
PROJECT_ID="$(gcloud config get-value project 2>/dev/null | tr -d '\r' | xargs || true)"
if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  read -r -p '👉 Enter your Google Cloud Project ID: ' PROJECT_ID
  [[ -n "$PROJECT_ID" ]] || fail 'Project ID cannot be empty.'
  gcloud config set project "$PROJECT_ID" >/dev/null
fi

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
[[ -n "$PROJECT_NUMBER" ]] || fail 'Could not determine the project number.'
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

printf 'Project ID     : %s\n' "$PROJECT_ID"
printf 'Project Number : %s\n' "$PROJECT_NUMBER"
printf 'Region         : %s\n' "$REGION"

log 'Enabling required Google Cloud APIs'
gcloud services enable \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  run.googleapis.com \
  api-gateway.googleapis.com \
  servicemanagement.googleapis.com \
  servicecontrol.googleapis.com \
  pubsub.googleapis.com \
  --project="$PROJECT_ID" \
  --quiet
ok 'Required APIs are enabled.'

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

# ------------------------------------------------------------
# Task 1: Deploy Hello World Cloud Run function (2nd gen)
# ------------------------------------------------------------
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

FUNCTION_URL="$(gcloud functions describe "$FUNCTION_NAME" \
  --gen2 \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --format='value(serviceConfig.uri)')"

[[ -n "$FUNCTION_URL" ]] || fail 'Could not determine the deployed function URL.'
ok "Cloud Run function deployed: $FUNCTION_URL"

# ------------------------------------------------------------
# Task 2: Create API Gateway
# ------------------------------------------------------------
log 'Task 2 - Building OpenAPI spec'

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

if gcloud api-gateway apis describe "$API_ID" --project="$PROJECT_ID" >/dev/null 2>&1; then
  ok "API $API_ID already exists; reusing it."
else
  gcloud api-gateway apis create "$API_ID" \
    --display-name="$DISPLAY_NAME" \
    --project="$PROJECT_ID" \
    --quiet
  ok "API $API_ID created."
fi

# API config IDs are immutable. If an old config exists, reuse it.
if gcloud api-gateway api-configs describe "$API_CONFIG" \
    --api="$API_ID" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then
  ok "API config $API_CONFIG already exists; reusing it."
else
  gcloud api-gateway api-configs create "$API_CONFIG" \
    --api="$API_ID" \
    --openapi-spec="$WORKDIR/openapispec.yaml" \
    --backend-auth-service-account="$COMPUTE_SA" \
    --project="$PROJECT_ID" \
    --quiet
  ok "API config $API_CONFIG created."
fi

# Gateway creation can take several minutes.
if gcloud api-gateway gateways describe "$GATEWAY_ID" \
    --location="$REGION" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then
  ok "API Gateway $GATEWAY_ID already exists; reusing it."
else
  gcloud api-gateway gateways create "$GATEWAY_ID" \
    --api="$API_ID" \
    --api-config="$API_CONFIG" \
    --location="$REGION" \
    --display-name="$DISPLAY_NAME" \
    --project="$PROJECT_ID" \
    --quiet
  ok "API Gateway $GATEWAY_ID created."
fi

log 'Waiting for API Gateway to become ACTIVE'
GATEWAY_STATE=''
for attempt in {1..40}; do
  GATEWAY_STATE="$(gcloud api-gateway gateways describe "$GATEWAY_ID" \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    --format='value(state)' 2>/dev/null || true)"
  printf 'Gateway state: %s (check %s/40)\n' "${GATEWAY_STATE:-UNKNOWN}" "$attempt"
  [[ "$GATEWAY_STATE" == 'ACTIVE' ]] && break
  sleep 15
done
[[ "$GATEWAY_STATE" == 'ACTIVE' ]] || fail 'API Gateway did not reach ACTIVE state in the expected time.'
ok 'API Gateway is ACTIVE.'

# ------------------------------------------------------------
# Task 3: Pub/Sub topic + message publishing backend
# ------------------------------------------------------------
log 'Task 3 - Creating Pub/Sub topic'

if gcloud pubsub topics describe "$TOPIC_NAME" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then
  ok "Topic $TOPIC_NAME already exists; reusing it."
else
  gcloud pubsub topics create "$TOPIC_NAME" --project="$PROJECT_ID"
  ok "Topic $TOPIC_NAME created."
fi

# The lab asks for the default subscription. The console's default subscription
# for demo-topic is demo-topic-sub; create the same deterministic name via CLI.
if gcloud pubsub subscriptions describe "$DEFAULT_SUBSCRIPTION" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then
  ok "Subscription $DEFAULT_SUBSCRIPTION already exists; reusing it."
else
  gcloud pubsub subscriptions create "$DEFAULT_SUBSCRIPTION" \
    --topic="$TOPIC_NAME" \
    --project="$PROJECT_ID"
  ok "Default subscription $DEFAULT_SUBSCRIPTION created."
fi

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

functions.http('helloHttp', (req, res) => {
  // Send a message to the topic
  topic.publishMessage({data: Buffer.from('Hello from Cloud Run functions!')});
  res.status(200).send("Message sent to Topic demo-topic!");
});
JS3

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

# ------------------------------------------------------------
# Invoke API Gateway endpoint
# ------------------------------------------------------------
log 'Invoking the API through API Gateway'

GATEWAY_HOST="$(gcloud api-gateway gateways describe "$GATEWAY_ID" \
  --location="$REGION" \
  --project="$PROJECT_ID" \
  --format='value(defaultHostname)')"
[[ -n "$GATEWAY_HOST" ]] || fail 'Could not determine the API Gateway hostname.'

GATEWAY_URL="https://${GATEWAY_HOST}/gcfunction"
printf 'Gateway URL: %s\n' "$GATEWAY_URL"

RESPONSE=''
SUCCESS=0
for attempt in {1..20}; do
  RESPONSE="$(curl -fsS --max-time 30 "$GATEWAY_URL" 2>/dev/null || true)"
  if [[ "$RESPONSE" == *'Message sent to Topic demo-topic!'* ]]; then
    SUCCESS=1
    break
  fi
  printf '⏳ Gateway endpoint not ready yet (attempt %s/20)\n' "$attempt"
  sleep 15
done

[[ "$SUCCESS" -eq 1 ]] || {
  printf 'Last response: %s\n' "$RESPONSE" >&2
  fail 'API Gateway invocation did not return the expected success message.'
}
ok 'API Gateway successfully invoked the Pub/Sub backend.'

# ------------------------------------------------------------
# Final banner
# ------------------------------------------------------------
printf '\n'
printf '%s\n' '============================================================'
printf '%s\n' '            🎉 LAB AUTOMATION COMPLETED 🎉'
printf '%s\n' '============================================================'
printf '✅ Task 1: Cloud Run function deployed\n'
printf '✅ Task 2: API Gateway configured\n'
printf '✅ Task 3: Pub/Sub topic + default subscription configured\n'
printf '✅ API Gateway invocation completed successfully\n'
printf '\nProject : %s\nRegion  : %s\nFunction: %s\nTopic   : %s\nGateway : %s\n' \
  "$PROJECT_ID" "$REGION" "$FUNCTION_NAME" "$TOPIC_NAME" "$GATEWAY_URL"
printf '\n%s\n' '👉 Now click “Check my progress” on the lab page.'
printf '%s\n' '============================================================'
