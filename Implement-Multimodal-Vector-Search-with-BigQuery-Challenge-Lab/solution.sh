#!/bin/bash
set -e

echo "======================================================================"
echo "         Automated Solution for Multimodal Vector Search Lab          "
echo "======================================================================"
echo ""

# Auto-detect Project ID & Region directly from Cloud Shell context
export PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
export REGION="us-east4"
export CONN_NAME="vector_conn"

if [ -z "$PROJECT_ID" ]; then
  echo "Error: Project ID not found. Please make sure you are logged in."
  exit 1
fi

echo "--> Target Project ID: $PROJECT_ID"
echo "--> Target Region: $REGION"
echo ""

# ------------------------------------------------------------------------------
# Task 1: Create a source connection and grant IAM permissions
# ------------------------------------------------------------------------------
echo "--> [Task 1/4] Creating BigQuery Connection & Setting IAM permissions..."

bq mk --connection \
  --location=$REGION \
  --project_id=$PROJECT_ID \
  --connection_type=CLOUD_RESOURCE $CONN_NAME

SA_ID=$(bq show --location=$REGION --connection $CONN_NAME | grep "serviceAccountId" | awk -F '"' '{print $4}')

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_ID" \
  --role="roles/bigquery.dataOwner" --no-user-output-enabled

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_ID" \
  --role="roles/storage.objectViewer" --no-user-output-enabled

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_ID" \
  --role="roles/aiplatform.user" --no-user-output-enabled

echo "Waiting 10s for IAM propagation..."
sleep 10

# ------------------------------------------------------------------------------
# Task 2: Create an object table
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
echo "--> [Task 3/4] Creating Embedding Model and Generating Embeddings..."

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
echo "                     Lab Completed Successfully!                     "
echo "======================================================================"
