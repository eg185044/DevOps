# Kubernetes Beginner Assignment - Part 2 Answers

Written answers for the conceptual questions in `1_k8s work assignment.pdf`.
Part 1 (hands-on commands) is exercised directly against the cluster used
for `../k8s/` - see `../k8s/README.md` "Verifying it works" for the
equivalent commands run against this project's actual namespace
(`devops-app`) instead of a scratch namespace.

## Section F: Core Concepts

**1. Pod vs Deployment.**
A Pod is the smallest deployable unit - one or more containers sharing
network/storage, with no self-healing of its own: if its node dies, it's
gone. A Deployment manages a ReplicaSet of Pods, so it restarts failed Pods,
supports rolling updates, and lets you declare a desired replica count. Use
a bare Pod only for one-off debugging; every real workload (this project's
frontend/backend/worker) uses a Deployment.

**2. `replicas: 3` but only 1 Pod running - possible reasons.**
- Image pull failure (`ErrImagePull`/`ImagePullBackOff` - wrong tag, private
  registry auth missing).
- Insufficient cluster resources - the other 2 Pods are stuck `Pending`
  because no node has enough CPU/memory (or matches a required affinity/
  toleration).
- `CrashLoopBackOff` - the container starts and exits immediately (bad
  config, missing env var, failing readiness dependency) and Kubernetes is
  backing off restarts.

**3. ReplicaSet.**
Yes - creating a Deployment automatically creates a ReplicaSet, which is
what actually creates/deletes Pods to match `replicas`. Verify with
`kubectl get rs -n <namespace>` and note the `OWNER` chain:
`kubectl describe pod <pod> -n <namespace>` shows an Owner Reference to the
ReplicaSet, and `kubectl describe rs <rs-name>` shows one to the Deployment.

**4. Purpose of a namespace.**
A namespace is a logical partition of one cluster - scoping names,
NetworkPolicies, RBAC, and resource quotas. Two real scenarios: (1)
separating `devops-app` (this project) from `kube-system`/`ingress-nginx` so
an accidental `kubectl delete -n <ns> --all` can't touch cluster
infrastructure; (2) separating `staging` from `production` copies of the
same app in one cluster, each with its own Secrets/quotas.

**5. `kubectl apply` vs `kubectl create`.**
`create` is imperative: it fails if the object already exists. `apply` is
declarative: it computes a three-way diff (last-applied-config, current
live object, new file) and patches only what changed, so it's safe to run
repeatedly - this is why every command in `../k8s/README.md` uses `apply`.

## Section G: Control Plane & Request Flow

**6. `kubectl apply -f deployment.yaml` - the full journey.**
kubectl reads/validates the YAML client-side, then sends an HTTPS request to
the **API server**, authenticated via the kubeconfig's credentials. The API
server authenticates and authorizes the request (RBAC), runs it through
admission controllers/webhooks, then persists the object to **etcd**. The
**Deployment controller** (in `kube-controller-manager`) notices the new
Deployment via a watch on the API server and creates a ReplicaSet; the
**ReplicaSet controller** creates the requested number of Pod objects
(still just API objects at this point, unscheduled). The **scheduler**
watches for unscheduled Pods, picks a node for each, and writes that back
to the API server/etcd. The **kubelet** on the chosen node watches for Pods
assigned to it, and instructs the **container runtime** (containerd) to
pull the image and start the container(s), then reports status back to the
API server.

**7. Which component schedules a Pod, and how.**
`kube-scheduler`. It filters nodes that can't run the Pod (insufficient
resources, taints without matching tolerations, node selectors/affinity not
satisfied), then scores the remaining candidates (e.g. spreading Pods for
anti-affinity, bin-packing) and picks the highest-scoring node.

**8. Which component starts the container.**
The **kubelet** on the assigned node, via the container runtime (containerd/
CRI-O) it talks to over the Container Runtime Interface.

**9. If the API server goes down, do existing Pods keep running?**
Yes. Once scheduled, Pods are run and kept alive by the kubelet talking
directly to the local container runtime - that doesn't depend on the API
server being reachable. What breaks: no new Pods can be scheduled, no
`kubectl` commands work, and controllers can't reconcile drift (e.g. a
crashed Pod's ReplicaSet won't get a replacement until the API server is
back), because they all depend on watching the API server.

**10. etcd.**
A distributed, strongly-consistent key-value store - the single source of
truth for all cluster state (every object: Pods, Deployments, Secrets,
ConfigMaps, etc; nothing else persists this). If it loses all its data, the
cluster's control plane has no record of what should exist. Already-running
Pods keep running (kubelets don't need etcd moment-to-moment), but nothing
can be created/updated/rescheduled, and on any Pod/node failure there is no
record to recreate it from - in practice this is a full cluster rebuild,
which is why etcd backups are the single most important thing to get right
operationally.

## Section H: Services & Networking

**11. ClusterIP vs NodePort vs LoadBalancer.**
- **ClusterIP** (default): an internal-only virtual IP, reachable from
  inside the cluster. Use case: `backend-svc`/`worker-svc` in this project -
  never need external reachability.
- **NodePort**: ClusterIP plus a static port (30000-32767) opened on every
  node's IP. Use case: quick manual testing on a bare-metal/on-prem cluster
  with no cloud load balancer available.
- **LoadBalancer**: NodePort plus a cloud provider provisions an external
  load balancer pointing at it. Use case: exposing `frontend-svc` directly
  without an Ingress controller - this project uses an Ingress instead
  (one shared LB in front of potentially many host-based routes), but a
  bare `type: LoadBalancer` Service is the equivalent for a single service.

**12. How a Service finds its Pods.**
Via its `spec.selector` label matcher - the Service continuously watches for
Pods whose labels match, and populates its Endpoints/EndpointSlice with
their IPs. In this project, `service-backend.yaml`'s
`selector: { app: backend, tier: backend }` matches exactly the labels on
`deployment-backend.yaml`'s Pod template.

**13. Pod not receiving traffic from its Service - first 3 checks.**
1. `kubectl get endpoints <svc> -n <ns>` - if empty, the Service's selector
   doesn't match any Pod's labels (or none of the matching Pods are Ready).
2. `kubectl get pods -n <ns> -o wide --show-labels` - confirm the Pod is
   `Running` **and** `READY` (a failing readinessProbe removes it from
   Endpoints even while `Running`).
3. Port mismatch - confirm `targetPort` on the Service matches the actual
   `containerPort` the app listens on (by name or number).

**14. Cross-namespace DNS name.**
`payments-svc.team-b.svc.cluster.local` (short form `payments-svc.team-b`
also resolves from any namespace; only the bare `payments-svc` requires
being *in* `team-b`). This project's own equivalent:
`backend-svc.devops-app.svc.cluster.local`, used by `frontend-nginx-conf`.

## Section I: Finalizers

**19. What is a finalizer?**
A string key on an object's `metadata.finalizers` list that tells the API
server "don't fully delete this object until whatever registered this key
has finished its own cleanup." It solves the problem of needing to run
cleanup logic (e.g. releasing a cloud load balancer, an external volume)
*before* an object disappears, when that cleanup can't happen synchronously
inside the delete call itself.

**20. What happens on delete with a finalizer present?**
The object is **not** removed from etcd. Instead, the API server sets
`metadata.deletionTimestamp` to the current time and leaves the object
otherwise intact (with its finalizers list). The controller responsible for
each finalizer sees the `deletionTimestamp`, does its cleanup, then removes
its own key from `finalizers`. Once the list is empty, the API server
performs the actual delete.

**21. Service stuck `Terminating` for a long time.**
Most likely cause: a finalizer (commonly
`service.kubernetes.io/load-balancer-cleanup` on a `LoadBalancer` Service)
whose owning controller either crashed, lost cloud API permissions, or is
stuck retrying a failed cloud-side deletion (e.g. the cloud load balancer
was already deleted out-of-band). Investigate with
`kubectl get svc <name> -n <ns> -o yaml` (check `metadata.finalizers` and
`deletionTimestamp`), then check the controller's logs (e.g.
`kube-controller-manager` or, on EKS, the AWS Load Balancer Controller Pod)
for errors related to that specific object.

**22. `service.kubernetes.io/load-balancer-cleanup`.**
It tells the cloud-controller-manager "don't let this Service object
disappear from etcd until the actual cloud load balancer backing it has
been deleted." Without it, deleting the Service would remove the
Kubernetes object immediately but silently **orphan** the real AWS load
balancer - it would keep running, keep costing money, and nothing in
Kubernetes would know it still existed.

**23. Force-deleting a stuck resource.**
`kubectl patch <kind> <name> -n <ns> -p '{"metadata":{"finalizers":[]}}' --type=merge`
(or `kubectl delete ... --force --grace-period=0`, which for finalizers
just strips them the same way). The risk: whatever cleanup that finalizer
existed to guarantee (releasing a cloud load balancer, detaching a volume,
running a webhook) **never happens** - you've now got exactly the orphaned
external resource described in Q22, just created deliberately instead of by
a bug.

**24. True or False: a resource with a finalizer is immediately removed
from etcd on `kubectl delete`.**
**False.** It stays in etcd (visible, with `deletionTimestamp` set) until
every finalizer is removed by its owning controller - see Q20.

**25. Who adds/removes finalizers?**
Either Kubernetes core controllers or the resource's owning controller -
never the object's creator by default. Examples: Kubernetes core adds/
removes `kubernetes.io/pv-protection` on a PersistentVolume currently bound
to a PVC; the cloud-controller-manager adds/removes
`service.kubernetes.io/load-balancer-cleanup` on a `LoadBalancer` Service
(Q22); a custom operator (e.g. an External Secrets Operator) would add its
own finalizer to a `SecretStore` it manages, to clean up any external
session before the object disappears.

## Section G (Bonus): Advanced Thinking

**15. Why not run a standalone Pod in production.**
A bare Pod has no controller watching it: if its node fails or it crashes,
nothing recreates it - the app is just down until a human intervenes.
Every workload in this project (`deployment-frontend/backend/worker.yaml`)
uses a Deployment specifically so a ReplicaSet notices and replaces a dead
Pod automatically (demonstrated in the [Pod restart demo](../k8s/README.md#verifying-it-works)).

**16. Scaling a Deployment to 0 replicas.**
All its Pods are terminated (gracefully, respecting
`terminationGracePeriodSeconds`) and none remain - but the Deployment object
itself, its ReplicaSet, and its rollout history all still exist. Bring them
back with `kubectl scale deployment <name> -n <ns> --replicas=<n>` (or edit
`spec.replicas` and re-`apply`); new Pods are created from the same
template, no image re-pull/rebuild needed unless the image changed.

**17. Deleted Deployment, no backup YAML - recoverable with only `kubectl`?**
Only partially, and only within a short window. `kubectl get deployment -o yaml`
would have worked *before* deletion; after, `kubectl rollout history` and
past ReplicaSets are also gone once the Deployment is deleted (they're
owned by it via garbage collection). If a Pod happens to still be
`Terminating`, `kubectl get pod <name> -o yaml` can recover the container
spec/env/image well enough to hand-reconstruct a Deployment manifest - but
there is no "undelete." This is the practical argument for storing every
manifest in Git (as this project does) rather than relying on cluster
state as the source of truth.

**18. `CrashLoopBackOff` - what it means and how to start debugging.**
The container starts, exits (crashes, or the entrypoint process just
finishes), and Kubernetes restarts it with an exponential backoff delay
between attempts - the "loop" is that cycle repeating. Start with
`kubectl logs <pod> -n <ns>` (and `--previous` to see the last crashed
instance's output, since the current one may have just started), then
`kubectl describe pod <pod> -n <ns>` for the Events section (OOMKilled,
failed liveness probe, failed volume mount, etc. all show up there before
you'd ever need to exec into the container).
