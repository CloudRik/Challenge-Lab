#!/bin/bash
# ==========================================================================
# Implement DevOps Workflows in Google Cloud (Challenge Lab)
# Powered by ArcadeSuite
# ==========================================================================
set -uo pipefail
exec > >(tee -a "$HOME/gsp330.log") 2>&1

MAX_TRIES=4
STATE="$HOME/.gsp330_state"; touch "$STATE"

G=$(tput setaf 2 2>/dev/null || true); R=$(tput setaf 1 2>/dev/null || true)
Y=$(tput setaf 3 2>/dev/null || true); N=$(tput sgr0 2>/dev/null || true)
step(){ echo; echo "${Y}=== $* ===${N}"; }
info(){ echo "${G}[ok]${N} $*"; }
warn(){ echo "${Y}[warn]${N} $*"; }
bad(){  echo "${R}[error]${N} $*" >&2; }

save(){ grep -v "^$1=" "$STATE" > "$STATE.tmp" 2>/dev/null || true; mv "$STATE.tmp" "$STATE"; printf '%s=%q\n' "$1" "$2" >> "$STATE"; }
load(){ set +u; source "$STATE" 2>/dev/null || true; set -u; }

retry_cmd(){ # retry_cmd <tries> <cmd...>
  local n="$1" i; shift
  for i in $(seq 1 "$n"); do "$@" && return 0; sleep 5; done; return 1
}

# ---------------------------- environment ---------------------------------
command -v gcloud >/dev/null && command -v kubectl >/dev/null && command -v git >/dev/null \
  && command -v python3 >/dev/null && command -v curl >/dev/null || { bad "Required tool missing (gcloud/kubectl/git/python3/curl)."; exit 1; }

export PROJECT_ID; PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
[[ -n "$PROJECT_ID" ]] || { bad "No active project. Open the lab's Cloud Shell."; exit 1; }
export PROJECT_NUMBER=""
for _i in 1 2 3 4 5; do
  PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)' 2>/dev/null)"
  [[ -n "$PROJECT_NUMBER" ]] && break; sleep 5
done
[[ -n "$PROJECT_NUMBER" ]] || { bad "Could not read project number."; exit 1; }

detect_zone(){ gcloud compute instances list --filter='name=git-server' --format='value(zone.basename())' 2>/dev/null | head -n1; }
export ZONE; ZONE="$(detect_zone || true)"; ZONE="${ZONE:-us-west1-b}"
export REGION="${ZONE%-*}"
export CLUSTER=hello-cluster REPO=my-repository
gcloud config set compute/region "$REGION" >/dev/null 2>&1
gcloud config set compute/zone "$ZONE" >/dev/null 2>&1

refresh_git_ip(){
  GIT_SERVER_IP="$(gcloud compute instances describe git-server --zone="$ZONE" \
    --format='get(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null)"
  AUTH="http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/sample-app.git"
}
retry_cmd 5 refresh_git_ip; refresh_git_ip
[[ -n "${GIT_SERVER_IP:-}" ]] || { bad "Could not detect git-server IP."; exit 1; }
echo "Project=$PROJECT_ID  Region=$REGION  Zone=$ZONE  GitServer=$GIT_SERVER_IP"

COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
BUILD_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"

# ------------------------------ auto-heal ---------------------------------
heal(){ # heal <task> <attempt>
  warn "Auto-heal started (task=$1, attempt=$2) ..."
  gcloud services enable container.googleapis.com cloudbuild.googleapis.com \
    artifactregistry.googleapis.com compute.googleapis.com >/dev/null 2>&1 || true
  gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:${BUILD_SA}" \
    --role="roles/container.developer" --quiet >/dev/null 2>&1 || true
  for r in roles/artifactregistry.writer roles/container.developer roles/logging.logWriter roles/storage.objectViewer; do
    gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:${COMPUTE_SA}" \
      --role="$r" --quiet >/dev/null 2>&1 || true
  done
  gcloud artifacts repositories describe "$REPO" --location="$REGION" >/dev/null 2>&1 || \
    gcloud artifacts repositories create "$REPO" --repository-format=docker --location="$REGION" \
      --description="Docker repository" >/dev/null 2>&1 || true
  if ! gcloud container clusters describe "$CLUSTER" --zone="$ZONE" >/dev/null 2>&1; then
    warn "Cluster missing - recreating"
    gcloud container clusters create "$CLUSTER" --zone="$ZONE" --release-channel=regular \
      --num-nodes=3 --enable-autoscaling --min-nodes=2 --max-nodes=6 >/dev/null 2>&1 || true
  fi
  gcloud container clusters get-credentials "$CLUSTER" --zone="$ZONE" >/dev/null 2>&1 || true
  kubectl get ns prod >/dev/null 2>&1 || kubectl create namespace prod >/dev/null 2>&1 || true
  kubectl get ns dev  >/dev/null 2>&1 || kubectl create namespace dev  >/dev/null 2>&1 || true
  refresh_git_ip || true
  if [[ -d "$HOME/sample-app/.git" ]]; then
    ( cd "$HOME/sample-app" && rm -f .git/index.lock \
      && { git merge --abort; git rebase --abort; git cherry-pick --abort; } >/dev/null 2>&1; \
      git reset -q --hard >/dev/null 2>&1 ) || true
  fi
  local id; id="$(gcloud builds list --region="$REGION" --limit=1 --sort-by='~createTime' \
        --filter='status=FAILURE' --format='value(id)' 2>/dev/null | head -n1)"
  if [[ -n "$id" ]]; then
    echo "--- last failed build ($id) ---"
    gcloud builds log "$id" --region="$REGION" 2>/dev/null | tail -15 || true
    echo "-------------------------------"
  fi
  sleep $(( 10 * $2 ))
}

run_task(){ # run_task <function>
  local f="$1" a
  for a in $(seq 1 "$MAX_TRIES"); do
    load
    ( set -Eeuo pipefail; trap 'echo "  -> step failed at line $LINENO"' ERR; "$f" ) && { info "$f finished"; return 0; }
    bad "$f failed (attempt $a/$MAX_TRIES)"
    [[ "$a" -lt "$MAX_TRIES" ]] && heal "$f" "$a"
  done
  bad "$f could not be fixed automatically after $MAX_TRIES attempts."
  bad "Run:  tail -60 ~/gsp330.log   and share the output."
  exit 1
}

# ----------------------------- helpers ------------------------------------
dep_name(){ # wait for a deployment to exist in namespace $1
  local d i
  for i in $(seq 1 24); do
    d="$(kubectl get deploy -n "$1" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
    [[ -n "$d" ]] && { echo "$d"; return 0; }; sleep 5; done
  return 1
}
cur_image(){ kubectl get deploy -n "$1" -o jsonpath='{.items[0].spec.template.spec.containers[0].image}'; }

img_from_cfg(){ # <cloudbuild file> <fallback image name>
  local i
  i="$(grep -oE '[A-Za-z0-9.<>_-]*docker\.pkg\.dev/[^ "'"'"',]+' "$1" | head -n1 || true)"
  [[ -n "$i" ]] || i="${REGION}-docker.pkg.dev/\$PROJECT_ID/${REPO}/$2:v1.0"
  echo "$i" | sed "s/\${PROJECT_ID}/${PROJECT_ID}/g; s/\$PROJECT_ID/${PROJECT_ID}/g"
}
set_manifest_image(){ # <manifest> <image>
  if grep -q '<todo>' "$1"; then sed -i "s|<todo>|$2|" "$1"
  else sed -i -E "0,/^(\s*-?\s*image:\s*).*/s||\1$2|" "$1"; fi
}
build(){ # <cloudbuild file>
  gcloud builds submit --config="$1" --region="$REGION" . && return 0
  warn "Regional build failed - trying global build"
  gcloud builds submit --config="$1" .
}
expose_lb(){ # <namespace> <service-name>
  local d; d="$(dep_name "$1")" || return 1
  kubectl get svc "$2" -n "$1" >/dev/null 2>&1 || \
    kubectl expose deployment "$d" -n "$1" --name="$2" --type=LoadBalancer --port=8080 --target-port="$PORT"
}
lb_ip(){ # <namespace> <service>
  local ip i
  for i in $(seq 1 45); do
    ip="$(kubectl get svc "$2" -n "$1" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)"
    [[ -n "$ip" ]] && { echo "$ip"; return 0; }; sleep 8; done
  return 1
}
check_http(){ # <namespace> <service> <path> <expected-code>
  local ip c="" i
  ip="$(lb_ip "$1" "$2")" || { bad "No LoadBalancer IP for $2"; return 1; }
  for i in $(seq 1 30); do
    c="$(curl -s -o /dev/null -m 8 -w '%{http_code}' "http://${ip}:8080$3" 2>/dev/null)"
    [[ "$c" == "$4" ]] && { info "$1 $3 -> HTTP $c (expected $4)"; return 0; }
    sleep 10
  done
  bad "$1 $3 -> HTTP $c (expected $4)"; return 1
}
rollout_ok(){ kubectl rollout status "deployment/$(dep_name "$1")" -n "$1" --timeout=300s; }

cat > /tmp/editmain.py <<'PY'
import re
s = open('main.go').read()
newmain = '''func main() {
	http.HandleFunc("/blue", blueHandler)
	http.HandleFunc("/red", redHandler)
	http.ListenAndServe(":8080", nil)
}'''
s = re.sub(r'func main\(\)\s*\{.*?\n\}', newmain, s, count=1, flags=re.S)
s = re.sub(r'\n*func redHandler\(.*?\n\}\n?', '\n', s, flags=re.S)
s = s.rstrip('\n') + '''

func redHandler(w http.ResponseWriter, r *http.Request) {
	img := image.NewRGBA(image.Rect(0, 0, 100, 100))
	draw.Draw(img, img.Bounds(), &image.Uniform{color.RGBA{255, 0, 0, 255}}, image.ZP, draw.Src)
	w.Header().Set("Content-Type", "image/png")
	png.Encode(w, img)
}
'''
open('main.go', 'w').write(s)
PY

# =============================== TASKS ====================================
task1(){
  step "ArcadeSuite Setup: Initializing APIs, IAM, and GKE Cluster"
  gcloud services enable container.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com
  gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:${BUILD_SA}" \
    --role="roles/container.developer" --quiet >/dev/null
  git config --global user.name "Student"
  git config --global user.email "student@qwiklabs.net"
  gcloud artifacts repositories describe "$REPO" --location="$REGION" >/dev/null 2>&1 || \
    gcloud artifacts repositories create "$REPO" --repository-format=docker --location="$REGION" --description="Docker repository"
  gcloud container clusters describe "$CLUSTER" --zone="$ZONE" >/dev/null 2>&1 || \
    gcloud container clusters create "$CLUSTER" --zone="$ZONE" --release-channel=regular \
      --num-nodes=3 --enable-autoscaling --min-nodes=2 --max-nodes=6
  gcloud container clusters get-credentials "$CLUSTER" --zone="$ZONE"
  kubectl get ns prod >/dev/null 2>&1 || kubectl create namespace prod
  kubectl get ns dev  >/dev/null 2>&1 || kubectl create namespace dev
  kubectl get ns prod dev
}

task2(){
  step "ArcadeSuite Deployment: Setting up Repository & Branches"
  refresh_git_ip
  git config --global user.name "Student"; git config --global user.email "student@qwiklabs.net"
  cd ~; rm -rf ~/sample-app; mkdir -p ~/sample-app
  gcloud storage cp -r "gs://spls/gsp330/sample-app/*" ~/sample-app/
  for f in ~/sample-app/cloudbuild-dev.yaml ~/sample-app/cloudbuild.yaml; do
    sed -i "s/<your-region>/${REGION}/g; s/<your-zone>/${ZONE}/g; s/<version>/v1.0/g" "$f"
    sed -i "s/CLOUDSDK_COMPUTE_REGION=${ZONE}/CLOUDSDK_COMPUTE_ZONE=${ZONE}/g" "$f"
  done
  cd ~/sample-app
  git init -q
  git remote remove origin 2>/dev/null || true
  git remote add origin "http://${GIT_SERVER_IP}:3000/giteaadmin/sample-app.git"
  git branch -m master
  git add . && git commit -qm "initial commit"
  git push -f -u "$AUTH" master
  git checkout -q -b dev
  git push -f -u "$AUTH" dev
  git checkout -q master
}

task3(){
  step "ArcadeSuite CI/CD: Generating Cloud Build Triggers"
  local SA="projects/${PROJECT_ID}/serviceAccounts/${COMPUTE_SA}"
  cd ~/sample-app
  gcloud builds triggers describe sample-app-prod-deploy --region="$REGION" >/dev/null 2>&1 || \
    gcloud builds triggers create manual --name="sample-app-prod-deploy" --inline-config="cloudbuild.yaml" \
      --service-account="$SA" --region="$REGION"
  gcloud builds triggers describe sample-app-dev-deploy --region="$REGION" >/dev/null 2>&1 || \
    gcloud builds triggers create manual --name="sample-app-dev-deploy" --inline-config="cloudbuild-dev.yaml" \
      --service-account="$SA" --region="$REGION"
  gcloud builds triggers describe sample-app-prod-deploy --region="$REGION" >/dev/null
  gcloud builds triggers describe sample-app-dev-deploy  --region="$REGION" >/dev/null
  gcloud builds triggers list --region="$REGION" --format="table(name,createTime)"
}

port_of_dockerfile(){
  local p; p="$(grep -iE '^[[:space:]]*EXPOSE' "$HOME/sample-app/Dockerfile" 2>/dev/null | head -n1 | awk '{print $2}' | sed 's#/.*##' || true)"
  echo "${p:-8080}"
}

task4_dev(){
  step "ArcadeSuite Pipeline: Executing DEV Deployment (v1.0)"
  PORT="$(port_of_dockerfile)"; echo "Container port: $PORT"
  cd ~/sample-app; refresh_git_ip
  git checkout -q -f dev
  local img; img="$(img_from_cfg cloudbuild-dev.yaml hello-cloudbuild-dev)"; echo "dev image: $img"
  set_manifest_image dev/deployment.yaml "$img"
  git add . && git commit -qm "Deploy v1.0 on dev" || true
  git push -f "$AUTH" dev
  build cloudbuild-dev.yaml
  expose_lb dev dev-deployment-service
  rollout_ok dev
  check_http dev dev-deployment-service /blue 200
}

task4_prod(){
  step "ArcadeSuite Pipeline: Executing PROD Deployment (v1.0)"
  PORT="$(port_of_dockerfile)"
  cd ~/sample-app; refresh_git_ip
  git checkout -q -f master
  local img; img="$(img_from_cfg cloudbuild.yaml hello-cloudbuild)"; echo "prod image: $img"
  set_manifest_image prod/deployment.yaml "$img"
  git add . && git commit -qm "Deploy v1.0 on master" || true
  git push -f "$AUTH" master
  save V1_COMMIT "$(git rev-parse HEAD)"
  build cloudbuild.yaml
  expose_lb prod prod-deployment-service
  rollout_ok prod
  check_http prod prod-deployment-service /blue 200
}

task5_dev(){
  step "ArcadeSuite Pipeline: Updating DEV Deployment (v2.0 + /red)"
  cd ~/sample-app; refresh_git_ip
  git checkout -q -f dev
  python3 /tmp/editmain.py
  sed -i 's/v1\.0/v2.0/g' cloudbuild-dev.yaml dev/deployment.yaml
  git add . && git commit -qm "Deploy v2.0 on dev" || true
  git push -f "$AUTH" dev
  build cloudbuild-dev.yaml
  rollout_ok dev
  [[ "$(cur_image dev)" == *":v2.0" ]] || { bad "dev is not running v2.0: $(cur_image dev)"; return 1; }
  check_http dev dev-deployment-service /red 200
}

task5_prod(){
  step "ArcadeSuite Pipeline: Updating PROD Deployment (v2.0 + /red)"
  cd ~/sample-app; refresh_git_ip
  git checkout -q -f master
  python3 /tmp/editmain.py
  sed -i 's/v1\.0/v2.0/g' cloudbuild.yaml prod/deployment.yaml
  git add . && git commit -qm "Deploy v2.0 on master" || true
  git push -f "$AUTH" master
  build cloudbuild.yaml
  rollout_ok prod
  [[ "$(cur_image prod)" == *":v2.0" ]] || { bad "prod is not running v2.0: $(cur_image prod)"; return 1; }
  check_http prod prod-deployment-service /red 200
}

task6(){
  step "ArcadeSuite Pipeline: Rolling back PROD to v1.0"
  PORT="$(port_of_dockerfile)"
  cd ~/sample-app; refresh_git_ip
  local v1="${V1_COMMIT:-}"
  [[ -n "$v1" ]] || v1="$(git log master --grep='Deploy v1.0 on master' -n1 --format=%H)"
  [[ -n "$v1" ]] || { bad "v1.0 commit not found"; return 1; }
  local img_v1; img_v1="$(git show "$v1:prod/deployment.yaml" | awk '/image:/ {print $NF; exit}')"
  echo "v1.0 commit: $v1   image: $img_v1"
  rm -rf /tmp/rollback; git worktree prune
  git worktree add -f /tmp/rollback "$v1" >/dev/null 2>&1
  ( cd /tmp/rollback && build cloudbuild.yaml )
  rollout_ok prod || true
  if [[ "$(cur_image prod)" != *":v1.0" ]]; then
    warn "Forcing prod image back to v1.0"
    kubectl set image "deployment/$(dep_name prod)" "*=${img_v1}" -n prod
    rollout_ok prod
  fi
  info "prod image now: $(cur_image prod)"
  check_http prod prod-deployment-service /red 404
}

final_report(){
  step "ArcadeSuite Final Verification Report"
  gcloud builds triggers list --region="$REGION" --format="table(name,createTime)" 2>/dev/null || true
  kubectl get ns prod dev 2>/dev/null || true
  kubectl get deploy,svc -n dev 2>/dev/null || true
  kubectl get deploy,svc -n prod 2>/dev/null || true
  echo "dev  image : $(cur_image dev 2>/dev/null)"
  echo "prod image : $(cur_image prod 2>/dev/null)"
  for t in "dev dev-deployment-service /blue" "dev dev-deployment-service /red" \
           "prod prod-deployment-service /blue" "prod prod-deployment-service /red"; do
    set -- $t
    ip="$(kubectl get svc "$2" -n "$1" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)"
    echo "$1 $3 -> HTTP $(curl -s -o /dev/null -m 8 -w '%{http_code}' "http://${ip}:8080$3" 2>/dev/null)"
  done
  echo
  echo "${G}"
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
  echo "${N}"
  echo "${G}==========================================================${N}"
  echo "${G}               POWERED BY ARCADESUITE                     ${N}"
  echo "${G}==========================================================${N}"
  echo "${G}Deployment Pipeline Completed Successfully.${N}"
  echo "${G}Please check 'Check my progress' on every task in Skills Boost now.${N}"
  echo "${G}==========================================================${N}"
}

# ================================ RUN =====================================
run_task task1
run_task task2
run_task task3
run_task task4_dev
run_task task4_prod
run_task task5_dev
run_task task5_prod
run_task task6
final_report
