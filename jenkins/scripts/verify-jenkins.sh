#!/usr/bin/env bash
# Runs exactly the evidence commands the task asks for, in order, so their
# output can be copy-pasted (or screenshotted) straight into
# jenkins/evidence/. Read-only - makes no changes to the cluster.
set -euo pipefail
NAMESPACE="jenkins"

section() { echo ""; echo "=== $1 ==="; }

section "kubectl get namespaces"
kubectl get namespaces

section "kubectl get pods -n jenkins -o wide"
kubectl get pods -n "$NAMESPACE" -o wide

section "kubectl get service,ingress,pvc -n jenkins"
kubectl get service,ingress,pvc -n "$NAMESPACE"

section "kubectl get serviceaccount,role,rolebinding -n jenkins"
kubectl get serviceaccount,role,rolebinding -n "$NAMESPACE"

section "helm list -n jenkins"
helm list -n "$NAMESPACE"

section "Controller readiness"
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=jenkins-controller \
  -o jsonpath='{range .items[*]}{.metadata.name}{" -> "}{.status.phase}{" (Ready="}{.status.conditions[?(@.type=="Ready")].status}{")"}{"\n"}{end}'

section "cd-deploy RBAC in the application namespaces (cross-namespace binding check)"
kubectl get role,rolebinding -n devops-app     -l app.kubernetes.io/component=cd-agent || true
kubectl get role,rolebinding -n devops-app-dev -l app.kubernetes.io/component=cd-agent || true
kubectl get clusterrole,clusterrolebinding -l app.kubernetes.io/component=cd-agent

section "Jenkins jobs present (requires port-forward - see create-jobs.sh for the pattern)"
echo "Run manually if needed:"
echo "  kubectl port-forward -n jenkins svc/jenkins-controller 18080:8080 &"
echo "  curl -s -u \$USER:\$PASS http://127.0.0.1:18080/api/json?tree=jobs[name] | python3 -m json.tool"

echo ""
echo "Verification sweep complete."
