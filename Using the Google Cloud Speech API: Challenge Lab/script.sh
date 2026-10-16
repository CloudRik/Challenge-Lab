#!/bin/bash
# GSPxxx - Using the Google Cloud Speech API - Task 2 & 3 Automation
set +e

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[1;36m'; NC='\033[0m'

echo -e "${CYAN}"
echo "============================================================"
echo "  🎮 Speech API Challenge Lab - Task 2 & 3 Automation"
echo "  🎬 Presented By ArcadeSuite"
echo "  📺 YouTube: @imasis-k8x"
echo "============================================================"
echo -e "${NC}"

# ============================================================
# API KEY INPUT
# ============================================================
echo -e "${YELLOW}⚠️  Pehle Task 1 me API key create kar (Console → APIs & Services → Credentials)${NC}"
echo ""
read -p "Enter your API Key: " API_KEY

if [ -z "$API_KEY" ]; then
  echo -e "${RED}❌ API key cannot be empty!${NC}"
  exit 1
fi

export API_KEY
echo -e "${GREEN}✓ API Key saved${NC}"

# ============================================================
# ENVIRONMENT VARIABLES
# ============================================================
export GOOGLE_CLOUD_PROJECT=$(gcloud config get-value project 2>/dev/null)
export BUCKET_NAME="${GOOGLE_CLOUD_PROJECT}-speech"

echo ""
echo -e "${CYAN}Project: ${GREEN}$GOOGLE_CLOUD_PROJECT${NC}"
echo -e "${CYAN}Bucket:  ${GREEN}$BUCKET_NAME${NC}"

# ============================================================
# TASK 2 — ENGLISH TRANSCRIPTION
# ============================================================
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  TASK 2 : English Transcription${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"

# Request file
cat > request_en.json <<EOF
{
  "config": {
    "encoding": "LINEAR16",
    "sampleRateHertz": 24000,
    "languageCode": "en-US",
    "audioChannelCount": 2
  },
  "audio": {
    "uri": "gs://spls/arc131/question_en.wav"
  }
}
EOF

echo -e "${GREEN}✓ request_en.json created${NC}"

# API call
echo "Calling Speech-to-Text API..."
curl "https://speech.googleapis.com/v1/speech:recognize?key=${API_KEY}" \
  -s -X POST -H "Content-Type: application/json" \
  --data-binary @request_en.json > response_en.json

# Check response
if grep -q "transcript" response_en.json; then
  echo -e "${GREEN}✓ Transcription successful${NC}"
  echo -e "${CYAN}Transcript:${NC}"
  cat response_en.json | grep -A2 "transcript" | head -5
else
  echo -e "${RED}✗ Transcription failed${NC}"
  cat response_en.json
fi

# Upload to bucket
gcloud storage cp request_en.json gs://${BUCKET_NAME}/ 2>/dev/null
gcloud storage cp response_en.json gs://${BUCKET_NAME}/ 2>/dev/null

echo -e "${GREEN}✓ Files uploaded to bucket${NC}"
echo -e "${YELLOW}>>> Click 'Check my progress' for Task 2${NC}"

# ============================================================
# TASK 3 — SPANISH TRANSCRIPTION
# ============================================================
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  TASK 3 : Spanish Transcription${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"

# Request file
cat > request_fr.json <<EOF
{
  "config": {
    "encoding": "FLAC",
    "sampleRateHertz": 44100,
    "languageCode": "es-ES"
  },
  "audio": {
    "uri": "gs://spls/arc131/multi_es.flac"
  }
}
EOF

echo -e "${GREEN}✓ request_fr.json created${NC}"

# API call
echo "Calling Speech-to-Text API..."
curl "https://speech.googleapis.com/v1/speech:recognize?key=${API_KEY}" \
  -s -X POST -H "Content-Type: application/json" \
  --data-binary @request_fr.json > response_fr.json

# Check response
if grep -q "transcript" response_fr.json; then
  echo -e "${GREEN}✓ Transcription successful${NC}"
  echo -e "${CYAN}Transcript:${NC}"
  cat response_fr.json | grep -A2 "transcript" | head -5
else
  echo -e "${RED}✗ Transcription failed${NC}"
  cat response_fr.json
fi

# Upload to bucket
gcloud storage cp request_fr.json gs://${BUCKET_NAME}/ 2>/dev/null
gcloud storage cp response_fr.json gs://${BUCKET_NAME}/ 2>/dev/null

echo -e "${GREEN}✓ Files uploaded to bucket${NC}"
echo -e "${YELLOW}>>> Click 'Check my progress' for Task 3${NC}"

# ============================================================
# FINAL
# ============================================================
echo ""
echo -e "${GREEN}"
cat << "EOF"
  _____                      _      _       
 / ____|                    | |    | |      
| |     ___  _ __ ___  _ __ | | ___| |_ ___ 
| |    / _ \| '_ ` _ \| '_ \| |/ _ \ __/ _ \
| |___| (_) | | | | | | |_) | |  __/ ||  __/
 \_____\___/|_| |_| |_| .__/|_|\___|\__\___|
                      | |                    
                      |_|                    
EOF
echo -e "${NC}"
echo -e "${YELLOW}🎉 TASK 2 & 3 COMPLETE! 🎉${NC}"
echo -e "${CYAN}============================================================${NC}"
echo -e "${GREEN}🎬 Presented By ArcadeSuite${NC}"
echo -e "${CYAN}📺 YouTube: https://youtube.com/@imasis-k8x${NC}"
echo -e "${CYAN}💻 GitHub:  https://github.com/CloudRik${NC}"
echo -e "${YELLOW}🏆 Arcade Points: https://arcadesuite.pages.dev/${NC}"
echo -e "${CYAN}============================================================${NC}"
echo -e "${YELLOW}⚠️  Dono tasks ke liye 'Check my progress' click karo!${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""
