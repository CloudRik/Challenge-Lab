#!/bin/bash
# Create and Manage AlloyDB Instances - Universal Automated Script
set +e

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[1;36m'; NC='\033[0m'

echo -e "${CYAN}"
echo "============================================================"
echo "  🎮 Create and Manage AlloyDB Instances - Automated"
echo "  🎬 Presented By ArcadeSuite"
echo "  📺 YouTube: @imasis-k8x"
echo "============================================================"
echo -e "${NC}"

# ============================================================
# USER INPUT (Lab panel se copy karo)
# ============================================================
export PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
echo -e "${YELLOW}Current Project: ${GREEN}$PROJECT_ID${NC}"
echo ""

echo -e "${YELLOW}⚠️  Lab panel se ye values EXACT copy karo:${NC}"
echo ""

read -p "GCP Region (e.g., us-central1): " REGION
while [ -z "$REGION" ]; do
  echo -e "${RED}Region cannot be empty!${NC}"
  read -p "GCP Region: " REGION
done

read -p "Cluster ID [default: lab-cluster]: " CLUSTER_ID
CLUSTER_ID=${CLUSTER_ID:-lab-cluster}

read -p "Cluster Password [default: Change3Me]: " DB_PASSWORD
DB_PASSWORD=${DB_PASSWORD:-Change3Me}

read -p "Network [default: peering-network]: " NETWORK
NETWORK=${NETWORK:-peering-network}

read -p "Primary Instance ID [default: lab-instance]: " INSTANCE_ID
INSTANCE_ID=${INSTANCE_ID:-lab-instance}

read -p "Read Pool Instance ID [default: lab-instance-rp1]: " RP_INSTANCE_ID
RP_INSTANCE_ID=${RP_INSTANCE_ID:-lab-instance-rp1}

read -p "Backup ID [default: lab-backup]: " BACKUP_ID
BACKUP_ID=${BACKUP_ID:-lab-backup}

echo ""
echo -e "${CYAN}=====================================${NC}"
echo -e "${CYAN}  Project:    $PROJECT_ID${NC}"
echo -e "${CYAN}  Region:     $REGION${NC}"
echo -e "${CYAN}  Cluster:    $CLUSTER_ID${NC}"
echo -e "${CYAN}  Instance:   $INSTANCE_ID${NC}"
echo -e "${CYAN}  Read Pool:  $RP_INSTANCE_ID${NC}"
echo -e "${CYAN}  Backup:     $BACKUP_ID${NC}"
echo -e "${CYAN}=====================================${NC}"
echo ""

read -p "Confirm? (y/n): " CONFIRM
[ "$CONFIRM" != "y" ] && { echo "Aborting."; exit 1; }

# Save for later
cat > ~/alloydb.env <<EOF
export PROJECT_ID=$PROJECT_ID
export REGION=$REGION
export CLUSTER_ID=$CLUSTER_ID
export DB_PASSWORD=$DB_PASSWORD
export NETWORK=$NETWORK
export INSTANCE_ID=$INSTANCE_ID
export RP_INSTANCE_ID=$RP_INSTANCE_ID
export BACKUP_ID=$BACKUP_ID
EOF

# ============================================================
# TASK 1 — Cluster + Primary Instance
# ============================================================
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  TASK 1 : Cluster + Primary Instance${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"

# Check if cluster exists
if gcloud beta alloydb clusters describe $CLUSTER_ID --region=$REGION --quiet 2>/dev/null; then
  echo -e "${GREEN}✓ Cluster already exists${NC}"
else
  echo "Creating cluster $CLUSTER_ID..."
  gcloud beta alloydb clusters create $CLUSTER_ID \
    --password=$DB_PASSWORD \
    --network=$NETWORK \
    --region=$REGION \
    --project=$PROJECT_ID

  if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Cluster create failed!${NC}"
    echo -e "${YELLOW}Possible reasons:${NC}"
    echo "  1. Region me AlloyDB resources nahi hain"
    echo "  2. Network 'peering-network' exist nahi karta"
    echo "  3. Permission issue"
    exit 1
  fi
  echo -e "${GREEN}✓ Cluster created${NC}"
fi

sleep 15

# Check if instance exists
if gcloud beta alloydb instances describe $INSTANCE_ID --region=$REGION --cluster=$CLUSTER_ID --quiet 2>/dev/null; then
  echo -e "${GREEN}✓ Instance already exists${NC}"
else
  echo "Creating primary instance $INSTANCE_ID..."
  gcloud beta alloydb instances create $INSTANCE_ID \
    --instance-type=PRIMARY \
    --cpu-count=2 \
    --region=$REGION \
    --cluster=$CLUSTER_ID \
    --project=$PROJECT_ID

  if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Instance create failed!${NC}"
    exit 1
  fi
  echo -e "${GREEN}✓ Instance created${NC}"
fi

sleep 10

# Get Private IP
ALLOYDB_IP=$(gcloud beta alloydb instances describe $INSTANCE_ID \
  --region=$REGION \
  --cluster=$CLUSTER_ID \
  --format="value(ipAddress)")

echo ""
echo -e "${GREEN}✓ Private IP: ${YELLOW}$ALLOYDB_IP${NC}"
echo "$ALLOYDB_IP" > ~/alloydb_ip.txt
echo ""
echo -e "${YELLOW}>>> Click 'Check my progress' for Task 1${NC}"
read -p "Press ENTER after clicking..."

# ============================================================
# TASK 2 + 3 — Tables + Data Load (via SSH)
# ============================================================
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  TASK 2 + 3 : Tables + Data Load${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"

# Find alloydb-client VM
VM_ZONE=$(gcloud compute instances list --filter="name=alloydb-client" --format="value(zone.basename())" | head -1)

if [ -z "$VM_ZONE" ]; then
  echo -e "${RED}✗ VM 'alloydb-client' nahi mila!${NC}"
  exit 1
fi

echo "alloydb-client zone: $VM_ZONE"

# SSH + create tables + load data
gcloud compute ssh alloydb-client --zone=$VM_ZONE --quiet --command="
export ALLOYDB=$ALLOYDB_IP
echo \$ALLOYDB > alloydbip.txt

# Install psql if needed
which psql > /dev/null 2>&1 || (sudo apt update -qq && sudo apt install -y postgresql-client -qq)

# Wait
sleep 20

# Create tables + data
PGPASSWORD=$DB_PASSWORD psql -h \$ALLOYDB -U postgres -d postgres <<'SQLEOF'
CREATE TABLE IF NOT EXISTS regions (
  region_id bigint NOT NULL,
  region_name varchar(25)
);
ALTER TABLE regions ADD PRIMARY KEY (region_id);

CREATE TABLE IF NOT EXISTS countries (
  country_id char(2) NOT NULL,
  country_name varchar(40),
  region_id bigint
);
ALTER TABLE countries ADD PRIMARY KEY (country_id);

CREATE TABLE IF NOT EXISTS departments (
  department_id smallint NOT NULL,
  department_name varchar(30),
  manager_id integer,
  location_id smallint
);
ALTER TABLE departments ADD PRIMARY KEY (department_id);

INSERT INTO regions VALUES
(1, 'Europe'),(2, 'Americas'),(3, 'Asia'),(4, 'Middle East and Africa')
ON CONFLICT DO NOTHING;

INSERT INTO countries VALUES
('IT','Italy',1),('JP','Japan',3),('US','United States of America',2),
('CA','Canada',2),('CN','China',3),('IN','India',3),('AU','Australia',3),
('ZW','Zimbabwe',4),('SG','Singapore',3)
ON CONFLICT DO NOTHING;

INSERT INTO departments VALUES
(10,'Administration',200,1700),(20,'Marketing',201,1800),
(30,'Purchasing',114,1700),(40,'Human Resources',203,2400),
(50,'Shipping',121,1500),(60,'IT',103,1400)
ON CONFLICT DO NOTHING;

SELECT 'regions' as tbl, COUNT(*) FROM regions
UNION ALL SELECT 'countries', COUNT(*) FROM countries
UNION ALL SELECT 'departments', COUNT(*) FROM departments;
SQLEOF
" 2>/dev/null

echo -e "${GREEN}✓ Tables + data done${NC}"
echo ""
echo -e "${YELLOW}>>> Click 'Check my progress' for Task 2 and 3${NC}"
read -p "Press ENTER after clicking..."

# ============================================================
# TASK 4 — Read Pool Instance
# ============================================================
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  TASK 4 : Read Pool Instance${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"

if gcloud beta alloydb instances describe $RP_INSTANCE_ID --region=$REGION --cluster=$CLUSTER_ID --quiet 2>/dev/null; then
  echo -e "${GREEN}✓ Read Pool already exists${NC}"
else
  gcloud beta alloydb instances create $RP_INSTANCE_ID \
    --instance-type=READ_POOL \
    --cpu-count=2 \
    --read-pool-node-count=2 \
    --region=$REGION \
    --cluster=$CLUSTER_ID \
    --project=$PROJECT_ID

  [ $? -eq 0 ] && echo -e "${GREEN}✓ Read Pool created${NC}" || echo -e "${RED}✗ Read Pool failed${NC}"
fi

echo ""
echo -e "${YELLOW}>>> Click 'Check my progress' for Task 4${NC}"
read -p "Press ENTER after clicking..."

# ============================================================
# TASK 5 — Backup
# ============================================================
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  TASK 5 : Backup${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"

gcloud beta alloydb backups create $BACKUP_ID \
  --cluster=$CLUSTER_ID \
  --region=$REGION \
  --project=$PROJECT_ID

[ $? -eq 0 ] && echo -e "${GREEN}✓ Backup created${NC}" || echo -e "${RED}✗ Backup failed${NC}"

echo ""
echo -e "${YELLOW}>>> Click 'Check my progress' for Task 5${NC}"

# ============================================================
# FINAL BANNER
# ============================================================
echo ""
echo -e "${GREEN}"
cat << "EOF"
  _____                      _      _       
 / ____|                    | |    | |      
| |     ___  _ __ ___  _ __ | | ___| |_ ___ 
| |    / _ \| '_ ` _ \| '_ \| |/ _ \ __/ _ \
| |___| (_) | | | | | | |_) | |  __/ ||  __/
 \_____\___/|_| |_| |_| .__/|_|\___|\__\___|
                      | |                    
                      |_|                    
EOF
echo -e "${NC}"
echo -e "${YELLOW}🎉 ALL TASKS COMPLETED! 🎉${NC}"
echo -e "${CYAN}============================================================${NC}"
echo -e "${GREEN}🎬 Presented By ArcadeSuite${NC}"
echo -e "${CYAN}📺 YouTube: https://youtube.com/@imasis-k8x${NC}"
echo -e "${CYAN}💻 GitHub:  https://github.com/CloudRik${NC}"
echo -e "${YELLOW}🏆 Arcade Points: https://arcadesuite.pages.dev/${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""
