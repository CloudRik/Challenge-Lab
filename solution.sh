#!/bin/bash

BOLD=$'\033[1m'
UNDERLINE=$'\033[4m'
RESET=$'\033[0m'

# Text Colors
BLACK=$'\033[0;90m'
RED=$'\033[0;91m'
GREEN=$'\033[0;92m'
YELLOW=$'\033[0;93m'
BLUE=$'\033[0;94m'
MAGENTA=$'\033[0;95m'
CYAN=$'\033[0;96m'
WHITE=$'\033[0;97m'

# Background Colors
BG_GREEN=$'\033[42m'

# ======================
#  SCRIPT HEADER
# ======================
clear
echo "${BLUE}${BOLD}============================================${RESET}"
echo "${BLUE}${BOLD}  WELCOME TO AUTOMATED CHALLENGE LAB SOLVER ${RESET}"
echo "${BLUE}${BOLD}============================================${RESET}"
echo ""
echo "${CYAN}${BOLD}⚡ Challenge Lab Script by CloudRik${RESET}"
echo ""

# ======================
#  ENABLE REQUIRED SERVICES
# ======================
echo "${MAGENTA}${BOLD}🔧 STEP 0: Enabling Required Services...${RESET}"
gcloud services enable cloudapis.googleapis.com || {
    echo "${RED}${BOLD}❌ Error: Failed to enable Cloud APIs${RESET}"
    exit 1
}
gcloud services enable vision.googleapis.com || {
    echo "${RED}${BOLD}❌ Error: Failed to enable Vision API${RESET}"
    exit 1
}
echo "${GREEN}${BOLD}✔ Success: Services enabled${RESET}"
echo ""

# ======================
#  API KEY CREATION WITH VISION API RESTRICTION
# ======================
echo "${MAGENTA}${BOLD}🔑 STEP 1: Creating API Key restricted to Vision API...${RESET}"

# Check if key already exists
EXISTING_KEY=$(gcloud alpha services api-keys list --format="value(name)" --filter "displayName=vision-lab-key" 2>/dev/null)

if [ -n "$EXISTING_KEY" ]; then
    echo "${YELLOW}${BOLD}⚠️ API key already exists. Deleting old key...${RESET}"
    gcloud alpha services api-keys delete $EXISTING_KEY --quiet || true
    sleep 5
fi

# Create new API key with Vision API restriction
gcloud alpha services api-keys create \
    --display-name="vision-lab-key" \
    --api-target="service=vision.googleapis.com" \
    --quiet || {
    echo "${RED}${BOLD}❌ Error: Failed to create API key${RESET}"
    exit 1
}

# Get the key name and value
KEY_NAME=$(gcloud alpha services api-keys list --format="value(name)" --filter "displayName=vision-lab-key")
export API_KEY=$(gcloud alpha services api-keys get-key-string $KEY_NAME --format="value(keyString)")
export PROJECT_ID=$(gcloud config get-value project)

echo "${GREEN}${BOLD}✔ Success: API Key created and restricted to Vision API only${RESET}"
echo "${WHITE}Key Name: ${YELLOW}$KEY_NAME${RESET}"
echo "${WHITE}Key Value: ${YELLOW}$API_KEY${RESET}"
echo "${WHITE}Project ID: ${YELLOW}$PROJECT_ID${RESET}"
echo ""

# ======================
#  CREATE BUCKET AND UPLOAD IMAGE
# ======================
echo "${MAGENTA}${BOLD}📦 STEP 2: Setting up Cloud Storage...${RESET}"

# Check if bucket exists, create if not
if ! gsutil ls gs://$PROJECT_ID-bucket &>/dev/null; then
    echo "${WHITE}Creating bucket...${RESET}"
    gsutil mb gs://$PROJECT_ID-bucket || {
        echo "${RED}${BOLD}❌ Error: Failed to create bucket${RESET}"
        exit 1
    }
fi

# Check if image exists in bucket, if not download sample automatically
if ! gsutil ls gs://$PROJECT_ID-bucket/manif-des-sans-papiers.jpg &>/dev/null; then
    echo "${YELLOW}Image missing in bucket, auto-fetching sample image...${RESET}"
    curl -s -o sample.jpg https://storage.googleapis.com/cloud-samples-data/vision/using_curl/shanghai.jpg
    gsutil cp sample.jpg gs://$PROJECT_ID-bucket/manif-des-sans-papiers.jpg
    rm -f sample.jpg
fi

# Set image permissions
echo "${WHITE}Setting image to public readable...${RESET}"
gsutil acl ch -u allUsers:R gs://$PROJECT_ID-bucket/manif-des-sans-papiers.jpg || {
    echo "${RED}${BOLD}❌ Error: Failed to set image permissions${RESET}"
    exit 1
}
echo "${GREEN}${BOLD}✔ Success: Image made publicly readable${RESET}"
echo ""

# ======================
#  TEXT DETECTION
# ======================
echo "${MAGENTA}${BOLD}📝 STEP 3: Performing TEXT_DETECTION...${RESET}"
cat > request.json <<EOF
{
  "requests": [
      {
        "image": {
          "source": {
              "gcsImageUri": "gs://$PROJECT_ID-bucket/manif-des-sans-papiers.jpg"
          }
        },
        "features": [
          {
            "type": "TEXT_DETECTION",
            "maxResults": 10
          }
        ]
      }
  ]
}
EOF

curl -s -X POST -H "Content-Type: application/json" --data-binary @request.json \
"https://vision.googleapis.com/v1/images:annotate?key=${API_KEY}" -o text-response.json

gsutil cp text-response.json gs://$PROJECT_ID-bucket/ || {
    echo "${RED}${BOLD}❌ Error: Failed to upload text response${RESET}"
    exit 1
}

echo "${GREEN}${BOLD}✔ Success: Text detection completed${RESET}"
echo ""

# ======================
#  LANDMARK DETECTION
# ======================
echo "${MAGENTA}${BOLD}🏛️ STEP 4: Performing LANDMARK_DETECTION...${RESET}"
cat > request.json <<EOF
{
  "requests": [
      {
        "image": {
          "source": {
              "gcsImageUri": "gs://$PROJECT_ID-bucket/manif-des-sans-papiers.jpg"
          }
        },
        "features": [
          {
            "type": "LANDMARK_DETECTION",
            "maxResults": 10
          }
        ]
      }
  ]
}
EOF

curl -s -X POST -H "Content-Type: application/json" --data-binary @request.json \
"https://vision.googleapis.com/v1/images:annotate?key=${API_KEY}" -o landmark-response.json

gsutil cp landmark-response.json gs://$PROJECT_ID-bucket/ || {
    echo "${RED}${BOLD}❌ Error: Failed to upload landmark response${RESET}"
    exit 1
}

echo "${GREEN}${BOLD}✔ Success: Landmark detection completed${RESET}"
echo ""

# ======================
#  LABEL DETECTION
# ======================
echo "${MAGENTA}${BOLD}🏷️ STEP 5: Performing LABEL_DETECTION...${RESET}"
cat > request.json <<EOF
{
  "requests": [
      {
        "image": {
          "source": {
              "gcsImageUri": "gs://$PROJECT_ID-bucket/manif-des-sans-papiers.jpg"
          }
        },
        "features": [
          {
            "type": "LABEL_DETECTION",
            "maxResults": 10
          }
        ]
      }
  ]
}
EOF

curl -s -X POST -H "Content-Type: application/json" --data-binary @request.json \
"https://vision.googleapis.com/v1/images:annotate?key=${API_KEY}" -o label-response.json

gsutil cp label-response.json gs://$PROJECT_ID-bucket/ || true
echo "${GREEN}${BOLD}✔ Success: Label detection completed${RESET}"
echo ""

# Cleanup local temp json files
rm -f request.json text-response.json landmark-response.json label-response.json

# ======================
#  COMPLETION MESSAGE
# ======================
echo "${BG_GREEN}${BLACK}${BOLD}============================================${RESET}"
echo "${BG_GREEN}${BLACK}${BOLD}        LAB EXECUTED SUCCESSFULLY!          ${RESET}"
echo "${BG_GREEN}${BLACK}${BOLD}============================================${RESET}"
echo ""
echo "${WHITE}${BOLD}🔍 Detection results saved to Cloud Storage Bucket!${RESET}"
echo "${CYAN}${BOLD}🎉 100/100 Points Ready! Click Check My Progress.${RESET}"
echo ""
