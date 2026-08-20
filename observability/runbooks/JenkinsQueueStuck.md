# Runbook: JenkinsQueueStuck

**Fires when:** `jenkins_queue_stuck_value > 0` for 10 minutes - the
controller itself has flagged one or more queued builds as stuck (waiting
longer than Jenkins's own internal threshold for an available executor).

## 1. Confirm it's real

- Jenkins UI (`kubectl port-forward -n jenkins svc/jenkins-controller
  8080:8080`) - the queue view shows exactly which job is stuck and why
  Jenkins thinks so (usually printed inline, e.g. "waiting for next
  available executor").
- Jenkins & Delivery dashboard: "Queue Length" and "Executors: Busy vs
  Total" panels - a persistent gap between busy and total executors while
  the queue is nonzero means agent Pods aren't being scheduled at all.
- `kubectl get pods -n jenkins` - look for ci-agent/cd-agent Pods stuck in
  `Pending`.

## 2. Likely causes, in order of frequency

1. **Agent Pod can't schedule.** `kubectl describe pod <pending-agent-pod>
   -n jenkins` - insufficient cluster capacity, or a node selector/taint
   mismatch.
2. **RBAC regression.** The `jenkins-controller` ServiceAccount lost its
   ability to create Pods in the `jenkins` namespace (see
   jenkins/rbac/controller-role.yaml) - check for a recent RBAC change;
   `kubectl auth can-i create pods -n jenkins
   --as=system:serviceaccount:jenkins:jenkins-controller` should return
   `yes`.
3. **Image pull failure for the agent image itself** (`jenkins/inbound-
   agent`, the kaniko/trivy/deployer images) - registry rate-limiting or a
   typo'd pinned tag after an update to jenkins/jcasc/jenkins.yaml.
4. **Kubernetes cloud misconfiguration.** JCasC's `clouds:` block (see
   jenkins/jcasc/jenkins.yaml) pointing at the wrong namespace/API server
   after an edit - check `containerCapStr` isn't already at its limit
   (10) with builds genuinely queued behind each other, which is
   expected behavior, not a bug, under real concurrent load.

## 3. Mitigate

- **Scheduling/capacity:** scale the node group, or reduce concurrent
  build load (`disableConcurrentBuilds()` is already set on both jobs -
  see jenkins/jobs/seed.groovy - so this is about total *distinct* queued
  jobs, not one job running twice).
- **RBAC regression:** re-apply `jenkins/rbac/controller-role.yaml` and
  `jenkins/rbac/controller-rolebinding.yaml` - this is why they're
  reviewable, plain, versioned manifests rather than something baked
  silently into the Helm chart.
- **Image pull failure:** verify the pinned tags in
  jenkins/jcasc/jenkins.yaml's pod templates still exist upstream.

## 4. Confirm recovery

`jenkins_queue_stuck_value` back to 0; queued jobs actually start (agent
Pods appear in `kubectl get pods -n jenkins` and are deleted again on
completion - `podRetention: never`).
