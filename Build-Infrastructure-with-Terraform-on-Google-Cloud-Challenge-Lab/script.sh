#!/usr/bin/env bash

set -Eeuo pipefail

###############################################################################
# GSP345 - Build Infrastructure with Terraform on Google Cloud
#
# Fully automated solution for the Challenge Lab.
#
# User input required:
#   1. Bucket Name
#   2. Third Instance Name
#   3. VPC Name
#
# Project ID, Zone, Region, existing VM details and boot images are detected
# automatically from the active Qwiklabs project.
###############################################################################

###############################################################################
# COLORS / LOGGING
###############################################################################

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
NC="\033[0m"

log() {
    echo -e "${CYAN}[INFO]${NC} $*"
}

ok() {
    echo -e "${GREEN}[OK]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

die() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    exit 1
}

###############################################################################
# ERROR HANDLER
###############################################################################

trap 'echo -e "${RED}[ERROR]${NC} Script stopped at line $LINENO."; exit 1' ERR

###############################################################################
# CHECK REQUIRED COMMANDS
###############################################################################

command -v gcloud >/dev/null 2>&1 || die "gcloud is not installed."
command -v terraform >/dev/null 2>&1 || die "Terraform is not installed."

###############################################################################
# PROJECT DETECTION
###############################################################################

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"

[[ -n "$PROJECT_ID" && "$PROJECT_ID" != "(unset)" ]] \
    || die "No active Google Cloud project was detected."

echo
echo "============================================================"
echo " GSP345 - Terraform Challenge Lab"
echo "============================================================"
echo
echo "Project ID detected:"
echo "  $PROJECT_ID"
echo

###############################################################################
# USER INPUT
###############################################################################

echo "Enter the values shown in the Google Skills Boost Lab Setup."
echo "You only need to enter these three values."
echo

read -r -p "Bucket Name: " BUCKET_NAME
read -r -p "Third Instance Name: " INSTANCE_3
read -r -p "VPC Name: " VPC_NAME

BUCKET_NAME="$(echo "$BUCKET_NAME" | xargs)"
INSTANCE_3="$(echo "$INSTANCE_3" | xargs)"
VPC_NAME="$(echo "$VPC_NAME" | xargs)"

[[ -n "$BUCKET_NAME" ]] || die "Bucket Name cannot be empty."
[[ -n "$INSTANCE_3" ]] || die "Third Instance Name cannot be empty."
[[ -n "$VPC_NAME" ]] || die "VPC Name cannot be empty."

###############################################################################
# VALIDATE USER-SUPPLIED RESOURCE NAMES
###############################################################################

if [[ ! "$BUCKET_NAME" =~ ^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$ ]]; then
    die "Invalid bucket name: $BUCKET_NAME"
fi

if [[ ! "$INSTANCE_3" =~ ^[a-z]([-a-z0-9]*[a-z0-9])?$ ]]; then
    die "Invalid instance name: $INSTANCE_3"
fi

if [[ ! "$VPC_NAME" =~ ^[a-z]([-a-z0-9]*[a-z0-9])?$ ]]; then
    die "Invalid VPC name: $VPC_NAME"
fi

###############################################################################
# DISCOVER EXISTING INSTANCES
###############################################################################

log "Detecting pre-created lab instances..."

for VM in tf-instance-1 tf-instance-2; do
    gcloud compute instances describe "$VM" \
        --project="$PROJECT_ID" \
        >/dev/null 2>&1 \
        || die "$VM was not found in the current lab project."

    ok "$VM exists."
done

###############################################################################
# DISCOVER ZONE
###############################################################################

ZONE_1="$(
    gcloud compute instances describe tf-instance-1 \
        --project="$PROJECT_ID" \
        --format='value(zone.basename())'
)"

ZONE_2="$(
    gcloud compute instances describe tf-instance-2 \
        --project="$PROJECT_ID" \
        --format='value(zone.basename())'
)"

[[ -n "$ZONE_1" ]] || die "Could not determine zone of tf-instance-1."
[[ -n "$ZONE_2" ]] || die "Could not determine zone of tf-instance-2."

[[ "$ZONE_1" == "$ZONE_2" ]] \
    || die "The two lab instances are in different zones: $ZONE_1 / $ZONE_2"

ZONE="$ZONE_1"
REGION="${ZONE%-*}"

###############################################################################
# DISCOVER MACHINE TYPES
###############################################################################

log "Detecting machine types..."

MACHINE_1="$(
    gcloud compute instances describe tf-instance-1 \
        --project="$PROJECT_ID" \
        --zone="$ZONE" \
        --format='value(machineType.basename())'
)"

MACHINE_2="$(
    gcloud compute instances describe tf-instance-2 \
        --project="$PROJECT_ID" \
        --zone="$ZONE" \
        --format='value(machineType.basename())'
)"

[[ -n "$MACHINE_1" ]] || die "Could not determine machine type of tf-instance-1."
[[ -n "$MACHINE_2" ]] || die "Could not determine machine type of tf-instance-2."

###############################################################################
# DISCOVER BOOT IMAGE
#
# IMPORTANT:
# Do NOT use disks[0].deviceName.
#
# deviceName is typically "persistent-disk-0".
# We need disks[0].source, extract the actual disk name, then query the disk.
###############################################################################

get_boot_image() {
    local VM="$1"
    local DISK_SOURCE
    local DISK_NAME
    local IMAGE

    DISK_SOURCE="$(
        gcloud compute instances describe "$VM" \
            --project="$PROJECT_ID" \
            --zone="$ZONE" \
            --format='value(disks[0].source)'
    )"

    [[ -n "$DISK_SOURCE" ]] \
        || die "Could not determine boot disk source for $VM."

    DISK_NAME="${DISK_SOURCE##*/}"

    [[ -n "$DISK_NAME" ]] \
        || die "Could not determine boot disk name for $VM."

    IMAGE="$(
        gcloud compute disks describe "$DISK_NAME" \
            --project="$PROJECT_ID" \
            --zone="$ZONE" \
            --format='value(sourceImage)'
    )"

    [[ -n "$IMAGE" ]] \
        || die "Could not determine boot image for $VM."

    echo "$IMAGE"
}

log "Detecting boot images..."

IMAGE_1="$(get_boot_image tf-instance-1)"
IMAGE_2="$(get_boot_image tf-instance-2)"

###############################################################################
# PRE-FLIGHT SUMMARY
###############################################################################

echo
echo "============================================================"
echo " PRE-FLIGHT CONFIGURATION"
echo "============================================================"
echo "Project ID       : $PROJECT_ID"
echo "Region           : $REGION"
echo "Zone             : $ZONE"
echo "Bucket           : $BUCKET_NAME"
echo "Third Instance   : $INSTANCE_3"
echo "VPC              : $VPC_NAME"
echo "VM1 Machine Type : $MACHINE_1"
echo "VM2 Machine Type : $MACHINE_2"
echo "VM1 Boot Image   : $IMAGE_1"
echo "VM2 Boot Image   : $IMAGE_2"
echo "============================================================"
echo

###############################################################################
# CHECK RESOURCE NAME CONFLICTS
###############################################################################

if gcloud compute instances describe "$INSTANCE_3" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" >/dev/null 2>&1; then

    die "Third instance '$INSTANCE_3' already exists. Use a fresh lab."
fi

###############################################################################
# WORKSPACE
###############################################################################

log "Preparing Terraform workspace..."

mkdir -p modules/instances
mkdir -p modules/storage

###############################################################################
# ROOT VARIABLES
###############################################################################

cat > variables.tf <<EOF
variable "region" {
  type    = string
  default = "$REGION"
}

variable "zone" {
  type    = string
  default = "$ZONE"
}

variable "project_id" {
  type    = string
  default = "$PROJECT_ID"
}
EOF

###############################################################################
# INSTANCE MODULE VARIABLES
###############################################################################

cat > modules/instances/variables.tf <<EOF
variable "region" {
  type    = string
  default = "$REGION"
}

variable "zone" {
  type    = string
  default = "$ZONE"
}

variable "project_id" {
  type    = string
  default = "$PROJECT_ID"
}
EOF

cat > modules/instances/outputs.tf <<'EOF'
EOF

###############################################################################
# STORAGE MODULE VARIABLES
###############################################################################

cat > modules/storage/variables.tf <<EOF
variable "region" {
  type    = string
  default = "$REGION"
}

variable "zone" {
  type    = string
  default = "$ZONE"
}

variable "project_id" {
  type    = string
  default = "$PROJECT_ID"
}
EOF

cat > modules/storage/outputs.tf <<'EOF'
output "bucket_name" {
  value = google_storage_bucket.tf_bucket.name
}
EOF

###############################################################################
# TASK 1 - ROOT MAIN.TF
###############################################################################

cat > main.tf <<EOF
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

module "instances" {
  source     = "./modules/instances"
  region     = var.region
  zone       = var.zone
  project_id = var.project_id
}
EOF

###############################################################################
# TASK 1 - INITIALIZE
###############################################################################

log "Task 1: Initializing Terraform..."

terraform fmt -recursive
terraform init -upgrade
terraform validate

ok "Task 1 complete."

###############################################################################
# TASK 2 - INSTANCE CONFIGURATION
###############################################################################

log "Task 2: Creating minimal instance configuration..."

cat > modules/instances/instances.tf <<EOF
resource "google_compute_instance" "tf-instance-1" {
  name         = "tf-instance-1"
  machine_type = "$MACHINE_1"

  boot_disk {
    initialize_params {
      image = "$IMAGE_1"
    }
  }

  network_interface {
    network = "default"
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
  EOT

  allow_stopping_for_update = true
}

resource "google_compute_instance" "tf-instance-2" {
  name         = "tf-instance-2"
  machine_type = "$MACHINE_2"

  boot_disk {
    initialize_params {
      image = "$IMAGE_2"
    }
  }

  network_interface {
    network = "default"
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
  EOT

  allow_stopping_for_update = true
}
EOF

terraform fmt -recursive
terraform validate

###############################################################################
# IMPORT INSTANCE 1
###############################################################################

if terraform state list 2>/dev/null | grep -Fxq \
    'module.instances.google_compute_instance.tf-instance-1'; then

    warn "tf-instance-1 is already in Terraform state."

else
    log "Importing tf-instance-1..."

    terraform import -input=false \
        'module.instances.google_compute_instance.tf-instance-1' \
        "projects/$PROJECT_ID/zones/$ZONE/instances/tf-instance-1"
fi

###############################################################################
# IMPORT INSTANCE 2
###############################################################################

if terraform state list 2>/dev/null | grep -Fxq \
    'module.instances.google_compute_instance.tf-instance-2'; then

    warn "tf-instance-2 is already in Terraform state."

else
    log "Importing tf-instance-2..."

    terraform import -input=false \
        'module.instances.google_compute_instance.tf-instance-2' \
        "projects/$PROJECT_ID/zones/$ZONE/instances/tf-instance-2"
fi

###############################################################################
# TASK 2 APPLY
###############################################################################

log "Applying Task 2..."

terraform plan
terraform apply -auto-approve

ok "Task 2 complete."

###############################################################################
# TASK 3 - STORAGE MODULE
###############################################################################

log "Task 3: Creating Cloud Storage bucket..."

cat > modules/storage/storage.tf <<EOF
resource "google_storage_bucket" "tf_bucket" {
  name                        = "$BUCKET_NAME"
  location                    = "US"
  force_destroy               = true
  uniform_bucket_level_access = true
}
EOF

cat >> main.tf <<EOF

module "storage" {
  source     = "./modules/storage"
  region     = var.region
  zone       = var.zone
  project_id = var.project_id
}
EOF

terraform fmt -recursive
terraform init
terraform validate

###############################################################################
# CREATE BUCKET
###############################################################################

terraform plan
terraform apply -auto-approve

###############################################################################
# VERIFY BUCKET
###############################################################################

gcloud storage buckets describe "gs://$BUCKET_NAME" \
    --project="$PROJECT_ID" >/dev/null 2>&1 \
    || die "Terraform reported success but bucket verification failed."

ok "Bucket created and verified."

###############################################################################
# TASK 3 - CONFIGURE GCS BACKEND
###############################################################################

log "Configuring GCS remote backend..."

python3 - "$BUCKET_NAME" <<'PY'
from pathlib import Path
import sys

bucket = sys.argv[1]

p = Path("main.tf")
s = p.read_text()

backend = f'''terraform {{
  backend "gcs" {{
    bucket = "{bucket}"
    prefix = "terraform/state"
  }}

'''

if 'backend "gcs"' in s:
    raise SystemExit("GCS backend already exists in main.tf.")

if not s.startswith("terraform {"):
    raise SystemExit("Terraform block not found.")

s = s.replace("terraform {\n", backend, 1)

p.write_text(s)
PY

terraform fmt -recursive

###############################################################################
# MIGRATE LOCAL STATE -> GCS
###############################################################################

log "Migrating Terraform state to the GCS backend..."

printf 'yes\n' | terraform init -migrate-state

ok "Task 3 complete."

###############################################################################
# TASK 4 - MODIFY EXISTING INSTANCES
###############################################################################

log "Task 4: Updating both existing instances to e2-standard-2..."

python3 <<'PY'
from pathlib import Path

p = Path("modules/instances/instances.tf")
s = p.read_text()

s = s.replace(
    'machine_type = "' + s.split('machine_type = "')[1].split('"')[0] + '"',
    'machine_type = "e2-standard-2"',
    1
)

s = s.replace(
    'machine_type = "' + s.split('machine_type = "')[1].split('"')[0] + '"',
    'machine_type = "e2-standard-2"',
    1
)

p.write_text(s)
PY

###############################################################################
# ADD THIRD INSTANCE
###############################################################################

cat >> modules/instances/instances.tf <<EOF

resource "google_compute_instance" "tf-instance-3" {
  name         = "$INSTANCE_3"
  machine_type = "e2-standard-2"

  boot_disk {
    initialize_params {
      image = "$IMAGE_1"
    }
  }

  network_interface {
    network = "default"
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
  EOT

  allow_stopping_for_update = true
}
EOF

terraform fmt -recursive
terraform validate

###############################################################################
# TASK 4 APPLY
###############################################################################

terraform plan
terraform apply -auto-approve

###############################################################################
# VERIFY THIRD VM
###############################################################################

gcloud compute instances describe "$INSTANCE_3" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" >/dev/null 2>&1 \
    || die "Third instance was not found after Terraform apply."

ok "Task 4 complete."

###############################################################################
# TASK 5 - REMOVE THIRD INSTANCE FROM CONFIGURATION
###############################################################################

log "Task 5: Removing third instance from Terraform configuration..."

python3 <<'PY'
from pathlib import Path
import re

p = Path("modules/instances/instances.tf")
s = p.read_text()

pattern = r'\nresource "google_compute_instance" "tf-instance-3" \{.*?\n\}\s*$'

new_s, count = re.subn(pattern, '', s, flags=re.S)

if count != 1:
    raise SystemExit("Could not locate exactly one third-instance block.")

p.write_text(new_s.rstrip() + "\n")
PY

terraform fmt -recursive
terraform validate

terraform plan
terraform apply -auto-approve

###############################################################################
# VERIFY THIRD VM IS GONE
###############################################################################

if gcloud compute instances describe "$INSTANCE_3" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" >/dev/null 2>&1; then

    die "Task 5 failed: third instance still exists."
fi

ok "Task 5 complete."

###############################################################################
# TASK 6 - NETWORK MODULE
###############################################################################

log "Task 6: Adding Terraform Registry Network Module 10.0.0..."

cat >> main.tf <<EOF

module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "10.0.0"

  project_id   = var.project_id
  network_name = "$VPC_NAME"
  routing_mode = "GLOBAL"

  subnets = [
    {
      subnet_name   = "subnet-01"
      subnet_ip     = "10.10.10.0/24"
      subnet_region = var.region
    },
    {
      subnet_name   = "subnet-02"
      subnet_ip     = "10.10.20.0/24"
      subnet_region = var.region
    }
  ]
}
EOF

terraform fmt -recursive
terraform init -upgrade
terraform validate

###############################################################################
# CREATE VPC + SUBNETS
###############################################################################

terraform plan
terraform apply -auto-approve

###############################################################################
# VERIFY NETWORK
###############################################################################

gcloud compute networks describe "$VPC_NAME" \
    --project="$PROJECT_ID" >/dev/null 2>&1 \
    || die "VPC '$VPC_NAME' was not created."

gcloud compute networks subnets describe subnet-01 \
    --region="$REGION" \
    --project="$PROJECT_ID" >/dev/null 2>&1 \
    || die "subnet-01 was not created."

gcloud compute networks subnets describe subnet-02 \
    --region="$REGION" \
    --project="$PROJECT_ID" >/dev/null 2>&1 \
    || die "subnet-02 was not created."

ok "VPC and both subnets verified."

###############################################################################
# UPDATE VM1 -> subnet-01
# UPDATE VM2 -> subnet-02
###############################################################################

log "Connecting tf-instance-1 to subnet-01..."
log "Connecting tf-instance-2 to subnet-02..."

python3 - "$VPC_NAME" <<'PY'
from pathlib import Path
import sys

vpc = sys.argv[1]

p = Path("modules/instances/instances.tf")
s = p.read_text()

old = '''network_interface {
    network = "default"
  }'''

new1 = '''network_interface {
    network    = "''' + vpc + '''"
    subnetwork = "subnet-01"
  }'''

new2 = '''network_interface {
    network    = "''' + vpc + '''"
    subnetwork = "subnet-02"
  }'''

if s.count(old) != 2:
    raise SystemExit(
        f"Expected exactly 2 default network_interface blocks, found {s.count(old)}."
    )

s = s.replace(old, new1, 1)
s = s.replace(old, new2, 1)

p.write_text(s)
PY

terraform fmt -recursive
terraform validate

###############################################################################
# APPLY NETWORK CHANGES
###############################################################################

terraform plan
terraform apply -auto-approve

ok "Task 6 complete."

###############################################################################
# TASK 7 - FIREWALL
###############################################################################

log "Task 7: Creating HTTP firewall rule..."

cat >> main.tf <<EOF

resource "google_compute_firewall" "tf-firewall" {
  name    = "tf-firewall"
  network = "projects/$PROJECT_ID/global/networks/$VPC_NAME"

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
}
EOF

terraform fmt -recursive
terraform validate

###############################################################################
# APPLY FIREWALL
###############################################################################

terraform plan
terraform apply -auto-approve

###############################################################################
# VERIFY FIREWALL
###############################################################################

gcloud compute firewall-rules describe tf-firewall \
    --project="$PROJECT_ID" >/dev/null 2>&1 \
    || die "tf-firewall was not created."

ok "Task 7 complete."

###############################################################################
# FINAL STATE CHECK
###############################################################################

echo
echo "============================================================"
echo " FINAL VERIFICATION"
echo "============================================================"

log "Terraform state:"
terraform state list

echo
log "Checking required resources..."

terraform state list | grep -Fx \
    'module.instances.google_compute_instance.tf-instance-1' \
    >/dev/null \
    || die "tf-instance-1 missing from Terraform state."

terraform state list | grep -Fx \
    'module.instances.google_compute_instance.tf-instance-2' \
    >/dev/null \
    || die "tf-instance-2 missing from Terraform state."

terraform state list | grep -Fx \
    'module.storage.google_storage_bucket.tf_bucket' \
    >/dev/null \
    || die "Storage bucket missing from Terraform state."

terraform state list | grep -Fx \
    'module.vpc.google_compute_network.network' \
    >/dev/null \
    || die "VPC missing from Terraform state."

terraform state list | grep -Fx \
    'google_compute_firewall.tf-firewall' \
    >/dev/null \
    || die "Firewall missing from Terraform state."

if terraform state list | grep -Fq 'tf-instance-3'; then
    die "Third instance is still present in Terraform state."
fi

echo
echo "============================================================"
echo -e "${GREEN} ALL TASKS COMPLETED SUCCESSFULLY ${NC}"
echo "============================================================"
echo
echo "Project : $PROJECT_ID"
echo "Region  : $REGION"
echo "Zone    : $ZONE"
echo "Bucket  : $BUCKET_NAME"
echo "VPC     : $VPC_NAME"
echo
echo "Task 1  : COMPLETE"
echo "Task 2  : COMPLETE"
echo "Task 3  : COMPLETE"
echo "Task 4  : COMPLETE"
echo "Task 5  : COMPLETE"
echo "Task 6  : COMPLETE"
echo "Task 7  : COMPLETE"
echo
echo "Now use Google Skills Boost -> Check my progress."
echo
