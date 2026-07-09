# student-web - a from-scratch Helm chart, step by step

**Who this is for:** learning what Helm actually generates, one command at a
time, before touching the real four-service `cv-platform` chart next door.
Every command below is copy-paste-able in **Windows PowerShell** and tells
you exactly what you should see if it worked.

**What this chart is:** the smallest possible real Helm chart - one NGINX
`Deployment` + one `Service` - built to satisfy the assignment's Part 1
practical section exactly as written. It deliberately does **not** try to be
the real application (that's `../cv-platform/`, see
[the "Or with Helm" section of `k8s/README.md`](../../README.md)) - fewer moving
parts means the `helm install` / `upgrade` / `rollback` history is easy to
read.

---

## 0. Before you start

1. **Helm is installed:**
   ```powershell
   helm version
   ```
   Should print something like `version.BuildInfo{Version:"v3...`.
2. **You have a cluster to point at.** Any will do - the fastest is the
   `kind` cluster from
   [`../../../docs/local-kind-runbook.md`](../../../docs/local-kind-runbook.md)
   Part A (`kind create cluster --name cv-platform`, then `kubectl get nodes`
   to confirm). This chart has no AWS dependency at all - `kind`/`minikube`/
   Docker Desktop's built-in Kubernetes are all fine.
3. You're in a terminal at the repo root (the folder containing `k8s/`).

---

## 1. What's actually in this folder, and why

```
k8s/helm/student-web/
├── Chart.yaml           # chart identity: name + chart version + app version
├── values.yaml           # every default parameter - the chart's "API"
├── values-dev.yaml        # dev overrides (only what differs from values.yaml)
├── values-prod.yaml       # prod overrides (only what differs from values.yaml)
├── templates/
│   ├── _helpers.tpl       # reusable name/label snippets - see below
│   ├── deployment.yaml    # the NGINX Deployment
│   ├── service.yaml       # the Service in front of it
│   └── NOTES.txt          # printed after every install/upgrade
└── README.md               # this file
```

**`Chart.yaml`** identifies the chart to Helm itself: `name` (must match the
folder name Helm expects to find it in), `version` (the *chart's* own
version - bump this when you change the templates), and `appVersion` (just a
label for which version of the *application* - here, NGINX - this chart
version deploys; Helm doesn't parse or enforce it, it's informational).

**`values.yaml`** is the one file that defines every knob this chart
exposes: `replicaCount`, `image.repository`/`image.tag`, `service.port`.
Nothing in `templates/` hardcodes any of these - they all read
`.Values.replicaCount` etc. instead, so the exact same template renders
differently depending on which values file(s) you pass at install time.

**`templates/_helpers.tpl`** defines three reusable snippets so the naming/
labeling logic exists in exactly one place instead of being retyped in both
`deployment.yaml` and `service.yaml`:
- `student-web.fullname` → the name every resource gets, prefixed with the
  Helm *release* name (so two releases of this chart never collide).
- `student-web.labels` → the full, human-readable label set (chart version,
  app version, `managed-by: Helm`) - safe to change on every upgrade.
- `student-web.selectorLabels` → the minimal label pair
  (`app.kubernetes.io/name` + `app.kubernetes.io/instance`) used **only**
  where Kubernetes has to *match* Pods (`Deployment.spec.selector`,
  `Service.spec.selector`) - kept separate because that field is immutable
  once a Deployment exists, so it must never contain a label that's allowed
  to change later.

Both `deployment.yaml` and `service.yaml` call these with
`{{ include "student-web.fullname" . }}` / `{{ include "student-web.labels" . | nindent 4 }}`
- that's what "use the helper functions throughout the chart" means in
practice: zero hardcoded names or label blocks anywhere else in the chart.

**`templates/NOTES.txt`** is plain text (with the same `{{ }}` templating
available) that Helm prints to your terminal automatically after every
`helm install`/`helm upgrade` - the "what do I do now" message.

---

## 2. Lint it (no cluster needed)

```powershell
helm lint .\k8s\helm\student-web
```
Expected output:
```
==> Linting .\k8s\helm\student-web
[INFO] Chart.yaml: icon is recommended
1 chart(s) linted, 0 chart(s) failed
```
The `icon is recommended` line is just a suggestion (charts published to a
public repo benefit from one) - not an error. `0 chart(s) failed` is the
part that matters: Helm parsed every template and found no structural
problems, without ever contacting a cluster.

## 3. Render it and read the output (still no cluster needed)

```powershell
helm template student-web .\k8s\helm\student-web
```

This prints the exact plain Kubernetes YAML Helm *would* send to the
cluster - it's the single best way to understand what a chart does, because
every `{{ }}` template expression is gone, replaced by its real value. Look
for:
- `metadata.name: student-web` - this came from the `student-web.fullname`
  helper: release name `student-web` already contains the chart name
  `student-web`, so it isn't repeated (compare Section 6 below, where the
  release is named `student-web-dev` instead).
- `spec.replicas: 2` - straight from `values.yaml`'s `replicaCount: 2`.
- `spec.selector.matchLabels` and `spec.template.metadata.labels` **both**
  contain `app.kubernetes.io/name: student-web` /
  `app.kubernetes.io/instance: student-web` - proof the selector helper and
  the Pod template are using the exact same source, so they can never drift
  apart.

Try it again with a different values file to see the same templates render
differently:
```powershell
helm template student-web-dev .\k8s\helm\student-web -f .\k8s\helm\student-web\values-dev.yaml
```
`spec.replicas` is now `1`, and every resource name is now prefixed
`student-web-dev-` instead of `student-web-` - same templates, different
release name + values, different output.

## 4. Install it for real

```powershell
helm install student-web .\k8s\helm\student-web
```
Expected output ends with the NOTES.txt message and:
```
NAME: student-web
LAST DEPLOYED: ...
NAMESPACE: default
STATUS: deployed
REVISION: 1
```
`REVISION: 1` is the important part - this is Helm creating **release**
history entry #1 (stored as a Secret named
`sh.helm.release.v1.student-web.v1` in the same namespace, if you're
curious: `kubectl get secrets | Select-String helm`). This is what makes
`helm rollback` possible later.

Verify it actually created real resources:
```powershell
kubectl get deployment,svc,pods -l app.kubernetes.io/instance=student-web
```
You should see 2 Pods (matching `replicaCount: 2`), 1 Deployment, 1 Service,
all named `student-web`.

## 5. Upgrade it - 2 replicas to 5

```powershell
helm upgrade student-web .\k8s\helm\student-web --set replicaCount=5
```
`--set replicaCount=5` overrides just that one value on top of
`values.yaml`'s default of `2`, for this one command - it does **not** edit
any file. Expected output now says `REVISION: 2`. Confirm:
```powershell
kubectl get deployment student-web
kubectl rollout status deployment/student-web
```
You should see `5/5` ready.

Check the revision history Helm has been building:
```powershell
helm history student-web
```
```
REVISION  UPDATED       STATUS      CHART               APP VERSION  DESCRIPTION
1         ...           superseded  student-web-0.1.0    1.27        Install complete
2         ...           deployed    student-web-0.1.0    1.27        Upgrade complete
```

## 6. Roll back - and how Helm knows which version to restore

```powershell
helm rollback student-web 1
```
This tells Helm: "re-apply exactly what revision 1's rendered manifests
were." Helm can do this because **every** `install`/`upgrade` is stored as
its own Secret (revision 1's Secret still exists even after revision 2 was
created - Helm never deletes old revisions on its own) containing that
revision's fully-rendered YAML *and* the values used to produce it. Rolling
back doesn't "undo" revision 2 - it creates a **new** revision 3 whose
content happens to match revision 1's:
```powershell
helm history student-web
```
```
REVISION  ...  DESCRIPTION
1         ...  Install complete
2         ...  Upgrade complete
3         ...  Rollback to 1
```
Confirm replicas are back to 2:
```powershell
kubectl get deployment student-web
```

## 7. Deploy both environments from their own values files

```powershell
helm install student-web-dev  .\k8s\helm\student-web -f .\k8s\helm\student-web\values-dev.yaml
helm install student-web-prod .\k8s\helm\student-web -f .\k8s\helm\student-web\values-prod.yaml
```
Two independent Releases of the same Chart, side by side (see
`docs/helm-argocd-assignment-answers.md` Part 1 Q7 for the Chart-vs-Release
distinction) - `kubectl get deploy` now shows `student-web`,
`student-web-dev`, and `student-web-prod`, each with the replica count its
own values file specified.

## 8. Clean up

```powershell
helm uninstall student-web
helm uninstall student-web-dev
helm uninstall student-web-prod
```

---

Next: [`../../argocd/README.md`](../../argocd/README.md) - hand this exact
chart (or the real `cv-platform` one) to ArgoCD so Git, not your terminal,
becomes the thing that runs these commands.
