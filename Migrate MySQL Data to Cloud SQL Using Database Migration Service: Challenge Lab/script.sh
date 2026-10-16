#!/bin/bash
# MySQL to Cloud SQL Migration - Automated
set +e

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[1;36m'; NC='\033[0m'

echo -e "${CYAN}"
echo "============================================================"
echo "  🎮 MySQL to Cloud SQL Migration - Automated"
echo "  🎬 Presented By ArcadeSuite"
echo "  📺 YouTube: @imasis-k8x"
echo "============================================================"
echo -e "${NC}"

# ============================================================
# USER INPUT
# ============================================================
export PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
echo -e "${YELLOW}Current Project: ${GREEN}$PROJECT_ID${NC}"
echo ""

read -p "Enter Source VM Name (e.g., dev-eng-lx4): " SOURCE_VM
read -p "Enter MySQL Source External IP: " SOURCE_IP
read -p "Enter Region [default: us-central1]: " REGION
REGION=${REGION:-us-central1}
read -p "Enter One-time Target Instance (e.g., mysql-eng-lx4): " TARGET_1
read -p "Enter Continuous Target Instance (e.g., mysql-eng-lx4-cont): " TARGET_2

echo ""
echo -e "${CYAN}=====================================${NC}"
echo -e "${CYAN}  Project: $PROJECT_ID${NC}"
echo -e "${CYAN}  Source VM: $SOURCE_VM${NC}"
echo -e "${CYAN}  Source IP: $SOURCE_IP${NC}"
echo -e "${CYAN}  Region: $REGION${NC}"
echo -e "${CYAN}  Target 1: $TARGET_1${NC}"
echo -e "${CYAN}  Target 2: $TARGET_2${NC}"
echo -e "${CYAN}=====================================${NC}"
echo ""

read -p "Confirm? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
  echo -e "${RED}Aborting.${NC}"
  exit 1
fi

# ============================================================
# TASK 1 — Connection Profile
# ============================================================
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  TASK 1 : Connection Profile${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"

PROFILE_NAME="dev-eng-profile"

# Delete agar exists
gcloud database-migration connection-profiles delete $PROFILE_NAME \
  --region=$REGION -q 2>/dev/null

# Create
gcloud database-migration connection-profiles create mysql $PROFILE_NAME \
  --region=$REGION \
  --host=$SOURCE_IP \
  --port=3306 \
  --username=admin \
  --password=changeme \
  --display-name="Dev Eng Profile" 2>/dev/null

echo -e "${GREEN}✓ Connection profile created: $PROFILE_NAME${NC}"
echo -e "${YELLOW}>>> Click 'Check my progress' for Task 1${NC}"
echo ""
read -p "Press ENTER after clicking Check my progress..."

# ============================================================
# TASK 2 — One-time Migration Job
# ============================================================
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  TASK 2 : One-time Migration Job${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"

# Delete agar exists
gcloud database-migration migration-jobs delete $TARGET_1 \
  --region=$REGION -q 2>/dev/null

# Create one-time migration job
gcloud database-migration migration-jobs create $TARGET_1 \
  --region=$REGION \
  --type=ONE_TIME \
  --source=$PROFILE_NAME \
  --destination=$TARGET_1 \
  --display-name="One-time Migration" 2>/dev/null

# Start job
gcloud database-migration migration-jobs start $TARGET_1 \
  --region=$REGION 2>/dev/null

echo -e "${GREEN}✓ One-time migration job started: $TARGET_1${NC}"
echo -e "${YELLOW}⏳ Waiting 2 minutes for migration...${NC}"
sleep 120

echo -e "${YELLOW}>>> Click 'Check my progress' for Task 2${NC}"
echo ""
read -p "Press ENTER after clicking Check my progress..."

# ============================================================
# TASK 3 — Continuous Migration Job
# ============================================================
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  TASK 3 : Continuous Migration Job${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"

# Delete agar exists
gcloud database-migration migration-jobs delete $TARGET_2 \
  --region=$REGION -q 2>/dev/null

# Create continuous migration job
gcloud database-migration migration-jobs create $TARGET_2 \
  --region=$REGION \
  --type=CONTINUOUS \
  --source=$PROFILE_NAME \
  --destination=$TARGET_2 \
  --display-name="Continuous Migration" 2>/dev/null

# Start
gcloud database-migration migration-jobs start $TARGET_2 \
  --region=$REGION 2>/dev/null

echo -e "${GREEN}✓ Continuous migration job started: $TARGET_2${NC}"
echo -e "${YELLOW}⏳ Waiting 2 minutes for job to be RUNNING...${NC}"
sleep 120

echo -e "${YELLOW}>>> Click 'Check my progress' for Task 3${NC}"
echo ""
read -p "Press ENTER after clicking Check my progress..."

# ============================================================
# TASK 4 — Update Source DB
# ============================================================
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  TASK 4 : Update Source DB${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"

# SSH into source VM and update DB
ZONE=$(gcloud compute instances list --filter="name=$SOURCE_VM" --format="value(zone.basename())" | head -1)

echo "Updating source DB on $SOURCE_VM (zone: $ZONE)..."

gcloud compute ssh $SOURCE_VM --zone=$ZONE --quiet --command="
mysql -u admin -pchangeme -h 127.0.0.1 -e \"USE customers_data; UPDATE customers SET gender='FEMALE' WHERE addressKey=934; SELECT gender FROM customers WHERE addressKey=934;\"
" 2>/dev/null

echo -e "${GREEN}✓ Source DB updated${NC}"
echo -e "${YELLOW}⏳ Waiting 60 seconds for replication...${NC}"
sleep 60

echo -e "${YELLOW}>>> Click 'Check my progress' for Task 4${NC}"
echo ""
read -p "Press ENTER after clicking Check my progress..."

# ============================================================
# TASK 5 — Promote Cloud SQL
# ============================================================
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  TASK 5 : Promote Cloud SQL${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"

gcloud database-migration migration-jobs promote $TARGET_2 \
  --region=$REGION 2>/dev/null

echo -e "${GREEN}✓ Promote started for $TARGET_2${NC}"
echo -e "${YELLOW}⏳ Waiting 2 minutes for promotion...${NC}"
sleep 120

echo -e "${YELLOW}>>> Click 'Check my progress' for Task 5${NC}"
echo ""

# ============================================================
# FINAL
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
echo -e "${YELLOW}⚠️  Har task ke baad 'Check my progress' click karo!${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""
