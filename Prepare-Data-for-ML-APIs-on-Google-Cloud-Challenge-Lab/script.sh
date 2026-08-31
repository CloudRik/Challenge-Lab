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

# Prompt inputs from user with GREEN text
read -p "$(echo -e "${GREEN}ENTER BIGQUERY DATASET NAME (e.g., lab_116): ${NC}")" BQ_DATASET
echo ""

read -p "$(echo -e "${GREEN}ENTER BIGQUERY TABLE NAME (e.g., customers_791): ${NC}")" BQ_TABLE
echo ""

read -p "$(echo -e "${GREEN}ENTER REGION (e.g., us-central1): ${NC}")" LOCATION_REGION
echo ""

read -p "$(echo -e "${GREEN}ENTER DATAPROC CLUSTER ZONE (e.g., us-central1-a): ${NC}")" CLUSTER_ZONE
echo ""

read -p "$(echo -e "${GREEN}ENTER TASK 3 RESULT FILE NAME (e.g., task3-gcs-355.result): ${NC}")" TASK3_FILE
echo ""

read -p "$(echo -e "${GREEN}ENTER TASK 4 RESULT FILE NAME (e.g., task4-cnl-120.result): ${NC}")" TASK4_FILE
echo ""

# Export derived & automated variables
export MARKING_BUCKET="${DEVSHELL_PROJECT_ID}-marking"
export CLUSTER_NAME="spark-cluster"

# Display Summary
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    CONFIGURATION SUMMARY                        ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║ ${CYAN}Project ID:${NC} $DEVSHELL_PROJECT_ID"
echo -e "${GREEN}║ ${CYAN}BQ Dataset / Table:${NC} $BQ_DATASET / $BQ_TABLE"
echo -e "${GREEN}║ ${CYAN}Region / Zone:${NC} $LOCATION_REGION / $CLUSTER_ZONE"
echo -e "${GREEN}║ ${CYAN}Marking Bucket:${NC} gs://$MARKING_BUCKET"
echo -e "${GREEN}║ ${CYAN}Task 3 Target:${NC} $TASK3_FILE"
echo -e "${GREEN}║ ${CYAN}Task 4 Target:${NC} $TASK4_FILE"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

read -p "$(echo -e "${YELLOW}Proceed with execution? (y/n): ${NC}")" confirm
if [[ $confirm != [yY] ]]; then
    echo -e "${RED}Setup aborted by user.${NC}"
    exit 1
fi

echo -e "${GREEN}Starting lab setup...${NC}"
echo ""

# Basic Environment & IAM Setup
echo -e "${BLUE}Configuring IAM permissions & Enabling APIs...${NC}"
gcloud services enable dataflow.googleapis.com dataproc.googleapis.com speech.googleapis.com language.googleapis.com

PROJECT_NUMBER=$(gcloud projects describe $DEVSHELL_PROJECT_ID --format="value(projectNumber)")

gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID \
    --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
    --role="roles/storage.admin" --quiet

gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID \
    --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
    --role="roles/dataflow.worker" --quiet

echo -e "${GREEN}✓ APIs enabled & IAM Roles granted successfully${NC}"
echo ""

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
# TASK 2: RUN MANAGED APACHE SPARK JOB
# ==========================================
echo -e "${MAGENTA}--- STARTING TASK 2: DATAPROC SPARK JOB ---${NC}"
echo -e "${BLUE}Creating Dataproc Cluster...${NC}"

gcloud dataproc clusters create $CLUSTER_NAME \
    --region=$LOCATION_REGION \
    --zone=$CLUSTER_ZONE \
    --master-machine-type=n2d-standard-2 \
    --worker-machine-type=n2d-standard-2 \
    --num-workers=2 \
    --master-boot-disk-type=pd-standard \
    --master-boot-disk-size=100 \
    --worker-boot-disk-type=pd-standard \
    --worker-boot-disk-size=100 \
    --no-address

echo -e "${BLUE}Copying data.txt into Cluster HDFS & Running Spark Job...${NC}"
gcloud compute ssh ${CLUSTER_NAME}-m --zone=$CLUSTER_ZONE --quiet --command="hdfs dfs -cp gs://spls/gsp323/data.txt /data.txt"

gcloud dataproc jobs submit spark \
    --cluster=$CLUSTER_NAME \
    --region=$LOCATION_REGION \
    --class=org.apache.spark.examples.SparkPageRank \
    --jars=file:///usr/lib/spark/examples/jars/spark-examples.jar \
    --max-failures-per-hour=1 \
    -- /data.txt

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

# Completion Banner
echo -e "${GREEN}======================================================================${NC}"
echo -e "${MAGENTA}   🎉 LAB EXECUTED SUCCESSFULLY! WAIT 2 MINS FOR DATAFLOW TO FINISH   ${NC}"
echo -e "${GREEN}======================================================================${NC}"
