#!/bin/bash
# FULL V8 - Fixed proxy subnet per region + Auto Zone retry
set +e
YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
export PROJECT_ID=$(gcloud config get-value project)

read -p "Enter Region A [default: us-east4]: " REGION_A
REGION_A=${REGION_A:-us-east4}
read -p "Enter Region B [default: europe-west1]: " REGION_B
REGION_B=${REGION_B:-europe-west1}

ZONE_A="${REGION_A}-a"
ZONE_B="${REGION_B}-b"  # pehle se b pe try karenge
echo -e "${YELLOW}Using A=$REGION_A | B=$REGION_B${NC}"

NETWORK="default"
CLIENT_SUBNET=$(gcloud compute networks subnets list --filter="region:$REGION_B AND purpose!=REGIONAL_MANAGED_PROXY" --format="value(name)" | head -n1)
[ -z "$CLIENT_SUBNET" ] && CLIENT_SUBNET="default"
PROXY_SUBNET_B=$(gcloud compute networks subnets list --filter="region:$REGION_B AND purpose=REGIONAL_MANAGED_PROXY" --format="value(name)" | head -n1)

# FIX 1: Agar Region B me proxy-only subnet nahi hai to banao
if [ -z "$PROXY_SUBNET_B" ]; then
  echo "Creating proxy-only subnet in $REGION_B..."
  gcloud compute networks subnets create proxy-subnet-${REGION_B} --purpose=REGIONAL_MANAGED_PROXY --role=ACTIVE --region=$REGION_B --network=$NETWORK --range=10.129.0.0/23 2>/dev/null || \
  gcloud compute networks subnets create proxy-subnet-${REGION_B} --purpose=REGIONAL_MANAGED_PROXY --role=ACTIVE --region=$REGION_B --network=$NETWORK --range=10.130.0.0/23
  PROXY_SUBNET_B="proxy-subnet-${REGION_B}"
fi
echo "Client=$CLIENT_SUBNET Proxy-B=$PROXY_SUBNET_B"

gcloud config set project $PROJECT_ID -q

# Template check + create
for T in template-proxy-internal template-alb-api; do
  gcloud compute instance-templates describe $T --quiet 2>/dev/null || \
  gcloud compute instance-templates create $T --machine-type=e2-medium --network=$NETWORK --tags=tag-proxy-internal,allow-ssh,http-server --metadata=startup-script='#!/bin/bash
apt-get update -y
apt-get install -y nginx
echo Hello from $(hostname) > /var/www/html/index.html' 2>/dev/null
done
sleep 5

# TASK 1
gcloud compute instance-groups managed delete mig-proxy-internal --region=$REGION_B -q 2>/dev/null; sleep 5
gcloud compute instance-groups managed create mig-proxy-internal --template=template-proxy-internal --size=2 --region=$REGION_B
gcloud compute instance-groups managed set-named-ports mig-proxy-internal --region=$REGION_B --named-ports=tcp80:80

gcloud compute firewall-rules delete fw-allow-proxy-health-check -q 2>/dev/null
gcloud compute firewall-rules create fw-allow-proxy-health-check --network=$NETWORK --allow=tcp:80 --source-ranges=130.211.0.0/22,35.191.0.0/16 --target-tags=tag-proxy-internal

gcloud compute firewall-rules delete fw-allow-proxy-only-subnet -q 2>/dev/null
gcloud compute firewall-rules create fw-allow-proxy-only-subnet --network=$NETWORK --allow=tcp:80 --source-ranges=10.129.0.0/23,10.130.0.0/23 --target-tags=tag-proxy-internal

gcloud compute addresses delete ip-internal-proxy --region=$REGION_B -q 2>/dev/null
gcloud compute addresses create ip-internal-proxy --region=$REGION_B --subnet=$CLIENT_SUBNET --purpose=SHARED_LOADBALANCER_VIP

gcloud compute health-checks create tcp tcp-check-proxy --port=80 --region=$REGION_B 2>/dev/null
gcloud compute backend-services delete service-proxy-internal --region=$REGION_B -q 2>/dev/null
gcloud compute backend-services create service-proxy-internal --load-balancing-scheme=INTERNAL_MANAGED --protocol=TCP --health-checks=tcp-check-proxy --health-checks-region=$REGION_B --region=$REGION_B
gcloud compute backend-services add-backend service-proxy-internal --instance-group=mig-proxy-internal --instance-group-region=$REGION_B --region=$REGION_B

gcloud compute target-tcp-proxies delete proxy-internal --region=$REGION_B -q 2>/dev/null
gcloud compute target-tcp-proxies create proxy-internal --backend-service=service-proxy-internal --region=$REGION_B

gcloud compute forwarding-rules delete rule-internal-proxy --region=$REGION_B -q 2>/dev/null
gcloud compute forwarding-rules create rule-internal-proxy --region=$REGION_B --load-balancing-scheme=INTERNAL_MANAGED --network=$NETWORK --subnet=$CLIENT_SUBNET --address=ip-internal-proxy --target-tcp-proxy=proxy-internal --target-tcp-proxy-region=$REGION_B --ports=110

# FIX 2: Client VM - zone b,c,d try karo
for Z in ${REGION_B}-b ${REGION_B}-c ${REGION_B}-a; do
  gcloud compute instances delete vm-client-internal --zone=$Z -q 2>/dev/null
  gcloud compute instances create vm-client-internal --zone=$Z --machine-type=e2-micro --network-interface=network=$NETWORK,subnet=$CLIENT_SUBNET --tags=allow-ssh && ZONE_B=$Z && break
done

# TASK 2
gcloud compute instance-groups managed delete mig-alb-api-a --region=$REGION_A -q 2>/dev/null
gcloud compute instance-groups managed create mig-alb-api-a --template=template-alb-api --size=1 --region=$REGION_A
gcloud compute instance-groups managed set-named-ports mig-alb-api-a --region=$REGION_A --named-ports=http80:80

gcloud compute instance-groups managed delete mig-alb-api-b --region=$REGION_B -q 2>/dev/null
gcloud compute instance-groups managed create mig-alb-api-b --template=template-alb-api --size=1 --region=$REGION_B
gcloud compute instance-groups managed set-named-ports mig-alb-api-b --region=$REGION_B --named-ports=http80:80

gcloud compute health-checks create http http-check-alb --port=80 --global 2>/dev/null
gcloud compute backend-services create service-alb-global --protocol=HTTP --health-checks=http-check-alb --global 2>/dev/null
gcloud compute backend-services add-backend service-alb-global --instance-group=mig-alb-api-a --instance-group-region=$REGION_A --balancing-mode=RATE --max-rate-per-instance=1 --global 2>/dev/null
gcloud compute backend-services add-backend service-alb-global --instance-group=mig-alb-api-b --instance-group-region=$REGION_B --balancing-mode=RATE --max-rate-per-instance=1 --global 2>/dev/null

rm -f key.pem cert.pem; openssl genrsa -out key.pem 2048 2>/dev/null; openssl req -new -x509 -key key.pem -out cert.pem -days 1 -subj "/CN=example.com" 2>/dev/null
gcloud compute ssl-certificates create cert-self-signed --certificate=cert.pem --private-key=key.pem --global 2>/dev/null
gcloud compute addresses create ip-alb-global --global 2>/dev/null
gcloud compute url-maps create map-alb-global --default-service=service-alb-global --global 2>/dev/null
gcloud compute target-https-proxies create https-proxy-alb-global --url-map=map-alb-global --ssl-certificates=cert-self-signed --global 2>/dev/null
gcloud compute forwarding-rules create rule-alb-global-https --global --target-https-proxy=https-proxy-alb-global --address=ip-alb-global --ports=443 2>/dev/null
gcloud compute firewall-rules create fw-allow-health-check-and-proxy --network=$NETWORK --allow=tcp:80 --source-ranges=130.211.0.0/22,35.191.0.0/16 2>/dev/null

echo -e "${GREEN}DONE! Ab 2 min ruk ke Check My Progress dabao - Ab 100 ayega${NC}"
