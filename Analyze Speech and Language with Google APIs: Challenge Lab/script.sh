#!/bin/bash

# Colors
CYAN='\033[0;96m'
GREEN='\033[0;92m'
YELLOW='\033[0;93m'
RED='\033[0;91m'
MAGENTA='\033[0;95m'
BLUE='\033[0;94m'
WHITE='\033[0;97m'
BOLD='\033[1m'
RESET='\033[0m'

clear
echo
echo "${CYAN}${BOLD}=================================================${RESET}"
echo "${CYAN}${BOLD}   ANALYZE SPEECH AND LANGUAGE (CHALLENGE LAB)   ${RESET}"
echo "${CYAN}${BOLD}=================================================${RESET}"
echo

# ===============================
# ENVIRONMENT DETECTION
# ===============================
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
echo "${BLUE}Project: ${WHITE}$PROJECT_ID${RESET}"
echo

# ===============================
# TASK 1: API KEY CHECK (Manual)
# ===============================
echo "${YELLOW}${BOLD}=================================================${RESET}"
echo "${YELLOW}${BOLD}   TASK 1: CREATE API KEY (MANUAL)              ${RESET}"
echo "${YELLOW}${BOLD}=================================================${RESET}"
echo
echo "${WHITE}Console se API Key banao:${RESET}"
echo "  1. Navigation menu → APIs & Services → Credentials"
echo "  2. Create credentials → API key"
echo "  3. Copy the key"
echo
echo "${WHITE}Phir yeh chalao:${RESET}"
echo "${GREEN}export API_KEY=<your-api-key>${RESET}"
echo

if [ -z "$API_KEY" ]; then
  read -p "API Key paste karo (ya Enter to skip): " API_KEY
  if [ -n "$API_KEY" ]; then
    export API_KEY
    echo "${GREEN}API_KEY set${RESET}"
  else
    echo "${RED}API_KEY not set. Task 2 & 3 fail honge.${RESET}"
    exit 1
  fi
fi

echo

# ===============================
# FIND VM INSTANCE
# ===============================
echo "${YELLOW}Finding VM instance...${RESET}"
VM_NAME=$(gcloud compute instances list --format="value(name)" 2>/dev/null | head -n 1)
VM_ZONE=$(gcloud compute instances list --filter="name:$VM_NAME" --format="value(zone)" 2>/dev/null)

if [ -z "$VM_NAME" ]; then
  read -p "Enter VM name: " VM_NAME
  read -p "Enter VM zone: " VM_ZONE
fi

echo "${BLUE}VM: ${WHITE}$VM_NAME${RESET}"
echo "${BLUE}Zone: ${WHITE}$VM_ZONE${RESET}"
echo

# ===============================
# TASK 2: Entity Analysis
# ===============================
echo "${GREEN}${BOLD}Task 2: Entity Analysis Request${RESET}"
echo

gcloud compute ssh $VM_NAME --zone=$VM_ZONE --command="
  # Create nl_request.json
  cat > nl_request.json <<'EOF'
{
  \"document\": {
    \"type\": \"PLAIN_TEXT\",
    \"content\": \"With approximately 8.2 million people residing in Boston, the capital city of Massachusetts is one of the largest in the United States.\"
  },
  \"encodingType\": \"UTF8\"
}
EOF

  # Call Natural Language API
  curl \"https://language.googleapis.com/v1/documents:analyzeEntities?key=$API_KEY\" \
    -s -X POST -H \"Content-Type: application/json\" \
    --data-binary @nl_request.json > nl_response.json

  echo '--- nl_response.json preview ---'
  cat nl_response.json | head -20
" --quiet

echo "${GREEN}Task 2 complete${RESET}"
echo

# ===============================
# TASK 3: Speech Analysis
# ===============================
echo "${MAGENTA}${BOLD}Task 3: Speech Analysis Request${RESET}"
echo

gcloud compute ssh $VM_NAME --zone=$VM_ZONE --command="
  # Create speech_request.json
  cat > speech_request.json <<'EOF'
{
  \"config\": {
    \"encoding\": \"FLAC\",
    \"languageCode\": \"en-US\"
  },
  \"audio\": {
    \"uri\": \"gs://cloud-samples-tests/speech/brooklyn.flac\"
  }
}
EOF

  # Call Speech API
  curl \"https://speech.googleapis.com/v1/speech:recognize?key=$API_KEY\" \
    -s -X POST -H \"Content-Type: application/json\" \
    --data-binary @speech_request.json > speech_response.json

  echo '--- speech_response.json preview ---'
  cat speech_response.json | head -20
" --quiet

echo "${GREEN}Task 3 complete${RESET}"
echo

# ===============================
# VERIFICATION
# ===============================
echo "${CYAN}${BOLD}=================================================${RESET}"
echo "${CYAN}${BOLD}   VERIFICATION${RESET}"
echo "${CYAN}${BOLD}=================================================${RESET}"
echo

gcloud compute ssh $VM_NAME --zone=$VM_ZONE --command="
  echo '--- Files ---'
  ls -la nl_request.json nl_response.json speech_request.json speech_response.json 2>/dev/null
" --quiet

echo
echo "${CYAN}${BOLD}=================================================${RESET}"
echo "${CYAN}${BOLD}   TASK 2 & 3 COMPLETED${RESET}"
echo "${CYAN}${BOLD}=================================================${RESET}"
echo
echo "${WHITE}Now:${RESET}"
echo "  1. Task 1 (API Key) — Check my progress (Console se manually banaya tha)"
echo "  2. Task 2 (Entity Analysis) — Check my progress"
echo "  3. Task 3 (Speech Analysis) — Check my progress"
echo "  4. Task 4 (Sentiment Analysis) — MANUAL Python code edit"
echo
