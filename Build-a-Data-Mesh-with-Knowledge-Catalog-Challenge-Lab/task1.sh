#!/bin/bash
# ============================================
# Task 1: Create Knowledge Catalog Lake with 2 Zones & 2 Assets
# ============================================

# ---------- STEP 0: USER INPUTS (Har user ke liye alag) ----------
echo "======================================"
echo "  Task 1 Setup - Enter Your Details"
echo "======================================"

# Lab panel se copy karke daalo (screenshot mein jo dikh raha hai)
read -p "Enter your Project ID: " PROJECT_ID
read -p "Enter your Region (e.g., us-east4): " REGION

# Ye lab mein pre-created hai - screenshot se copy karo
read -p "Enter Cloud Storage bucket name: " BUCKET_NAME
read -p "Enter BigQuery dataset name (project.dataset): " BQ_DATASET

# ---------- STEP 1: SETUP ----------
# Auto-detect project if not entered
if [ -z "$PROJECT_ID" ]; then
  PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
fi

echo ""
echo "📋 Summary:"
echo "Project : $PROJECT_ID"
echo "Region  : $REGION"
echo "Bucket  : $BUCKET_NAME"
echo "BQ Data : $BQ_DATASET"
echo "======================================"
read -p "Proceed? (y/n): " CONFIRM
[[ "$CONFIRM" != "y" ]] && echo "❌ Cancelled" && exit 1

# ---------- STEP 2: ENABLE API (agar pehle se enable nahi hai) ----------
gcloud services enable dataplex.googleapis.com --project=$PROJECT_ID
echo "✅ Dataplex API enabled"

# ---------- STEP 3: CREATE LAKE ----------
gcloud dataplex lakes create sales-lake \
  --location=$REGION \
  --display-name="Sales Lake" \
  --project=$PROJECT_ID
echo "✅ Lake 'Sales Lake' created"

# ---------- STEP 4: CREATE ZONES ----------
# Raw Customer Zone
gcloud dataplex zones create raw-customer-zone \
  --lake=sales-lake \
  --location=$REGION \
  --type=RAW \
  --resource-location-type=SINGLE_REGION \
  --display-name="Raw Customer Zone" \
  --project=$PROJECT_ID
echo "✅ Raw Customer Zone created"

# Curated Customer Zone
gcloud dataplex zones create curated-customer-zone \
  --lake=sales-lake \
  --location=$REGION \
  --type=CURATED \
  --resource-location-type=SINGLE_REGION \
  --display-name="Curated Customer Zone" \
  --project=$PROJECT_ID
echo "✅ Curated Customer Zone created"

# ---------- STEP 5: ATTACH ASSETS ----------
# Asset 1: Cloud Storage bucket → Raw Customer Zone
gcloud dataplex assets create customer-engagements \
  --lake=sales-lake \
  --zone=raw-customer-zone \
  --location=$REGION \
  --resource-type=STORAGE_BUCKET \
  --resource-name=projects/$PROJECT_ID/buckets/$BUCKET_NAME \
  --display-name="Customer Engagements" \
  --project=$PROJECT_ID
echo "✅ Asset 'Customer Engagements' attached to Raw Customer Zone"

# Asset 2: BigQuery dataset → Curated Customer Zone
gcloud dataplex assets create customer-orders \
  --lake=sales-lake \
  --zone=curated-customer-zone \
  --location=$REGION \
  --resource-type=BIGQUERY_DATASET \
  --resource-name=projects/$PROJECT_ID/datasets/$BQ_DATASET \
  --display-name="Customer Orders" \
  --project=$PROJECT_ID
echo "✅ Asset 'Customer Orders' attached to Curated Customer Zone"

# ---------- STEP 6: VALIDATION ----------
echo ""
echo "======================================"
echo "✅ Task 1 Complete!"
echo "======================================"
echo "Ab lab panel mein 'Check my progress' click karo."
