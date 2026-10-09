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

REGION=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null)

if [ -z "$REGION" ]; then
  echo "${RED}Could not auto-detect region.${RESET}"
  read -p "Enter your region (e.g., us-central1): " REGION
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

echo "${YELLOW}Waiting for cluster to be READY...${RESET}"
for i in {1..90}; do
  STATUS=$(gcloud beta alloydb clusters describe lab-cluster --region=$REGION --format="value(state)" 2>/dev/null)
  if [ "$STATUS" = "READY" ]; then
    break
  fi
  sleep 20
done

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
# TASK 2 & 3: Create tables + Load data
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
# TASK 5: SKIP (Run manually)
# ===============================
echo "${YELLOW}${BOLD}=================================================${RESET}"
echo "${YELLOW}${BOLD}   TASK 5: RUN MANUALLY (Auth token issue)${RESET}"
echo "${YELLOW}${BOLD}=================================================${RESET}"
echo
echo "${WHITE}Task 5 (Backup) ke liye yeh command chalao:${RESET}"
echo
echo "${GREEN}gcloud beta alloydb backups create lab-backup \\${RESET}"
echo "${GREEN}  --cluster=lab-cluster \\${RESET}"
echo "${GREEN}  --region=$REGION \\${RESET}"
echo "${GREEN}  --project=$PROJECT \\${RESET}"
echo "${GREEN}  --quiet${RESET}"
echo
echo "${WHITE}Ya Console se:${RESET}"
echo "  AlloyDB → Backups → Create backup → lab-backup → Create"
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

echo "${CYAN}${BOLD}=================================================${RESET}"
echo "${CYAN}${BOLD}   TASK 1-4 COMPLETED${RESET}"
echo "${CYAN}${BOLD}=================================================${RESET}"
echo
echo "${WHITE}Now:${RESET}"
echo "  1. Task 1, 2, 3, 4 ke Check my progress click karo"
echo "  2. Task 5 manually chalao (upar wali command)"
echo "  3. Task 5 Check my progress click karo"
echo
