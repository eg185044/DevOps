#!/usr/bin/env bash
# Idempotently (re)creates ci-application and cd-application by triggering
# the "seed-job" pipeline (defined inline in jenkins/jcasc/jenkins.yaml),
# which runs Job DSL against jenkins/jobs/seed.groovy. This is the CLI/API
# script referenced by the task's "jobs created as code" requirement -
# nothing here is a manual click through the Jenkins UI.
#
# Talks to Jenkins over a temporary `kubectl port-forward` (no Ingress
# required) using the admin credential already stored in the
# jenkins-admin-credentials Secret - never prints the password.
set -euo pipefail

LOCAL_PORT="${LOCAL_PORT:-18080}"
NAMESPACE="jenkins"

command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }

ADMIN_USER="$(kubectl get secret jenkins-admin-credentials -n "$NAMESPACE" -o jsonpath='{.data.admin-user}' | base64 -d)"
ADMIN_PASSWORD="$(kubectl get secret jenkins-admin-credentials -n "$NAMESPACE" -o jsonpath='{.data.admin-password}' | base64 -d)"

echo "==> Starting temporary port-forward on 127.0.0.1:${LOCAL_PORT}"
kubectl port-forward -n "$NAMESPACE" svc/jenkins-controller "${LOCAL_PORT}:8080" >/tmp/create-jobs-portforward.log 2>&1 &
PF_PID=$!
trap 'kill "$PF_PID" 2>/dev/null || true' EXIT

BASE_URL="http://127.0.0.1:${LOCAL_PORT}"
echo "==> Waiting for Jenkins to answer..."
for _ in $(seq 1 30); do
  curl -s -o /dev/null -u "${ADMIN_USER}:${ADMIN_PASSWORD}" "${BASE_URL}/login" && break
  sleep 2
done

echo "==> Fetching CSRF crumb"
CRUMB_HEADER="$(curl -s -u "${ADMIN_USER}:${ADMIN_PASSWORD}" \
  "${BASE_URL}/crumbIssuer/api/json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(f"{d["crumbRequestField"]}: {d["crumb"]}")')"

echo "==> Triggering seed-job (creates/updates ci-application + cd-application)"
curl -s -u "${ADMIN_USER}:${ADMIN_PASSWORD}" -H "${CRUMB_HEADER}" \
  -X POST "${BASE_URL}/job/seed-job/build" -o /dev/null -w "HTTP %{http_code}\n"

echo "==> Waiting for seed-job to finish..."
for _ in $(seq 1 60); do
  BUILDING="$(curl -s -u "${ADMIN_USER}:${ADMIN_PASSWORD}" \
    "${BASE_URL}/job/seed-job/lastBuild/api/json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("building", True))' 2>/dev/null || echo True)"
  [ "$BUILDING" = "False" ] && break
  sleep 2
done

RESULT="$(curl -s -u "${ADMIN_USER}:${ADMIN_PASSWORD}" \
  "${BASE_URL}/job/seed-job/lastBuild/api/json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("result"))')"
echo "==> seed-job result: ${RESULT}"

curl -s -u "${ADMIN_USER}:${ADMIN_PASSWORD}" "${BASE_URL}/job/ci-application/api/json" -o /dev/null -w "ci-application job exists: HTTP %{http_code}\n"
curl -s -u "${ADMIN_USER}:${ADMIN_PASSWORD}" "${BASE_URL}/job/cd-application/api/json" -o /dev/null -w "cd-application job exists: HTTP %{http_code}\n"

if [ "$RESULT" != "SUCCESS" ]; then
  echo "seed-job did not succeed - check ${BASE_URL}/job/seed-job/lastBuild/console (via port-forward)." >&2
  exit 1
fi
echo "Done: ci-application and cd-application are created/updated."
