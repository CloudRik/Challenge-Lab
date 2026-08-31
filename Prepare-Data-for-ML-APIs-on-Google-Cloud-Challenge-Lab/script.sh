#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

echo -e "${CYAN}======================================================================${NC}"
echo -e "${MAGENTA}   GCP CHALLENGE LAB: PREPARE DATA FOR ML APIS (ALL-IN-ONE SCRIPT)   ${NC}"
echo -e "${CYAN}======================================================================${NC}"
echo ""

# Auto-Detect Region and Zone
echo -e "${BLUE}Auto-detecting Region and Zone...${NC}"
export CLUSTER_ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])" 2>/dev/null)
if [ -z "$CLUSTER_ZONE" ]; then
    export CLUSTER_ZONE=$(gcloud config get-value compute/zone 2>/dev/null)
fi
if [ -z "$CLUSTER_ZONE" ]; then
    export CLUSTER_ZONE="us-central1-a"
fi

export LOCATION_REGION=$(echo $CLUSTER_ZONE | cut -d'-' -f1,2)

echo -e "${GREEN}✓ Detected Zone:${NC} $CLUSTER_ZONE"
echo -e "${GREEN}✓ Detected Region:${NC} $LOCATION_REGION"
echo ""

# Dynamic User Inputs
read -p "$(echo -e "${GREEN}ENTER BIGQUERY DATASET NAME (e.g., lab_116): ${NC}")" BQ_DATASET
echo ""

read -p "$(echo -e "${GREEN}ENTER BIGQUERY TABLE NAME (e.g., customers_791): ${NC}")" BQ_TABLE
echo ""

read -p "$(echo -e "${GREEN}ENTER TASK 3 RESULT FILE NAME (e.g., task3-gcs-355.result): ${NC}")" TASK3_FILE
echo ""

read -p "$(echo -e "${GREEN}ENTER TASK 4 RESULT FILE NAME (e.g., task4-cnl-120.result): ${NC}")" TASK4_FILE
echo ""

export MARKING_BUCKET="${DEVSHELL_PROJECT_ID}-marking"
export CLUSTER_NAME="spark-cluster"

echo -e "${GREEN}Starting lab setup...${NC}"
echo ""

# Enable APIs & Setup IAM Roles
echo -e "${BLUE}Enabling APIs and setting up IAM roles...${NC}"
gcloud services enable dataflow.googleapis.com dataproc.googleapis.com speech.googleapis.com language.googleapis.com --quiet

PROJECT_NUMBER=$(gcloud projects describe $DEVSHELL_PROJECT_ID --format="value(projectNumber)")

gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID \
    --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
    --role="roles/storage.admin" --quiet

gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID \
    --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
    --role="roles/dataflow.worker" --quiet

# ==========================================
# TASK 1: RUN DATAFLOW JOB
# ==========================================
echo -e "${MAGENTA}--- STARTING TASK 1: DATAFLOW JOB ---${NC}"
bq mk --location=$LOCATION_REGION $BQ_DATASET 2>/dev/null || true
gcloud storage buckets create gs://$MARKING_BUCKET --location=$LOCATION_REGION 2>/dev/null || true

gcloud dataflow jobs run batch-bq-job \
    --gcs-location="gs://dataflow-templates/latest/GCS_Text_to_BigQuery" \
    --region=$LOCATION_REGION \
    --staging-location="gs://$MARKING_BUCKET/temp" \
    --worker-machine-type="e2-standard-2" \
    --parameters \
javascriptTextTransformGcsPath="gs://spls/gsp323/lab.js",\
javascriptTextTransformFunctionName="transform",\
JSONPath="gs://spls/gsp323/lab.schema",\
inputFilePattern="gs://spls/gsp323/lab.csv",\
outputTable="${DEVSHELL_PROJECT_ID}:${BQ_DATASET}.${BQ_TABLE}",\
bigQueryLoadingTemporaryDirectory="gs://$MARKING_BUCKET/bigquery_temp"

echo -e "${GREEN}✓ Task 1 Dataflow Job submitted${NC}"
echo ""

# ==========================================
# TASK 2: DATAPROC SPARK JOB
# ==========================================
echo -e "${MAGENTA}--- STARTING TASK 2: DATAPROC SPARK JOB ---${NC}"

# Delete broken cluster if any exists
gcloud dataproc clusters delete $CLUSTER_NAME --region=$LOCATION_REGION --quiet 2>/dev/null || true

# Create Dataproc Cluster
gcloud dataproc clusters create $CLUSTER_NAME \
    --region=$LOCATION_REGION \
    --zone=$CLUSTER_ZONE \
    --master-machine-type=n2d-standard-2 \
    --worker-machine-type=n2d-standard-2 \
    --num-workers=2 \
    --master-boot-disk-type=pd-standard \
    --master-boot-disk-size=100 \
    --worker-boot-disk-type=pd-standard \
    --worker-boot-disk-size=100

echo -e "${BLUE}Waiting 20 seconds for cluster services to stabilize...${NC}"
sleep 20

# Submit Spark Job directly referencing GCS file path
gcloud dataproc jobs submit spark \
    --cluster=$CLUSTER_NAME \
    --region=$LOCATION_REGION \
    --class=org.apache.spark.examples.SparkPageRank \
    --jars=file:///usr/lib/spark/examples/jars/spark-examples.jar \
    --max-failures-per-hour=1 \
    -- gs://spls/gsp323/data.txt

echo -e "${GREEN}✓ Task 2 Spark Job executed successfully${NC}"
echo ""

# ==========================================
# TASK 3: CLOUD SPEECH-TO-TEXT API
# ==========================================
echo -e "${MAGENTA}--- STARTING TASK 3: SPEECH-TO-TEXT API ---${NC}"
cat <<'EOF' > request_speech.json
{
  "config": {
    "encoding": "FLAC",
    "languageCode": "en-US"
  },
  "audio": {
    "uri": "gs://spls/gsp323/task3.flac"
  }
}
EOF

curl -s -X POST \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    -H "Content-Type: application/json; charset=utf-8" \
    https://speech.googleapis.com/v1/speech:recognize \
    -d @request_speech.json > $TASK3_FILE

gcloud storage cp $TASK3_FILE gs://$MARKING_BUCKET/$TASK3_FILE
echo -e "${GREEN}✓ Task 3 Speech API completed & uploaded${NC}"
echo ""

# ==========================================
# TASK 4: CLOUD NATURAL LANGUAGE API
# ==========================================
echo -e "${MAGENTA}--- STARTING TASK 4: NATURAL LANGUAGE API ---${NC}"
cat <<'EOF' > request_nlp.json
{
  "document": {
    "type": "PLAIN_TEXT",
    "content": "Old Norse texts portray Odin as one-eyed and long-bearded, frequently wielding a spear named Gungnir and wearing a cloak and a broad hat."
  },
  "encodingType": "UTF8"
}
EOF

curl -s -X POST \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    -H "Content-Type: application/json; charset=utf-8" \
    https://language.googleapis.com/v1/documents:analyzeEntities \
    -d @request_nlp.json > $TASK4_FILE

gcloud storage cp $TASK4_FILE gs://$MARKING_BUCKET/$TASK4_FILE
echo -e "${GREEN}✓ Task 4 Natural Language API completed & uploaded${NC}"
echo ""

# Completion Message
echo -e "${GREEN}======================================================================${NC}"
echo -e "${MAGENTA}   🎉 LAB EXECUTED SUCCESSFULLY! CHECK YOUR SCORE ON LAB PORTAL   ${NC}"
echo -e "${GREEN}======================================================================${NC}"
