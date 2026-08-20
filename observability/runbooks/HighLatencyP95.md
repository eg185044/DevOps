# Runbook: HighLatencyP95

**Fires when:** `app:latency:p95_5m > 0.5` (seconds) for 10 minutes straight
- 95% of backend requests should complete in under 500ms; this means the
slowest 5% are regularly taking longer than that.

## 1. Confirm it's real

- **Application Overview** dashboard: "Latency Percentiles (p50/p95/p99)" -
  is it p95 only, or p50 too? p50 climbing means the whole service is slow
  (systemic); p95-only means a specific slow path or a subset of requests.
- "Request Rate by Endpoint" on the same dashboard - is traffic unusually
  high? Latency under load that disappears when load drops is a capacity
  issue, not a code issue.

## 2. Likely causes, in order of frequency

1. **RDS latency.** `/db/events` and `/db/init` are the only routes that
   touch Postgres - if only those endpoints are slow, check RDS's own
   CloudWatch metrics (connections, CPU, IOPS) outside this cluster's
   Prometheus entirely.
2. **CPU throttling.** Check the Kubernetes / Cluster dashboard's "CPU
   Throttling" panel - a pod hitting its CPU *limit* queues work instead of
   failing outright, which shows up as latency, not errors.
3. **Cold start after a deploy/restart.** Check for a deploy annotation
   right before the latency climb - the first requests after a rollout can
   be slower (import caches, DB connection pool warming) before settling.
   If it resolves within a few minutes on its own, this is almost
   certainly it.

## 3. Mitigate

- **RDS-bound:** this is a platform issue outside Kubernetes - check RDS
  instance class/IOPS provisioning; no rollback fixes this.
- **CPU-bound:** bump `resources.limits.cpu` for `backend` in
  `k8s/helm/cv-platform/values-<env>.yaml` and redeploy via `cd-application`.
- **Cold-start:** usually self-resolves; if it doesn't within ~5 minutes,
  treat it as cause #1 or #2 instead.

## 4. Confirm recovery

`app:latency:p95_5m` back under 0.5s on the dashboard, alert resolved in
Alertmanager.
