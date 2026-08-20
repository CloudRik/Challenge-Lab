#!/bin/bash
set -e

echo "======================================================================"
echo "         Automated Solution for Multimodal Vector Search Lab          "
echo "======================================================================"
echo ""

# Auto-detect Project ID from active Cloud Shell session
export PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

# Auto-detect Region from gcloud config, fallback to us-east4 if not set
DETECTED_REGION=$(gcloud config get-value compute/region 2>/dev/null)
export REGION=${DETECTED_REGION:-"us-east4"}

export CONN_NAME="vector_conn"

if [ -z "$PROJECT_ID" ]; then
  echo "Error: Project ID could not be detected. Please make sure you are in Cloud Shell."
  exit 1
fi

echo "--> Detected Project ID : $PROJECT_ID"
echo "--> Detected Region     : $REGION"
echo ""

gcloud config set project $PROJECT_ID --quiet

# ------------------------------------------------------------------------------
# Task 1: Create connection and grant IAM permissions
# ------------------------------------------------------------------------------
echo "--> [Task 1/4] Creating BigQuery Connection & Granting IAM Roles..."

bq mk --connection \
  --location=$REGION \
  --project_id=$PROJECT_ID \
  --connection_type=CLOUD_RESOURCE $CONN_NAME || true

# Extract Service Account ID dynamically
SA_ID=$(bq show --location=$REGION --connection $CONN_NAME | grep "serviceAccountId" | awk -F '"' '{print $4}')

echo "--> Connection Service Account: $SA_ID"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_ID" \
  --role="roles/bigquery.dataOwner" --no-user-output-enabled

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_ID" \
  --role="roles/storage.objectViewer" --no-user-output-enabled

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_ID" \
  --role="roles/aiplatform.user" --no-user-output-enabled

echo "Waiting 25 seconds for IAM permissions to propagate fully..."
sleep 25

# ------------------------------------------------------------------------------
# Task 2: Create external object table
# ------------------------------------------------------------------------------
echo "--> [Task 2/4] Creating External Object Table..."

bq query --use_legacy_sql=false \
"CREATE OR REPLACE EXTERNAL TABLE \`$PROJECT_ID.gcc_bqml_dataset.gcc_image_object_table\`
WITH CONNECTION \`$PROJECT_ID.$REGION.$CONN_NAME\`
OPTIONS (
  object_metadata = 'SIMPLE',
  uris = ['gs://$PROJECT_ID/*']
);"

# ------------------------------------------------------------------------------
# Task 3: Create Model & Generate Embeddings
# ------------------------------------------------------------------------------
echo "--> [Task 3/4] Creating Remote Embedding Model & Generating Embeddings..."

bq query --use_legacy_sql=false \
"CREATE OR REPLACE MODEL \`$PROJECT_ID.gcc_bqml_dataset.gcc_embedding\`
REMOTE WITH CONNECTION \`$PROJECT_ID.$REGION.$CONN_NAME\`
OPTIONS (
  endpoint = 'multimodalembedding@001'
);"

bq query --use_legacy_sql=false \
"CREATE OR REPLACE TABLE \`$PROJECT_ID.gcc_bqml_dataset.gcc_retail_store_embeddings\` AS
SELECT *, REGEXP_EXTRACT(uri, r'[^/]+$') AS product_name
FROM ML.GENERATE_EMBEDDING(
  MODEL \`$PROJECT_ID.gcc_bqml_dataset.gcc_embedding\`,
  TABLE \`$PROJECT_ID.gcc_bqml_dataset.gcc_image_object_table\`
);"

# ------------------------------------------------------------------------------
# Task 4: Run Vector Search
# ------------------------------------------------------------------------------
echo "--> [Task 4/4] Executing Vector Search Query..."

bq query --use_legacy_sql=false \
"CREATE OR REPLACE TABLE \`$PROJECT_ID.gcc_bqml_dataset.gcc_vector_search_table\` AS
SELECT base.uri,
       base.product_name,
       base.content_type,
       distance
FROM VECTOR_SEARCH(
  TABLE \`$PROJECT_ID.gcc_bqml_dataset.gcc_retail_store_embeddings\`,
  'ml_generate_embedding_result',
  (
    SELECT ml_generate_embedding_result AS embedding_col
    FROM ML.GENERATE_EMBEDDING(
      MODEL \`$PROJECT_ID.gcc_bqml_dataset.gcc_embedding\`,
      (SELECT 'Men Sweaters' AS content),
      STRUCT(TRUE AS flatten_json_output)
    )
  ),
  top_k => 2,
  distance_type => 'COSINE'
);"

echo ""
echo "======================================================================"
echo "                   Lab Completed Successfully!                       "
echo "======================================================================"
