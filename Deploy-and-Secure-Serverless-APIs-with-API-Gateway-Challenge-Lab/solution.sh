```bash
#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# ARC109 - Deploy and Secure Serverless APIs with API Gateway
# Full automation for Tasks 1, 2 and 3
#
# IMPORTANT:
# Qwiklabs enables the required APIs automatically.
# DO NOT run "gcloud services enable" with the student account.
#
# This script is safe to run with:
# curl -fsSL "RAW_GITHUB_URL" | bash
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
# Helpers
# ------------------------------------------------------------

log() {
  printf '\n🔹 %s\n' "$1"
}

ok() {
  printf '✅ %s\n' "$1"
}

fail() {
  printf '\n❌ %s\n' "$1" >&2
  exit 1
}

# ------------------------------------------------------------
# Wait for a list of APIs
# Usage:
#   wait_for_services "label" service1 service2 service3
# ------------------------------------------------------------

wait_for_services() {
  local label="$1"
  shift

  local services=("$@")
  local max_checks=36
  local interval=10
  local missing=()
  local attempt
  local service

  log "Waiting for $label"

  for attempt in $(seq 1 "$max_checks"); do
    missing=()

    printf '\nChecking %s APIs (%s/%s)...\n' \
      "$label" "$attempt" "$max_checks"

    for service in "${services[@]}"; do
      if gcloud services describe "$service" \
          --project="$PROJECT_ID" >/dev/null 2>&1; then

        printf '  ✅ %s\n' "$service"

      else

        missing+=("$service")
        printf '  ⏳ %s\n' "$service"

      fi
    done

    if (( ${#missing[@]} == 0 )); then
      ok "$label APIs are available."
      return 0
    fi

    if (( attempt < max_checks )); then
      printf '\nWaiting %s seconds for lab setup...\n' "$interval"
      sleep "$interval"
    fi
  done

  printf '\n'
  printf '%s\n' '============================================================'
  printf '%s\n' "❌ $label API SETUP DID NOT FINISH IN TIME"
  printf '%s\n' '============================================================'
  printf '\nStill unavailable:\n'
  printf '  - %s\n' "${missing[@]}"
  printf '\n'
  printf '%s\n' 'Do NOT run gcloud services enable.'
  printf '%s\n' 'Restart the Qwiklabs lab if the setup is stuck.'
  exit 1
}

# ============================================================
# START
# ============================================================

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
# Detect project
# ------------------------------------------------------------

log 'Detecting Qwiklabs project'

PROJECT_ID="$(
  gcloud config get-value project 2>/dev/null |
  tr -d '\r' |
  xargs || true
)"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  fail 'No Google Cloud project is configured in this Cloud Shell.'
fi

printf 'Project ID : %s\n' "$PROJECT_ID"

# ------------------------------------------------------------
# Project number
# ------------------------------------------------------------

log 'Getting project number'

PROJECT_NUMBER="$(
  gcloud projects describe "$PROJECT_ID" \
    --project="$PROJECT_ID" \
    --format='value(projectNumber)'
)"

[[ -n "$PROJECT_NUMBER" ]] || \
  fail 'Could not determine the project number.'

COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

printf 'Project Number : %s\n' "$PROJECT_NUMBER"
printf 'Region         : %s\n' "$REGION"
printf 'Backend SA     : %s\n' "$COMPUTE_SA"

# ============================================================
# TASK 1 API CHECK
# IMPORTANT:
# API Gateway is NOT checked here.
# ============================================================

TASK1_APIS=(
  "cloudfunctions.googleapis.com"
  "cloudbuild.googleapis.com"
  "artifactregistry.googleapis.com"
  "run.googleapis.com"
)

wait_for_services "Task 1" "${TASK1_APIS[@]}"

# ============================================================
# TASK 1 - CREATE CLOUD RUN FUNCTION
# ============================================================

log 'Task 1 - Creating Cloud Run function'

WORKDIR="$(mktemp -d)"

cleanup() {
  rm -rf "$WORKDIR"
}

trap cleanup EXIT

cat > "$WORKDIR/package.json" <<'EOF'
{
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0"
  }
}
EOF

cat > "$WORKDIR/index.js" <<'EOF'
const functions = require('@google-cloud/functions-framework');

functions.http('helloHttp', (req, res) => {
  res.status(200).send('Hello World!');
});
EOF

log 'Deploying gcfunction'

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

FUNCTION_URL="$(
  gcloud functions describe "$FUNCTION_NAME" \
    --gen2 \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format='value(serviceConfig.uri)'
)"

[[ -n "$FUNCTION_URL" ]] || \
  fail 'Could not determine the deployed function URL.'

ok "Task 1 complete: $FUNCTION_URL"

# ============================================================
# TASK 2 API CHECK
# Now wait specifically for API Gateway APIs.
# ============================================================

TASK2_APIS=(
  "api-gateway.googleapis.com"
  "servicemanagement.googleapis.com"
  "servicecontrol.googleapis.com"
)

wait_for_services "Task 2 / API Gateway" "${TASK2_APIS[@]}"

# ============================================================
# TASK 2 - API GATEWAY
# ============================================================

log 'Task 2 - Creating OpenAPI specification'

cat > "$WORKDIR/openapispec.yaml" <<EOF
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
EOF

# ------------------------------------------------------------
# API
# ------------------------------------------------------------

log 'Checking API'

if gcloud api-gateway apis describe "$API_ID" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  ok "API $API_ID already exists"

else

  gcloud api-gateway apis create "$API_ID" \
    --display-name="$DISPLAY_NAME" \
    --project="$PROJECT_ID" \
    --quiet

  ok "API $API_ID created"
fi

# ------------------------------------------------------------
# API CONFIG
# ------------------------------------------------------------

log 'Checking API config'

if gcloud api-gateway api-configs describe "$API_CONFIG" \
    --api="$API_ID" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  ok "API config $API_CONFIG already exists"

else

  log 'Creating API config - this can take several minutes'

  gcloud api-gateway api-configs create "$API_CONFIG" \
    --api="$API_ID" \
    --openapi-spec="$WORKDIR/openapispec.yaml" \
    --backend-auth-service-account="$COMPUTE_SA" \
    --project="$PROJECT_ID" \
    --quiet

  ok "API config $API_CONFIG created"
fi

# ------------------------------------------------------------
# GATEWAY
# ------------------------------------------------------------

log 'Checking API Gateway'

if gcloud api-gateway gateways describe "$GATEWAY_ID" \
    --location="$REGION" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  ok "Gateway $GATEWAY_ID already exists"

else

  log 'Creating API Gateway - this can take several minutes'

  gcloud api-gateway gateways create "$GATEWAY_ID" \
    --api="$API_ID" \
    --api-config="$API_CONFIG" \
    --location="$REGION" \
    --display-name="$DISPLAY_NAME" \
    --project="$PROJECT_ID" \
    --quiet

  ok "Gateway $GATEWAY_ID created"
fi

# ------------------------------------------------------------
# WAIT FOR ACTIVE
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

  printf 'Gateway state: %s (%s/%s)\n' \
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
  fail 'API Gateway did not become ACTIVE in the expected time.'

ok 'API Gateway is ACTIVE'

# ============================================================
# TASK 3 API CHECK
# ============================================================

TASK3_APIS=(
  "pubsub.googleapis.com"
)

wait_for_services "Task 3 / Pub/Sub" "${TASK3_APIS[@]}"

# ============================================================
# TASK 3 - PUB/SUB
# ============================================================

log 'Task 3 - Creating Pub/Sub topic'

# ------------------------------------------------------------
# TOPIC
# ------------------------------------------------------------

if gcloud pubsub topics describe "$TOPIC_NAME" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  ok "Topic $TOPIC_NAME already exists"

else

  gcloud pubsub topics create "$TOPIC_NAME" \
    --project="$PROJECT_ID" \
    --quiet

  ok "Topic $TOPIC_NAME created"
fi

# ------------------------------------------------------------
# DEFAULT SUBSCRIPTION
# ------------------------------------------------------------

if gcloud pubsub subscriptions describe "$DEFAULT_SUBSCRIPTION" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  ok "Subscription $DEFAULT_SUBSCRIPTION already exists"

else

  gcloud pubsub subscriptions create "$DEFAULT_SUBSCRIPTION" \
    --topic="$TOPIC_NAME" \
    --project="$PROJECT_ID" \
    --quiet

  ok "Default subscription $DEFAULT_SUBSCRIPTION created"
fi

# ------------------------------------------------------------
# UPDATE FUNCTION SOURCE
# ------------------------------------------------------------

log 'Updating function to publish to Pub/Sub'

cat > "$WORKDIR/package.json" <<'EOF'
{
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0",
    "@google-cloud/pubsub": "^3.4.1"
  }
}
EOF

cat > "$WORKDIR/index.js" <<'EOF'
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
EOF

# ------------------------------------------------------------
# REDEPLOY
# ------------------------------------------------------------

log 'Redeploying gcfunction with Pub/Sub code'

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

ok 'Function redeployed with Pub/Sub publishing code'

# ============================================================
# INVOKE API GATEWAY
# ============================================================

log 'Getting API Gateway hostname'

GATEWAY_HOST="$(
  gcloud api-gateway gateways describe "$GATEWAY_ID" \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    --format='value(defaultHostname)'
)"

[[ -n "$GATEWAY_HOST" ]] || \
  fail 'Could not determine API Gateway hostname.'

GATEWAY_URL="https://${GATEWAY_HOST}/gcfunction"

printf '\nGateway URL: %s\n' "$GATEWAY_URL"

log 'Invoking API Gateway'

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

  printf '⏳ Gateway invocation not ready (%s/%s)\n' \
    "$attempt" "$MAX_INVOKE_ATTEMPTS"

  if [[ -n "$RESPONSE" ]]; then
    printf '   Response: %s\n' "$RESPONSE"
  fi

  if (( attempt < MAX_INVOKE_ATTEMPTS )); then
    sleep "$INVOKE_INTERVAL"
  fi
done

if [[ "$SUCCESS" -ne 1 ]]; then
  printf '\nLast response: %s\n' "$RESPONSE" >&2
  fail 'API Gateway invocation did not return the expected success message.'
fi

ok 'API Gateway successfully invoked the Pub/Sub backend'

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
