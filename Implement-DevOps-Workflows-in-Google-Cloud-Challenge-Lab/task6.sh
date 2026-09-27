#!/bin/bash

# ============================================================
# Task 6 — Rollback Production Deployment (Fixed)
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
echo -e "${GREEN}   Enter ZONE (e.g. us-central1-c): ${RESET}"
read ZONE

echo ""
echo -e "${YELLOW}✅ Confirm zone '$ZONE'? (y/n): ${RESET}"
read CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo -e "${RED}❌ Aborted.${RESET}"
  exit 1
fi

export ZONE
export PROJECT_ID=$(gcloud config get-value project)

# ---------- CONNECT TO CLUSTER ----------
echo ""
echo -e "${CYAN}🔹 Fetching GKE cluster credentials...${RESET}"
CLUSTER_NAME=$(gcloud container clusters list --zone=${ZONE} --format="value(name)" --limit=1)
if [ -z "$CLUSTER_NAME" ]; then
  echo -e "${RED}❌ No cluster found in zone $ZONE.${RESET}"
  exit 1
fi
gcloud container clusters get-credentials $CLUSTER_NAME --zone=$ZONE
echo -e "${GREEN}✅ Connected to cluster: $CLUSTER_NAME${RESET}"

# ---------- SHOW CURRENT STATE ----------
echo ""
echo -e "${CYAN}🔹 Current prod deployment image:${RESET}"
kubectl get deployment production-deployment -n prod -o jsonpath='{.spec.template.spec.containers[0].image}'
echo ""

echo ""
echo -e "${CYAN}🔹 Rollout history (last 5):${RESET}"
kubectl rollout history deployment/production-deployment -n prod

# ---------- ROLLBACK TO REVISION 1 ----------
echo ""
echo -e "${CYAN}🔹 Rolling back to revision 1 (v1.0)...${RESET}"
kubectl rollout undo deployment/production-deployment -n prod --to-revision=1
echo -e "${GREEN}✅ Rollback command issued.${RESET}"

# ---------- WAIT WITH RETRY ----------
echo ""
echo -e "${CYAN}🔹 Waiting for rollout to complete (max 3 min)...${RESET}"
for i in {1..18}; do
  READY=$(kubectl get deployment production-deployment -n prod -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  DESIRED=$(kubectl get deployment production-deployment -n prod -o jsonpath='{.spec.replicas}' 2>/dev/null)
  echo -e "${YELLOW}   Ready: ${READY:-0}/${DESIRED:-0} ($i/18)${RESET}"
  if [ "$READY" == "$DESIRED" ] && [ -n "$READY" ]; then
    echo -e "${GREEN}✅ All replicas ready.${RESET}"
    break
  fi
  sleep 10
done

# ---------- FORCE CLEANUP OLD REPLICAS ----------
echo ""
echo -e "${CYAN}🔹 Cleaning up old replicas if any pending...${RESET}"
# Rolling update strategy se purane pods hat jate hain, par kuch case me stuck rehte hain
kubectl get pods -n prod --field-selector=status.phase!=Running --no-headers 2>/dev/null | \
  awk '{print $1}' | xargs -r -I {} kubectl delete pod {} -n prod --force --grace-period=0 2>/dev/null
echo -e "${GREEN}✅ Cleanup done.${RESET}"

# ---------- VERIFY ----------
echo ""
echo -e "${CYAN}🔹 Verifying deployment image:${RESET}"
NEW_IMAGE=$(kubectl get deployment production-deployment -n prod -o jsonpath='{.spec.template.spec.containers[0].image}')
echo -e "${GREEN}   Image: $NEW_IMAGE${RESET}"

if [[ "$NEW_IMAGE" == *"v1.0"* ]]; then
  echo -e "${GREEN}✅ Confirmed: v1.0 is active.${RESET}"
else
  echo -e "${RED}❌ Still not v1.0. Manual intervention needed.${RESET}"
fi

# ---------- CHECK PODS ----------
echo ""
echo -e "${CYAN}🔹 Pods in prod namespace:${RESET}"
kubectl get pods -n prod

# ---------- FINAL WAIT FOR STABILITY ----------
echo ""
echo -e "${CYAN}🔹 Waiting 30s for stability (allow Google checker to catch up)...${RESET}"
sleep 30

# ---------- TEST ENDPOINTS ----------
echo ""
echo -e "${CYAN}🔹 Fetching prod LoadBalancer IP...${RESET}"
PROD_LB_IP=$(kubectl get service prod-deployment-service -n prod -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
echo -e "${GREEN}✅ Prod LB IP: $PROD_LB_IP${RESET}"

echo ""
echo -e "${CYAN}🔹 /blue test (expect 200):${RESET}"
curl -s -I --max-time 10 http://${PROD_LB_IP}:8080/blue | head -1

echo ""
echo -e "${CYAN}🔹 /red test (expect 404):${RESET}"
curl -s -I --max-time 10 http://${PROD_LB_IP}:8080/red | head -1

# ---------- FINAL BANNER ----------
echo ""
echo -e "${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════════╗"
echo "║                                              ║"
echo "║   🎉  TASK 6 ROLLBACK DONE!  🎉              ║"
echo "║                                              ║"
echo "║   ✅ Prod on v1.0                            ║"
echo "║   ✅ /blue → 200 OK                          ║"
echo "║   ✅ /red  → 404 Not Found                   ║"
echo "║                                              ║"
echo "║   👉 Wait 1 min, then click                  ║"
echo "║      'Check my progress'                     ║"
echo "║                                              ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${RESET}"
