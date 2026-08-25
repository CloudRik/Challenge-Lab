#!/bin/bash

# Enhanced Color Definitions
BLACK=$'\033[0;90m'
RED=$'\033[0;91m'
GREEN=$'\033[0;92m'
YELLOW=$'\033[0;93m'
BLUE=$'\033[0;94m'
MAGENTA=$'\033[0;95m'
CYAN=$'\033[0;96m'
WHITE=$'\033[0;97m'

BG_BLACK=`tput setab 0`
BG_RED=`tput setab 1`
BG_GREEN=`tput setab 2`
BG_YELLOW=`tput setab 3`
BG_BLUE=`tput setab 4`
BG_MAGENTA=`tput setab 5`
BG_CYAN=`tput setab 6`
BG_WHITE=`tput setab 7`

BOLD=`tput bold`
RESET=`tput sgr0`

# Header Section
echo
echo
echo "${BLUE}${BOLD}⚡ Initializing Binary Authorization Setup...${RESET}"
echo

# Environment Setup
echo "${GREEN}${BOLD}▬▬▬▬▬▬▬▬▬ ENVIRONMENT CONFIGURATION ▬▬▬▬▬▬▬▬▬${RESET}"
echo "${YELLOW}Retrieving project details...${RESET}"
export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION=$(echo "$ZONE" | cut -d '-' -f 1-2)

echo "${YELLOW}Project ID: ${WHITE}${BOLD}$PROJECT_ID${RESET}"
echo "${YELLOW}Project Number: ${WHITE}${BOLD}$PROJECT_NUMBER${RESET}"
echo "${YELLOW}Zone: ${WHITE}${BOLD}$ZONE${RESET}"
echo "${YELLOW}Region: ${WHITE}${BOLD}$REGION${RESET}"
echo

# Service Enablement
echo "${GREEN}${BOLD}▬▬▬▬▬▬▬▬▬ ENABLING SERVICES ▬▬▬▬▬▬▬▬▬${RESET}"
echo "${YELLOW}Enabling required Google Cloud services...${RESET}"
gcloud services enable \
  cloudkms.googleapis.com \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  container.googleapis.com \
  containerregistry.googleapis.com \
  artifactregistry.googleapis.com \
  containerscanning.googleapis.com \
  ondemandscanning.googleapis.com \
  binaryauthorization.googleapis.com
echo "${GREEN}✅ Services enabled successfully!${RESET}"
echo

# Application Setup
echo "${GREEN}${BOLD}▬▬▬▬▬▬▬▬▬ APPLICATION SETUP ▬▬▬▬▬▬▬▬▬${RESET}"
echo "${YELLOW}Setting up sample application...${RESET}"
mkdir sample-app && cd sample-app
gcloud storage cp gs://spls/gsp521/* .
echo "${GREEN}✅ Sample application setup complete!${RESET}"
echo

# Artifact Registry Setup
echo "${GREEN}${BOLD}▬▬▬▬▬▬▬▬▬ ARTIFACT REGISTRY CONFIGURATION ▬▬▬▬▬▬▬▬▬${RESET}"
echo "${YELLOW}Creating artifact repositories...${RESET}"
gcloud artifacts repositories create artifact-scanning-repo \
  --repository-format=docker \
  --location=$REGION \
  --description="Scanning repository"

gcloud artifacts repositories create artifact-prod-repo \
  --repository-format=docker \
  --location=$REGION \
  --description="Production repository"

gcloud auth configure-docker $REGION-docker.pkg.dev
echo "${GREEN}✅ Artifact Registry setup complete!${RESET}"
echo

# IAM Configuration
echo "${GREEN}${BOLD}▬▬▬▬▬▬▬▬▬ IAM PERMISSIONS ▬▬▬▬▬▬▬▬▬${RESET}"
echo "${YELLOW}Configuring IAM permissions...${RESET}"
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/ondemandscanning.admin"
echo "${GREEN}✅ IAM permissions configured!${RESET}"
echo

# Initial Build
echo "${GREEN}${BOLD}▬▬▬▬▬▬▬▬▬ INITIAL BUILD ▬▬▬▬▬▬▬▬▬${RESET}"
echo "${YELLOW}Creating initial cloudbuild.yaml...${RESET}"
cat > cloudbuild.yaml <<EOF
steps:
- id: "build"
  name: 'gcr.io/cloud-builders/docker'
  args: ['build', '-t', '${REGION}-docker.pkg.dev/${PROJECT_ID}/artifact-scanning-repo/sample-image', '.']
  waitFor: ['-']

- id: "push"
  name: 'gcr.io/cloud-builders/docker'
  args: ['push', '${REGION}-docker.pkg.dev/${PROJECT_ID}/artifact-scanning-repo/sample-image']

images:
  - ${REGION}-docker.pkg.dev/${PROJECT_ID}/artifact-scanning-repo/sample-image
EOF

echo "${YELLOW}Submitting initial build...${RESET}"
gcloud builds submit
echo "${GREEN}✅ Initial build completed!${RESET}"
echo

# Binary Authorization Setup
echo "${GREEN}${BOLD}▬▬▬▬▬▬▬▬▬ BINARY AUTHORIZATION SETUP ▬▬▬▬▬▬▬▬▬${RESET}"
echo "${YELLOW}Creating vulnerability note...${RESET}"
cat > ./vulnerability_note.json << EOM
{
"attestation": {
"hint": {
 "human_readable_name": "Container Vulnerabilities attestation authority"
}
}
}
EOM

NOTE_ID=vulnerability_note
curl -X POST \
-H "Content-Type: application/json" \
-H "Authorization: Bearer $(gcloud auth print-access-token)" \
--data-binary @./vulnerability_note.json \
"https://containeranalysis.googleapis.com/v1/projects/${PROJECT_ID}/notes/?noteId=${NOTE_ID}"
echo "${GREEN}✅ Vulnerability note created!${RESET}"

echo "${YELLOW}Creating attestor...${RESET}"
ATTESTOR_ID=vulnerability-attestor
gcloud container binauthz attestors create $ATTESTOR_ID \
--attestation-authority-note=$NOTE_ID \
--attestation-authority-note-project=${PROJECT_ID}
echo "${GREEN}✅ Attestor created!${RESET}"

echo "${YELLOW}Configuring IAM permissions for attestor...${RESET}"
BINAUTHZ_SA_EMAIL="service-${PROJECT_NUMBER}@gcp-sa-binaryauthorization.iam.gserviceaccount.com"
cat > ./iam_request.json << EOM
{
'resource': 'projects/${PROJECT_ID}/notes/${NOTE_ID}',
'policy': {
'bindings': [
 {
   'role': 'roles/containeranalysis.notes.occurrences.viewer',
   'members': [
     'serviceAccount:${BINAUTHZ_SA_EMAIL}'
   ]
 }
]
}
}
EOM

curl -X POST \
-H "Content-Type: application/json" \
-H "Authorization: Bearer $(gcloud auth print-access-token)" \
--data-binary @./iam_request.json \
"https://containeranalysis.googleapis.com/v1/projects/${PROJECT_ID}/notes/${NOTE_ID}:setIamPolicy"
echo "${GREEN}✅ IAM permissions configured!${RESET}"
echo

# KMS Key Setup
echo "${GREEN}${BOLD}▬▬▬▬▬▬▬▬▬ KMS KEY SETUP ▬▬▬▬▬▬▬▬▬${RESET}"
echo "${YELLOW}Creating KMS keyring and key...${RESET}"
KEY_LOCATION=global
KEYRING=binauthz-keys
KEY_NAME=lab-key
KEY_VERSION=1

gcloud kms keyrings create "${KEYRING}" --location="${KEY_LOCATION}"

gcloud kms keys create "${KEY_NAME}" \
--keyring="${KEYRING}" --location="${KEY_LOCATION}" \
--purpose asymmetric-signing \
--default-algorithm="ec-sign-p256-sha256"

gcloud beta container binauthz attestors public-keys add \
--attestor="${ATTESTOR_ID}" \
--keyversion-project="${PROJECT_ID}" \
--keyversion-location="${KEY_LOCATION}" \
--keyversion-keyring="${KEYRING}" \
--keyversion-key="${KEY_NAME}" \
--keyversion="${KEY_VERSION}"
echo "${GREEN}✅ KMS key setup complete!${RESET}"
echo

# Policy Configuration
echo "${GREEN}${BOLD}▬▬▬▬▬▬▬▬▬ POLICY CONFIGURATION ▬▬▬▬▬▬▬▬▬${RESET}"
echo "${YELLOW}Configuring Binary Authorization policy...${RESET}"
cat > my_policy.yaml << EOM
defaultAdmissionRule:
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
  evaluationMode: REQUIRE_ATTESTATION
  requireAttestationsBy:
    - projects/${PROJECT_ID}/attestors/vulnerability-attestor
globalPolicyEvaluationMode: ENABLE
name: projects/${PROJECT_ID}/policy
EOM

gcloud container binauthz policy import my_policy.yaml
echo "${GREEN}✅ Policy configured successfully!${RESET}"
echo

# Additional IAM Permissions
echo "${GREEN}${BOLD}▬▬▬▬▬▬▬▬▬ ADDITIONAL IAM PERMISSIONS ▬▬▬▬▬▬▬▬▬${RESET}"
echo "${YELLOW}Configuring additional permissions...${RESET}"
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
--member serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com \
--role roles/binaryauthorization.attestorsViewer

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
--member serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com \
--role roles/cloudkms.signerVerifier

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
--member serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com \
--role roles/cloudkms.signerVerifier

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
--member serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com \
--role roles/containeranalysis.notes.attacher
echo "${GREEN}✅ Additional permissions configured!${RESET}"
echo

# Build Attestation
echo "${GREEN}${BOLD}▬▬▬▬▬▬▬▬▬ BUILD ATTESTATION SETUP ▬▬▬▬▬▬▬▬▬${RESET}"
echo "${YELLOW}Setting up build attestation...${RESET}"
git clone https://github.com/GoogleCloudPlatform/cloud-builders-community.git
cd cloud-builders-community/binauthz-attestation
gcloud builds submit . --config cloudbuild.yaml
cd ../..
rm -rf cloud-builders-community
echo "${GREEN}✅ Build attestation setup complete!${RESET}"
echo

# Final Build Pipeline
echo "${GREEN}${BOLD}▬▬▬▬▬▬▬▬▬ FINAL BUILD PIPELINE ▬▬▬▬▬▬▬▬▬${RESET}"
echo "${YELLOW}Creating final build pipeline...${RESET}"
cat <<EOF > cloudbuild.yaml
steps:
- id: "build"
  name: 'gcr.io/cloud-builders/docker'
  args: ['build', '-t', '${REGION}-docker.pkg.dev/${PROJECT_ID}/artifact-scanning-repo/sample-image:latest', '.']
  waitFor: ['-']

- id: "push"
  name: 'gcr.io/cloud-builders/docker'
  args: ['push', '${REGION}-docker.pkg.dev/${PROJECT_ID}/artifact-scanning-repo/sample-image:latest']

- id: scan
  name: 'gcr.io/cloud-builders/gcloud'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
      (gcloud artifacts docker images scan \\
      ${REGION}-docker.pkg.dev/${PROJECT_ID}/artifact-scanning-repo/sample-image:latest \\
      --location us \\
      --format="value(response.scan)") > /workspace/scan_id.txt

- id: severity check
  name: 'gcr.io/cloud-builders/gcloud'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
      gcloud artifacts docker images list-vulnerabilities \$(cat /workspace/scan_id.txt) \\
      --format="value(vulnerability.effectiveSeverity)" | if grep -Fxq CRITICAL; \\
      then echo "Failed vulnerability check for CRITICAL level" && exit 1; else echo \\
      "No CRITICAL vulnerability found, congrats !" && exit 0; fi

- id: 'create-attestation'
  name: 'gcr.io/${PROJECT_ID}/binauthz-attestation:latest'
  args:
    - '--artifact-url'
    - '${REGION}-docker.pkg.dev/${PROJECT_ID}/artifact-scanning-repo/sample-image:latest'
    - '--attestor'
    - 'projects/${PROJECT_ID}/attestors/vulnerability-attestor'
    - '--keyversion'
    - 'projects/${PROJECT_ID}/locations/global/keyRings/binauthz-keys/cryptoKeys/lab-key/cryptoKeyVersions/1'

- id: "push-to-prod"
  name: 'gcr.io/cloud-builders/docker'
  args: 
    - 'tag' 
    - '${REGION}-docker.pkg.dev/${PROJECT_ID}/artifact-scanning-repo/sample-image:latest'
    - '${REGION}-docker.pkg.dev/${PROJECT_ID}/artifact-prod-repo/sample-image:latest'
- id: "push-to-prod-final"
  name: 'gcr.io/cloud-builders/docker'
  args: ['push', '${REGION}-docker.pkg.dev/${PROJECT_ID}/artifact-prod-repo/sample-image:latest']

- id: 'deploy-to-cloud-run'
  name: 'gcr.io/cloud-builders/gcloud'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    gcloud run deploy auth-service --image=${REGION}-docker.pkg.dev/${PROJECT_ID}/artifact-scanning-repo/sample-image:latest \
    --binary-authorization=default --region=$REGION --allow-unauthenticated

images:
  - ${REGION}-docker.pkg.dev/${PROJECT_ID}/artifact-scanning-repo/sample-image:latest
EOF

echo "${YELLOW}Running final build pipeline...${RESET}"
gcloud builds submit
echo "${GREEN}✅ Final build pipeline completed!${RESET}"
echo

# Application Update
echo "${GREEN}${BOLD}▬▬▬▬▬▬▬▬▬ APPLICATION UPDATE ▬▬▬▬▬▬▬▬▬${RESET}"
echo "${YELLOW}Updating application dependencies...${RESET}"
cat > ./Dockerfile << EOF
FROM python:3.8-alpine

# App
WORKDIR /app
COPY . ./

RUN pip3 install Flask==3.0.3
RUN pip3 install gunicorn==23.0.0
RUN pip3 install Werkzeug==3.0.4

CMD exec gunicorn --bind :\$PORT --workers 1 --threads 8 main:app
EOF

gcloud builds submit
echo "${GREEN}✅ Application updated successfully!${RESET}"
echo

# Final Configuration
echo "${GREEN}${BOLD}▬▬▬▬▬▬▬▬▬ FINAL CONFIGURATION ▬▬▬▬▬▬▬▬▬${RESET}"
echo "${YELLOW}Configuring Cloud Run permissions...${RESET}"
gcloud beta run services add-iam-policy-binding --region=$REGION --member=allUsers --role=roles/run.invoker auth-service
echo "${GREEN}✅ Cloud Run permissions configured!${RESET}"
echo

# Completion Message
echo "${BG_GREEN}${BOLD}          BINARY AUTHORIZATION TUTORIAL COMPLETE!        ${RESET}"
echo
echo
echo "${MAGENTA}${BOLD}🔒 Happy secure deployments on Google Cloud!${RESET}"
