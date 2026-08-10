#!/usr/bin/env bash
# Removes Jenkins and everything this project added for it. Deliberately
# does NOT touch devops-app / devops-app-dev or anything deployed into
# them (the CD role/rolebinding it removes there are Jenkins's own access
# grants, not the application itself) - the application keeps running
# after Jenkins is gone.
set -euo pipefail

if [ "${1:-}" != "--yes" ]; then
  echo "This deletes the jenkins-controller Helm release, the entire 'jenkins'"
  echo "namespace (including its PVC - all build history/JENKINS_HOME is lost),"
  echo "and the cd-deploy RBAC this project granted in devops-app/devops-app-dev."
  echo "Re-run as: $0 --yes"
  exit 1
fi

helm uninstall jenkins-controller -n jenkins || true
kubectl delete -f jenkins/rbac/cd-deploy-clusterrole-namespaces.yaml --ignore-not-found
kubectl delete -f jenkins/rbac/cd-deploy-rolebinding-dev.yaml --ignore-not-found
kubectl delete -f jenkins/rbac/cd-deploy-role-dev.yaml --ignore-not-found
kubectl delete -f jenkins/rbac/cd-deploy-rolebinding.yaml --ignore-not-found
kubectl delete -f jenkins/rbac/cd-deploy-role.yaml --ignore-not-found
kubectl delete namespace jenkins --ignore-not-found

echo "Jenkins removed. devops-app / devops-app-dev and everything in them were left untouched."
