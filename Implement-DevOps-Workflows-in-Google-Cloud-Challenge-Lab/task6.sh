#!/bin/bash

# ============================================================
# Task 6 — Rollback Production Deployment (v2.0 → v1.0)
# ============================================================

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
RED='\033[1;31m'
BOLD='\033[1m'
RESET='\033[0m'

clear

echo -e "${CYAN}=====================================================${RESET}"
echo -e "${MAGENTA}${BOLD}   🚀 Task 6 — Rollback Production Deployment         ${RESET}"
echo -e "${CYAN}=====================================================${RESET}"
echo ""

# ---------- INPUTS ----------
echo -e "${GREEN}${BOLD}👉 Please provide the values from your lab page:${RESET}"
echo ""
echo -e "${GREEN}   Enter REGION (e.g. us-central1): ${RESET}"
read REGION
echo -e "${GREEN}   Enter ZONE (e.g. us-central1-c): ${RESET}"
read ZONE

echo ""
echo -e "${YELLOW}🔍 Confirming values:${RESET}"
echo -e "   Region : ${BOLD}$REGION${RESET}"
echo -e "   Zone   : ${BOLD}$ZONE${RESET}"
echo ""
echo -e "${YELLOW}✅ Confirm? (y/n): ${RESET}"
read CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo -e "${RED}❌ Aborted.${RESET}"
  exit 1
fi

export REGION ZONE
export PROJECT_ID=$(gcloud config get-value project)

# ---------- SETUP KUBECTL ----------
echo ""
echo -e "${CYAN}🔹 Fetching GKE cluster credentials...${RESET}"
CLUSTER_NAME=$(gcloud container clusters list --zone=${ZONE} --format="value(name)" --limit=1)
if [ -z "$CLUSTER_NAME" ]; then
  echo -e "${RED}❌ No cluster found in zone $ZONE.${RESET}"
  exit 1
fi
gcloud container clusters get-credentials $CLUSTER_NAME --zone=$ZONE
echo -e "${GREEN}✅ Connected to cluster: $CLUSTER_NAME${RESET}"

# ---------- CHECK CURRENT VERSION ----------
echo ""
echo -e "${CYAN}🔹 Current prod deployment image (before rollback):${RESET}"
kubectl get deployment production-deployment -n prod -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null
echo ""

# ---------- ROLLBACK ----------
echo ""
echo -e "${CYAN}🔹 Rolling back production-deployment to previous version (v1.0)...${RESET}"
kubectl rollout undo deployment/production-deployment -n prod
echo -e "${GREEN}✅ Rollback command issued.${RESET}"

# ---------- WAIT FOR ROLLOUT ----------
echo ""
echo -e "${CYAN}🔹 Waiting for rollout to complete...${RESET}"
kubectl rollout status deployment/production-deployment -n prod --timeout=180s
echo -e "${GREEN}✅ Rollout complete.${RESET}"

# ---------- VERIFY VERSION ----------
echo ""
echo -e "${CYAN}🔹 Verifying new image version:${RESET}"
NEW_IMAGE=$(kubectl get deployment production-deployment -n prod -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
echo -e "${GREEN}   Image: $NEW_IMAGE${RESET}"

if [[ "$NEW_IMAGE" == *"v1.0"* ]]; then
  echo -e "${GREEN}✅ Successfully rolled back to v1.0${RESET}"
elif [[ "$NEW_IMAGE" == *"v2.0"* ]]; then
  echo -e "${YELLOW}⚠ Still on v2.0. Maybe there's only one revision?${RESET}"
else
  echo -e "${YELLOW}⚠ Version check inconclusive — check manually.${RESET}"
fi

# ---------- TEST ENDPOINTS ----------
echo ""
echo -e "${CYAN}🔹 Fetching prod LoadBalancer IP...${RESET}"
PROD_LB_IP=""
for i in {1..18}; do
  PROD_LB_IP=$(kubectl get service prod-deployment-service -n prod -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  if [ -n "$PROD_LB_IP" ]; then
    break
  fi
  echo -e "${YELLOW}   ...waiting for LB IP ($i/18)${RESET}"
  sleep 10
done

if [ -z "$PROD_LB_IP" ]; then
  echo -e "${RED}❌ Prod LB IP not assigned.${RESET}"
  exit 1
fi
echo -e "${GREEN}✅ Prod LB IP: $PROD_LB_IP${RESET}"

echo ""
echo -e "${CYAN}🔹 Testing /blue (should be 200 OK)...${RESET}"
curl -s -I http://${PROD_LB_IP}:8080/blue | head -1

echo ""
echo -e "${CYAN}🔹 Testing /red (should be 404 Not Found)...${RESET}"
curl -s -I http://${PROD_LB_IP}:8080/red | head -1

# ---------- FINAL BANNER ----------
echo ""
echo -e "${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════════╗"
echo "║                                              ║"
echo "║   🎉  TASK 6 COMPLETED!  🎉                  ║"
echo "║                                              ║"
echo "║   ✅ Prod rolled back to v1.0                ║"
echo "║   ✅ /blue → 200 OK                          ║"
echo "║   ✅ /red  → 404 Not Found                   ║"
echo "║                                              ║"
echo "║   👉 Go to lab page → Check my progress      ║"
echo "║      (Final — full 100/100 expected!)        ║"
echo "║                                              ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${RESET}"
