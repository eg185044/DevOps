# Runbook: NodeNotReadyOrPressure

**Fires when:** a node reports `Ready=false`, or `MemoryPressure` /
`DiskPressure` / `PIDPressure` = true, sustained for 10 minutes. This is a
**platform-level** alert - it fires independently of whether any
application Pod is currently unhealthy, precisely so you can tell platform
incidents apart from application incidents (see the Kubernetes dashboard's
own framing: "is the root cause the application or the platform?").

## 1. Confirm it's real

```
kubectl get nodes -o wide
kubectl describe node <node>
kubectl top nodes
```

Kubernetes / Cluster dashboard: "Nodes NotReady / Under Pressure" stat
panel plus the CPU/Memory/Disk utilization panels for the specific node.

## 2. Likely causes

1. **DiskPressure:** node's ephemeral storage is full - usually unbounded
   container logs or an accumulation of unused images. `kubectl describe
   node` shows the exact threshold breached.
2. **MemoryPressure:** node-level memory exhaustion, typically because too
   many Pods without memory *limits* landed on one node and one of them
   leaked - contrast with a single Pod hitting OOMKilled (a Pod-level
   event, not a node-level one; that's covered under HighErrorRate.md's
   "resource exhaustion" cause instead).
3. **NotReady:** kubelet stopped reporting - node-level failure (VM
   issue, network partition to the control plane, kubelet crash). On a
   managed EKS node group this is usually transient and self-heals via the
   Auto Scaling Group's health check replacing the instance; on this
   project's local demo cluster (Docker Desktop / kind) it typically means
   the underlying container runtime needs a restart.

## 3. Mitigate

- **DiskPressure:** `kubectl describe node` -> identify and clean up the
  actual consumer (often `docker system prune` / equivalent at the node
  level, or reducing log retention).
- **MemoryPressure:** add `resources.limits.memory` to any Deployment
  missing it (this project's app Deployments all already set one - see
  k8s/helm/cv-platform/values-<env>.yaml - so this most likely points at
  an unrelated workload on a shared cluster).
- **NotReady, managed node group:** let the ASG's health check cycle the
  instance; only intervene manually if it doesn't self-heal within ~10
  minutes.

## 4. Confirm recovery

`kubectl get nodes` shows `Ready` for every node, no pressure conditions
`True` in `kubectl describe node`.
