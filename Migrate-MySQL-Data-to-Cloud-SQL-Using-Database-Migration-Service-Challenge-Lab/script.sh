#!/bin/bash

# Color definitions
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}Starting Solution for: Migrate MySQL Data to Cloud SQL Using Database Migration Service: Challenge Lab${NC}\n"

# Environment Variables setup
export PROJECT_ID=$(gcloud config get-value project)
export REGION="europe-west1"
export ZONE="europe-west1-d"

gcloud config set compute/zone $ZONE --quiet
gcloud config set compute/region $REGION --quiet
gcloud config set database_migration/region $REGION --quiet

echo -e "${GREEN}Project ID:${NC} $PROJECT_ID"
echo -e "${GREEN}Region:${NC} $REGION"
echo -e "${GREEN}Zone:${NC} $ZONE\n"

# Fetch VM Details Dynamically
VM_NAME=$(gcloud compute instances list --format='value(name)' | head -n 1)
VM_ZONE=$(gcloud compute instances list --format='value(zone)' | head -n 1)
SOURCE_IP=$(gcloud compute instances describe $VM_NAME --zone=$VM_ZONE --format='value(networkInterfaces[0].accessConfigs[0].natIP)')

echo -e "${GREEN}Source MySQL Instance:${NC} $VM_NAME"
echo -e "${GREEN}Source Zone:${NC} $VM_ZONE"
echo -e "${GREEN}Source MySQL External IP:${NC} $SOURCE_IP\n"

# Enable required Service APIs
gcloud services enable datamigration.googleapis.com --quiet

# Task 1: Create Connection Profile
echo -e "${CYAN}Task 1: Creating Connection Profile...${NC}"

gcloud database-migration connection-profiles create mysql mysql-source-profile \
    --region=$REGION \
    --host=$SOURCE_IP \
    --port=3306 \
    --username=admin \
    --password=changeme \
    --quiet || true

# Task 2: Perform One-time Migration Job
echo -e "${CYAN}Task 2: Performing One-Time Migration Job...${NC}"

gcloud database-migration migration-jobs create mysql-one-time-job \
    --region=$REGION \
    --source-connection-profile=mysql-source-profile \
    --type=ONE_TIME \
    --quiet || true

# Task 3: Create Continuous Migration Job
echo -e "${CYAN}Task 3: Creating Continuous Migration Job...${NC}"

gcloud database-migration migration-jobs create mysql-continuous-job \
    --region=$REGION \
    --source-connection-profile=mysql-source-profile \
    --type=CONTINUOUS \
    --quiet || true

# Task 4: Update Data on Source Database
echo -e "${CYAN}Task 4: Updating Source MySQL Database Data...${NC}"

gcloud compute ssh $VM_NAME --zone=$VM_ZONE --command="mysql -u admin -pchangeme -e 'USE customers_data; UPDATE customers SET gender = \"FEMALE\" WHERE addressKey = 934;'" --quiet || true

# Task 5: Promote Continuous Migration Job
echo -e "${CYAN}Task 5: Promoting Continuous Migration Job...${NC}"

gcloud database-migration migration-jobs promote mysql-continuous-job --region=$REGION --quiet || true

echo -e "\n${GREEN}Lab Completed! Check progress on all tasks now.${NC}"
