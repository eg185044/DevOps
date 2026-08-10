# Kubernetes deployment - Erez Glik CV Platform

This folder is the Kubernetes migration of the EC2 + Terraform + Ansible
stack in `../terraform` and `../ansible`. Same three services (frontend/
nginx, backend, worker), same external AWS dependencies (RDS PostgreSQL, S3,
SNS) - now running as Pods in one EKS cluster/namespace instead of three
EC2 instances wired together by Ansible roles.

It also folds in the two standalone Kubernetes learning assignments
(beginner hands-on commands, intermediate topics: volumes, scheduling,
probes, jobs, ConfigMaps/Secrets) by applying those concepts directly to
this real application rather than to a throwaway scenario. See
[Assumptions & how the three assignments were combined](#assumptions--how-the-three-assignments-were-combined)
for exactly what came from where.

Architecture diagram: [architecture-diagram.md](architecture-diagram.md).
Conceptual Q&A (Part 2 of the beginner/intermediate assignments):
[../docs/k8s-assignment1-answers.md](../docs/k8s-assignment1-answers.md) and
[../docs/k8s-assignment2-answers.md](../docs/k8s-assignment2-answers.md).

**No AWS access, or just want to test on your laptop first?**
[../docs/local-kind-runbook.md](../docs/local-kind-runbook.md) is a
baby-step guide to running this entire stack on a free local `kind`
cluster and producing every screenshot the assignments ask for, with no
AWS account needed.

## What runs where

| Service | In-cluster? | Exposed how |
|---|---|---|
| frontend (nginx) | Yes - `deployment-frontend.yaml` | Only component with an Ingress (`ingress.yaml`) |
| backend (Flask API) | Yes - `deployment-backend.yaml` | ClusterIP only, reachable from frontend only |
| worker (Flask) | Yes - `deployment-worker.yaml` | ClusterIP only, reachable from frontend only |
| redis-cache | Yes, **optional/bonus** - `deployment-redis.yaml` | ClusterIP only, reachable from backend/worker only |
| PostgreSQL | **Stays outside the cluster**, on RDS | Reached via `db-credentials` Secret (`DB_HOST` = RDS endpoint) |
| S3 / SNS | **Stays outside the cluster**, managed AWS services | Reached via IRSA (see [IAM / IRSA](#iam--irsa)) |

Running PostgreSQL as a Pod inside the cluster was intentionally **not**
chosen: it would mean re-inventing HA/backup/patching that RDS already
solves, for a workload (a CV/demo platform) with no requirement to avoid
RDS costs. Keeping it on RDS is also what makes IRSA/Secrets meaningfully
different from the in-cluster redis-cache bonus tier - one dependency lives
outside Kubernetes, one lives inside.

## Folder layout

```
k8s/
├── namespace.yaml                  # devops-app namespace (never use `default`)
├── configmap.yaml                  # app-config + frontend-nginx-conf (non-secret only)
├── secret.example.yaml             # template - copy to secret.yaml, never commit the real one
├── deployment-frontend.yaml
├── deployment-backend.yaml
├── deployment-worker.yaml
├── deployment-redis.yaml           # optional/bonus cache tier
├── service-frontend.yaml
├── service-backend.yaml
├── service-worker.yaml
├── service-redis.yaml
├── ingress.yaml                    # the ONLY externally-reachable route
├── pvc.yaml                        # redis-data, backs deployment-redis.yaml
├── job-db-migration.yaml           # one-off: creates the cv_events table
├── cronjob-cache-cleanup.yaml      # nightly: FLUSHDB on redis-cache
├── rbac/
│   ├── serviceaccounts.yaml        # one SA per Deployment + IRSA annotations
│   ├── role.yaml                   # read-only namespace-viewer Role
│   └── rolebinding.yaml            # bound to diagnostics-sa only (see Security)
├── network-policies/
│   ├── 00-default-deny-ingress.yaml
│   ├── 10-allow-ingress-to-frontend.yaml
│   ├── 20-allow-backend-from-frontend.yaml
│   ├── 30-allow-worker-from-frontend.yaml
│   └── 40-allow-redis-from-backend-worker.yaml
├── helm/
│   ├── cv-platform/                 # bonus: same stack as a Helm chart (deploy via ArgoCD - see argocd/)
│   └── student-web/                 # minimal teaching chart - see its own README.md
├── argocd/                          # ArgoCD Application manifests - GitOps deploy of the Helm charts above
├── architecture-diagram.md
└── README.md                       # this file
```

**New to Helm/ArgoCD?** Start at
[`helm/student-web/README.md`](helm/student-web/README.md) (baby-step
`helm install`/`upgrade`/`rollback` walkthrough on a tiny chart), then
[`argocd/README.md`](argocd/README.md) (baby-step ArgoCD walkthrough,
including on the real `cv-platform` chart below). Theory Q&A for both:
[`../docs/helm-argocd-assignment-answers.md`](../docs/helm-argocd-assignment-answers.md).

Related Dockerfiles: `../app/frontend/Dockerfile` (new - the frontend was
previously deployed straight onto an EC2 nginx via Ansible, not
containerized), `../app/backend/Dockerfile`, `../app/worker/Dockerfile`
(both updated here to run as a non-root user and ship a `.dockerignore`).

## Building and pushing images

```bash
# from the repo root
export ECR_REGISTRY=<account-id>.dkr.ecr.eu-west-1.amazonaws.com
aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin "$ECR_REGISTRY"

for svc in frontend backend worker; do
  aws ecr create-repository --repository-name erez-cv-devops-$svc --region eu-west-1 || true
  docker build -t "$ECR_REGISTRY/erez-cv-devops-$svc:1.0.0" app/$svc
  docker push "$ECR_REGISTRY/erez-cv-devops-$svc:1.0.0"
done
```

Every manifest in this folder uses the placeholder
`REPLACE_ME_REGISTRY/erez-cv-devops-<service>:1.0.0`. Before applying,
replace `REPLACE_ME_REGISTRY` with your real `$ECR_REGISTRY` (or point the
Helm chart at it with `--set image.registry=$ECR_REGISTRY`). Never use the
`latest` tag - every image here is pinned (`1.0.0`, `redis:7.2-alpine`,
`nginxinc/nginx-unprivileged:1.25-alpine`), per the assignment's explicit
"no `latest`" rule, so a rollback always has an exact previous tag to go back to.

## Creating the namespace

```bash
kubectl apply -f k8s/namespace.yaml
```

## Creating Secrets

`secret.example.yaml` is a template only - it is **not** applied as-is.
Real secrets are created directly with `kubectl`, so the plaintext password
never touches a file on disk that could accidentally get committed:

```bash
# Get the real values first:
terraform -chdir=terraform output rds_endpoint
terraform -chdir=terraform output s3_bucket_name
terraform -chdir=terraform output sns_topic_arn

kubectl create secret generic db-credentials \
  --namespace devops-app \
  --from-literal=DB_HOST="<rds_endpoint output>" \
  --from-literal=DB_USERNAME="erezadmin" \
  --from-literal=DB_PASSWORD="<the real terraform.tfvars db_password>"
```

Then fill the real (non-secret) `S3_BUCKET_NAME` / `SNS_TOPIC_ARN` values
into `configmap.yaml` before applying it (they're identifiers, not
credentials, so ConfigMap - not Secret - is correct for them).

## Applying everything

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
# db-credentials Secret created above, not applied from a file
kubectl apply -f k8s/rbac/
kubectl apply -f k8s/pvc.yaml
kubectl apply -f k8s/deployment-frontend.yaml
kubectl apply -f k8s/deployment-backend.yaml
kubectl apply -f k8s/deployment-worker.yaml
kubectl apply -f k8s/deployment-redis.yaml   # optional bonus tier
kubectl apply -f k8s/service-frontend.yaml
kubectl apply -f k8s/service-backend.yaml
kubectl apply -f k8s/service-worker.yaml
kubectl apply -f k8s/service-redis.yaml
kubectl apply -f k8s/network-policies/
kubectl apply -f k8s/ingress.yaml            # requires an Ingress controller already installed
kubectl apply -f k8s/job-db-migration.yaml
kubectl apply -f k8s/cronjob-cache-cleanup.yaml
```

(Order matters only loosely - Kubernetes will retry Pods that reference a
not-yet-existing ConfigMap/Secret, but applying namespace/config/secrets
first avoids the retry churn.)

### Or with Helm (bonus)

```bash
helm upgrade --install cv-platform-prod ./k8s/helm/cv-platform \
  -f ./k8s/helm/cv-platform/values.yaml \
  -f ./k8s/helm/cv-platform/values-prod.yaml \
  --set image.registry=$ECR_REGISTRY \
  --set secrets.dbHost=<rds endpoint> \
  --set secrets.dbUsername=erezadmin \
  --set secrets.dbPassword=$DB_PASSWORD \
  --set config.s3BucketName=<bucket name> \
  --set config.snsTopicArn=<topic arn>
```

`helm lint`/`helm template` both run clean against `values.yaml`,
`values-dev.yaml`, and `values-prod.yaml` (verified locally). Every resource
this chart creates is prefixed with the Helm *release* name (via the
`cv-platform.fullname` helper in `templates/_helpers.tpl`) - so
`cv-platform-prod` above creates `cv-platform-prod-backend`,
`cv-platform-prod-frontend-svc`, etc., not the bare `backend`/`frontend-svc`
names the raw manifests above use. This lets `cv-platform-dev` and
`cv-platform-prod` (see `values-dev.yaml`) run as fully independent Helm
Releases without colliding, even in the same namespace. See
`k8s/helm/cv-platform/values.yaml` for every override point, and its
`NOTES.txt` for the post-install message.

### Or with ArgoCD - GitOps, no local `helm`/`kubectl` commands at all

Instead of running `helm upgrade --install` from your terminal, point
ArgoCD at this Git repo and let it apply the chart automatically, keep it
in sync with Git going forward, and auto-heal/prune any drift. Full
baby-step walkthrough: [`helm/student-web/README.md`](helm/student-web/README.md)
(Helm mechanics first) then [`argocd/README.md`](argocd/README.md) (ArgoCD
on top). Theory: [`../docs/helm-argocd-assignment-answers.md`](../docs/helm-argocd-assignment-answers.md).

### Prerequisite: an Ingress controller

`ingress.yaml` assumes `ingress-nginx` is already installed in the cluster
(`ingressClassName: nginx`). On EKS:

```bash
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace
```

To use the AWS Load Balancer Controller + native ALB instead, see the
comment at the top of `ingress.yaml`.

## Verifying it works

```bash
kubectl get nodes
kubectl get namespaces
kubectl get pods -n devops-app
kubectl get deployments -n devops-app
kubectl get services -n devops-app
kubectl get ingress -n devops-app
kubectl describe pod <pod-name> -n devops-app
kubectl logs <pod-name> -n devops-app
kubectl logs -n devops-app job/db-migration
```

External access:
```bash
kubectl get ingress cv-platform-ingress -n devops-app
# once DNS/LB is up:
curl -H "Host: cv.example.com" http://<ingress-lb-address>/health
curl -H "Host: cv.example.com" http://<ingress-lb-address>/api/health
curl -H "Host: cv.example.com" http://<ingress-lb-address>/worker/health
```

Frontend -> backend and frontend -> worker communication is exactly this
`/api/*` and `/worker/*` proxying, visible in `frontend-nginx-conf`
(`k8s/configmap.yaml`) and enforced (not just configured) by
`network-policies/20-` and `30-`.

Pod restart / self-healing demo:
```bash
kubectl delete pod -n devops-app -l app=backend --field-selector status.phase=Running -o name | head -1 | xargs kubectl delete -n devops-app
kubectl get pods -n devops-app -w   # watch the ReplicaSet recreate it within seconds
```

## Security

### RBAC & ServiceAccounts

Every Deployment gets its **own** ServiceAccount (`rbac/serviceaccounts.yaml`):
`frontend-sa`, `backend-sa`, `worker-sa`, `redis-sa`. None of these
ServiceAccounts is bound to any Kubernetes RBAC `Role` - **no application
code in this project calls the Kubernetes API**, so granting API read/write
access to any of them would be a permission with no matching need. This is
the deliberate answer to "why not give every service the same permissions":
the four app ServiceAccounts get *zero* Kubernetes API permissions, and
differ from each other only in their **AWS** IAM permissions via IRSA.

`rbac/role.yaml` defines a single read-only `namespace-viewer` Role
(`get/list/watch` on Pods/Services/ConfigMaps/Deployments - explicitly **not**
Secrets) bound only to `diagnostics-sa` (`rbac/rolebinding.yaml`), which
isn't attached to any running workload. It exists for ad-hoc troubleshooting:

```bash
kubectl run debug --rm -it --image=busybox -n devops-app \
  --overrides='{"spec":{"serviceAccountName":"diagnostics-sa"}}' -- sh
```

No `ClusterRole`, no `cluster-admin` binding, anywhere in this project.

### IAM / IRSA

`backend-sa` and `worker-sa` carry an
`eks.amazonaws.com/role-arn` annotation (IRSA). On EKS, the Pod Identity
webhook uses that annotation to inject short-lived, automatically-rotated
AWS credentials into any Pod using that ServiceAccount - `boto3` in
`app/backend/app.py` / would-be S3 calls in the worker pick these up
automatically via the default credential chain, so **no static AWS access
key ever exists in an image, ConfigMap, or Secret**.

The underlying IAM roles (not created by this folder - see
`terraform/main.tf`'s `aws_iam_role_policy.ec2_policy` for the equivalent
EC2-era policy) should scope `s3:GetObject/PutObject/ListBucket` to just the
CV bucket ARN and `sns:Publish` to just the events topic ARN, exactly like
the existing EC2 instance profile policy - just attached to two new IAM
roles trusted by the cluster's OIDC provider instead of to an EC2 instance
profile.

If you deploy without EKS/IRSA (e.g. kind/k3d for local grading), the
alternative is a static IAM user's access key injected via the
`db-credentials`-style Secret pattern - explicitly worse (a long-lived key
sitting in etcd instead of a token that auto-expires), documented here only
because the assignment asks for the trade-off to be named.

### Secrets management

- `db-credentials` (`DB_HOST`, `DB_USERNAME`, `DB_PASSWORD`) is a native
  Kubernetes Secret, created directly with `kubectl create secret generic`
  (see [Creating Secrets](#creating-secrets)) - never `kubectl apply -f` on a
  file containing real values.
- `secret.example.yaml` is the only Secret-shaped file that gets committed;
  it contains placeholder values and is what a teammate copies from.
- No secrets ever live in a ConfigMap, in an image layer, or in `git`
  history - the repo's `.gitignore` already excludes `secret.yaml`.
- **Only Kubernetes Secrets are used here** - no Sealed Secrets/External
  Secrets Operator/AWS Secrets Manager integration is wired up. That's a
  named trade-off: a real production rollout should sync `db-credentials`
  from AWS Secrets Manager via the External Secrets Operator so the RDS
  password has one source of truth shared with any non-Kubernetes consumer,
  rather than being copy-pasted into a `kubectl create secret` command by
  hand.

### Network security

`network-policies/00-default-deny-ingress.yaml` denies all inbound traffic
in the namespace by default; every other policy in that folder is an
explicit allow:

- frontend Pods: reachable only from the Ingress controller's namespace
  (or same-namespace, for health-check tooling) - `10-`.
- backend Pods: reachable only from frontend Pods, port 5000 - `20-`.
- worker Pods: reachable only from frontend Pods, port 5002 - `30-`.
- redis-cache Pods: reachable only from backend/worker/cache-cleanup Pods,
  port 6379 - `40-`.

**Egress is deliberately left unrestricted** by these NetworkPolicies - see
the comment at the top of `00-default-deny-ingress.yaml`. backend and worker
need outbound access to RDS (5432), S3/SNS (443), and cluster DNS (53);
modelling that correctly with egress NetworkPolicy rules requires knowing
the VPC/node CIDR ranges, which vary per environment. Egress is instead
already constrained at the AWS Security Group layer
(`terraform/main.tf`: `aws_security_group.app`, `aws_security_group.rds`).
A future hardening pass would add egress NetworkPolicies plus VPC endpoints
for S3/SNS so traffic never has to leave the VPC at all - listed again under
Trade-offs below.

### Container security

Every container in every workload sets:

```yaml
securityContext:
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  capabilities: { drop: ["ALL"] }
  readOnlyRootFilesystem: true   # container-level, alongside pod-level runAsNonRoot/runAsUser
```

This is real, not cosmetic:
- frontend uses `nginxinc/nginx-unprivileged:1.25-alpine` (listens on 8080,
  runs as uid 101 out of the box) instead of patching around stock nginx's
  need for root to bind port 80.
- backend/worker Dockerfiles add `RUN useradd --uid 1000 ... && USER appuser`.
- redis-cache runs as the image's built-in uid 999.
- Since the root filesystem is read-only, every container that needs to
  write anything (nginx's cache/pid/tmp dirs, Python's `/tmp`, Redis's
  `/data`) gets an explicit `emptyDir` or PVC volume mount for exactly that
  path - nothing else is writable.

### Image security

- No image in this project uses the `latest` tag (`1.0.0` for the three
  custom images, `redis:7.2-alpine`, `nginxinc/nginx-unprivileged:1.25-alpine`).
- `app/frontend`, `app/backend`, `app/worker` each have a `.dockerignore`
  (none existed before this migration) so `.git`, `__pycache__`, and any
  stray `.env` never end up baked into a layer.
- No secret is ever `COPY`'d into an image; all runtime config comes from
  ConfigMap/Secret at Pod start.
- Not done here, listed as a bonus: wiring `trivy image erez-cv-devops-backend:1.0.0`
  (or Docker Scout / ECR image scanning) into CI before push.

### Ingress security

- Only `frontend-svc` is referenced by `ingress.yaml` - backend/worker/redis
  have no Ingress at all, so they're unreachable from outside the cluster
  regardless of NetworkPolicy (defense in depth, not the only control).
- TLS is **not** configured in `ingress.yaml` as shipped
  (`ssl-redirect: "false"`) - this is the single biggest gap for a real
  production rollout. Bonus/next step: `cert-manager` + a `ClusterIssuer`
  (Let's Encrypt) or an ACM certificate on the ALB if using the AWS Load
  Balancer Controller instead of ingress-nginx.
- No WAF is attached. On EKS with ALB, AWS WAF would sit in front of the
  ALB; with ingress-nginx, ModSecurity or an upstream CDN/WAF would be the
  equivalent.

## Trade-offs and decisions

- **Namespace name**: `devops-app`, not `flash-sale` (the name used by the
  standalone intermediate assignment's generic exercise) - this project
  deploys the *real* CV platform, so a name describing that felt more
  honest than reusing the practice-exercise name. See
  [Assumptions](#assumptions--how-the-three-assignments-were-combined).
- **redis-cache is optional and unused by application code today.** It
  exists to satisfy the intermediate assignment's Volumes/PVC and
  Advanced-Scheduling (`nodeAffinity`) requirements against something real
  instead of a `busybox` placeholder. Deleting `deployment-redis.yaml`,
  `service-redis.yaml`, `pvc.yaml`, and `cronjob-cache-cleanup.yaml` does
  not break frontend/backend/worker.
- **Redis is a `Deployment`, not a `StatefulSet`**, at `replicas: 1`, per
  the assignment's literal spec. This only works safely at exactly 1
  replica - see the warning comment in `deployment-redis.yaml`.
- **Ingress controller**: ingress-nginx, not the AWS Load Balancer
  Controller - it's portable across EKS/kind/k3d, so the same `ingress.yaml`
  works whichever of the assignment's two approved cluster options
  (EKS "recommended", or local kind/k3d) is used for grading. The
  ALB-controller equivalent annotations are documented as a comment in
  `ingress.yaml`.
- **PostgreSQL stays on RDS**, not in-cluster - see
  [What runs where](#what-runs-where) above.
- **Egress NetworkPolicy is not modelled** - see
  [Network security](#network-security) above; enforced at the AWS Security
  Group layer instead.
- **No Sealed Secrets / External Secrets Operator / AWS Secrets Manager** -
  plain Kubernetes Secrets only, named as a gap under
  [Secrets management](#secrets-management).

## Cleanup

```bash
kubectl delete -f k8s/network-policies/
kubectl delete -f k8s/cronjob-cache-cleanup.yaml -f k8s/job-db-migration.yaml
kubectl delete -f k8s/ingress.yaml
kubectl delete -f k8s/service-frontend.yaml -f k8s/service-backend.yaml -f k8s/service-worker.yaml -f k8s/service-redis.yaml
kubectl delete -f k8s/deployment-frontend.yaml -f k8s/deployment-backend.yaml -f k8s/deployment-worker.yaml -f k8s/deployment-redis.yaml
kubectl delete -f k8s/pvc.yaml
kubectl delete -f k8s/rbac/
kubectl delete secret db-credentials -n devops-app
kubectl delete -f k8s/configmap.yaml
kubectl delete -f k8s/namespace.yaml   # deletes anything left behind in one shot
```

Deleting the namespace last (`kubectl delete namespace devops-app`) is
enough on its own to remove everything in this list - the explicit ordering
above is only there so each `kubectl delete` prints a clean per-kind
confirmation. Note the namespace enters `Terminating` until every object
inside it (including any stuck with a finalizer) is actually gone; see
`docs/k8s-assignment1-answers.md` Section I for what to do if it hangs.

Or with Helm: `helm uninstall cv-platform-prod` (matches whatever release
name you `helm install`ed with - `cv-platform-dev` for the dev overlay).
This does **not** delete the `devops-app`/`devops-app-dev` Namespace itself
even though the chart's own `templates/namespace.yaml` created it (Helm
doesn't delete a Namespace it created if the release's other resources
already got individually removed in a way that leaves it looking "shared" -
in practice just run `kubectl delete namespace devops-app` after uninstall
if you want it gone too).

Or with ArgoCD: delete the `Application` object (see
`argocd/README.md` "Clean up") - its `resources-finalizer.argocd.argoproj.io`
finalizer means that one delete cascades to every resource ArgoCD created.

## Assumptions & how the three assignments were combined

1. **Beginner assignment (hands-on commands)**: mostly a set of commands to
   run and observe, not artifacts to ship - its Part 2 conceptual questions
   are answered in `docs/k8s-assignment1-answers.md`. Its finalizer section
   directly informed the `Terminating` note in [Cleanup](#cleanup).
2. **Intermediate assignment ("flash-sale" scenario)**: its Part 1
   conceptual questions (volumes, labels, scheduling, taints, jobs, probes,
   ConfigMaps/Secrets) are answered in `docs/k8s-assignment2-answers.md`.
   Its Part 2 practical scenario (nginx + busybox + redis, generic
   `app-config`/`app-secrets` names) was **not** deployed as a separate
   parallel stack - instead its patterns were folded into the real
   frontend/backend/worker deployment: the readiness/liveness timing spec,
   the anti-affinity requirement, the emptyDir cache mount, and the
   PVC/nodeAffinity pattern all ended up on `deployment-frontend.yaml` /
   `deployment-redis.yaml`. `db-migration` and `cache-cleanup` are the real
   Job/CronJob equivalents of that assignment's `db-migration`/
   `cache-cleanup` examples, wired to this project's actual Postgres schema
   and actual (bonus) cache tier instead of `echo` placeholders.
3. **Advanced assignment ("DevOps on AWS")**: this README, `ingress.yaml`,
   `network-policies/`, `rbac/`, and the Security section above are a direct
   implementation of its numbered requirements (Namespace, Deployments,
   Services, Ingress/LoadBalancer, ConfigMaps, Secrets, RDS/S3/SNS
   connection, RBAC, Secrets Management, Network Security, Container
   Security, Image Security, Ingress Security, architecture diagram).
4. **Naming**: the app tier is called `web-api` in the intermediate
   assignment's practical scenario and `frontend` / `nginx` everywhere else
   (including the actual application code) - this project uses `frontend`
   throughout, since that's what the real service is.

   Thanks.
   