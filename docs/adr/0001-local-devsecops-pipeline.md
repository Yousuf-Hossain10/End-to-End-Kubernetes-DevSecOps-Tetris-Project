# ADR-0001: Local DevSecOps Pipeline via GitHub Actions + Kind

**Status:** Accepted
**Date:** 2026-07-26
**Deciders:** Yousuf Hossain

## Context

The original design of this project runs Jenkins on a dedicated AWS EC2 instance
(provisioned by `Jenkins-Server-TF/`). Two Jenkins pipelines
(`Jenkinsfile-TetrisV1` / `Jenkinsfile-TetrisV2`) build the Tetris app, run it
through SonarQube, OWASP Dependency-Check, and Trivy, push the image to Docker
Hub, and update a Kubernetes manifest that's deployed onto an AWS EKS cluster
(`EKS-TF/`), with ArgoCD handling GitOps sync per the README.

That design requires an active AWS account, ongoing EC2 spend for the Jenkins
box, a Docker Hub account, and an EKS cluster kept running. The author no
longer has an AWS account, but wants to demonstrate the same end-to-end
DevSecOps workflow live in a job interview — ideally as a real, clickable app,
not just green CI logs.

## Decision

Add a second, parallel pipeline that requires no cloud account:
`.github/workflows/local-kind-devsecops.yml`, triggered by push or manual
dispatch, executed by a **self-hosted GitHub Actions runner installed on the
author's own machine**, deploying to a **local Kind cluster**. The built image
is loaded directly into Kind (`kind load docker-image`) instead of being
pushed to a registry. The original Jenkins/EKS pipeline is left untouched as
the reference "production" architecture; the new pipeline is additive and
documented separately (see `docs/RUNNING_LOCALLY.md`).

## Options Considered

### Option A: Self-hosted GitHub Actions runner + persistent local Kind cluster (chosen)

| Dimension | Assessment |
|---|---|
| Complexity | Medium — one-time runner registration + service install |
| Cost | Free — runs on existing hardware |
| Team familiarity | High — same Actions YAML, different runner |
| Demo experience | Best — cluster and app persist after the run |

**Pros:** No cloud dependency; the cluster and app stay up after the workflow
finishes, so an interviewer can see real running pods, not just logs; the
runner is reused across pushes so repeat runs are fast.

**Cons:** Requires the laptop to be on with the runner service running at
demo time; one-time manual setup (the runner registration token is
interactive and can't be scripted); the pipeline can only run when the
machine is reachable.

### Option B: Ephemeral Kind cluster inside a GitHub-hosted runner

| Dimension | Assessment |
|---|---|
| Complexity | Low — nothing to install locally |
| Cost | Free tier of GitHub-hosted minutes |
| Team familiarity | High |
| Demo experience | Weaker — cluster is destroyed when the job ends |

**Pros:** Fully reproducible from a fresh clone with zero local setup;
triggerable from anywhere, even without the author's laptop present; no
runner to maintain.

**Cons:** Nothing persists to show afterward — only log output; doesn't
satisfy "runs on my local cluster"; SonarQube would need to be started fresh
(or skipped) on every run, adding minutes per job.

### Option C: Keep Jenkins, point it at local Kind instead of EKS

| Dimension | Assessment |
|---|---|
| Complexity | Medium-high — still requires running/maintaining Jenkins somewhere |
| Cost | Free if self-hosted, but duplicates infra being retired |
| Team familiarity | High — closest to the existing Jenkinsfiles |
| Demo experience | Good, but two services (Jenkins + Kind) instead of one |

**Pros:** Minimal changes to existing Jenkinsfiles — swap the EKS kubeconfig
context and Docker Hub push for `kind load`.

**Cons:** Still requires installing and keeping Jenkins running locally
(another background service, another thing to explain); doesn't reduce
operational surface area, just relocates it; GitHub Actions is more
universally recognizable to an interviewer than a self-hosted Jenkins.

## Trade-off Analysis

The central trade-off is **reliability of remote triggering** (Option B) vs
**richness of the live demo** (Option A). Since the goal is a running,
clickable app during an interview — not just a passing CI run — persistence
outside the workflow matters more than being triggerable from anywhere.
Option A was chosen; its main risk (laptop/runner must be on) is mitigated by
installing the runner as a background service (`svc.sh install`) so it
survives reboots without manual restarts. Option C was rejected because it
keeps a server process (Jenkins) alive for no benefit once EKS and Docker Hub
are out of the picture — GitHub Actions already provides that orchestration
for free.

Two secondary decisions were bundled into Option A:

- **Image distribution:** `kind load docker-image` instead of a registry
  push, since no registry account is needed and it's simpler when the build
  and the cluster are on the same machine.
- **Tool stack:** kept the full SonarQube + OWASP Dependency-Check + Trivy
  stack rather than trimming it, to preserve parity with the original
  pipeline's security coverage — that coverage is itself part of the story
  being demonstrated.

## Consequences

- **Easier:** No cloud cost or account dependency; the whole pipeline can run
  offline (aside from the first-time pull of Actions/Docker images); a real
  running app can be shown, not just logs.
- **Harder:** The runner service and SonarQube container need to be up before
  a demo; there are now two parallel deployment manifests
  (`Manifest-file/deployment-service.yml` for EKS,
  `Manifest-file/deployment-service.local.yml` for Kind) that can drift if
  only one is updated; there's no ArgoCD in the loop locally, so the GitOps
  story is partially simulated — the manifest is still committed back to git,
  but deployment is applied directly via `kubectl` rather than pulled by a
  sync controller.
- **To revisit:** If AWS access is restored, decide whether to keep
  maintaining both pipelines or retire the local one; consider adding a
  lightweight ArgoCD-in-Kind setup if the GitOps sync step should be
  demonstrated end-to-end rather than approximated.

## Action Items

1. [x] Add `.github/workflows/local-kind-devsecops.yml`
2. [x] Add `Manifest-file/deployment-service.local.yml`
3. [x] Add `scripts/setup-local-runner.sh`, `scripts/kind-cluster-config.yaml`,
   `scripts/check-quality-gate.sh`
4. [ ] Register a self-hosted runner on the target machine and install it as
   a service
5. [ ] Generate a SonarQube token and add it as the `SONAR_TOKEN` repo secret
6. [ ] (Optional) Evaluate ArgoCD-in-Kind if a fuller GitOps demo is wanted
