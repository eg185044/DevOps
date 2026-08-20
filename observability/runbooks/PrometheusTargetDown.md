# Runbook: PrometheusTargetDown

**Fires when:** `up == 0` for any scrape target for 10 minutes - Prometheus
itself has not been able to reach a target it's configured to scrape. This
is the "watch the watchers" alert: every other alert in this project
depends on the target's metrics actually existing, so a target being down
silently disables whatever that target's own alerts were supposed to catch.

## 1. Confirm it's real

```
kubectl port-forward -n observability svc/kube-prometheus-stack-prometheus 9090:9090
```
Open `http://localhost:9090/targets` - the down target's "Error" column
usually names the exact problem (connection refused, context deadline
exceeded, x509 error, 403, etc).

## 2. Likely causes, in order of frequency

1. **The target Pod is actually down/restarting.** `kubectl get pods -n
   <target-namespace>` - if the Pod itself is unhealthy, fix that first
   (see HighErrorRate.md / ReplicasMismatch.md) - this alert will
   self-resolve once it does.
2. **NetworkPolicy regression.** A scrape-allow rule
   (`observability/network-policies/`, `k8s/network-policies/50-allow-
   observability-scrape.yaml`, `jenkins/network-policies/30-allow-
   observability-scrape.yaml`) was removed or its label selector no longer
   matches after an unrelated label change.
3. **Wrong port/path in the ServiceMonitor.** A typo'd `port:` or `path:`
   in `observability/service-monitors/*.yaml` after an edit - the /targets
   page's target URL shows exactly what Prometheus is trying to hit.
4. **Application-side auth regression** (Jenkins target specifically): if
   `unclassified.prometheusConfiguration.useAuthenticatedEndpoint` in
   jenkins/jcasc/jenkins.yaml reverted to `true` (e.g. a JCasC redeploy
   without this override), `/prometheus` starts requiring a login and
   Prometheus's anonymous scrape gets a 403.

## 3. Mitigate

- **Target Pod down:** follow that component's own runbook.
- **NetworkPolicy:** `kubectl get networkpolicy -n <namespace>` and
  re-apply the missing/broken one from the versioned manifest.
- **ServiceMonitor typo:** fix and re-apply
  `observability/service-monitors/<name>.yaml` - no Helm release restart
  needed, Prometheus Operator picks it up automatically.
- **Jenkins auth regression:** re-run `./jenkins/scripts/configure-
  jenkins.sh` to reassert the JCasC config from source.

## 4. Confirm recovery

Target shows "UP" (green) on the `/targets` page; `up{job="...",
instance="..."} == 1` in a Prometheus query.
