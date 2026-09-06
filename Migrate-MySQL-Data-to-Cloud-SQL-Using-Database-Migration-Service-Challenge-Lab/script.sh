#!/bin/bash

# Color definitions
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}Starting Solution for: Migrate MySQL Data to Cloud SQL Using Database Migration Service: Challenge Lab${NC}\n"

# Fetch environment variables dynamically
export PROJECT_ID=$(gcloud config get-value project)
export REGION="europe-west1"
export ZONE="europe-west1-d"

gcloud config set compute/zone $ZONE
gcloud config set compute/region $REGION

echo -e "${GREEN}Project ID:${NC} $PROJECT_ID"
echo -e "${GREEN}Region:${NC} $REGION"
echo -e "${GREEN}Zone:${NC} $ZONE\n"

# Fetch External IP of MySQL_Source_compute_instance
SOURCE_IP=$(gcloud compute instances describe mysql-source-compute-instance --zone=$ZONE --format='value(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null || gcloud compute instances list --filter="name~mysql" --format='value(networkInterfaces[0].accessConfigs[0].natIP)')

if [ -z "$SOURCE_IP" ]; then
    SOURCE_IP=$(gcloud compute instances list --format='value(networkInterfaces[0].accessConfigs[0].natIP)' | head -n 1)
fi

echo -e "${GREEN}Source MySQL External IP:${NC} $SOURCE_IP"

# Enable required Database Migration Service API
gcloud services enable datamigration.googleapis.com --quiet

# Task 1: Create Connection Profile
echo -e "${CYAN}Task 1: Creating Connection Profile...${NC}"

gcloud datamigration connection-profiles create mysql mysql-source-profile \
    --location=$REGION \
    --host=$SOURCE_IP \
    --port=3306 \
    --username=admin \
    --password=changeme \
    --quiet || true

# Task 2: Perform One-time Migration
echo -e "${CYAN}Task 2: Performing One-Time Migration Job...${NC}"

# Create One-time Migration Job
gcloud datamigration migration-jobs create mysql-one-time-job \
    --location=$REGION \
    --source-connection-profile=projects/$PROJECT_ID/locations/$REGION/connectionProfiles/mysql-source-profile \
    --type=ONE_TIME \
    --quiet || true

# Task 3: Continuous Migration Job
echo -e "${CYAN}Task 3: Creating Continuous Migration Job...${NC}"

gcloud datamigration migration-jobs create mysql-continuous-job \
    --location=$REGION \
    --source-connection-profile=projects/$PROJECT_ID/locations/$REGION/connectionProfiles/mysql-source-profile \
    --type=CONTINUOUS \
    --quiet || true

# Task 4: Update Data on Source MySQL Instance
echo -e "${CYAN}Task 4: Updating Source MySQL Database Data...${NC}"

# Execute SQL query on source VM via gcloud compute ssh
gcloud compute ssh mysql-source-compute-instance --zone=$ZONE --command="mysql -u admin -pchangeme -e 'USE customers_data; UPDATE customers SET gender = \"FEMALE\" WHERE addressKey = 934;'" --quiet || \
gcloud compute ssh $(gcloud compute instances list --format='value(name)' | head -n 1) --zone=$ZONE --command="mysql -u admin -pchangeme -e 'USE customers_data; UPDATE customers SET gender = \"FEMALE\" WHERE addressKey = 934;'" --quiet || true

# Task 5: Promote Destination Instance
echo -e "${CYAN}Task 5: Promoting Continuous Migration Job...${NC}"

gcloud datamigration migration-jobs promote mysql-continuous-job --location=$REGION --quiet || true

echo -e "\n${GREEN}Lab Script Execution Completed! Check progress on all tasks.${NC}"
