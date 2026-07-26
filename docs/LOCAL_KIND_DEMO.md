# Interview Quick Reference

Fast reference for demoing the local pipeline live. For full first-time setup
(installing prerequisites, registering the runner, generating tokens), see
[`RUNNING_LOCALLY.md`](RUNNING_LOCALLY.md) — do that once, ahead of time.

## Before the interview

Confirm these are running:
```
docker ps                      # sonarqube container should be Up
kind get clusters               # devsecops-tetris should be listed
```
And in GitHub: **Settings → Actions → Runners** — your runner should show
**Idle**.

## Triggering the pipeline live

GitHub repo → **Actions** tab → **Local DevSecOps Pipeline (Kind)** → **Run
workflow** → choose `Tetris-V1` or `Tetris-V2` → **Run workflow**.

Watch it execute in real time: SonarQube scan + quality gate, OWASP
Dependency-Check, Trivy filesystem scan, Docker build, Trivy image scan,
`kind load docker-image`, manifest update, deploy.

## Showing the result

Once the run finishes: **http://localhost:30080** — live app, 3 replicas, on
your local Kind cluster.
```
kubectl get pods
kubectl logs -l app=tetris --tail=50
```

## Talking points

- Same security/quality gates as the AWS version of this pipeline
  (SonarQube, OWASP Dependency-Check, Trivy fs + image scans) — only the
  deploy target and image distribution changed (Kind + `kind load
  docker-image` instead of EKS + Docker Hub).
- The manifest update step still commits the new image tag back to git
  (`Manifest-file/deployment-service.local.yml`), preserving the GitOps-style
  audit trail from the original pipeline — applied directly with `kubectl`
  here since there's no ArgoCD instance running locally.
- The full reasoning behind this design (why a self-hosted runner + Kind
  instead of ArgoCD-on-EKS or an ephemeral cloud runner) is written up as an
  ADR: [`adr/0001-local-devsecops-pipeline.md`](adr/0001-local-devsecops-pipeline.md).
- If asked directly: "In production this runs on Jenkins against EKS; here
  it's the same pipeline logic on GitHub Actions against a local Kind
  cluster, since I don't currently have an AWS account to keep EKS running."

## Resetting between runs / after the interview

```
kind delete cluster --name devsecops-tetris
docker rm -f sonarqube
```
Then re-run `bash scripts/setup-local-runner.sh` to start clean.
