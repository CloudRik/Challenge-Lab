#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# GSP345 - Build Infrastructure with Terraform on Google Cloud
# Fully automated version
# ============================================================

die() {
    echo
    echo "ERROR: $*" >&2
    exit 1
}

# ============================================================
# AUTO-DETECT PROJECT
# ============================================================

PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"

[[ -n "$PROJECT_ID" && "$PROJECT_ID" != "(unset)" ]] \
    || die "No active Google Cloud project."

echo
echo "============================================================"
echo " GSP345 - Build Infrastructure with Terraform"
echo "============================================================"
echo
echo "Project ID detected:"
echo "$PROJECT_ID"
echo

# ============================================================
# ASK USER FOR LAB VALUES
# ============================================================

echo "Enter the values shown in the Google Skills Boost Lab Setup."
echo "You only need to enter these ONCE."
echo

read -r -p "Bucket Name: " BUCKET_NAME
read -r -p "Third Instance Name: " INSTANCE_NAME
read -r -p "VPC Name: " VPC_NAME
read -r -p "Zone: " ZONE

# Remove accidental spaces
BUCKET_NAME="$(echo "$BUCKET_NAME" | xargs)"
INSTANCE_NAME="$(echo "$INSTANCE_NAME" | xargs)"
VPC_NAME="$(echo "$VPC_NAME" | xargs)"
ZONE="$(echo "$ZONE" | xargs)"

[[ -n "$BUCKET_NAME" ]] || die "Bucket Name cannot be empty."
[[ -n "$INSTANCE_NAME" ]] || die "Instance Name cannot be empty."
[[ -n "$VPC_NAME" ]] || die "VPC Name cannot be empty."
[[ -n "$ZONE" ]] || die "Zone cannot be empty."

REGION="${ZONE%-*}"

echo
echo "============================================================"
echo "Configuration"
echo "============================================================"
echo "Project       : $PROJECT_ID"
echo "Bucket        : $BUCKET_NAME"
echo "Third VM      : $INSTANCE_NAME"
echo "VPC           : $VPC_NAME"
echo "Zone          : $ZONE"
echo "Region        : $REGION"
echo "============================================================"
echo

# ============================================================
# CHECK EXISTING INSTANCES
# ============================================================

echo "[CHECK] Checking pre-created instances..."

for VM in tf-instance-1 tf-instance-2; do

    if ! gcloud compute instances describe "$VM" \
        --zone="$ZONE" >/dev/null 2>&1; then

        die "$VM was not found in zone $ZONE."
    fi

done

echo "[OK] Existing instances found."

# ============================================================
# GET MACHINE TYPE
# ============================================================

get_machine_type() {

    gcloud compute instances describe "$1" \
        --zone="$ZONE" \
        --format='value(machineType.basename())'
}

# ============================================================
# GET BOOT IMAGE
# ============================================================

get_image() {

    local VM="$1"
    local DISK

    DISK="$(
        gcloud compute instances describe "$VM" \
            --zone="$ZONE" \
            --format='value(disks[0].deviceName)'
    )"

    gcloud compute disks describe "$DISK" \
        --zone="$ZONE" \
        --format='value(sourceImage)'
}

MACHINE_1="$(get_machine_type tf-instance-1)"
MACHINE_2="$(get_machine_type tf-instance-2)"

IMAGE_1="$(get_image tf-instance-1)"
IMAGE_2="$(get_image tf-instance-2)"

echo
echo "Detected infrastructure:"
echo "tf-instance-1 -> $MACHINE_1"
echo "tf-instance-2 -> $MACHINE_2"
echo "Image 1      -> $IMAGE_1"
echo "Image 2      -> $IMAGE_2"
echo

# ============================================================
# CREATE DIRECTORY STRUCTURE
# ============================================================

mkdir -p modules/instances
mkdir -p modules/storage

# ============================================================
# ROOT VARIABLES
# ============================================================

cat > variables.tf <<EOF
variable "region" {
  default = "$REGION"
}

variable "zone" {
  default = "$ZONE"
}

variable "project_id" {
  default = "$PROJECT_ID"
}
EOF

# ============================================================
# INSTANCE MODULE VARIABLES
# ============================================================

cat > modules/instances/variables.tf <<EOF
variable "region" {
  default = "$REGION"
}

variable "zone" {
  default = "$ZONE"
}

variable "project_id" {
  default = "$PROJECT_ID"
}
EOF

cat > modules/instances/outputs.tf <<'EOF'
EOF

# ============================================================
# STORAGE MODULE VARIABLES
# ============================================================

cat > modules/storage/variables.tf <<EOF
variable "region" {
  default = "$REGION"
}

variable "zone" {
  default = "$ZONE"
}

variable "project_id" {
  default = "$PROJECT_ID"
}
EOF

cat > modules/storage/outputs.tf <<'EOF'
output "bucket_name" {
  value = google_storage_bucket.tf_bucket.name
}
EOF

# ============================================================
# MAIN.TF
# ============================================================

cat > main.tf <<'EOF'
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.50.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

module "instances" {
  source = "./modules/instances"
}
EOF

# ============================================================
# INSTANCE RESOURCES
# ============================================================

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

# ============================================================
# STORAGE BUCKET
# ============================================================

cat > modules/storage/storage.tf <<EOF
resource "google_storage_bucket" "tf_bucket" {

  name                        = "$BUCKET_NAME"
  location                    = "US"
  force_destroy               = true
  uniform_bucket_level_access = true
}
EOF

# ============================================================
# TASK 1
# ============================================================

echo
echo "============================================================"
echo "TASK 1 - Configuration files"
echo "============================================================"

terraform fmt -recursive
terraform init -upgrade
terraform validate

echo "[OK] Task 1 complete."

# ============================================================
# TASK 2 - IMPORT EXISTING INSTANCES
# ============================================================

echo
echo "============================================================"
echo "TASK 2 - Import infrastructure"
echo "============================================================"

if ! terraform state show \
    'module.instances.google_compute_instance.tf-instance-1' \
    >/dev/null 2>&1; then

    terraform import -input=false \
        'module.instances.google_compute_instance.tf-instance-1' \
        "projects/$PROJECT_ID/zones/$ZONE/instances/tf-instance-1"
fi

if ! terraform state show \
    'module.instances.google_compute_instance.tf-instance-2' \
    >/dev/null 2>&1; then

    terraform import -input=false \
        'module.instances.google_compute_instance.tf-instance-2' \
        "projects/$PROJECT_ID/zones/$ZONE/instances/tf-instance-2"
fi

terraform apply -auto-approve

echo "[OK] Task 2 complete."

# ============================================================
# TASK 3 - STORAGE MODULE
# ============================================================

echo
echo "============================================================"
echo "TASK 3 - Remote backend"
echo "============================================================"

cat >> main.tf <<'EOF'

module "storage" {
  source = "./modules/storage"
}
EOF

terraform fmt -recursive
terraform init -upgrade

if ! terraform state show \
    'module.storage.google_storage_bucket.tf_bucket' \
    >/dev/null 2>&1; then

    terraform import -input=false \
        'module.storage.google_storage_bucket.tf_bucket' \
        "$BUCKET_NAME"
fi

terraform apply -auto-approve

# ============================================================
# ADD GCS BACKEND
# ============================================================

python3 - <<PY
from pathlib import Path

p = Path("main.tf")
s = p.read_text()

if 'backend "gcs"' not in s:

    s = s.replace(
        'terraform {',
        '''terraform {
  backend "gcs" {
    bucket = "$BUCKET_NAME"
    prefix = "terraform/state"
  }
''',
        1
    )

p.write_text(s)
PY

terraform fmt -recursive

echo "Migrating state to GCS..."

printf 'yes\n' | terraform init -migrate-state -force-copy

echo "[OK] Task 3 complete."

# ============================================================
# TASK 4 - MODIFY INSTANCES
# ============================================================

echo
echo "============================================================"
echo "TASK 4 - Modify infrastructure"
echo "============================================================"

python3 - <<PY
from pathlib import Path

p = Path("modules/instances/instances.tf")
s = p.read_text()

s = s.replace(
    'machine_type = "$MACHINE_1"',
    'machine_type = "e2-standard-2"',
    1
)

s = s.replace(
    'machine_type = "$MACHINE_2"',
    'machine_type = "e2-standard-2"',
    1
)

p.write_text(s)
PY

# Add third instance

cat >> modules/instances/instances.tf <<EOF


resource "google_compute_instance" "$INSTANCE_NAME" {

  name         = "$INSTANCE_NAME"
  machine_type = "e2-standard-2"
  zone         = "$ZONE"

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
terraform apply -auto-approve

echo "[OK] Task 4 complete."

# ============================================================
# TASK 5 - DESTROY THIRD INSTANCE
# ============================================================

echo
echo "============================================================"
echo "TASK 5 - Destroy resources"
echo "============================================================"

python3 - <<PY
from pathlib import Path

p = Path("modules/instances/instances.tf")
s = p.read_text()

marker = 'resource "google_compute_instance" "$INSTANCE_NAME"'

start = s.find(marker)

if start == -1:
    raise SystemExit("Third instance resource was not found.")

brace_start = s.find("{", start)

depth = 0
end = None

for i in range(brace_start, len(s)):

    if s[i] == "{":
        depth += 1

    elif s[i] == "}":
        depth -= 1

        if depth == 0:
            end = i + 1
            break

if end is None:
    raise SystemExit("Could not determine third instance block.")

s = s[:start] + s[end:]

p.write_text(s.strip() + "\n")
PY

terraform fmt -recursive
terraform validate
terraform apply -auto-approve

echo "[OK] Task 5 complete."

# ============================================================
# TASK 6 - NETWORK REGISTRY MODULE
# ============================================================

echo
echo "============================================================"
echo "TASK 6 - Network module"
echo "============================================================"

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
terraform apply -auto-approve

# ============================================================
# CONNECT INSTANCES TO SUBNETS
# ============================================================

python3 - <<PY
from pathlib import Path

p = Path("modules/instances/instances.tf")
s = p.read_text()

old = '''network_interface {
    network = "default"
  }'''

new1 = '''network_interface {
    network    = "$VPC_NAME"
    subnetwork = "subnet-01"
  }'''

new2 = '''network_interface {
    network    = "$VPC_NAME"
    subnetwork = "subnet-02"
  }'''

if s.count(old) != 2:
    raise SystemExit(
        "Expected exactly two default network interfaces."
    )

s = s.replace(old, new1, 1)
s = s.replace(old, new2, 1)

p.write_text(s)
PY

terraform fmt -recursive
terraform validate
terraform apply -auto-approve

echo "[OK] Task 6 complete."

# ============================================================
# TASK 7 - FIREWALL
# ============================================================

echo
echo "============================================================"
echo "TASK 7 - Configure firewall"
echo "============================================================"

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
terraform apply -auto-approve

echo "[OK] Task 7 complete."

# ============================================================
# FINAL
# ============================================================

echo
echo "============================================================"
echo "              GSP345 COMPLETE"
echo "============================================================"

echo
echo "Terraform resources:"
terraform state list

echo
echo "Compute instances:"
gcloud compute instances list

echo
echo "VPC:"
gcloud compute networks describe "$VPC_NAME" \
    --format="value(name,routingConfig.routingMode)"

echo
echo "Firewall:"
gcloud compute firewall-rules describe tf-firewall \
    --format="value(name)"

echo
echo "============================================================"
echo " ALL TERRAFORM TASKS FINISHED SUCCESSFULLY"
echo "============================================================"
echo
