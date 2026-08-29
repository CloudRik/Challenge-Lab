#!/usr/bin/env bash
set -euo pipefail

# GSP345 - Build Infrastructure with Terraform on Google Cloud
# Before running:
#   export BUCKET_NAME="..."
#   export INSTANCE_NAME="..."
#   export VPC_NAME="..."
#   export ZONE="..."
# PROJECT_ID is read from the active gcloud project.
# REGION is derived from ZONE unless explicitly set.

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
BUCKET_NAME="${BUCKET_NAME:-}"
INSTANCE_NAME="${INSTANCE_NAME:-}"
VPC_NAME="${VPC_NAME:-}"
ZONE="${ZONE:-}"
REGION="${REGION:-}"

die(){ echo "ERROR: $*" >&2; exit 1; }
need(){ [[ -n "${!1:-}" ]] || die "Set $1 before running."; }

[[ -n "$PROJECT_ID" && "$PROJECT_ID" != "(unset)" ]] || die "No active gcloud project."
need BUCKET_NAME
need INSTANCE_NAME
need VPC_NAME
need ZONE
[[ -n "$REGION" ]] || REGION="${ZONE%-*}"

echo "Project=$PROJECT_ID  Region=$REGION  Zone=$ZONE"
echo "Bucket=$BUCKET_NAME  Third instance=$INSTANCE_NAME  VPC=$VPC_NAME"

# Discover the two lab-created VMs.
for VM in tf-instance-1 tf-instance-2; do
  gcloud compute instances describe "$VM" --zone="$ZONE" >/dev/null ||
    die "$VM was not found in zone $ZONE"
done

get_image() {
  local vm="$1" disk
  disk="$(gcloud compute instances describe "$vm" --zone="$ZONE"     --format='value(disks[0].deviceName)')"
  gcloud compute disks describe "$disk" --zone="$ZONE"     --format='value(sourceImage)'
}

MACHINE_1="$(gcloud compute instances describe tf-instance-1 --zone="$ZONE"   --format='value(machineType.basename())')"
MACHINE_2="$(gcloud compute instances describe tf-instance-2 --zone="$ZONE"   --format='value(machineType.basename())')"
IMAGE_1="$(get_image tf-instance-1)"
IMAGE_2="$(get_image tf-instance-2)"

echo "Detected tf-instance-1: $MACHINE_1 / $IMAGE_1"
echo "Detected tf-instance-2: $MACHINE_2 / $IMAGE_2"

mkdir -p modules/instances modules/storage

cat > variables.tf <<EOF
variable "region"     { default = "$REGION" }
variable "zone"       { default = "$ZONE" }
variable "project_id" { default = "$PROJECT_ID" }
EOF

cat > modules/instances/variables.tf <<EOF
variable "region"     { default = "$REGION" }
variable "zone"       { default = "$ZONE" }
variable "project_id" { default = "$PROJECT_ID" }
EOF

cat > modules/instances/outputs.tf <<'EOF'
EOF

cat > modules/storage/variables.tf <<EOF
variable "region"     { default = "$REGION" }
variable "zone"       { default = "$ZONE" }
variable "project_id" { default = "$PROJECT_ID" }
EOF

cat > modules/storage/outputs.tf <<'EOF'
output "bucket_name" {
  value = google_storage_bucket.tf_bucket.name
}
EOF

cat > main.tf <<EOF
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

cat > modules/instances/instances.tf <<EOF
resource "google_compute_instance" "tf-instance-1" {
  name         = "tf-instance-1"
  machine_type = "$MACHINE_1"

  boot_disk {
    initialize_params { image = "$IMAGE_1" }
  }

  network_interface { network = "default" }

  metadata_startup_script = <<-EOT
    #!/bin/bash
  EOT
  allow_stopping_for_update = true
}

resource "google_compute_instance" "tf-instance-2" {
  name         = "tf-instance-2"
  machine_type = "$MACHINE_2"

  boot_disk {
    initialize_params { image = "$IMAGE_2" }
  }

  network_interface { network = "default" }

  metadata_startup_script = <<-EOT
    #!/bin/bash
  EOT
  allow_stopping_for_update = true
}
EOF

cat > modules/storage/storage.tf <<EOF
resource "google_storage_bucket" "tf_bucket" {
  name                        = "$BUCKET_NAME"
  location                    = "US"
  force_destroy               = true
  uniform_bucket_level_access = true
}
EOF

# Task 1 / Task 2
terraform fmt -recursive
terraform init -upgrade
terraform validate

terraform import -input=false   'module.instances.google_compute_instance.tf-instance-1'   "projects/$PROJECT_ID/zones/$ZONE/instances/tf-instance-1"

terraform import -input=false   'module.instances.google_compute_instance.tf-instance-2'   "projects/$PROJECT_ID/zones/$ZONE/instances/tf-instance-2"

# Task 3: manage the supplied bucket, then migrate state to GCS.
cat >> main.tf <<'EOF'

module "storage" {
  source = "./modules/storage"
}
EOF

terraform fmt -recursive
terraform init
terraform import -input=false   'module.storage.google_storage_bucket.tf_bucket'   "$BUCKET_NAME" || true

terraform plan
terraform apply -auto-approve

python3 - <<PY
from pathlib import Path
p = Path("main.tf")
s = p.read_text()
old = '''terraform {
  required_providers {'''
new = '''terraform {
  backend "gcs" {
    bucket = "$BUCKET_NAME"
    prefix = "terraform/state"
  }

  required_providers {'''
if old not in s:
    raise SystemExit("Could not locate Terraform provider block.")
p.write_text(s.replace(old, new, 1))
PY

terraform fmt -recursive
terraform init -migrate-state -force-copy

# Task 4: both existing VMs -> e2-standard-2, plus third VM.
cat >> modules/instances/instances.tf <<EOF

resource "google_compute_instance" "$INSTANCE_NAME" {
  name         = "$INSTANCE_NAME"
  machine_type = "e2-standard-2"
  zone         = "$ZONE"

  boot_disk {
    initialize_params { image = "$IMAGE_1" }
  }

  network_interface { network = "default" }
  allow_stopping_for_update = true
}
EOF

python3 - <<PY
from pathlib import Path
p = Path("modules/instances/instances.tf")
s = p.read_text()
s = s.replace('machine_type = "$MACHINE_1"', 'machine_type = "e2-standard-2"', 1)
s = s.replace('machine_type = "$MACHINE_2"', 'machine_type = "e2-standard-2"', 1)
p.write_text(s)
PY

terraform fmt -recursive
terraform validate
terraform plan
terraform apply -auto-approve

echo
echo "============================================================"
echo "TASK 4 COMPLETE."
echo "Click Check my progress for Task 4, then press ENTER here."
echo "============================================================"
read -r

# Task 5: remove third VM from configuration and apply.
python3 - <<PY
from pathlib import Path
p = Path("modules/instances/instances.tf")
s = p.read_text()
marker = 'resource "google_compute_instance" "$INSTANCE_NAME"'
i = s.find(marker)
if i < 0:
    raise SystemExit("Third instance block not found.")
p.write_text(s[:i].rstrip() + "\n")
PY

terraform fmt -recursive
terraform plan
terraform apply -auto-approve

# Task 6: Registry Network Module 10.0.0.
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
terraform plan
terraform apply -auto-approve

# Connect instance-1 -> subnet-01 and instance-2 -> subnet-02.
python3 - <<PY
from pathlib import Path
p = Path("modules/instances/instances.tf")
s = p.read_text()
old = '''network_interface { network = "default" }'''
new1 = '''network_interface {
    network    = "$VPC_NAME"
    subnetwork = "subnet-01"
  }'''
new2 = '''network_interface {
    network    = "$VPC_NAME"
    subnetwork = "subnet-02"
  }'''
if s.count(old) < 2:
    raise SystemExit("Expected two default network_interface blocks.")
s = s.replace(old, new1, 1)
s = s.replace(old, new2, 1)
p.write_text(s)
PY

terraform fmt -recursive
terraform validate
terraform plan
terraform apply -auto-approve

echo
echo "============================================================"
echo "TASK 6 COMPLETE."
echo "Click Check my progress for Task 6, then press ENTER here."
echo "============================================================"
read -r

# Task 7: HTTP firewall.
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
terraform plan
terraform apply -auto-approve

echo
echo "============================================================"
echo "ALL TERRAFORM TASKS COMPLETE."
echo "Click Check my progress for Task 7."
echo "============================================================"
