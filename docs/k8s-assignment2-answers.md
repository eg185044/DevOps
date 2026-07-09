# Kubernetes Intermediate Assignment - Part 1 Answers

Written answers for the conceptual questions in
`2_Kubernetes Home Assignment Intermediate Topics.pdf`. Part 2 of that PDF
(the "flash sale" practical scenario) was not built as a separate parallel
stack - its patterns (probes, PVC, anti-affinity, taints, Jobs/CronJobs)
were applied directly to the real frontend/backend/worker/redis-cache
manifests in `../k8s/`; see `../k8s/README.md`
"[Assumptions & how the three assignments were combined](../k8s/README.md#assumptions--how-the-three-assignments-were-combined)"
for exactly what maps to what.

## 1. Volumes

**1. `emptyDir` lifecycle.**
Created empty when a Pod is scheduled to a node, exists for the Pod's
lifetime, and is deleted permanently (data included) the moment the Pod is
removed from that node - a container restarting *within* the same Pod keeps
the data, but the Pod being deleted/rescheduled does not. This project uses
one at `/tmp/cache` on `frontend` (`deployment-frontend.yaml`) - explicitly
disposable, never a source of truth.

**2. `hostPath` vs `emptyDir`.**
`hostPath` mounts a path from the **node's own filesystem** - so restarting
the Pod on the *same* node keeps the data (unlike `emptyDir`), but
rescheduling to a *different* node loses it, since it's not the same disk.
Concrete example: reading `/var/log` or `/var/run/docker.sock` from the
host for a node-level monitoring/log-shipping DaemonSide-car. Be careful:
it gives a container filesystem access on the host outside Kubernetes'
control - a compromised container with a `hostPath` mount to `/` is a
straightforward path to node takeover, so it's avoided entirely in this
project.

**3. PV vs PVC, who creates each on AWS.**
A `PersistentVolume` is the actual piece of storage (here, an EBS volume) -
cluster-scoped, usually **not** hand-written by an app team. A
`PersistentVolumeClaim` is a namespaced *request* for storage ("1Gi,
ReadWriteOnce") that an app team does write (`../k8s/pvc.yaml`'s
`redis-data`). In a production AWS/EKS setup, the **EBS CSI driver**
dynamically creates the PV (and the underlying EBS volume) in response to a
PVC that references a `StorageClass` (`gp3` here) - nobody hand-creates the
PV.

**4. `ReadWriteOnce` and the other access modes.**
`ReadWriteOnce` (RWO): mountable read-write by Pods on **one node** at a
time (multiple Pods on that same node can still share it). The others:
`ReadOnlyMany` (ROX) - many nodes, read-only (e.g. a shared reference
dataset); `ReadWriteMany` (RWX) - many nodes, read-write simultaneously
(needs a networked filesystem like EFS/NFS - EBS does not support this).
`redis-data` in this project is RWO because EBS is single-attach and
`redis-cache` only ever runs at `replicas: 1` (see the warning comment in
`deployment-redis.yaml`).

**5. EBS-backed PV reclaimPolicy on PVC delete.**
`Retain`: the underlying EBS volume is kept (not deleted), just detached and
marked `Released` - safe from accidental data loss, but it becomes an
orphaned volume someone has to notice and either re-bind or manually delete
(cost implication). `Delete` (the default for dynamically-provisioned EBS
volumes): the EBS volume is deleted along with the PV - convenient, but
means deleting a PVC by mistake permanently destroys the data with no
recovery path.

## 2. Labels and Selectors

**1. Label vs selector, Service example.**
A label is an arbitrary `key: value` tag on an object (`app: backend`).
A selector is a query against those labels (`app: backend`) used by another
object to find matches. `service-backend.yaml`'s
`selector: { app: backend, tier: backend }` is exactly this: it finds every
Pod carrying both labels and adds them to its Endpoints.

**2. Both `env=prod` and `tier=backend`.**
```bash
kubectl get pods -l env=prod,tier=backend
```
(comma = logical AND between label selectors).

**4. Can two Deployments select the same Pod?**
Not by *creating* the same Pod twice, but two Deployments **can** end up
with overlapping `spec.selector` match criteria against Pods that satisfy
both - Kubernetes doesn't prevent this at admission time. The problem: both
ReplicaSets will believe they own the same Pods, and will fight over
scaling/deleting them - Pods flap between being "extra" for one controller
and "missing" for the other. This project avoids it by giving every
Deployment's selector a compound, tier-specific match
(`{ app: backend, tier: backend }`, never just `app: backend` alone) so no
two Deployments' selectors can accidentally overlap.

**5. Why `app: myapp` alone is bad practice.**
It can't distinguish this Pod from every *other* component also labeled
`app: myapp` in a multi-service application, nor across environments/
versions. Recommended additions (used throughout this project):
`tier`/`component` (frontend/backend/worker/cache), `env` (production/
staging), and ideally the `app.kubernetes.io/*` convention
(`app.kubernetes.io/name`, `/part-of`, `/managed-by`) for tooling
interoperability.

## 3. ReplicaSet vs Deployment

**1. What a ReplicaSet guarantees / doesn't handle.**
Guarantees: exactly N Pods matching its selector are running at all times,
replacing any that die. Does **not** handle: rolling updates - a ReplicaSet
has no concept of a previous vs new Pod template or how to transition
between them without downtime; that orchestration is the Deployment's job.

**2. Manually delete one Pod from a `replicas: 3` ReplicaSet.**
The ReplicaSet controller notices only 2 Pods match its selector, and
immediately creates 1 new Pod to bring the count back to 3 - same
reconcile loop as Q2 in the beginner assignment, just observed directly on
the ReplicaSet instead of through a Deployment.

**3. Rolling update strategy.**
With `maxUnavailable: 1, maxSurge: 1` (used on every Deployment in this
project), Kubernetes creates 1 new-template Pod above the desired count,
waits for it to pass its readinessProbe, then removes 1 old-template Pod -
repeating until all Pods run the new template. At every point at least
`replicas - maxUnavailable` old-or-new Pods are Ready, so there's no
traffic-serving gap.

**4. Ever use a ReplicaSet directly? Honestly?**
Essentially never in practice. The only quasi-legitimate case is a
one-off/experimental workload you deliberately don't want rolling-update
semantics for - but even then a Deployment with `replicas` set once and
never changed behaves identically with strictly more capability. Nothing in
this project uses a bare ReplicaSet.

**5. `kubectl rollout undo deployment/my-app` under the hood.**
The Deployment controller looks at its stored `ControllerRevision` history
(one per previous `spec.template`, kept via the ReplicaSets it created),
picks the previous revision, and updates the Deployment's `spec.template`
back to that older Pod spec. From there it's an ordinary rolling update
*to* the old template - new (old-spec) Pods created, new (current-spec)
Pods removed, governed by the same `maxUnavailable`/`maxSurge` as any other
update.

## 4. Advanced Scheduling - nodeSelector, Affinity, Anti-Affinity

**1. `nodeSelector` vs `nodeAffinity` limitation.**
`nodeSelector` is a flat, exact-match `key: value` map - AND-only, no
"prefer but don't require," no `In`/`NotIn`/`Exists` operators. `nodeAffinity`
supports both required and preferred rules with richer match expressions.
`deployment-redis.yaml` needs exactly this: "prefer `storage=fast` nodes,
but still schedule somewhere if none exist" - not expressible with
`nodeSelector` at all.

**2. `required...` vs `preferred...IgnoredDuringExecution`.**
`requiredDuringSchedulingIgnoredDuringExecution`: a hard constraint - the
Pod simply won't be scheduled if no node satisfies it. `preferred...`: a
soft, weighted hint - the scheduler favors matching nodes but still
schedules elsewhere if none match. Both share "IgnoredDuringExecution": if
node labels change *after* the Pod is already running, Kubernetes does not
evict it to re-satisfy the rule.

**3. Never co-locate app Pods, for HA.**
Pod **anti-affinity**, `requiredDuringSchedulingIgnoredDuringExecution` -
this is a hard HA requirement (one node failure must not be able to take
out two replicas), so it must be required, not merely preferred. Used
exactly this way on `frontend` in `deployment-frontend.yaml`.

**4. Frontend near backend, same zone, soft requirement.**
```yaml
affinity:
  podAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          topologyKey: topology.kubernetes.io/zone
          labelSelector:
            matchLabels: { app: backend, tier: backend }
```

**5. `topologyKey: kubernetes.io/hostname`.**
It scopes the affinity/anti-affinity rule to **node** granularity - two
Pods are considered "co-located" only if they land on the Node with the
exact same `kubernetes.io/hostname` label value. This is what makes
`deployment-frontend.yaml`'s anti-affinity mean "never the same node,"
rather than "never the same zone/region" (which would use
`topology.kubernetes.io/zone`/`region` instead).

## 5. Taints and Tolerations

**1. Taint vs toleration, relationship.**
A taint is applied to a **node** ("repel Pods unless they say otherwise").
A toleration is applied to a **Pod** ("I am willing to be scheduled on a
node with this taint"). They're opt-in, not opt-out: a toleration only
*permits* scheduling there, it never *forces* it (that's what nodeAffinity
is for) - which is exactly why `deployment-frontend.yaml` pairs a
toleration with no matching nodeAffinity: frontend Pods *may* land on the
tainted dedicated node group, but aren't required to.

**2. The three taint effects.**
- `NoSchedule`: new Pods without a matching toleration won't be scheduled
  here; existing Pods already running here are left alone.
- `PreferNoSchedule`: a soft version of the above - the scheduler tries to
  avoid it but will use the node if it has to.
- `NoExecute`: new Pods without a matching toleration won't be scheduled
  **and** existing Pods already running here without a matching toleration
  are evicted.

**3. GPU node, `gpu=true:NoSchedule`, only ML Pods should land there.**
```yaml
tolerations:
  - key: "gpu"
    operator: "Equal"
    value: "true"
    effect: "NoSchedule"
```
(a toleration alone; if only ML Pods should *ever* land there - not just
"may" - pair it with `nodeAffinity` `required...` on a matching node label,
otherwise other Pods simply won't be repelled from it by anything but the
taint itself.)

**4. Adding a `NoExecute` taint to a node with Pods already running,
no matching toleration.**
Those Pods are evicted (terminated and, if managed by a
Deployment/ReplicaSet, rescheduled elsewhere) - `NoExecute` acts
retroactively on already-running Pods, unlike `NoSchedule`/`PreferNoSchedule`.

**5. Taints/tolerations vs node affinity, when to combine.**
Taints/tolerations are node-side repulsion ("keep most things off me");
node affinity is Pod-side attraction ("put me on nodes like this"). Neither
alone can express "only ML Pods, and *always* on GPU nodes": a toleration
without affinity lets ML Pods land there but doesn't stop them landing
elsewhere too; affinity without the taint lets *other* Pods still land on
the GPU node. Combining both is the standard pattern for genuinely
dedicated node pools.

## 6. Jobs and CronJobs

**1. Pod vs Job, when to use a Job over a Deployment.**
A bare Pod that exits is just done - nothing retries it or records
success/failure. A Job wraps that with a completion guarantee (retry on
failure up to `backoffLimit`, track success). Use a Job instead of a
Deployment whenever the workload is meant to **finish** (a migration, a
batch report) - a Deployment actively fights to keep a container running
forever, which is wrong for a task that should exit 0 and stay stopped.
`job-db-migration.yaml` in this project is exactly this case.

**2. `completions: 5` and `parallelism: 2`.**
The Job isn't done until 5 Pods have completed successfully in total, and
at most 2 of those run at the same time - so it processes the 5 required
completions in waves of up to 2 concurrent Pods.

**3. A Job's Pod fails - default behavior, retry limit field.**
By default the Job controller creates a replacement Pod (Pod-level restart
policy `OnFailure`/`Never` governs container-level retries; the Job
controller handles Pod-level replacement). `spec.backoffLimit` caps how
many times the Job as a whole will retry before being marked `Failed`
(`job-db-migration.yaml` sets this to 3, per the assignment's spec).

**4. CronJob; cron for every day at 2:30 AM.**
A CronJob creates a new Job on a schedule. `30 2 * * *`.
(`cronjob-cache-cleanup.yaml` in this project uses `0 0 * * *` - midnight -
per its own spec.)

**5. `concurrencyPolicy: Forbid` and the alternatives.**
`Forbid`: if the previous scheduled Job run hasn't finished yet, skip
starting a new one entirely (used on `cache-cleanup` - a redis `FLUSHDB`
overlapping with itself is pointless work, not a correctness bug, but still
wasted). Alternatives: `Allow` (the default - runs overlap freely) and
`Replace` (cancels the still-running previous Job and starts the new one
in its place).

**6. `startingDeadlineSeconds` (self-learn).**
If the CronJob controller itself was down/unreachable at a scheduled
trigger time, this is how many seconds past that scheduled time it's still
allowed to start the (now-late) Job - past the deadline, that run is
counted as missed and skipped rather than run arbitrarily late. It matters
because without it, a CronJob controller that was down for hours could, on
recovery, try to fire every missed run back-to-back.

## 7. Pod Health - Liveness and Readiness Probes

**1. Liveness vs readiness, what Kubernetes does on failure.**
Readiness failing: the Pod is removed from its Service's Endpoints (stops
receiving traffic) but is **not** restarted - it might just be busy/warming
up. Liveness failing: the container is killed and restarted (a
stuck-forever process gets a fresh start) - it says nothing about traffic
routing on its own.

**2. Why not a liveness probe that also checks DB connectivity.**
If the database has a brief outage, every backend Pod's liveness probe
would fail simultaneously, and Kubernetes would restart **all of them** at
once - compounding a database outage into a full application outage, and
restarting perfectly healthy application processes fixes nothing (the DB
is still down after the restart). `deployment-backend.yaml`'s liveness
probe deliberately only checks `/health` (process-alive), never the DB/S3/
SNS-dependent routes - documented inline in that file.

**3. 30s startup app - configuring `initialDelaySeconds`.**
Set it to roughly 30s (or, better, use a `startupProbe` instead - see Q4 -
so liveness/readiness don't even start counting until the app is actually
up, regardless of exact timing). If set too low (e.g. 5s), the liveness
probe starts failing *before* the app has finished starting, and
Kubernetes kills and restarts a container that was never actually broken -
a self-inflicted crash loop.

**4. Two probe mechanisms, example use case each.**
`httpGet` - any HTTP service (`/health` on frontend/backend/worker in this
project). `tcpSocket` - anything that doesn't speak HTTP, like the
`redis-cache` liveness/readiness probes in `deployment-redis.yaml`, which
just check that the Redis port accepts a TCP connection. (A third,
`exec`, runs a command inside the container and checks its exit code - not
used in this project, but the right tool for e.g. a CLI healthcheck script.)

**5. Running Pod, readiness failing - traffic and restart behavior.**
It stops receiving new traffic from its Service (removed from Endpoints)
but is **not** restarted by Kubernetes - readiness failures are about
routing, not liveness. It will start receiving traffic again automatically
the moment the readiness probe starts passing.

## 8. ConfigMaps and Secrets

**1. ConfigMap vs Secret, internal storage.**
Both store key-value data in etcd; a Secret's values are stored
**base64-encoded**, not encrypted, by default - base64 is an encoding, not
an encryption, so a Secret is only actually protected by whatever RBAC
controls `get`/`list` on Secrets, plus (if enabled) etcd
encryption-at-rest. `db-credentials` in this project relies on
namespace-scoped RBAC (no app ServiceAccount can even read it, and only
backend-sa gets it injected) as the real access control, not the encoding.

**2. Two ways to consume a ConfigMap, trade-offs.**
`envFrom`/`env` (as env vars - `deployment-backend.yaml` and
`deployment-worker.yaml` use this for `app-config`): simple, but the Pod
must restart to pick up a changed ConfigMap. Volume mount (as a file -
`deployment-frontend.yaml` mounts `frontend-nginx-conf` this way): the
kubelet updates the mounted file automatically on ConfigMap change (with a
short propagation delay), no restart needed - but the application has to
actively re-read the file (nginx needs an explicit reload) to see it.

**3. Update a mounted ConfigMap - do running Pods see the new value?**
Volume-mounted: yes, eventually (kubelet syncs it, typically within
~1 minute) - but the process inside the container won't necessarily *act*
on the new content without its own reload logic. Injected as env vars: no,
never, for already-running Pods - env vars are fixed at container start; a
new value requires deleting/recreating the Pod.

**4. Why not a plaintext DB password in a Pod's env block.**
It's stored, unencrypted, directly on the Deployment object in etcd and
shows up verbatim in `kubectl get deployment -o yaml`, `kubectl describe`,
and Git if the manifest is committed - anyone with read access to the
Deployment (which is far more people than should ever see the DB password)
can read it in plaintext. This is exactly why this project uses
`secretRef`/a Secret (`db-credentials`) instead of a literal value in
`deployment-backend.yaml`.

**5. `secretKeyRef` vs `configMapKeyRef`.**
Identical mechanism (both project a single key from the referenced object
into one env var) - the only difference is which object type they read
from, and Secret values additionally get the RBAC/encoding treatment from
Q1. `envFrom: secretRef` (whole-Secret) is used in this project rather than
per-key `secretKeyRef`, since all three `db-credentials` keys are needed.

**6. Mounting a TLS cert Secret as a file.**
```yaml
volumes:
  - name: tls-cert
    secret:
      secretName: my-tls-secret
containers:
  - volumeMounts:
      - name: tls-cert
        mountPath: /etc/tls
        readOnly: true
```
The app then reads `/etc/tls/tls.crt` and `/etc/tls/tls.key` (the standard
keys a `kubernetes.io/tls`-type Secret exposes) directly as files - this
project doesn't terminate TLS in-Pod (see `k8s/README.md` "Ingress
security" - TLS termination is left to the Ingress/cert-manager instead),
but the pattern is identical to how `db-credentials` or any Secret gets
volume-mounted.
