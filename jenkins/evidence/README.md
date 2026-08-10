# Evidence

This folder is intentionally empty in the code deliverable - it's the
target location for the screenshots/command output required by the
Mission 4 submission, captured against a real deployed cluster (this
project was built and validated as code only - no live EKS cluster was
available in this session; see [../README.md](../README.md) "What was and
wasn't run live").

Run [`../scripts/verify-jenkins.sh`](../scripts/verify-jenkins.sh) first -
it runs the exact `kubectl`/`helm` commands below in order and prints
their output, ready to paste into files here (or screenshot).

## Files to add before submitting

- `01-jenkins-namespaces.txt` - `kubectl get namespaces`
- `02-jenkins-pods.txt` - `kubectl get pods -n jenkins -o wide`
- `03-jenkins-service-ingress-pvc.txt` - `kubectl get service,ingress,pvc -n jenkins`
- `04-jenkins-rbac.txt` - `kubectl get serviceaccount,role,rolebinding -n jenkins`
- `05-helm-list.txt` - `helm list -n jenkins`
- `06-agent-pod-lifecycle.png` (or `.txt` from `kubectl get pods -n jenkins -w` during a build) - shows a `ci-agent`/`cd-agent` Pod appear during a build and disappear after
- `07-no-build-on-controller.txt` - controller Pod's own log during a build, showing no build steps execute there
- `08-jobs-created-from-code.png` - Jenkins UI (or `curl .../api/json?tree=jobs[name]`) showing `ci-application` and `cd-application`, both created by `create-jobs.sh`
- `09-ci-run-webhook-triggered.png` - a `ci-application` build whose "Started by" cause is the Git webhook, not a manual click
- `10-ci-stages-lint-test-pass.png` - Blue Ocean / stage view showing Lint and Unit Tests green
- `11-ci-image-tag-immutable.txt` - console excerpt showing the resolved `IMAGE_TAG` (short SHA + build number)
- `12-ci-trivy-scan-result.txt` - `trivy-reports/*.txt` build artifact
- `13-ci-image-in-registry.png` - ECR console (or `aws ecr describe-images`) showing the pushed tag + digest
- `14-ci-intentional-failure.png` - a deliberately broken build (e.g. a failing test) that goes red and does NOT trigger `cd-application`
- `15-cd-deployments-pods-svc-ingress.txt` - `kubectl get deployments,pods,services,ingress -n devops-app`
- `16-cd-rollout-status.txt` - `kubectl rollout status deployment/<name> -n devops-app`
- `17-cd-running-image-matches-ci.txt` - `kubectl get pods -n devops-app -o jsonpath='{..image}'` next to the `IMAGE_TAG` from evidence #11
- `18-cd-events.txt` - `kubectl get events -n devops-app --sort-by=.metadata.creationTimestamp`
- `19-app-http-access.png` - browser or `curl` hitting the app through the Ingress
- `20-app-frontend-to-backend.txt` - the CD "Smoke Test" stage log (backend -> frontend-svc call)
- `21-app-db-connectivity.txt` - `curl <app>/db/init` and `/db/events` output (or pod log showing the query)
- `22-app-s3-sns.txt` - `curl <app>/s3/upload` and `/sns/publish` output
- `23-pod-restart-recovers.txt` - `kubectl delete pod <one-backend-pod> -n devops-app` followed by `kubectl get pods -n devops-app -w` showing a new Ready pod
- `24-cd-rollback-demo.txt` - `helm history` + a real `helm rollback` run once, with before/after `helm list -n devops-app` revisions
