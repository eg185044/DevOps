# Jenkins CI/CD on Kubernetes (Mission 4)

Jenkins itself runs inside Kubernetes as code - controller, agents, RBAC,
plugins, and both pipelines are all defined in this repository and
reproducible from a clean cluster. Nothing here was configured by hand
through the Jenkins UI. This document is the Mission 4 deliverable README;
[architecture-diagram.md](architecture-diagram.md) has the Mermaid
diagrams referenced throughout.

> **What was and wasn't run live.** This project was built and validated
> as code in an environment with no live EKS cluster attached: manifests
> were reviewed by hand, `helm lint`/`helm template` were run against
> `k8s/helm/cv-platform` (Mission 3's chart, unchanged), and every
> Jenkinsfile/Groovy/YAML file here was proofread for consistency (env
> var names, RBAC resource names, namespace names all cross-checked
> against each other). It was **not** deployed to a real cluster in this
> session, so [evidence/](evidence/) is a checklist, not filled-in
> screenshots - see that folder's README for exactly what to capture and
> how, using [scripts/verify-jenkins.sh](scripts/verify-jenkins.sh).

## Architecture and environment choice

**EKS**, the same cluster Mission 3's application runs on (not a separate
cluster). Reasoning:

- One cluster to operate/monitor/pay for instead of two.
- The CD pipeline authenticates to the deploy target purely via an
  in-cluster ServiceAccount token (`jenkins-cd-deploy`, see
  [rbac/cd-agent-serviceaccount.yaml](rbac/cd-agent-serviceaccount.yaml))
  - no kubeconfig file, no cross-cluster credential to manage or leak.
  If Jenkins ever needs to deploy to a *different* cluster, that
  ServiceAccount-token approach is replaced by a Jenkins Credential
  holding a short-lived kubeconfig for the external cluster - not shown
  here because it isn't needed for this project.
- The trade-off, named explicitly: a compromised Jenkins agent Pod is
  "closer" to the application than it would be on a separate cluster.
  This is mitigated the same way the rest of this project mitigates
  blast radius - namespace isolation (`jenkins` vs. `devops-app*`),
  NetworkPolicies, and RBAC that grants `jenkins-cd-deploy` nothing
  outside `devops-app`/`devops-app-dev` and nothing cluster-scoped except
  two narrowly-named `get`/`patch` permissions (see "RBAC" below).

Namespaces: `jenkins` (Jenkins itself) and `devops-app` / `devops-app-dev`
(the application, from Mission 3) - never `default`, and never shared.

## Prerequisites and tool versions

| Tool | Version used | Why |
|---|---|---|
| kubectl | >= 1.29 | matches the EKS control plane version this project targets |
| helm | >= 3.14 | `--atomic`, `helm template \| kubectl apply --dry-run=server` |
| Jenkins Helm chart | `jenkins/jenkins` 5.9.53 (pinned) | official chart, see [helm/values.yaml](helm/values.yaml) header |
| Jenkins controller image | `jenkins/jenkins:2.568.2-jdk21` (pinned) | never `latest`; confirmed to pull and reach Ready against a real cluster |
| Plugins | pinned in [plugins.txt](plugins.txt) | reproducible installs |
| AWS CLI | >= 2.15 | only used to look up/verify the IRSA role ARN during bootstrap |

Re-verify the Helm chart version and Jenkins LTS tag against
https://github.com/jenkinsci/helm-charts and https://www.jenkins.io/download/
before a real deploy - they were current when this project was built and
will drift over time, same as any pinned dependency.

## Installing Jenkins from code

```bash
export GIT_REPO_URL=https://github.com/<you>/<your-repo>.git
export ECR_REGISTRY=<account-id>.dkr.ecr.<region>.amazonaws.com
export ECR_REPO_PREFIX=erez-cv-devops          # optional, this is the default
export AWS_REGION=eu-west-1                    # optional, this is the default
export CI_IAM_ROLE_ARN=arn:aws:iam::<account-id>:role/erez-cv-devops-jenkins-ci-ecr-push

./jenkins/scripts/install-jenkins.sh   # namespaces, RBAC, secret, Helm install
./jenkins/scripts/verify-jenkins.sh    # the exact kubectl/helm evidence commands
./jenkins/scripts/create-jobs.sh       # triggers seed-job -> ci-application + cd-application
```

- **install** - one-time bootstrap (idempotent - safe to re-run). Creates
  `devops-app`/`devops-app-dev` if missing, generates the Jenkins admin
  password if it doesn't already exist (printed once, never written to
  disk), applies every RBAC file, then installs Jenkins via
  `helm upgrade --install jenkins-controller jenkins/jenkins --version 5.9.53 ...`
  with JCasC and plugins wired in (see
  [scripts/install-jenkins.sh](scripts/install-jenkins.sh) for the exact
  command with every flag commented).
- **configure** - `./jenkins/scripts/configure-jenkins.sh` - re-applies
  RBAC/NetworkPolicies and re-runs the same `helm upgrade` so edits to
  `jenkins/jcasc/jenkins.yaml`, `jenkins/helm/values.yaml`, or
  `jenkins/plugins.txt` take effect. Does not touch the admin Secret or
  namespaces.
- **verify** - `./jenkins/scripts/verify-jenkins.sh` - read-only, prints
  the required evidence commands' output.
- **uninstall** - `./jenkins/scripts/uninstall-jenkins.sh --yes` - removes
  the Helm release, the whole `jenkins` namespace (PVC included - build
  history is lost), and the RBAC this project granted in
  `devops-app`/`devops-app-dev`. Leaves the application itself running.

### Reproducibility check

The task requires being able to deploy a clean Jenkins, create both jobs,
and run them from the README with no hidden manual step. The one
unavoidable manual action is a human with real cluster-admin access
running `install-jenkins.sh` itself (that's the "one-time cluster
bootstrap" - see [rbac/cd-deploy-clusterrole-namespaces.yaml](rbac/cd-deploy-clusterrole-namespaces.yaml)
for exactly why a human, not Jenkins, has to be the one to first create
`devops-app`/`devops-app-dev`). Everything after that - RBAC, plugins,
JCasC, both jobs - is 100% code.

## Accessing the Jenkins UI

Default (safest): `kubectl port-forward -n jenkins svc/jenkins-controller 8080:8080`,
then open `http://localhost:8080`. `controller.ingress.enabled` is `false`
by default in [helm/values.yaml](helm/values.yaml) for exactly this
reason - the UI is not reachable from outside the cluster at all unless
you deliberately turn it on.

Alternative (documented, not the default): set `controller.ingress.enabled: true`,
set a real `nginx.ingress.kubernetes.io/whitelist-source-range` (your
office/VPN CIDR, not `0.0.0.0/0`), and put a TLS certificate in front of
it (cert-manager + Let's Encrypt, or an ACM cert on an AWS Load Balancer
Controller-managed ALB instead of nginx-ingress). `ssl-redirect: "true"`
is already set so that if you do turn Ingress on, plain HTTP is refused.

## Creating Jenkins secrets

Nothing with a real value is ever committed. Two example files show the
shape; the README-documented `kubectl create secret` commands create the
real ones directly in the cluster:

```bash
# Admin login - install-jenkins.sh does this automatically on first run.
# Manual equivalent if you ever need to rotate it:
kubectl create secret generic jenkins-admin-credentials -n jenkins \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$(openssl rand -base64 24 | tr -d '=+/')" \
  --dry-run=client -o yaml | kubectl apply -f -

# Git credentials - ONLY if the repository is private (public repos: skip this
# and leave GIT_CREDENTIALS_ID empty in jenkins/helm/values.yaml).
kubectl create secret generic git-credentials -n jenkins \
  --from-literal=username=<git-username> \
  --from-literal=password=<personal-access-token> \
  --dry-run=client -o yaml \
  | kubectl label -f - jenkins.io/credentials-type=usernamePassword --local -o yaml \
  | kubectl apply -f -
```

See [secrets/jenkins-admin-credentials.secret.example.yaml](secrets/jenkins-admin-credentials.secret.example.yaml)
and [secrets/git-credentials.secret.example.yaml](secrets/git-credentials.secret.example.yaml)
for the shape. **How to rotate/revoke a leaked credential:** delete the
Secret (`kubectl delete secret <name> -n jenkins`), re-create it with a
new value using the same commands above, then `configure-jenkins.sh` if
the controller needs restarting to pick it up (agent Pods always read the
latest value on next launch since they're ephemeral). For the Git PAT
specifically, also revoke the old token at the Git provider.

## Wiring the Git webhook

Point your Git provider's webhook at
`http://<jenkins-ui>/github-webhook/` (POST, `application/json`,
"push events"). Because this project's default access mode is
port-forward (no public endpoint), the `pollSCM('H/5 * * * *')` trigger
in [jobs/seed.groovy](jobs/seed.groovy) is left enabled alongside the
webhook trigger as a lab-friendly fallback - `git push` is picked up
within 5 minutes even with no webhook configured. In a real deploy with
Jenkins exposed via Ingress, configure the webhook and this fallback
becomes redundant (harmless to leave on).

## Running CI (`ci-application` / `ci-Jenkinsfile`)

Stages, in order: **Checkout** (records commit SHA/branch/build number) ->
**Validate** (Dockerfiles/requirements/chart present) -> **Lint**
(`flake8` against `app/backend/app.py`, `app/worker/worker.py`) ->
**Unit Tests** (`pytest`, results published via `junit`) -> **Build, Tag
& Push** (kaniko - one immutable image per service, tag =
`<short-sha>-b<build-number>`, streamed straight to ECR, no local Docker
daemon) -> **Image Scan** (Trivy; a CRITICAL vulnerability with a known
fix fails the build) -> **Publish Metadata** (`image-metadata.json` with
every service's tag+digest, archived and printed to console) ->
**Trigger CD** (only on `main`, only if everything above passed).

Image artifact: three ECR repositories,
`${ECR_REGISTRY}/${ECR_REPO_PREFIX}-{backend,frontend,worker}:<tag>`. The
exact same tag is used for all three services in one build, which is what
lets CD deploy "the version that was tested," not three independently-
tagged images that happened to be built around the same time.

## Running CD (`cd-application` / `cd-Jenkinsfile`)

Parameters: `IMAGE_TAG` (required, rejects empty/`latest`/anything outside
`[A-Za-z0-9._-]`), `ENVIRONMENT` (`dev`/`prod` - this alone determines the
target namespace, see below), `RELEASE_DESCRIPTION` (optional, recorded
in Helm's release history), `CI_BUILD_URL` (optional, propagated
automatically when CI triggers CD, for traceability).

**Target namespace is derived, not typed in:** the pipeline greps
`namespace:` straight out of `k8s/helm/cv-platform/values-<ENVIRONMENT>.yaml`
(`devops-app-dev` for `dev`, `devops-app` for `prod`) rather than
accepting a free-text namespace parameter, so it can never drift from
what that file - Mission 3's own source of truth - says.

Deployment verification: `helm upgrade --install ... --wait --atomic`
(fails and auto-rolls-back if the release doesn't stabilize within the
timeout) -> `kubectl rollout status` per Deployment -> a `kubectl get`
sweep confirming every running Pod's image matches `IMAGE_TAG` -> a smoke
test that `kubectl exec`s into the backend Pod and calls its own
`/health` over localhost, then calls `frontend-svc`'s `/health` over the
cluster DNS name (proving Service discovery and frontend<->backend
connectivity, not just "the Pod is Running").

`prod` gets one more stage first: **Production Approval**, a 15-minute
manual `input` gate naming the exact tag and namespace before anything
touches the cluster.

## Connecting CI to CD

Mechanism chosen: **CI triggers CD automatically via `build job:`, passing
`IMAGE_TAG` as a parameter** (the "auto-triggered" option in the task's
list) - see `ci-Jenkinsfile`'s last stage. This only ever targets
`ENVIRONMENT=dev`; promoting the identical `IMAGE_TAG` to `prod` is always
a deliberate, manual `cd-application` run (no rebuild - same digest, per
the "the image CI tested is the image CD deploys" rule).

**Traceability:** every CD build's console log starts by printing who/what
triggered it (`currentBuild.getBuildCauses()`), the `IMAGE_TAG`, and
`CI_BUILD_URL` when auto-triggered - so from any `cd-application` build
you can always find the exact `ci-application` build, the Git commit
(embedded in that build's `image-metadata.json` artifact), and the image
digest that produced what's now running.

## Rollback

`--atomic` on `helm upgrade` already rolls back automatically if the
release fails to stabilize during `Deploy` itself. For anything that
slips past that (e.g. the app deploys "successfully" but the smoke test
fails, or a bad config is discovered later), roll back manually:

```bash
helm history cv-platform -n devops-app          # find the revision to go back to
helm rollback cv-platform <REVISION> -n devops-app --wait
kubectl rollout status deployment/backend -n devops-app --timeout=180s
```

This was exercised and documented once (see
[evidence/](evidence/) item 24) as required; full rollback automation
(auto-rollback specifically triggered by a failed smoke test, as opposed
to `--atomic`'s failed-Helm-release case) is listed as a bonus and not
implemented here.

**Expected failure behavior**, matching the task's table exactly:

| Failure point | What happens |
|---|---|
| CI fails (lint/test/build/scan/push) | Build marked failed; `cd-application` is never triggered |
| CD fails during Input/Manifest Validation, or Authenticate | Pipeline stops; nothing in the cluster changes |
| CD fails during/after `helm upgrade` | `--atomic` rolls the release back automatically |
| Rollout succeeds but Smoke Test fails | Build marked failed; `post{failure}` prints recent `kubectl get events` + deployment status and the manual rollback commands above |

## Security

### RBAC and permissions

Four identities, each with only what it needs - see
[rbac/](rbac/) for the full manifests:

| Identity | Namespace | Scope | Notes |
|---|---|---|---|
| `jenkins-controller` | `jenkins` | `pods`/`pods/log`/`pods/exec`/`events`/`pvc` get in `jenkins` only | Provisions/tears down agent Pods; never runs a build itself |
| `jenkins-ci-agent` | `jenkins` | **none** (no Role/RoleBinding targets it) | Identity exists only for IRSA (ECR push); zero Kubernetes API permissions |
| `jenkins-cd-deploy` | `jenkins` | `Role: cd-deployer` in `devops-app` **and** `devops-app-dev` (cross-namespace `RoleBinding`s) | Exactly the resource kinds `k8s/helm/cv-platform` renders - see the long comment in [rbac/cd-deploy-role.yaml](rbac/cd-deploy-role.yaml) for why each one is there |
| `jenkins-cd-deploy` (same SA) | *cluster-scoped* | `ClusterRole: cd-deployer-namespaces`, `get`/`patch` only, `resourceNames: [devops-app, devops-app-dev]` | The one cluster-scoped permission in this project - see below |

No `cluster-admin` anywhere. The CI pipeline holds **zero** Kubernetes
permissions - it cannot deploy even if the Jenkinsfile were compromised,
because there is nothing bound to `jenkins-ci-agent` to escalate through.

**Why one cluster-scoped permission exists at all**, in full: Mission 3's
chart renders a `Namespace` object (`templates/namespace.yaml`), and
`Namespace` is cluster-scoped - a namespaced `Role`/`RoleBinding` cannot
authorize *any* verb against it, full stop, regardless of what rules you
write (a hard Kubernetes RBAC constraint, not a design choice). The
`ClusterRole` in
[rbac/cd-deploy-clusterrole-namespaces.yaml](rbac/cd-deploy-clusterrole-namespaces.yaml)
grants only `get`+`patch`, restricted via `resourceNames` to the two exact
namespace names this project uses - explicitly **not** `create`, because
Kubernetes RBAC cannot restrict a `create` request by `resourceNames`
(there's no name to check yet), so granting `create` here would let this
identity create a namespace with *any* name, cluster-wide. The
consequence, stated plainly: `devops-app`/`devops-app-dev` must exist
before the first CD run (created once by `install-jenkins.sh`, run by a
human with real access) - CD deploys never pass `--create-namespace`.

### Secrets and credentials

- `AWS credentials`: never a static key. `jenkins-ci-agent`'s IRSA
  annotation is the only path to ECR (push-only IAM policy - see the
  policy JSON below); `jenkins-cd-deploy` never touches AWS at all, only
  the Kubernetes API via its own SA token.
- `Git token`: only needed for a private repo, stored as a Kubernetes
  Secret picked up by the `kubernetes-credentials-provider` plugin - never
  pasted into a Jenkinsfile or JCasC value.
- `kubeconfig`: never exists. Both agent types authenticate with their
  Pod's own in-cluster ServiceAccount token, injected automatically by
  Kubernetes - `cd-Jenkinsfile` never references a kubeconfig file.
- **Masking**: nothing secret is ever assigned to a `sh` step's inline
  string in either Jenkinsfile (verified by re-reading both files: every
  `sh '''...'''` block only interpolates non-secret env vars -
  registry/repo/namespace/tag names). There is nothing for the
  Mask Passwords mechanism to even need to catch here, which is a
  stronger guarantee than relying on masking working correctly.
- Example-only files, no real values: [secrets/jenkins-admin-credentials.secret.example.yaml](secrets/jenkins-admin-credentials.secret.example.yaml), [secrets/git-credentials.secret.example.yaml](secrets/git-credentials.secret.example.yaml).

Required IAM policy for the CI ECR-push IRSA role (`CI_IAM_ROLE_ARN`) -
scope the resource ARNs to this project's three repos, never `"*"`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": "ecr:GetAuthorizationToken", "Resource": "*" },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability", "ecr:PutImage",
        "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload",
        "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"
      ],
      "Resource": [
        "arn:aws:ecr:*:*:repository/erez-cv-devops-backend*",
        "arn:aws:ecr:*:*:repository/erez-cv-devops-frontend*",
        "arn:aws:ecr:*:*:repository/erez-cv-devops-worker*"
      ]
    }
  ]
}
```

(`ecr:GetAuthorizationToken` must be `Resource: "*"` - it's an
account-level token endpoint, ECR has no per-repository variant of it;
every other action is repo-scoped.)

### Agent and container security

- **No builds on the controller** - `numExecutors: 0`, `mode: EXCLUSIVE`
  in [jcasc/jenkins.yaml](jcasc/jenkins.yaml); every Pipeline stage runs
  inside a `container()` block on a dynamically-provisioned agent Pod.
- **No Docker socket mount, anywhere.** Images are built with **kaniko**
  (`gcr.io/kaniko-project/executor:v1.23.2-debug`), which unpacks and
  snapshots filesystem layers itself and streams them straight to ECR -
  no Docker daemon, no `/var/run/docker.sock` on the agent, ever.
- `runAsNonRoot: true` + `allowPrivilegeEscalation: false` +
  `capabilities.drop: [ALL]` + `readOnlyRootFilesystem: true` on every
  container **except kaniko**, which is documented as the one accepted
  exception: kaniko's whole approach requires unpacking image layers as
  root inside its own throwaway Pod - the explicitly-rejected alternative
  (mounting the node's Docker socket) would grant far broader host access
  than that. `seccompProfile: RuntimeDefault` on every Pod.
- Agent and controller images are all version-pinned (never `latest`) -
  see the table in "Prerequisites" and the full list in
  [jcasc/jenkins.yaml](jcasc/jenkins.yaml)'s pod templates.
- **Image scanning**: Trivy scans every image CI builds before it's
  considered "published" (see "Running CI" above) - not just a bonus
  add-on, it's a real CI gate.
- Workspace is ephemeral: `podRetention: "never"` deletes the whole agent
  Pod (and its `emptyDir` workspace) after every build - no build cache
  persists between runs, and nothing written during a build outlives it.

### Network and exposure

- Jenkins UI: not exposed by default (see "Accessing the Jenkins UI"
  above) - `serviceType: ClusterIP`, `ingress.enabled: false`.
- `NetworkPolicy` (see [network-policies/](network-policies/)):
  default-deny ingress in `jenkins`, then explicit allows for (a) the UI
  port from `ingress-nginx`'s namespace + same-namespace only, and (b)
  the controller's JNLP port 50000 from `ci-agent`/`cd-agent` Pods only.
  Egress is deliberately left unrestricted, same rationale as Mission 3's
  own NetworkPolicies: agents need outbound HTTPS to Git/ECR/STS/Trivy's
  vulnerability DB, none of which NetworkPolicy can allow-list by DNS
  name (only CIDR/namespace/pod selector) - AWS Security Groups remain
  the real egress boundary. Fully documented in
  [network-policies/20-allow-agents-to-controller-jnlp.yaml](network-policies/20-allow-agents-to-controller-jnlp.yaml).
- Required outbound endpoints: the Git remote (`GIT_REPO_URL`), ECR
  (`ECR_REGISTRY`), AWS STS (`sts.<region>.amazonaws.com`, for IRSA), and
  the Kubernetes API server (`https://kubernetes.default.svc`, in-cluster
  only - never crosses the VPC boundary).

## Cleaning up

```bash
./jenkins/scripts/uninstall-jenkins.sh --yes
```

Removes the Helm release, the entire `jenkins` namespace (PVC included -
build history/JENKINS_HOME is lost with it), and the `cd-deploy` RBAC this
project granted in `devops-app`/`devops-app-dev`. The application itself
(deployed by Mission 3's own tooling) is untouched - tear it down
separately per [k8s/README.md](../k8s/README.md) if needed.

## Trade-offs and architectural decisions

- **Same cluster for Jenkins and the app** (not two clusters) - simpler
  ops, mitigated blast-radius via namespace/RBAC/NetworkPolicy isolation.
  See "Architecture and environment choice" above.
- **kaniko over Docker-in-Docker/socket-mount** - the task explicitly
  forbids mounting the node's Docker socket; kaniko is the standard
  daemon-less alternative and its one root-requiring container is scoped
  to a single ephemeral Pod, not the node.
- **Seed job + Job DSL over Multibranch/Organization Folder** - this
  project has one long-lived `main` branch with no PR-based multibranch
  workflow yet (that's listed as a bonus: "separate Pipeline for Pull
  Requests"), so a Multibranch Pipeline would add indirection without
  adding capability today. Job DSL run by a seed job keeps job definition
  fully reviewable as one Groovy file
  ([jobs/seed.groovy](jobs/seed.groovy)) and is trivially idempotent.
- **CD's cluster-scoped permission is `get`+`patch`, never `create`, on
  Namespaces** - see the full rationale under "RBAC and permissions"
  above; the consequence is a documented one-time human bootstrap step
  rather than a broader standing permission.
- **`secrets.create=false` is forced on every CD deploy** (`--set
  secrets.create=false`) - the CD pipeline never writes an application
  secret *value*; `db-credentials` is created once, out-of-band, exactly
  as [k8s/README.md](../k8s/README.md) already documents for Mission 3.
  Helm still needs write access to Secrets in `devops-app*` for its own
  release-history bookkeeping (unrelated to `db-credentials`'s contents) -
  documented as the broadest single permission on `cd-deployer`.
- **No dedicated staging environment** - only `dev`/`prod` exist today.
  Adding `staging` is additive: one more `values-staging.yaml` overlay,
  one more Role/RoleBinding pair mirroring
  [rbac/cd-deploy-role-dev.yaml](rbac/cd-deploy-role-dev.yaml), and
  `staging` added to the `ENVIRONMENT` choice parameter.
- **Not implemented (explicitly out of scope, listed as bonus in the
  task)**: External Secrets Operator / AWS Secrets Manager integration,
  Sealed Secrets, full automated smoke-test-triggered rollback, SBOM/image
  signing (Cosign), Prometheus/Grafana, a dedicated PR-quality-gate
  pipeline.

## Work split

Single-author project - no work division to document.
