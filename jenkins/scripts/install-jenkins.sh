#!/usr/bin/env bash
# One-time bootstrap: creates the namespaces this project uses, generates
# (or reuses) the Jenkins admin credential, applies every RBAC object, and
# installs Jenkins via the official Helm chart with our JCasC/plugins/
# values wired in. Safe to re-run - every step is idempotent.
#
# Run by a human with real (admin-level) kubectl/AWS access - this is the
# "One-time cluster bootstrap" referenced by jenkins/rbac/cd-deploy-
# clusterrole-namespaces.yaml, and is a fundamentally different actor from
# the constrained jenkins-cd-deploy ServiceAccount the CD pipeline itself
# runs as afterward.
#
# Usage:
#   GIT_REPO_URL=https://github.com/you/your-repo.git \
#   ECR_REGISTRY=123456789012.dkr.ecr.eu-west-1.amazonaws.com \
#     ./jenkins/scripts/install-jenkins.sh
set -euo pipefail
cd "$(dirname "$0")/../.."   # repo root

JENKINS_CHART_VERSION="${JENKINS_CHART_VERSION:-5.9.53}"
GIT_REPO_URL="${GIT_REPO_URL:?Set GIT_REPO_URL to this repository's clone URL}"
ECR_REGISTRY="${ECR_REGISTRY:?Set ECR_REGISTRY, e.g. 123456789012.dkr.ecr.eu-west-1.amazonaws.com}"
ECR_REPO_PREFIX="${ECR_REPO_PREFIX:-erez-cv-devops}"
AWS_REGION="${AWS_REGION:-eu-west-1}"
CI_IAM_ROLE_ARN="${CI_IAM_ROLE_ARN:?Set CI_IAM_ROLE_ARN - the IRSA role jenkins-ci-agent assumes to push to ECR (see jenkins/README.md)}"

for tool in kubectl helm; do
  command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 1; }
done

echo "==> 1/6  Namespaces (created once, out-of-band - see jenkins/rbac/cd-deploy-clusterrole-namespaces.yaml)"
kubectl apply -f jenkins/namespace.yaml
kubectl get namespace devops-app     >/dev/null 2>&1 || kubectl create namespace devops-app
kubectl get namespace devops-app-dev >/dev/null 2>&1 || kubectl create namespace devops-app-dev

echo "==> 2/6  Jenkins admin credential (generated once, never written to disk/Git)"
if kubectl get secret jenkins-admin-credentials -n jenkins >/dev/null 2>&1; then
  echo "    jenkins-admin-credentials already exists - leaving it as-is."
else
  ADMIN_PASSWORD="$(openssl rand -base64 24 | tr -d '=+/')"
  kubectl create secret generic jenkins-admin-credentials \
    --namespace jenkins \
    --from-literal=admin-user=admin \
    --from-literal=admin-password="${ADMIN_PASSWORD}"
  echo "    Created jenkins-admin-credentials. Save this now - it is shown ONCE:"
  echo "    user=admin  password=${ADMIN_PASSWORD}"
fi

echo "==> 3/6  RBAC (ServiceAccounts, Roles, RoleBindings, the one scoped ClusterRole)"
kubectl apply -f jenkins/rbac/controller-serviceaccount.yaml
kubectl apply -f jenkins/rbac/controller-role.yaml
kubectl apply -f jenkins/rbac/controller-rolebinding.yaml
kubectl apply -f jenkins/rbac/ci-agent-serviceaccount.yaml
kubectl apply -f jenkins/rbac/cd-agent-serviceaccount.yaml
kubectl apply -f jenkins/rbac/cd-deploy-role.yaml
kubectl apply -f jenkins/rbac/cd-deploy-rolebinding.yaml
kubectl apply -f jenkins/rbac/cd-deploy-role-dev.yaml
kubectl apply -f jenkins/rbac/cd-deploy-rolebinding-dev.yaml
kubectl apply -f jenkins/rbac/cd-deploy-clusterrole-namespaces.yaml

echo "==> 4/6  IRSA annotation on jenkins-ci-agent (ECR push role)"
kubectl annotate serviceaccount jenkins-ci-agent -n jenkins \
  "eks.amazonaws.com/role-arn=${CI_IAM_ROLE_ARN}" --overwrite

echo "==> 5/6  NetworkPolicies"
kubectl apply -f jenkins/network-policies/

echo "==> 6/6  Jenkins controller (official Helm chart, pinned version ${JENKINS_CHART_VERSION})"
helm repo add jenkins https://charts.jenkins.io >/dev/null
helm repo update jenkins >/dev/null

# IMPORTANT: Helm does NOT merge YAML lists across `-f` files by key (only
# maps get deep-merged) - a second `-f` overlay providing its own
# controller.containerEnv would silently REPLACE, not augment, the whole
# list in jenkins/helm/values.yaml (losing the ADMIN_USER/ADMIN_PASSWORD
# secretKeyRefs). So instead of a second values file, we resolve the
# REPLACE_ME_* placeholders in ONE complete copy of values.yaml with sed -
# still a single, fully-valid, reviewable values file at apply time.
RESOLVED_VALUES="$(mktemp)"
trap 'rm -f "$RESOLVED_VALUES"' EXIT
sed \
  -e "s#https://github.com/REPLACE_ME_ORG/REPLACE_ME_REPO.git#${GIT_REPO_URL}#g" \
  -e "s#REPLACE_ME_ACCOUNT_ID.dkr.ecr.REPLACE_ME_REGION.amazonaws.com#${ECR_REGISTRY}#g" \
  -e "s#value: \"erez-cv-devops\"#value: \"${ECR_REPO_PREFIX}\"#" \
  -e "s#value: \"eu-west-1\"#value: \"${AWS_REGION}\"#" \
  jenkins/helm/values.yaml > "${RESOLVED_VALUES}"

helm upgrade --install jenkins-controller jenkins/jenkins \
  --version "${JENKINS_CHART_VERSION}" \
  --namespace jenkins \
  -f "${RESOLVED_VALUES}" \
  --set-file controller.JCasC.configScripts.main=jenkins/jcasc/jenkins.yaml \
  --wait --timeout 10m

echo ""
echo "Done. Next: verify with jenkins/scripts/verify-jenkins.sh, then create the"
echo "two jobs with jenkins/scripts/create-jobs.sh."
