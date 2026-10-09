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
echo "${CYAN}${BOLD}   CREATE & MANAGE ALLOYDB INSTANCES (GSP1083)  ${RESET}"
echo "${CYAN}${BOLD}=================================================${RESET}"
echo

# ===============================
# ENVIRONMENT DETECTION
# ===============================
PROJECT=$(gcloud config get-value project 2>/dev/null)

# Region auto-detect (from lab)
REGION=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null)

if [ -z "$REGION" ]; then
  echo "${RED}Could not auto-detect region.${RESET}"
  read -p "Enter your region (e.g., us-east4): " REGION
fi

echo "${BLUE}Project: ${WHITE}$PROJECT${RESET}"
echo "${BLUE}Region:  ${WHITE}$REGION${RESET}"
echo

# ===============================
# TASK 1: Create cluster + instance
# ===============================
echo "${GREEN}${BOLD}Task 1: Creating AlloyDB cluster + instance${RESET}"
echo "${WHITE}This will take 9-13 minutes...${RESET}"
echo

# Create cluster
if gcloud beta alloydb clusters describe lab-cluster --region=$REGION &>/dev/null; then
  echo "${YELLOW}Cluster lab-cluster already exists, skipping...${RESET}"
else
  gcloud beta alloydb clusters create lab-cluster \
    --password=Change3Me \
    --network=peering-network \
    --region=$REGION \
    --project=$PROJECT \
    --quiet
fi

# Create instance
if gcloud beta alloydb instances describe lab-instance --cluster=lab-cluster --region=$REGION &>/dev/null; then
  echo "${YELLOW}Instance lab-instance already exists, skipping...${RESET}"
else
  gcloud beta alloydb instances create lab-instance \
    --instance-type=PRIMARY \
    --cpu-count=2 \
    --region=$REGION \
    --cluster=lab-cluster \
    --project=$PROJECT \
    --quiet
fi

echo "${GREEN}Task 1 complete${RESET}"
echo

# Wait for cluster READY
echo "${YELLOW}Waiting for cluster to be READY...${RESET}"
for i in {1..90}; do
  STATUS=$(gcloud beta alloydb clusters describe lab-cluster --region=$REGION --format="value(state)" 2>/dev/null)
  if [ "$STATUS" = "READY" ]; then
    break
  fi
  sleep 20
done

# Get private IP
ALLOYDB_IP=$(gcloud beta alloydb instances describe lab-instance \
  --cluster=lab-cluster \
  --region=$REGION \
  --format="value(ipAddress)" 2>/dev/null | head -n 1)

if [ -z "$ALLOYDB_IP" ]; then
  read -p "Enter AlloyDB Private IP manually: " ALLOYDB_IP
fi

echo "${BLUE}AlloyDB Private IP: ${WHITE}$ALLOYDB_IP${RESET}"
echo

# ===============================
# TASK 2 & 3: Create tables + Load data (VM pe psql)
# ===============================
echo "${GREEN}${BOLD}Task 2 & 3: Creating tables and loading data${RESET}"

VM_ZONE=$(gcloud compute instances list --filter="name:alloydb-client" --format="value(zone)" 2>/dev/null | head -n 1)

if [ -z "$VM_ZONE" ]; then
  read -p "Enter alloydb-client VM zone: " VM_ZONE
fi

echo "${BLUE}VM Zone: ${WHITE}$VM_ZONE${RESET}"
echo

echo "${WHITE}Creating tables and loading data on VM...${RESET}"

gcloud compute ssh alloydb-client --zone=$VM_ZONE --command="
  export ALLOYDB=$ALLOYDB_IP
  echo \$ALLOYDB > alloydbip.txt

  # Task 2: Create 3 tables
  PGPASSWORD=Change3Me psql -h \$ALLOYDB -U postgres <<'SQL_END'
CREATE TABLE regions (
  region_id bigint NOT NULL,
  region_name varchar(25)
);
ALTER TABLE regions ADD PRIMARY KEY (region_id);

CREATE TABLE countries (
  country_id char(2) NOT NULL,
  country_name varchar(40),
  region_id bigint
);
ALTER TABLE countries ADD PRIMARY KEY (country_id);

CREATE TABLE departments (
  department_id smallint NOT NULL,
  department_name varchar(30),
  manager_id integer,
  location_id smallint
);
ALTER TABLE departments ADD PRIMARY KEY (department_id);
SQL_END

  # Task 3: Load data
  PGPASSWORD=Change3Me psql -h \$ALLOYDB -U postgres <<'SQL_END'
INSERT INTO regions VALUES
  (1, 'Europe'), (2, 'Americas'), (3, 'Asia'), (4, 'Middle East and Africa');

INSERT INTO countries VALUES
  ('IT', 'Italy', 1), ('JP', 'Japan', 3), ('US', 'United States of America', 2),
  ('CA', 'Canada', 2), ('CN', 'China', 3), ('IN', 'India', 3),
  ('AU', 'Australia', 3), ('ZW', 'Zimbabwe', 4), ('SG', 'Singapore', 3);

INSERT INTO departments VALUES
  (10, 'Administration', 200, 1700),
  (20, 'Marketing', 201, 1800),
  (30, 'Purchasing', 114, 1700),
  (40, 'Human Resources', 203, 2400),
  (50, 'Shipping', 121, 1500),
  (60, 'IT', 103, 1400);
SQL_END

  echo '--- Tables ---'
  PGPASSWORD=Change3Me psql -h \$ALLOYDB -U postgres -c '\dt'
" --quiet

echo "${GREEN}Task 2 & 3 complete${RESET}"
echo

# ===============================
# TASK 4: Create Read Pool instance
# ===============================
echo "${MAGENTA}${BOLD}Task 4: Creating Read Pool instance (lab-instance-rp1)${RESET}"
echo "${WHITE}This will take 5-8 minutes...${RESET}"

if gcloud beta alloydb instances describe lab-instance-rp1 --cluster=lab-cluster --region=$REGION &>/dev/null; then
  echo "${YELLOW}Read Pool already exists, skipping...${RESET}"
else
  gcloud beta alloydb instances create lab-instance-rp1 \
    --instance-type=READ_POOL \
    --cpu-count=2 \
    --read-pool-node-count=2 \
    --region=$REGION \
    --cluster=lab-cluster \
    --project=$PROJECT \
    --quiet
fi

echo "${GREEN}Task 4 complete${RESET}"
echo

# ===============================
# TASK 5: Create backup
# ===============================
echo "${RED}${BOLD}Task 5: Creating backup (lab-backup)${RESET}"
echo "${WHITE}This will take 3-5 minutes...${RESET}"

if gcloud beta alloydb backups describe lab-backup --region=$REGION &>/dev/null; then
  echo "${YELLOW}Backup already exists, skipping...${RESET}"
else
  gcloud beta alloydb backups create lab-backup \
    --cluster=lab-cluster \
    --region=$REGION \
    --project=$PROJECT \
    --quiet
fi

echo "${GREEN}Task 5 complete${RESET}"
echo

# ===============================
# VERIFICATION
# ===============================
echo "${CYAN}${BOLD}=================================================${RESET}"
echo "${CYAN}${BOLD}   VERIFICATION${RESET}"
echo "${CYAN}${BOLD}=================================================${RESET}"
echo

echo "${YELLOW}AlloyDB clusters:${RESET}"
gcloud beta alloydb clusters list
echo

echo "${YELLOW}AlloyDB instances:${RESET}"
gcloud beta alloydb instances list --cluster=lab-cluster --region=$REGION
echo

echo "${YELLOW}AlloyDB backups:${RESET}"
gcloud beta alloydb backups list --region=$REGION
echo

echo "${CYAN}${BOLD}=================================================${RESET}"
echo "${CYAN}${BOLD}   AUTOMATED SETUP COMPLETED${RESET}"
echo "${CYAN}${BOLD}=================================================${RESET}"
echo
echo "${WHITE}Now click Check my progress in the lab for:${RESET}"
echo "  - Task 1 (Create a cluster and instance)"
echo "  - Task 2 (Create tables in your instance)"
echo "  - Task 3 (Load simple datasets into tables)"
echo "  - Task 4 (Create a Read Pool instance)"
echo "  - Task 5 (Create a backup)"
echo
