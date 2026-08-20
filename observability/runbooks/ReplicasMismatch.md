# Runbook: ReplicasMismatch

**Fires when:** `kube_deployment_status_replicas_available <
kube_deployment_spec_replicas` for a Deployment in `devops-app`/
`devops-app-dev`, sustained for 10 minutes.

## 1. Confirm it's real

```
kubectl get deployments,pods -n <namespace>
kubectl describe deployment <name> -n <namespace>
kubectl get events -n <namespace> --sort-by=.metadata.creationTimestamp | tail -30
```

Also check the Kubernetes / Cluster dashboard's "Deployments: Desired vs
Available Replicas" panel to see how long the gap has existed and whether
it's stable or worsening.

## 2. Likely causes, in order of frequency

1. **Failing readiness probe.** `kubectl describe pod <pod>` - look at the
   Events section for `Readiness probe failed`. The Pod is Running but
   never becomes Ready, so it never counts toward "available".
2. **Image pull failure.** `ImagePullBackOff` / `ErrImagePull` in `kubectl
   get pods` - usually a bad IMAGE_TAG (check it actually exists in ECR)
   or an ECR auth/IRSA problem on the *node's* pull path (different IAM
   role than the CI push path - see jenkins/README.md IAM section).
3. **Resource pressure.** `Pending` pods with a `FailedScheduling` event
   citing insufficient cpu/memory - check node capacity via the
   Kubernetes / Cluster dashboard.
4. **PodDisruptionBudget / anti-affinity conflict.** frontend's
   `requiredDuringSchedulingIgnoredDuringExecution` pod anti-affinity (see
   k8s/helm/cv-platform/templates/deployment-frontend.yaml) means it needs
   one node per replica - fewer nodes than `frontend.replicas` will
   permanently strand a Pod in Pending.

## 3. Mitigate

- **Readiness probe failing on genuinely broken code:** roll back (see
  HighErrorRate.md's rollback steps).
- **Image pull failure:** fix the tag/IAM role, then re-run `cd-application`
  with the corrected input - no rollback needed if `Deploy` never
  completed (Helm's `--atomic` means a failed upgrade doesn't touch the
  previously-running revision).
- **Resource pressure / anti-affinity:** scale the node group, or reduce
  `replicas` to match available node count as an immediate mitigation.

## 4. Confirm recovery

`kubectl get deployments -n <namespace>` shows `READY` == desired replica
count for every Deployment; the dashboard panel's two lines converge.
