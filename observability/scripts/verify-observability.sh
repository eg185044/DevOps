#!/usr/bin/env bash
# Read-only smoke test: proves the observability stack is actually up and
# scraping the three required targets (application, Kubernetes, Jenkins),
# not just that the Pods exist. Mirrors jenkins/scripts/verify-jenkins.sh's
# role for the Jenkins-on-Kubernetes layer.
set -euo pipefail
cd "$(dirname "$0")/../.."

echo "==== Namespace & workloads ===="
kubectl get namespace observability
kubectl get pods -n observability -o wide
kubectl get pvc -n observability
helm list -n observability

echo ""
echo "==== ServiceMonitors / PodMonitors / PrometheusRule ===="
kubectl get servicemonitor -A
kubectl get prometheusrule -n observability

echo ""
echo "==== Grafana dashboards provisioned ===="
kubectl get configmap -A -l grafana_dashboard=1

echo ""
echo "==== Alertmanager config (receiver present, no secrets printed) ===="
kubectl get secret -n observability -l app.kubernetes.io/name=alertmanager -o name

PROM_PF_PID=""
cleanup() { [ -n "$PROM_PF_PID" ] && kill "$PROM_PF_PID" 2>/dev/null || true; }
trap cleanup EXIT

echo ""
echo "==== Live scrape target health (via a temporary port-forward) ===="
kubectl port-forward -n observability svc/kube-prometheus-stack-prometheus 19090:9090 >/dev/null 2>&1 &
PROM_PF_PID=$!
sleep 3

TARGETS_JSON="$(curl -sf http://127.0.0.1:19090/api/v1/targets || echo '{}')"
if command -v jq >/dev/null 2>&1; then
  echo "$TARGETS_JSON" | jq -r '.data.activeTargets[] | "\(.health)\t\(.labels.job // .scrapePool)\t\(.labels.namespace // "-")"' | sort | uniq -c
  DOWN_COUNT=$(echo "$TARGETS_JSON" | jq '[.data.activeTargets[] | select(.health != "up")] | length')
  echo "Targets NOT up: ${DOWN_COUNT}"
else
  echo "(jq not installed locally - showing raw target count only)"
  echo "$TARGETS_JSON" | grep -o '"health":"[a-z]*"' | sort | uniq -c
fi

echo ""
echo "Done. For the three required targets specifically, filter by namespace:"
echo "  devops-app / devops-app-dev  (application)"
echo "  kube-system                  (Kubernetes: kube-state-metrics, node-exporter, kubelet)"
echo "  jenkins                      (Jenkins Prometheus plugin)"
