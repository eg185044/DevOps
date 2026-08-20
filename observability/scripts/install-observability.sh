#!/usr/bin/env bash
# One-time bootstrap: creates the observability namespace, generates (or
# reuses) the Grafana admin credential, applies NetworkPolicies, installs
# kube-prometheus-stack via the official Helm chart, then applies the
# ServiceMonitors/PrometheusRule/dashboard ConfigMaps/webhook-logger this
# project ships. Safe to re-run - every step is idempotent.
#
# Prerequisite: Mission 3 (k8s/) and Mission 4 (jenkins/) should already be
# installed - this script scrapes the app's and Jenkins's existing metrics
# endpoints, it doesn't create them.
#
# Usage:
#   ./observability/scripts/install-observability.sh
#   # non-EKS cluster (no gp3 StorageClass) - override at install time:
#   STORAGE_CLASS=hostpath ./observability/scripts/install-observability.sh
set -euo pipefail
cd "$(dirname "$0")/../.."   # repo root

KPS_CHART_VERSION="${KPS_CHART_VERSION:-88.3.0}"
STORAGE_CLASS="${STORAGE_CLASS:-gp3}"

for tool in kubectl helm; do
  command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 1; }
done

echo "==> 1/7  Namespace"
kubectl apply -f observability/namespace.yaml

echo "==> 2/7  Grafana admin credential (generated once, never written to disk/Git)"
if kubectl get secret grafana-admin-credentials -n observability >/dev/null 2>&1; then
  echo "    grafana-admin-credentials already exists - leaving it as-is."
else
  ADMIN_PASSWORD="$(openssl rand -base64 24 | tr -d '=+/')"
  kubectl create secret generic grafana-admin-credentials \
    --namespace observability \
    --from-literal=admin-user=admin \
    --from-literal=admin-password="${ADMIN_PASSWORD}"
  echo "    Created grafana-admin-credentials. Save this now - it is shown ONCE:"
  echo "    user=admin  password=${ADMIN_PASSWORD}"
fi

echo "==> 3/7  Safe demo Alertmanager receiver (webhook-logger)"
kubectl apply -f observability/webhook-logger.yaml

echo "==> 4/7  NetworkPolicies (observability namespace + scrape-allow rules elsewhere)"
kubectl apply -f observability/network-policies/
kubectl apply -f jenkins/network-policies/30-allow-observability-scrape.yaml
kubectl apply -f k8s/network-policies/50-allow-observability-scrape.yaml
# The Helm-chart flavor of the same rule is applied automatically by `helm
# upgrade --install` against k8s/helm/cv-platform whenever that release is
# next installed/upgraded (see k8s/helm/cv-platform/templates/network-
# policies.yaml) - nothing to do here if the app was deployed via Helm.

echo "==> 5/7  kube-prometheus-stack (official Helm chart, pinned version ${KPS_CHART_VERSION})"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo update prometheus-community >/dev/null

if [ "${STORAGE_CLASS}" != "gp3" ]; then
  echo "    Using storageClass override: ${STORAGE_CLASS} (non-default - see observability/README.md)"
fi

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --version "${KPS_CHART_VERSION}" \
  --namespace observability \
  -f observability/helm/values.yaml \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName="${STORAGE_CLASS}" \
  --set alertmanager.alertmanagerSpec.storage.volumeClaimTemplate.spec.storageClassName="${STORAGE_CLASS}" \
  --wait --timeout 10m

echo "==> 6/7  ServiceMonitors + PrometheusRule (CRDs are installed by the chart above, so this must come after)"
kubectl apply -f observability/service-monitors/
kubectl apply -f observability/alerts/

echo "==> 7/7  Grafana dashboards (provisioned as labeled ConfigMaps - see observability/README.md)"
for f in observability/dashboards/*.json; do
  name="$(basename "$f" .json)"
  kubectl create configmap "grafana-dashboard-${name}" \
    --namespace observability \
    --from-file="${name}.json=${f}" \
    --dry-run=client -o yaml \
  | kubectl apply -f -
  # Separate step (not --dry-run piped) so the label always lands even if
  # this script is re-run against a ConfigMap that already has it - avoids
  # any doubt about kubectl label's flag/stdin ordering.
  kubectl label configmap "grafana-dashboard-${name}" -n observability grafana_dashboard=1 --overwrite
done

echo ""
echo "Done. Next: verify with observability/scripts/verify-observability.sh."
echo ""
echo "If jenkins-controller was installed BEFORE this script ran, re-apply it"
echo "once so its PROMETHEUS_URL env var (see jenkins/helm/values.yaml) takes"
echo "effect and the CD post-deploy monitoring gate activates:"
echo "  ./jenkins/scripts/configure-jenkins.sh"
