# Runbook: HighErrorRate

**Fires when:** `app:availability:ratio_5m < 0.95` for 10 minutes straight
(more than 1 in 20 backend requests returned 5xx over a rolling 5-minute
window). This is also the Availability SLI/SLO breach signal - see
`observability/README.md` "SLI/SLO".

## 1. Confirm it's real

- Open the **Application Overview** Grafana dashboard - check "5xx Error
  Rate by Endpoint" to see which route(s) are actually failing, and
  "Running Version" to see which `git_sha` is deployed.
- `kubectl logs -n devops-app -l app.kubernetes.io/component=backend --tail=100 --since=15m`

## 2. Likely causes, in order of frequency

1. **A bad deploy.** Check the annotation markers on the Application
   Overview dashboard - did `git_sha` change right before the error rate
   climbed? If so, this is almost certainly the cause.
2. **RDS/S3/SNS connectivity.** `/db/events`, `/s3/upload`, `/sns/publish`
   all depend on AWS resources outside the cluster - check Security Group
   rules and IRSA role trust policy haven't drifted (see `k8s/README.md`
   "Security" for what backend-sa's IAM role is supposed to allow).
3. **Resource exhaustion.** Check the "Memory Usage by Pod" / "CPU Usage by
   Pod" panels - an OOMKilled backend Pod restarting in a loop shows up
   here as errors, not as the ReplicasMismatch alert (that one only fires
   on a *sustained* replica shortfall, not transient restarts).

## 3. Mitigate

- **If cause #1 (bad deploy):** roll back.
  ```
  helm history cv-platform -n devops-app
  helm rollback cv-platform <previous-revision> -n devops-app --wait
  ```
  Or re-run `cd-application` with the previous known-good `IMAGE_TAG`.
- **If cause #2 (AWS connectivity):** this is a platform issue, not a code
  issue - do not roll back; fix the Security Group / IRSA trust policy and
  the error rate should recover without a new deploy.
- **If cause #3 (resources):** bump `resources.limits` in
  `k8s/helm/cv-platform/values-<env>.yaml` and redeploy.

## 4. Confirm recovery

`app:availability:ratio_5m` back above 0.99 on the dashboard, and the alert
moves from firing to resolved in Alertmanager (`kubectl port-forward -n
observability svc/kube-prometheus-stack-alertmanager 9093:9093`).
