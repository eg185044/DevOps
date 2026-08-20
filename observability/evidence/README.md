# Evidence

This folder is intentionally empty in the code deliverable - it's the
target location for the screenshots/command output the final project's
submission asks for. Most of what's listed below was already confirmed
live this session (see [../README.md](../README.md)'s "What was and
wasn't run live" callout) - what's missing is mainly the registry-
dependent CI/CD evidence (a real `ci-application` push to ECR, a real
`cd-application` run) that needs an actual AWS account, plus screenshots
of the live session's results for the submission itself.

Run [`../scripts/verify-observability.sh`](../scripts/verify-observability.sh)
first - it runs most of the commands below in order and prints their
output, ready to paste into files here (or screenshot).

## Files to add before submitting

**Stack up and scraping:**
- `01-namespace-pods-pvc.txt` - `kubectl get pods,pvc -n observability -o wide`
- `02-helm-list.txt` - `helm list -n observability`
- `03-servicemonitors-rules.txt` - `kubectl get servicemonitor -A` + `kubectl get prometheusrule -n observability`
- `04-targets-up.png` - Prometheus UI `/targets` page showing all three required target groups (application, Kubernetes, Jenkins) green/UP
- `05-dashboards-provisioned.png` - Grafana's dashboard list showing all 3 dashboards present with no manual import step taken (fresh login after install)

**Dashboards showing real data:**
- `06-application-overview.png` - Application Overview dashboard with live traffic/latency/availability data and the running `git_sha`
- `07-kubernetes-cluster.png` - Kubernetes / Cluster dashboard with live node/pod data
- `08-jenkins-delivery.png` - Jenkins & Delivery dashboard with live queue/executor/build data

**Alerts firing and resolving (see `../README.md` "Failure drills"):**
- `09-alert-firing.png` - Alertmanager UI or `/api/v2/alerts` showing an alert in the `firing` state, triggered by one of the controlled drills
- `10-webhook-logger-received.txt` - `kubectl logs -n observability deploy/alertmanager-webhook-logger` showing the actual HTTP POST Alertmanager delivered
- `11-alert-resolved.png` - the same alert transitioning to `resolved` after the drill's mitigation

**CI/CD integration:**
- `12-ci-observability-validation.png` - `ci-Jenkinsfile`'s "Observability Validation" stage passing (YAML/JSON/promtool checks)
- `13-cd-monitoring-gate-pass.txt` - `cd-Jenkinsfile`'s "Post-Deploy Monitoring Gate" stage log on a healthy deploy
- `14-cd-monitoring-gate-fail-and-rollback.txt` - the same gate failing a deliberately unhealthy deploy, followed by the `helm rollback` it points to

**Traceability (the final project's own "worked example"):**
- `15-commit-to-dashboard.png` - side-by-side: a Git commit SHA, the `ci-application` build that produced that `IMAGE_TAG`, the `cd-application` deploy, and the Application Overview dashboard's "Running Version" panel showing the same `git_sha`

**SLI/SLO proof:**
- `16-availability-slo-panel-and-alert.png` - the Availability stat panel + the `HighErrorRate` PromQL from Prometheus's own query UI
- `17-latency-slo-panel-and-alert.png` - the p95 Latency stat panel + the `HighLatencyP95` PromQL, same treatment
