# Running This Project Locally (No Cloud Account Needed)

This guide walks you through running the full DevSecOps pipeline — SonarQube,
OWASP Dependency-Check, Trivy, Docker build, Kubernetes deploy — entirely on
your own machine, using [Kind](https://kind.sigs.k8s.io/) (Kubernetes in
Docker) instead of AWS EKS, and a GitHub Actions **self-hosted runner**
instead of a Jenkins server. No AWS account, no Docker Hub account required.

If you just want the fast interview-day checklist (assuming setup is already
done), see [`LOCAL_KIND_DEMO.md`](LOCAL_KIND_DEMO.md). The context behind
*why* it's built this way is in [`adr/0001-local-devsecops-pipeline.md`](adr/0001-local-devsecops-pipeline.md).
This doc is the one-time, start-to-finish setup.

## What you'll end up with

A live Tetris app running on a local Kubernetes cluster on your laptop,
deployed by a real CI/CD pipeline that runs every time you push code —
viewable in your browser at `http://localhost:30080`.

## Prerequisites

| Requirement | Notes |
|---|---|
| **Docker Desktop** | Installed and running. Get it from [docker.com](https://www.docker.com/products/docker-desktop/). You do **not** need to enable Docker Desktop's built-in "Kubernetes" toggle — Kind creates its own cluster using Docker containers. |
| **~8 GB RAM** free for Docker | This is Kind's own recommendation for reliable performance. |
| **Git** | To clone/fork the repo. |
| **A GitHub account** | You'll need your own fork of this repo, since the pipeline commits the deployed image tag back to git and needs a self-hosted runner registered against *your* repo. |
| **A terminal** | PowerShell on Windows, Terminal on macOS/Linux. On Windows, Docker Desktop typically sets up a WSL2 backend already — that WSL2 terminal is the easiest place to run the bash scripts in this repo. |

## Step 1 — Fork and clone

1. Fork this repository on GitHub (button in the top right of the repo page).
2. Clone your fork:
   ```
   git clone https://github.com/<your-username>/End-to-End-Kubernetes-DevSecOps-Tetris-Project.git
   cd End-to-End-Kubernetes-DevSecOps-Tetris-Project
   ```

## Step 2 — Install kubectl

Pick your OS:

- **macOS:** `brew install kubectl`
- **Windows:** `winget install -e --id Kubernetes.kubectl` (or `choco install kubernetes-cli`)
- **Linux:**
  ```
  curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  ```

Full reference: [kubernetes.io kubectl install docs](https://kubernetes.io/docs/tasks/tools/install-kubectl/).

## Step 3 — Install kind

- **macOS:** `brew install kind`
- **Windows:** `winget install Kubernetes.kind` (or `choco install kind`)
- **Linux:**
  ```
  curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64
  chmod +x ./kind
  sudo mv ./kind /usr/local/bin/kind
  ```

Full reference: [kind quick start](https://kind.sigs.k8s.io/docs/user/quick-start/).

## Step 4 — Confirm Docker Desktop is running

```
docker info
```
If this errors, open Docker Desktop and wait for it to fully start (the whale
icon stops animating) before continuing.

## Step 5 — Create the Kind cluster and start SonarQube

**macOS/Linux/WSL2:** run the bundled script — it does steps 5–7 for you and
is safe to re-run:
```
bash scripts/setup-local-runner.sh
```

**Windows without WSL2** (or if you'd rather run it by hand):
```
kind create cluster --name devsecops-tetris --config scripts/kind-cluster-config.yaml
docker run -d --name sonarqube -p 9000:9000 --restart unless-stopped sonarqube:community
```

Give SonarQube about a minute to finish booting, then confirm it's up at
`http://localhost:9000`.

## Step 6 — Generate a SonarQube token and add it as a GitHub secret

1. Open `http://localhost:9000`, log in with `admin` / `admin`, and set a new
   password when prompted.
2. **My Account → Security → Generate Token** — copy the token.
3. In your GitHub fork: **Settings → Secrets and variables → Actions → New
   repository secret**, name it `SONAR_TOKEN`, paste the value.

## Step 7 — Register a self-hosted GitHub Actions runner

This is the piece that lets GitHub Actions execute the workflow on *your*
machine instead of GitHub's cloud.

1. In your GitHub fork: **Settings → Actions → Runners → New self-hosted
   runner**, pick your OS.
2. Run the exact commands GitHub shows you (they include a one-time
   registration token, so they can't be copy-pasted from this doc — always
   use what's generated for your repo).
3. Install it as a background service so it keeps listening without you
   having to leave a terminal open:
   - macOS/Linux: `sudo ./svc.sh install && sudo ./svc.sh start`
   - Windows: use the equivalent service install command GitHub shows on the
     runner setup page.
4. Back in **Settings → Actions → Runners**, confirm your runner shows as
   **Idle** (green).

## Step 8 — Trigger the pipeline

- **On demand:** GitHub repo → **Actions** tab → **Local DevSecOps Pipeline
  (Kind)** → **Run workflow** → choose `Tetris-V1` or `Tetris-V2`.
- **Automatic:** push any change under `Tetris-V1/`, `Tetris-V2/`, or
  `Manifest-file/deployment-service.local.yml`.

## Step 9 — Watch it run and open the app

Watch progress live in the Actions tab — checkout, SonarQube scan + quality
gate, `npm install`, OWASP Dependency-Check, Trivy filesystem scan, Docker
build, Trivy image scan, load into Kind, manifest update, deploy.

When the run finishes, open **http://localhost:30080** — the app is served
from 3 pods running on your local Kind cluster. Useful checks:
```
kubectl get pods
kubectl logs -l app=tetris --tail=50
```

## Troubleshooting

- **`docker info` fails** — Docker Desktop isn't running; start it and wait
  for it to finish initializing.
- **Port 30080 already in use** — change `hostPort`/`containerPort` in
  `scripts/kind-cluster-config.yaml` and `nodePort` in
  `Manifest-file/deployment-service.local.yml` to match (keep both files in
  sync), then recreate the cluster.
- **Runner shows "Offline" in GitHub** — the runner service isn't running;
  restart it (`sudo ./svc.sh start` on macOS/Linux, or the Windows service).
- **`kind load docker-image` errors with "no nodes found"** — the cluster
  name doesn't match. It must be `devsecops-tetris` (matches
  `KIND_CLUSTER_NAME` in the workflow) — recreate it with
  `kind create cluster --name devsecops-tetris --config scripts/kind-cluster-config.yaml`.
- **SonarQube step hangs or fails** — confirm `http://localhost:9000` loads
  in a browser and `SONAR_TOKEN` is set correctly as a repo secret; a fresh
  SonarQube container can take a minute or two to become ready the first
  time.
- **Windows, bash scripts won't run** — `scripts/setup-local-runner.sh` and
  `scripts/check-quality-gate.sh` need bash. Use the WSL2 terminal that ships
  with Docker Desktop's backend, or Git Bash; the workflow's own steps that
  call these scripts run fine as long as your self-hosted runner is
  registered on WSL2/Linux, or has bash available (e.g. via Git for Windows).

## Tearing down

```
kind delete cluster --name devsecops-tetris
docker rm -f sonarqube
```
Also remove the self-hosted runner if you no longer need it: **Settings →
Actions → Runners**, select it, **Remove**.
