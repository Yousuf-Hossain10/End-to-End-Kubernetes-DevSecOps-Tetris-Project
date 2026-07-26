#!/usr/bin/env bash
#
# One-time bootstrap for the local Kind DevSecOps demo.
# Mirrors what Jenkins-Server-TF/tools-install.sh does for the AWS EC2
# Jenkins box, but targets your own laptop (Ubuntu/Debian) instead,
# and swaps Jenkins for a GitHub Actions self-hosted runner.
#
# What this script does:
#   1. Installs Docker, kubectl, kind (skips anything already present)
#   2. Creates the local Kind cluster ("devsecops-tetris")
#   3. Starts a persistent local SonarQube container
#   4. Prints the manual steps to register a GitHub Actions self-hosted
#      runner (registration tokens are short-lived/interactive, so that
#      part can't be scripted unattended)
#
# Re-running this script is safe — every step checks for an existing
# install/resource first.

set -euo pipefail

CLUSTER_NAME="devsecops-tetris"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo -e "\n\033[1;32m==> $*\033[0m"; }

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This script targets Ubuntu/Debian, matching the rest of the repo."
  echo "On macOS: brew install docker kind kubectl, then run 'docker run -d --name sonarqube -p 9000:9000 --restart unless-stopped sonarqube:community' and 'kind create cluster --name ${CLUSTER_NAME} --config ${SCRIPT_DIR}/kind-cluster-config.yaml' by hand."
  exit 1
fi

# --- 1. Docker -------------------------------------------------------
if ! command -v docker &>/dev/null; then
  log "Installing Docker"
  sudo apt update
  sudo apt install -y docker.io
  sudo usermod -aG docker "$USER"
  sudo systemctl enable --now docker
  echo "Docker installed. Log out/in (or 'newgrp docker') for group membership to take effect."
else
  log "Docker already installed ($(docker --version))"
fi

# --- 2. kubectl --------------------------------------------------------
if ! command -v kubectl &>/dev/null; then
  log "Installing kubectl"
  curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm -f kubectl
else
  log "kubectl already installed ($(kubectl version --client --short 2>/dev/null || kubectl version --client))"
fi

# --- 3. kind -----------------------------------------------------------
if ! command -v kind &>/dev/null; then
  log "Installing kind"
  curl -Lo ./kind "https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64"
  chmod +x ./kind
  sudo mv ./kind /usr/local/bin/kind
else
  log "kind already installed ($(kind version))"
fi

# --- 4. Kind cluster -----------------------------------------------------
if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  log "Kind cluster '${CLUSTER_NAME}' already exists"
else
  log "Creating Kind cluster '${CLUSTER_NAME}'"
  kind create cluster --name "${CLUSTER_NAME}" --config "${SCRIPT_DIR}/kind-cluster-config.yaml"
fi
kubectl config use-context "kind-${CLUSTER_NAME}"

# --- 5. SonarQube --------------------------------------------------------
if docker ps -a --format '{{.Names}}' | grep -qx sonarqube; then
  log "SonarQube container already exists — making sure it's running"
  docker start sonarqube >/dev/null 2>&1 || true
else
  log "Starting local SonarQube container on http://localhost:9000"
  docker run -d --name sonarqube -p 9000:9000 --restart unless-stopped sonarqube:community
fi

# --- 6. Self-hosted runner instructions -----------------------------------
cat <<'EOF'

==> Local infra is ready. Two things left to do by hand:

1. SonarQube (http://localhost:9000, default login admin/admin, you'll be
   forced to set a new password). Create a token under
   My Account -> Security -> Generate Token, then add it as a repo secret
   named SONAR_TOKEN (Settings -> Secrets and variables -> Actions).

2. GitHub Actions self-hosted runner (registration tokens are one-time/
   interactive, so this part is manual):
     - In your repo: Settings -> Actions -> Runners -> New self-hosted runner
     - Follow GitHub's generated Linux x64 commands, e.g.:
         mkdir actions-runner && cd actions-runner
         curl -o actions-runner.tar.gz -L <url GitHub shows you>
         tar xzf actions-runner.tar.gz
         ./config.sh --url https://github.com/<you>/<repo> --token <token>
     - Install it as a background service so it's always listening:
         sudo ./svc.sh install
         sudo ./svc.sh start

Once both are done, push to master (or trigger the workflow manually from
the Actions tab) and the pipeline will build, scan, and deploy to your
Kind cluster. App will be at http://localhost:30080 once the rollout
finishes.
EOF
