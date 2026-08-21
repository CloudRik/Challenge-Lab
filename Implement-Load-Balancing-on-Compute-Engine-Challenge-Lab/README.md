# Analyze Images with the Cloud Vision API: Challenge Lab

> ⚡ **Automated Speedrun Solution for Google Cloud Skills Boost**

---

## ⚠️ Disclaimer & Important Notice

> **Please Read Carefully Before Running the Script:**
>
> 1. **Educational Purpose Only:** This script and repository are created strictly for **educational and demonstration purposes**.
> 2. **Understand the Concepts:** It is highly recommended to read through the lab instructions first and understand what actually do behind the scenes.
> 3. **Fair Usage:** Use this script to speed up your workflow or troubleshoot errors, but make sure to learn the underlying Google Cloud concepts.

---

## 🚀 Quick Execution (1-Click Command)

Open **Google Cloud Shell** in your active lab session and run the following command:

```bash
#!/bin/bash

# =========================
# USER INPUT
# =========================

read -p "Enter your Google Cloud Project ID: " PROJECT_ID
read -p "Enter your Region: " REGION
read -p "Enter your Zone: " ZONE

echo ""
echo "Project ID : $PROJECT_ID"
echo "Region     : $REGION"
echo "Zone       : $ZONE"
echo ""

gcloud config set project "$PROJECT_ID"
gcloud config set compute/region "$REGION"
gcloud config set compute/zone "$ZONE"

# =========================
# TASK 1
# =========================

gcloud compute instances create web1 \
  --zone="$ZONE" \
  --machine-type=e2-small \
  --tags=network-lb-tag \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install apache2 -y
service apache2 restart
echo "<h3>Web Server: web1</h3>" | tee /var/www/html/index.html'

gcloud compute instances create web2 \
  --zone="$ZONE" \
  --machine-type=e2-small \
  --tags=network-lb-tag \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install apache2 -y
service apache2 restart
echo "<h3>Web Server: web2</h3>" | tee /var/www/html/index.html'

gcloud compute instances create web3 \
  --zone="$ZONE" \
  --machine-type=e2-small \
  --tags=network-lb-tag \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install apache2 -y
service apache2 restart
echo "<h3>Web Server: web3</h3>" | tee /var/www/html/index.html'

gcloud compute firewall-rules create www-firewall-network-lb \
  --network=default \
  --target-tags=network-lb-tag \
  --allow=tcp:80

# =========================
# TASK 2
# =========================

gcloud compute addresses create network-lb-ip-1 \
  --region="$REGION"

gcloud compute http-health-checks create basic-check

gcloud compute target-pools create www-pool \
  --region="$REGION" \
  --http-health-check=basic-check

gcloud compute target-pools add-instances www-pool \
  --instances=web1,web2,web3 \
  --instances-zone="$ZONE" \
  --region="$REGION"

gcloud compute forwarding-rules create www-rule \
  --region="$REGION" \
  --ports=80 \
  --address=network-lb-ip-1 \
  --target-pool=www-pool

# =========================
# TASK 3
# =========================

gcloud compute instance-templates create lb-backend-template \
  --machine-type=e2-medium \
  --tags=allow-health-check \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install apache2 -y
service apache2 restart
echo "<h3>Page served from: $(hostname)</h3>" | tee /var/www/html/index.html'

gcloud compute instance-groups managed create lb-backend-group \
  --template=lb-backend-template \
  --size=2 \
  --zone="$ZONE"

gcloud compute instance-groups managed set-named-ports lb-backend-group \
  --named-ports=http:80 \
  --zone="$ZONE"

gcloud compute firewall-rules create fw-allow-health-check \
  --network=default \
  --action=ALLOW \
  --direction=INGRESS \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --target-tags=allow-health-check \
  --rules=tcp:80

gcloud compute addresses create lb-ipv4-1 \
  --global \
  --ip-version=IPV4

gcloud compute health-checks create http http-basic-check \
  --port=80

gcloud compute backend-services create web-backend-service \
  --protocol=HTTP \
  --port-name=http \
  --health-checks=http-basic-check \
  --global

gcloud compute backend-services add-backend web-backend-service \
  --instance-group=lb-backend-group \
  --instance-group-zone="$ZONE" \
  --global

gcloud compute url-maps create web-map-http \
  --default-service=web-backend-service

gcloud compute target-http-proxies create http-lb-proxy \
  --url-map=web-map-http

gcloud compute forwarding-rules create http-content-rule \
  --global \
  --target-http-proxy=http-lb-proxy \
  --address=lb-ipv4-1 \
  --ports=80

echo "===== LAB COMPLEAT SUCCESSFULLY ====="
