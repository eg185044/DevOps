#!/usr/bin/env bash
# Removes the observability stack and everything this project added for it.
# Deliberately does NOT touch devops-app / devops-app-dev / jenkins or
# anything deployed into them (the scrape-allow NetworkPolicy rules it
# removes there are observability's own access grants, not those
# applications) - Mission 3/4 keep running after this runs.
set -euo pipefail
cd "$(dirname "$0")/../.."

if [ "${1:-}" != "--yes" ]; then
  echo "This deletes the kube-prometheus-stack Helm release, the entire"
  echo "'observability' namespace (including its PVCs - all metrics history is"
  echo "lost), the CRDs it installed (ServiceMonitor/PrometheusRule/etc - this"
  echo "also deletes every ServiceMonitor/PrometheusRule object cluster-wide,"
  echo "which is why it's separate from just deleting the namespace), and the"
  echo "scrape-allow NetworkPolicy rules this project granted in devops-app/"
  echo "devops-app-dev/jenkins."
  echo "Re-run as: $0 --yes"
  exit 1
fi

helm uninstall kube-prometheus-stack -n observability || true

kubectl delete -f jenkins/network-policies/30-allow-observability-scrape.yaml --ignore-not-found
kubectl delete -f k8s/network-policies/50-allow-observability-scrape.yaml --ignore-not-found
# The Helm-chart flavor of the app-side scrape-allow rule is removed
# automatically the next time the cv-platform release itself is uninstalled
# or upgraded with observability disabled - it is not a standalone object.

kubectl delete namespace observability --ignore-not-found

echo ""
echo "Note: kube-prometheus-stack's CRDs (ServiceMonitor, PrometheusRule,"
echo "Alertmanager, Prometheus, etc.) are intentionally NOT deleted here -"
echo "Helm never removes CRDs on uninstall by design, and doing so here would"
echo "risk deleting CRDs another release still depends on. To remove them"
echo "explicitly (only if nothing else on the cluster uses them):"
echo "  kubectl get crd -o name | grep monitoring.coreos.com | xargs kubectl delete"
echo ""
echo "observability removed. devops-app / devops-app-dev / jenkins and"
echo "everything in them were left untouched."
