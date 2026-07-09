# ArgoCD - step by step

**Who this is for:** you've already worked through
[`../helm/student-web/README.md`](../helm/student-web/README.md) and know
what `helm install`/`upgrade`/`rollback` do by hand. This is the next layer:
instead of you running those commands from your terminal, ArgoCD watches
this Git repo and runs the equivalent of `helm template` + `kubectl apply`
**for you**, automatically, every time something changes. Commands below are
**Windows PowerShell**.

**Concepts first:** if "Desired State", "Reconciliation", "OutOfSync", "Self
Heal", "Prune" don't mean anything yet, read
[`../../docs/helm-argocd-assignment-answers.md`](../../docs/helm-argocd-assignment-answers.md)
Part 2 first - this file is the *practical* companion to those definitions,
not a repeat of them.

---

## 0. Before you start

1. A cluster - the `kind` cluster from
   [`../../docs/local-kind-runbook.md`](../../docs/local-kind-runbook.md) works
   fine (`kind create cluster --name cv-platform`, then `kubectl get nodes`
   to confirm).
2. This repo pushed to a Git remote ArgoCD can reach - the Application
   manifests in this folder are already pointed at
   `https://github.com/eg185044/DevOps.git`, `targetRevision: main`. If
   you're working from a fork or a different remote, edit `repoURL` in each
   `*-application.yaml` first.

---

## 1. Install ArgoCD into the cluster

```powershell
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```
This is a one-time, ArgoCD-provided bundle of CRDs + controllers - not
something this repo needs to vendor a copy of. Wait for everything to come
up:
```powershell
kubectl get pods -n argocd -w
```
Ctrl+C once every pod shows `Running`/`1/1` (usually under 2 minutes).

## 2. Access the UI via `kubectl port-forward`

```powershell
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
Leave this running in its own terminal window. Open
**https://localhost:8080** (accept the self-signed cert warning - this is
local-only traffic).

Get the auto-generated admin password (only exists until you change it):
```powershell
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}"
```
That prints base64. Decode it:
```powershell
$b64 = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}"
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64))
```
Log in as `admin` with that password.

## 3. Push this Helm chart to Git

If you haven't already:
```powershell
git add k8s/helm k8s/argocd docs/helm-argocd-assignment-answers.md
git commit -m "Add Helm charts and ArgoCD Application manifests"
git push
```
ArgoCD only ever reads from the Git remote (`repoURL`/`targetRevision` in
the Application spec) - it never reads your local working directory. Every
step from here on requires the change to actually be **pushed**, not just
committed locally.

## 4. Create the ArgoCD Application

Start with the simple chart, matching Part 2's practical steps:
```powershell
kubectl create namespace student-web
kubectl apply -n argocd -f k8s\argocd\student-web-application.yaml
```
Watch it pick the chart up and deploy it:
```powershell
kubectl get application -n argocd -w
```
Within a few seconds you should see `student-web` go
`Synced`/`Healthy`. This one `kubectl apply` is the **only** manual step in
this entire workflow - from here on, changes happen through Git.

(The real application - `cv-platform-dev-application.yaml` /
`cv-platform-prod-application.yaml` - follow the identical pattern; see
[Part 3 below](#6-part-3---the-cv-platform-final-project-changes). They
don't need `kubectl create namespace` first because the chart creates its
own `Namespace` object - `k8s/helm/cv-platform/templates/namespace.yaml`.)

## 5. Auto Sync / Self Heal / Prune are already on

Look at `k8s/argocd/student-web-application.yaml`'s `spec.syncPolicy`:
```yaml
syncPolicy:
  automated:
    selfHeal: true
    prune: true
```
This is the "Enable Auto Sync, Self Heal and Prune" checkbox from the
assignment, done declaratively instead of clicked in the UI - `automated:`
being present at all **is** Auto Sync; `selfHeal`/`prune` are its two
sub-flags. (You can toggle these live in the UI too - App → App Details →
Sync Policy - but then the *running* config and *Git* disagree about
whether autosync is on, which defeats the point of a GitOps demo. Change
the YAML and push instead.)

### 5a. Modify replicas in Git, commit, push - what happens

```powershell
(Get-Content k8s\helm\student-web\values.yaml) -replace 'replicaCount: 2', 'replicaCount: 4' | Set-Content k8s\helm\student-web\values.yaml
git add k8s\helm\student-web\values.yaml
git commit -m "Scale student-web to 4 replicas"
git push
```
Within ArgoCD's default 3-minute polling interval (or immediately if you
click "Refresh" in the UI), the Application briefly shows **OutOfSync**
(Desired State from the new commit != Actual State still at 2 replicas),
then - because Auto Sync is on - ArgoCD applies the change itself and it
flips back to **Synced**. Confirm:
```powershell
kubectl get deployment student-web -n student-web
```

### 5b. Manually scale with `kubectl scale` - what ArgoCD does

```powershell
kubectl scale deployment/student-web -n student-web --replicas=10
kubectl get application student-web -n argocd -w
```
You'll briefly see 10 Pods, and the Application flip to **OutOfSync** (Git
still says 4, cluster now says 10) - then, because **Self Heal** is on,
ArgoCD reverts it back to 4 within its next reconciliation, with **no Git
change and no human action**. This is Self Heal doing exactly what
[the theory doc](../../docs/helm-argocd-assignment-answers.md) describes:
enforcing that Git, not `kubectl`, is the only real source of truth.

### 5c. Delete a resource from Git - what happens after sync

student-web has no Ingress to delete, so do this against the real chart
(see [Part 6](#6-part-3---the-cv-platform-final-project-changes) `Delete
the Ingress resource`) - the mechanism (Prune) is identical either way.

### 5d. Disable Auto Sync and change something else

Edit `k8s/argocd/student-web-application.yaml`, remove the whole
`automated:` block (leave `syncPolicy: {}` or delete `syncPolicy` entirely),
commit, push, then re-apply that one file by hand (since ArgoCD itself is no
longer auto-applying anything, including changes to its own Application
object unless you're also running `app-of-apps` - out of scope here):
```powershell
kubectl apply -n argocd -f k8s\argocd\student-web-application.yaml
```
Now repeat 5a (change a value in Git, commit, push). This time the
Application sits at **OutOfSync** indefinitely - ArgoCD has *detected* the
diff (that part never stops) but won't *apply* it without an explicit
```powershell
argocd app sync student-web
```
(or clicking "Sync" in the UI). This is the difference the assignment asks
you to explain: with Auto Sync, Git commit alone changes the cluster; without
it, Git commit only changes what ArgoCD *shows* as pending, until a human
approves it - the manual-gate model a real production environment might
deliberately want on top of prod, even while dev stays fully automated.
Re-enable `automated:` afterwards to match [Part 6](#6-part-3---the-cv-platform-final-project-changes)'s
expectations, commit, push, and re-apply.

---

## 6. Part 3 - the `cv-platform` final project changes

```powershell
kubectl apply -n argocd -f k8s\argocd\cv-platform-dev-application.yaml
```
(`devops-app-dev` namespace is created automatically by the chart's own
`templates/namespace.yaml`.) This Application already has
`valueFiles: [values.yaml, values-dev.yaml]` wired in
(`k8s/argocd/cv-platform-dev-application.yaml`), so every change below is a
one-line edit to `k8s/helm/cv-platform/values-dev.yaml`, then commit + push
- never edit a template file for any of these:

| Assignment step | Git-only change |
|---|---|
| Scale 2 → 5 replicas | `values-dev.yaml`: `backend.replicas: 5` |
| Upgrade the image version | `values-dev.yaml`: add e.g. `backend.tag: "1.1.0"` (needs a real pushed image at that tag to go `Healthy`, but `Synced` happens either way) |
| Service ClusterIP → NodePort | `values-dev.yaml`: add `frontend.service.type: NodePort` (this override point was added specifically for this demo - see `k8s/helm/cv-platform/values.yaml`'s `frontend.service.type`) |
| Add a new environment variable | `values-dev.yaml`: add a new key under `config:`, e.g. `config.featureFlag: "true"` - `backend`/`worker`'s `envFrom: configMapRef` (see `templates/deployment-backend.yaml`) picks up **every** key in the ConfigMap automatically, so a new `config.*` value in Git *is* a new env var, with no template change |
| Delete the Ingress resource | `values-dev.yaml`: `ingress.enabled: false` - the chart's `templates/ingress.yaml` is wrapped in `{{- if .Values.ingress.enabled }}`, so this makes the rendered output stop including it entirely; Prune then deletes the live Ingress object on the next sync |
| Verify Self Heal after `kubectl scale` | `kubectl scale deployment/cv-platform-dev-backend -n devops-app-dev --replicas=1`, then watch it get reverted back to whatever `values-dev.yaml` currently says - same mechanism as [5b](#5b-manually-scale-with-kubectl-scale---what-argocd-does) |

For each row: edit the file, then
```powershell
git add k8s\helm\cv-platform\values-dev.yaml
git commit -m "<describe the change>"
git push
kubectl get application cv-platform-dev -n argocd -w
```
and take your screenshot at the `OutOfSync` moment and again once it
settles back to `Synced`/`Healthy` - that pair of screenshots **is** the
"ArgoCD Synced" / "ArgoCD OutOfSync" deliverable the assignment asks for.

Repeat against `cv-platform-prod-application.yaml` /
`values-prod.yaml` for the prod environment once you're comfortable with the
dev cycle.

## 7. Clean up

```powershell
kubectl delete -n argocd -f k8s\argocd\student-web-application.yaml
kubectl delete -n argocd -f k8s\argocd\cv-platform-dev-application.yaml
kubectl delete -n argocd -f k8s\argocd\cv-platform-prod-application.yaml
kubectl delete namespace argocd student-web devops-app-dev devops-app
```
The `resources-finalizer.argocd.argoproj.io` finalizer on each Application
(see the YAML files) means deleting the `Application` object itself also
deletes every resource it created - the explicit namespace deletes above are
just belt-and-suspenders / faster cleanup.
