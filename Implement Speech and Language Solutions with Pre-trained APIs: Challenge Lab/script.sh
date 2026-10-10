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
echo "${CYAN}${BOLD}   IMPLEMENT SPEECH & LANGUAGE SOLUTIONS        ${RESET}"
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
echo "${WHITE}Console se API Key banao (Text-to-Speech + Speech-to-Text + Translation APIs enable karo):${RESET}"
echo "  1. Navigation menu → APIs & Services → Credentials"
echo "  2. Create credentials → API key"
echo "  3. Copy the key"
echo

if [ -z "$API_KEY" ]; then
  read -p "API Key paste karo (ya Enter to skip): " API_KEY
  if [ -n "$API_KEY" ]; then
    export API_KEY
    echo "${GREEN}API_KEY set${RESET}"
  else
    echo "${RED}API_KEY not set — Task 2, 3, 4, 5 fail honge${RESET}"
    exit 1
  fi
fi

echo

# ===============================
# FIND VM INSTANCE
# ===============================
echo "${YELLOW}Finding lab-vm instance...${RESET}"
VM_ZONE=$(gcloud compute instances list --filter="name:lab-vm" --format="value(zone)" 2>/dev/null | head -n 1)

if [ -z "$VM_ZONE" ]; then
  read -p "Enter lab-vm zone: " VM_ZONE
fi

echo "${BLUE}VM Zone: ${WHITE}$VM_ZONE${RESET}"
echo

# ===============================
# TASK 2: Text-to-Speech API
# ===============================
echo "${GREEN}${BOLD}Task 2: Text-to-Speech - Synthesize speech${RESET}"
echo

gcloud compute ssh lab-vm --zone=$VM_ZONE --command="
  # Create synthesize-text.json
  cat > synthesize-text.json <<'EOF'
{
  'input':{
    'text':'Cloud Text-to-Speech API allows developers to include natural-sounding, synthetic human speech as playable audio in their applications. The Text-to-Speech API converts text or Speech Synthesis Markup Language (SSML) input into audio data like MP3 or LINEAR16 (the encoding used in WAV files).'
  },
  'voice':{
    'languageCode':'en-gb',
    'name':'en-GB-Standard-A',
    'ssmlGender':'FEMALE'
  },
  'audioConfig':{
    'audioEncoding':'MP3'
  }
}
EOF

  # Call Text-to-Speech API
  curl -s -X POST \
    \"https://texttospeech.googleapis.com/v1/text:synthesize?key=$API_KEY\" \
    -H \"Content-Type: application/json\" \
    -d @synthesize-text.json > synthesize-text.txt

  echo '--- synthesize-text.txt created ---'
  ls -la synthesize-text.txt
" --quiet

echo "${GREEN}Task 2 part 1 complete${RESET}"
echo

# Create tts_decode.py
gcloud compute ssh lab-vm --zone=$VM_ZONE --command="
  cat > tts_decode.py <<'EOF'
import argparse
from base64 import decodebytes
import json

def decode_tts_output(input_file, output_file):
    with open(input_file) as input:
        response = json.load(input)
        audio_data = response['audioContent']
        with open(output_file, 'wb') as new_file:
            new_file.write(decodebytes(audio_data.encode('utf-8')))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Decode output from Cloud Text-to-Speech',
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--input',
        help='The response from the Text-to-Speech API.',
        required=True)
    parser.add_argument('--output',
        help='The name of the audio file to create',
        required=True)
    args = parser.parse_args()
    decode_tts_output(args.input, args.output)
EOF

  # Decode to MP3
  python3 tts_decode.py --input \"synthesize-text.txt\" --output \"synthesize-text-audio.mp3\"

  echo '--- MP3 created ---'
  ls -la synthesize-text-audio.mp3
" --quiet

echo "${GREEN}Task 2 complete${RESET}"
echo

# ===============================
# TASK 3: Speech-to-Text API
# ===============================
echo "${MAGENTA}${BOLD}Task 3: Speech-to-Text - Transcribe French audio${RESET}"
echo

gcloud compute ssh lab-vm --zone=$VM_ZONE --command="
  # Create speech_request.json
  cat > speech_request.json <<'EOF'
{
  'config': {
    'encoding': 'FLAC',
    'sampleRateHertz': 44100,
    'languageCode': 'fr-FR'
  },
  'audio': {
    'uri': 'gs://cloud-samples-data/speech/corbeau_renard.flac'
  }
}
EOF

  # Call Speech-to-Text API
  curl -s -X POST \
    \"https://speech.googleapis.com/v1/speech:recognize?key=$API_KEY\" \
    -H \"Content-Type: application/json\" \
    -d @speech_request.json > speech_response.json

  echo '--- speech_response.json preview ---'
  cat speech_response.json | head -20
" --quiet

echo "${GREEN}Task 3 complete${RESET}"
echo

# ===============================
# TASK 4: Translation API - Translate
# ===============================
echo "${BLUE}${BOLD}Task 4: Translate Japanese to English${RESET}"
echo

gcloud compute ssh lab-vm --zone=$VM_ZONE --command="
  # Translate Japanese sentence
  curl -s -X POST \
    \"https://translation.googleapis.com/language/translate/v2?key=$API_KEY\" \
    -H \"Content-Type: application/json\" \
    -d '{
      \"q\": \"これは日本語です。\",
      \"target\": \"en\"
    }' > translation_response.txt

  echo '--- translation_response.txt preview ---'
  cat translation_response.txt | head -20
" --quiet

echo "${GREEN}Task 4 complete${RESET}"
echo

# ===============================
# TASK 5: Translation API - Detect Language
# ===============================
echo "${YELLOW}${BOLD}Task 5: Detect language${RESET}"
echo

gcloud compute ssh lab-vm --zone=$VM_ZONE --command="
  # Detect language
  curl -s -X POST \
    \"https://translation.googleapis.com/language/translate/v2/detect?key=$API_KEY\" \
    -H \"Content-Type: application/json\" \
    -d '{
      \"q\": \"Este%é%japonés.\"
    }' > detection_response.txt

  echo '--- detection_response.txt preview ---'
  cat detection_response.txt | head -20
" --quiet

echo "${GREEN}Task 5 complete${RESET}"
echo

# ===============================
# VERIFICATION
# ===============================
echo "${CYAN}${BOLD}=================================================${RESET}"
echo "${CYAN}${BOLD}   VERIFICATION${RESET}"
echo "${CYAN}${BOLD}=================================================${RESET}"
echo

gcloud compute ssh lab-vm --zone=$VM_ZONE --command="
  echo '--- Files created ---'
  ls -la synthesize-text.json synthesize-text.txt synthesize-text-audio.mp3 tts_decode.py speech_request.json speech_response.json translation_response.txt detection_response.txt 2>/dev/null
" --quiet

echo
echo "${CYAN}${BOLD}=================================================${RESET}"
echo "${CYAN}${BOLD}   AUTOMATED SETUP COMPLETED${RESET}"
echo "${CYAN}${BOLD}=================================================${RESET}"
echo
echo "${WHITE}Now click Check my progress in the lab for:${RESET}"
echo "  - Task 1 (Create an API key) — MANUAL"
echo "  - Task 2 (Text-to-Speech)"
echo "  - Task 3 (Speech-to-Text)"
echo "  - Task 4 (Translate text)"
echo "  - Task 5 (Detect language)"
echo
