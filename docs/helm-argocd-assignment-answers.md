# Kubernetes Home Assignment - Helm & ArgoCD - Answers

Written answers for `4_Home Assignment part_3 Helm Argocd.pdf`, in the same
style as `k8s-assignment1-answers.md` / `k8s-assignment2-answers.md` - every
answer is tied to a real file in this repo, not a generic textbook example.

**Where the practical deliverables live:**
- Part 1 practical ("create a chart named `student-web`"): [`../k8s/helm/student-web/`](../k8s/helm/student-web/) - see its own [README.md](../k8s/helm/student-web/README.md) for the baby-step install/upgrade/rollback walkthrough.
- Part 2 + Part 3 practical (ArgoCD, the real production chart): [`../k8s/helm/cv-platform/`](../k8s/helm/cv-platform/) (already existed as this project's "deploy with Helm instead of raw `kubectl apply`" option; upgraded here to use `_helpers.tpl` throughout and gain `values-dev.yaml`/`values-prod.yaml`) plus [`../k8s/argocd/`](../k8s/argocd/) for the `Application` manifests. See [`../k8s/argocd/README.md`](../k8s/argocd/README.md) for the full ArgoCD walkthrough and what each practical step actually does.

Why two charts instead of one: `student-web` is a deliberately tiny,
disposable teaching chart - a single Deployment + Service - so the
install/upgrade/rollback revision history is easy to read with nothing else
going on. `cv-platform` is the real four-tier application this whole repo
deploys, and is the one actually meant to run production-style behind
ArgoCD. Folding the *learning* exercise into the *real* chart (the way the
intermediate K8s assignment's "flash-sale" scenario was folded into
`deployment-frontend.yaml` etc., see `k8s-assignment2-answers.md`) would
have made the simple rollback demo hard to follow underneath four
Deployments, two ConfigMaps, RBAC, NetworkPolicies, etc. - so this one
assignment gets both: a minimal chart for the mechanics, the real chart for
the production-shaped final project.

---

## Part 1 - Helm (Theory)

**1. What problem does Helm solve in Kubernetes?**
Plain `kubectl apply -f` manifests (like `../k8s/*.yaml`) have no concept of
"one versioned, parameterized unit." Every environment difference (replica
count, image tag, hostname) has to be hand-edited into the YAML itself, there
is no built-in history of what was previously applied, and "undo my last
change" means manually reconstructing the old YAML from memory or git. Helm
adds three things on top: **templating** (one set of YAML files, rendered
differently per environment via a `values.yaml`), **packaging** (a "Chart" -
one versioned, shareable unit, like an npm package for Kubernetes manifests),
and **release tracking** (Helm remembers every past revision of what was
installed, so `helm rollback` is a real, one-command operation instead of a
manual reconstruction).

**2. Kubernetes Manifest vs. Helm Chart.**
A Manifest (`../k8s/deployment-backend.yaml`) is one static, already-final
YAML file - what you see is exactly what gets applied, every time, for every
environment. A Chart (`../k8s/helm/cv-platform/`) is a *template* plus a
`values.yaml` of parameters - the same chart renders differently depending on
which values file it's combined with (compare `../k8s/helm/cv-platform/values-dev.yaml`
vs. `values-prod.yaml` - same templates, different replica counts/namespace/
hostname).

**3. Purpose of each file:**
- **`Chart.yaml`** - the chart's own metadata: name, chart version
  (`version`), and the version of the *application* it deploys
  (`appVersion`) - these are two independent numbers (see
  `../k8s/helm/cv-platform/Chart.yaml`: chart `0.1.0`, app `1.0.0`).
- **`values.yaml`** - the default parameters every template reads via
  `.Values.*` - the single place that defines every override point of the
  chart (`../k8s/helm/cv-platform/values.yaml`).
- **`templates/`** - the actual Kubernetes YAML, written with Go template
  syntax (`{{ }}`) instead of hardcoded values - Helm renders every file in
  here against `values.yaml` (+ any `-f`/`--set` overrides) before
  `kubectl apply`-ing the result.
- **`_helpers.tpl`** - not a manifest itself (the leading underscore tells
  Helm to skip rendering it directly) - it only *defines* reusable named
  template snippets (`{{- define "cv-platform.fullname" -}}`) that other
  files in `templates/` call with `{{ include ... }}`. See Q9 below for why
  this matters.
- **`NOTES.txt`** - plain text (with the same `{{ }}` templating available)
  printed to the terminal automatically after `helm install`/`helm upgrade`
  finishes - the "what do I do now" message (see
  `../k8s/helm/cv-platform/templates/NOTES.txt`, which prints the right
  `kubectl get` command and a warning if secrets were rendered from values).

**4. Purpose of `{{ }}`.**
It's Helm's templating delimiter (Go's `text/template` engine under the hood)
- anything inside gets evaluated and substituted before the YAML is sent to
Kubernetes; anything outside is copied through literally. Example from
`../k8s/helm/cv-platform/templates/deployment-backend.yaml`:
```yaml
replicas: {{ .Values.backend.replicas }}
```
`.Values.backend.replicas` looks up the `backend.replicas` key in whichever
values file(s) were passed to `helm install`/`helm template` - so this one
line renders as `replicas: 2` against `values-prod.yaml` and `replicas: 1`
against `values-dev.yaml`, from the exact same template file.

**5. `helm install` / `helm upgrade` / `helm rollback` / `helm template` / `helm lint`.**
- `helm install <release> <chart>` - creates a **new** Release (fails if one
  by that name already exists in the namespace).
- `helm upgrade <release> <chart>` - changes an **existing** Release to a new
  chart version and/or new values, recording the change as a new revision.
  `helm upgrade --install` does either, whichever applies - the form used
  everywhere in this repo's own docs (`../k8s/README.md`) since it works the
  first time too.
- `helm rollback <release> <revision>` - reverts a Release back to a
  previously-recorded revision's exact rendered manifests (see Q7).
- `helm template <chart>` - renders the chart to YAML **locally**, prints it
  to stdout, and touches the cluster **not at all** (no API calls, doesn't
  even need `kubectl` configured) - purely "show me what would be applied."
- `helm lint <chart>` - static analysis of the chart's structure/templates
  (missing required values, malformed YAML, bad chart metadata) - also
  doesn't touch the cluster. Both `helm lint` and `helm template` were run
  against every values combination in this repo as part of building it (see
  the command transcript in `../k8s/helm/cv-platform/README.md` if present,
  or re-run them yourself - exact commands in
  [`../k8s/helm/student-web/README.md`](../k8s/helm/student-web/README.md)).

**6. What is a Helm Release?**
One specific, named, running instance of a Chart installed into a namespace
- e.g. `cv-platform-dev` (from `k8s/argocd/cv-platform-dev-application.yaml`)
is a Release: it has its own revision history, its own currently-active
values, and its own set of live Kubernetes objects, all independent of any
other Release of the same Chart (e.g. `cv-platform-prod`) elsewhere in the
cluster.

**7. Helm Chart vs. Helm Release.**
The Chart is the template - unopinionated about *where* or *how many times*
it's deployed. The Release is one specific deployment of that Chart, with one
specific set of values, at one specific point in its own upgrade/rollback
history. Directly analogous to a class (Chart) vs. an instance of that class
(Release) - `cv-platform-dev` and `cv-platform-prod` are two Releases of the
exact same `cv-platform` Chart.

**8. `helm install` vs. `helm template`.**
`helm template` only renders YAML to your terminal/a file - completely
inert, no cluster contact, safe to run with zero permissions. `helm install`
does that same rendering **and then actually submits the result to the
Kubernetes API** (creating real objects) **and** records a new Release in
Helm's own storage (a Secret per revision, in-cluster) so future
upgrade/rollback/history commands have something to work from. Always
`helm template` first when unsure what a change will render as - it's the
zero-risk way to preview.

**9. Why is `_helpers.tpl` a best practice?**
Without it, every template repeats the same boilerplate (name, labels,
selector labels) with hand-typed strings - easy to typo, and a `Deployment`
whose `spec.selector.matchLabels` accidentally drifts from its own Pod
template's `metadata.labels` (even by one character) means the Deployment
can never find the Pods it created. `_helpers.tpl` defines that logic
**once** (`{{- define "cv-platform.selectorLabels" -}}` in
`../k8s/helm/cv-platform/templates/_helpers.tpl`) and every template
`{{ include }}`s it - so a naming-convention change is a one-file edit
instead of a find-and-replace across 14 files, and it's structurally
impossible for the selector labels to drift from the Pod template labels
because both come from the same `{{ include }}` call. See Q's below for what
this project's fullname/labels/selectorLabels helpers actually do.

**Practical - fullname / labels / selectorLabels, and what "used throughout
the chart" actually changed.**
Both charts define the same three helpers (`../k8s/helm/student-web/templates/_helpers.tpl`,
`../k8s/helm/cv-platform/templates/_helpers.tpl`):
- **`<chart>.fullname`** - `<release-name>-<chart-name>` (deduped if the
  release name already contains the chart name), so `helm install
  cv-platform-dev` names every resource it owns `cv-platform-dev-backend`,
  `cv-platform-dev-frontend-svc`, etc. Before this change, `cv-platform`'s
  templates all hardcoded plain names (`name: backend`) - which meant a
  second Release of the same chart in the same namespace (or even a typo'd
  double-install) would collide on every single resource name.
- **`<chart>.labels`** - the full, informational label set (chart version,
  app version, `managed-by: Helm`, ...) stamped on `metadata.labels`. Safe to
  change on every upgrade.
- **`<chart>.selectorLabels`** - the minimal, **immutable** subset
  (`app.kubernetes.io/name` + `app.kubernetes.io/instance`, plus this
  project's own `app.kubernetes.io/component` for the per-tier variant) used
  **only** where Kubernetes has to *match* Pods: `Deployment.spec.selector`,
  `Service.spec.selector`, `NetworkPolicy.spec.podSelector`. Kept separate
  from `labels` on purpose - `Deployment.spec.selector` is immutable after
  creation, so if a "safe to change" label like chart version ever leaked
  into it, the very next `helm upgrade` that bumped the chart version would
  fail outright with an immutable-field error.

Confirm it yourself:
```bash
helm template cv-platform-dev ./k8s/helm/cv-platform \
  -f k8s/helm/cv-platform/values.yaml -f k8s/helm/cv-platform/values-dev.yaml \
  --set secrets.dbHost=x --set secrets.dbPassword=y | grep "^  name:"
```
Every name comes back prefixed `cv-platform-dev-...` - that's `fullname`
being used throughout the chart, not just defined and ignored.

---

## Part 2 - ArgoCD (Theory)

**1. What is GitOps?**
An operating model where **Git is the single source of truth** for what
should be running in a cluster, and a controller (ArgoCD) continuously makes
the cluster match Git - rather than engineers running `kubectl apply`/`helm
upgrade` by hand from their laptop. Every change to what's deployed happens
as a Git commit (reviewable, revertible, auditable in `git log`), never as a
direct, untracked cluster mutation.

**2. Why is ArgoCD "declarative"?**
You never tell ArgoCD *how* to change the cluster (no "scale to 5", no "add
this env var") - you only tell it **what the end state should look like**
(by pointing it at a Git path, per `k8s/argocd/cv-platform-dev-application.yaml`'s
`spec.source`), and ArgoCD works out the *how* itself (compute a diff, apply
only what's changed) every reconciliation cycle. This is the same
declarative-vs-imperative distinction as `kubectl apply` (declarative) vs.
`kubectl scale`/`kubectl edit` (imperative) - ArgoCD is that same idea, one
level up, applied continuously and automatically instead of once per manual
command.

**3. Desired State / Actual State / Reconciliation / Configuration Drift.**
- **Desired State** - whatever the Git repo says right now (the rendered
  output of `k8s/helm/cv-platform` + `values-prod.yaml` at the commit
  `targetRevision: main` currently points to).
- **Actual State** - whatever is really running in the cluster this instant
  (queried live from the Kubernetes API).
- **Reconciliation** - ArgoCD's continuous loop: fetch Desired State, query
  Actual State, diff them, and (if `syncPolicy.automated` is set, as in this
  repo's Application manifests) apply whatever's needed to make Actual match
  Desired.
- **Configuration Drift** - the gap that opens up when Actual State diverges
  from Desired State outside of Git - e.g. someone runs `kubectl scale
  deployment/cv-platform-prod-backend --replicas=10` directly. Drift is
  exactly what **Self Heal** (Q9) exists to correct automatically.

**4. `Synced` / `OutOfSync` / `Healthy` / `Degraded`.**
- **Synced** - Actual State == Desired State (Git and cluster agree, or the
  last reconciliation already made them agree).
- **OutOfSync** - they differ - either Git changed and hasn't been applied
  yet, or something drifted in the cluster outside of Git.
- **Healthy** - ArgoCD's built-in per-resource health checks say the
  resources are up and functioning (e.g. a Deployment's
  `status.readyReplicas` == `spec.replicas`).
- **Degraded** - a resource's health check is actively failing (e.g. Pods
  crash-looping, a Deployment stuck below its desired replica count).
  `Synced` and `Healthy` are **independent axes** - a Release can be
  perfectly `Synced` (cluster exactly matches a bad Git commit) while
  `Degraded` (that bad commit points at an image tag that doesn't exist).

**5. How does ArgoCD deploy a Helm Chart behind the scenes?**
ArgoCD's repo-server clones the Git repo at `targetRevision`, finds the chart
at `spec.source.path` (`k8s/helm/cv-platform`), and calls the Helm **client
library directly** to render it (`helm template`-equivalent) using
`spec.source.helm.valueFiles` (this repo's `values.yaml` + `values-dev.yaml`/
`values-prod.yaml`) - producing plain Kubernetes YAML. It then diffs that
rendered YAML against live cluster state and applies (via the Kubernetes API,
not `kubectl` as a subprocess) whatever's different. No Helm **release**
object (the in-cluster Secret Helm itself would normally create) is created
by ArgoCD's default "Helm as a template renderer" mode - see Q6.

**6. Why doesn't ArgoCD execute `helm install`?**
`helm install`/`helm upgrade` would hand release-tracking ownership to
Helm's own in-cluster state (the `sh.helm.release.v1.*` Secrets), which
ArgoCD would then have to stay in sync with on top of its own Git-tracked
state - two separate sources of truth for the same thing. Instead ArgoCD
treats Helm purely as a **template renderer** (identical to running `helm
template` yourself) and manages the resulting plain YAML the exact same way
it manages a directory of raw manifests or a Kustomize overlay - one
consistent reconciliation model regardless of which templating tool
produced the YAML.

**7. What is the purpose of the Diff Engine?**
It's what actually computes "Desired State vs. Actual State" field-by-field
(not just "does a resource with this name exist") - the OutOfSync detection
in Q4 and the change list a manual `Sync` would apply both come from this
diff, and it's specifically what a `kubectl scale` drift (Q9's demo) shows up
as: `spec.replicas: 5 (desired) != 3 (actual)`.

**8. What is the purpose of Auto Sync?**
Without it, ArgoCD only ever **detects** drift (`OutOfSync`) and waits for a
human to click "Sync" - useful for prod environments that want a manual
approval gate. `syncPolicy.automated` (set on every Application in
`k8s/argocd/`) skips that gate: the moment ArgoCD's reconciliation loop sees
`OutOfSync`, it applies the change itself, with no human in the loop. This is
what makes "commit to Git" alone (Part 2/3's practical steps) enough to
actually change the running cluster.

**9. What is the purpose of Self Heal?**
Auto Sync alone only reacts to **Git** changing. Self Heal
(`syncPolicy.automated.selfHeal: true`) additionally reacts to the
**cluster** changing outside of Git - if someone runs `kubectl scale
deployment/cv-platform-dev-backend --replicas=10` directly, the next
reconciliation notices Actual State no longer matches Desired State (even
though Git never changed) and reverts it back to what Git says. This is the
practical enforcement of "Git is the only source of truth" - without Self
Heal, a manual `kubectl` change would just sit there indefinitely as
undetected drift.

**10. What is the purpose of Prune?**
When a resource is removed from the chart's rendered output (e.g. deleting
`k8s/helm/cv-platform/templates/ingress.yaml`, or setting
`ingress.enabled: false` in a values file, then committing), the resource
still exists in the cluster from before - Git no longer mentions it, but
nothing has told the cluster to delete it either. `syncPolicy.automated.prune:
true` makes ArgoCD delete any live resource it owns that's no longer present
in Desired State, so "removed from Git" reliably means "removed from the
cluster" too, instead of leaving an orphaned, silently-still-running
resource.

---

See [`../k8s/argocd/README.md`](../k8s/argocd/README.md) for the practical
walkthrough (install ArgoCD, apply the Application manifests, and the exact
sequence of Git-only / `kubectl`-only changes that demonstrate every
behavior answered above) and
[`../k8s/helm/student-web/README.md`](../k8s/helm/student-web/README.md) for
the Helm-only install/upgrade/rollback walkthrough.
