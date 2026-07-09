# Running the whole thing on your own laptop - step by step

**Who this is for:** anyone in the IT/DevOps team, even if you've never
touched Kubernetes before. Every step below is one thing at a time, with
the exact command to copy-paste and what you should see if it worked.

**What you're building:** a small, throwaway Kubernetes cluster that lives
entirely inside Docker on your own laptop (called "kind" - Kubernetes IN
Docker). You'll deploy the same app onto it that would normally go onto
AWS EKS, so you can take the screenshots the assignment asks for without
needing real AWS access. At the end you delete it all with one command -
nothing here touches AWS.

Commands below are written for **Windows PowerShell** (this machine's
default shell). If you're on Mac/Linux, every command is identical except
you don't need the `.exe`/`winget` bits in Part A, Step 1.

---

## Before you start: things that must already be true

1. **Docker Desktop is installed and running.** Look for the whale icon in
   your system tray. If it's not running, start it now and wait ~30
   seconds - nothing below will work without it.
2. **kubectl is installed.** Check by running:
   ```powershell
   kubectl version --client
   ```
   You should see a version number, not an error. If you get "command not
   found," install it with `winget install Kubernetes.kubectl`.
3. **You have this repository open in a terminal**, in the
   `final_aws_devops_project` folder (the one containing the `k8s/`
   folder).

---

## Part A - Create your own private test cluster

### Step 1 - Install `kind`

`kind` is the tool that creates a whole Kubernetes cluster using Docker
containers to pretend to be nodes. One-time install:

```powershell
winget install Kubernetes.kind
```

Close and reopen your terminal after this finishes (so it picks up the new
program), then confirm it worked:

```powershell
kind version
```

You should see something like `kind v0.23.0 ...`.

### Step 2 - Create the cluster

```powershell
kind create cluster --name cv-platform
```

This takes 1-3 minutes the first time (it's downloading a Kubernetes
node image). You'll see a few lines of progress ending in something like:

```
Set kubectl context to "kind-cv-platform"
You can now use your cluster with:

kubectl cluster-info --context kind-cv-platform
```

That last line already happened automatically - `kubectl` is now pointed
at your new local cluster.

### Step 3 - Confirm it's alive

```powershell
kubectl get nodes
```

Expected output (one line, roughly):
```
NAME                       STATUS   ROLES           AGE   VERSION
cv-platform-control-plane   Ready    control-plane   1m    v1.29.x
```

**This is your screenshot for assignment 1, Section A, Question 1.**

---

## Part B - Build the three application images

Nothing gets pushed anywhere for local testing - `kind` can load images
straight from your laptop's Docker into the cluster, no registry needed.

### Step 4 - Build the images

Run these three commands one at a time, from the `final_aws_devops_project`
folder:

```powershell
docker build -t erez-cv-devops-frontend:1.0.0 app/frontend
docker build -t erez-cv-devops-backend:1.0.0 app/backend
docker build -t erez-cv-devops-worker:1.0.0 app/worker
```

Each one ends with `writing image sha256:...` and `naming to
docker.io/library/erez-cv-devops-<name>:1.0.0` if it worked.

### Step 5 - Load the images into the cluster

```powershell
kind load docker-image erez-cv-devops-frontend:1.0.0 --name cv-platform
kind load docker-image erez-cv-devops-backend:1.0.0 --name cv-platform
kind load docker-image erez-cv-devops-worker:1.0.0 --name cv-platform
```

Each prints a line like `Image: "erez-cv-devops-frontend:1.0.0" with ID ...
found to be already present on all nodes.`

---

## Part C - Point the manifests at your local images

The files in `k8s/` are written for a real AWS registry
(`REPLACE_ME_REGISTRY/erez-cv-devops-frontend:1.0.0`). For local testing
only, make a temporary copy and swap that placeholder out - **don't edit
the real files**, so nothing you do here can accidentally get committed:

```powershell
Copy-Item -Recurse k8s k8s-local-test

(Get-Content k8s-local-test/deployment-frontend.yaml) -replace 'REPLACE_ME_REGISTRY/erez-cv-devops-frontend:1.0.0', 'erez-cv-devops-frontend:1.0.0' | Set-Content k8s-local-test/deployment-frontend.yaml
(Get-Content k8s-local-test/deployment-backend.yaml)  -replace 'REPLACE_ME_REGISTRY/erez-cv-devops-backend:1.0.0',  'erez-cv-devops-backend:1.0.0'  | Set-Content k8s-local-test/deployment-backend.yaml
(Get-Content k8s-local-test/deployment-worker.yaml)   -replace 'REPLACE_ME_REGISTRY/erez-cv-devops-worker:1.0.0',   'erez-cv-devops-worker:1.0.0'   | Set-Content k8s-local-test/deployment-worker.yaml
(Get-Content k8s-local-test/job-db-migration.yaml)    -replace 'REPLACE_ME_REGISTRY/erez-cv-devops-backend:1.0.0',  'erez-cv-devops-backend:1.0.0'  | Set-Content k8s-local-test/job-db-migration.yaml
```

From here on, every `kubectl apply` command uses the `k8s-local-test`
folder, not `k8s`.

Also tell every Deployment to use the image you just loaded instead of
trying to download it, by adding `imagePullPolicy: IfNotPresent` (already
set in every file - no change needed there, good).

---

## Part D - Create the namespace and configuration

### Step 6 - Namespace

```powershell
kubectl apply -f k8s-local-test/namespace.yaml
```
Expected: `namespace/devops-app created`

### Step 7 - ConfigMap

```powershell
kubectl apply -f k8s-local-test/configmap.yaml
```
Expected: two lines, `configmap/app-config created` and
`configmap/frontend-nginx-conf created`.

### Step 8 - A throwaway local database (stand-in for RDS)

This is **only** for local testing - it's not part of the real production
manifests, and is a separate file just for this purpose:

```powershell
kubectl apply -f k8s-local-test/local-dev/postgres-local.yaml
```
Expected: `deployment.apps/postgres-local created` and
`service/postgres-local created`.

### Step 9 - Secret (database credentials)

For local testing, point it at the throwaway database from Step 8:

```powershell
kubectl create secret generic db-credentials `
  --namespace devops-app `
  --from-literal=DB_HOST="postgres-local.devops-app.svc.cluster.local" `
  --from-literal=DB_USERNAME="erezadmin" `
  --from-literal=DB_PASSWORD="localtest123"
```
Expected: `secret/db-credentials created`

---

## Part E - Deploy the application

Run these one at a time. Each should print one line ending in `created`.

```powershell
kubectl apply -f k8s-local-test/rbac/
kubectl apply -f k8s-local-test/pvc.yaml
kubectl apply -f k8s-local-test/deployment-frontend.yaml
kubectl apply -f k8s-local-test/deployment-backend.yaml
kubectl apply -f k8s-local-test/deployment-worker.yaml
kubectl apply -f k8s-local-test/deployment-redis.yaml
kubectl apply -f k8s-local-test/service-frontend.yaml
kubectl apply -f k8s-local-test/service-backend.yaml
kubectl apply -f k8s-local-test/service-worker.yaml
kubectl apply -f k8s-local-test/service-redis.yaml
kubectl apply -f k8s-local-test/network-policies/
```

Note: `kind`'s default network plugin does not enforce NetworkPolicy, so
that last command will apply successfully but won't actually block
anything on this local cluster - that part only truly takes effect on
EKS/a policy-enforcing CNI. Still fine to apply and screenshot.

---

## Part F - Prove it's working (this is where your screenshots come from)

### Step 10 - Is everything running?

```powershell
kubectl get pods -n devops-app
```

Give it about 30-60 seconds after Part E, then run it again if anything
still says `ContainerCreating` or `Pending`. You want to see every row say
`Running` and `1/1` (or `2/2`) under `READY`:

```
NAME                              READY   STATUS    RESTARTS   AGE
backend-xxxxxxxxxx-xxxxx          1/1     Running   0          1m
backend-xxxxxxxxxx-yyyyy          1/1     Running   0          1m
frontend-xxxxxxxxxx-xxxxx         1/1     Running   0          1m
frontend-xxxxxxxxxx-yyyyy         1/1     Running   0          1m
frontend-xxxxxxxxxx-zzzzz         1/1     Running   0          1m
worker-xxxxxxxxxx-xxxxx           1/1     Running   0          1m
worker-xxxxxxxxxx-yyyyy           1/1     Running   0          1m
redis-cache-xxxxxxxxxx-xxxxx      1/1     Running   0          1m
postgres-local-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
```

**Screenshot this.** It answers assignment 1 Section B, Question 8.

### Step 11 - Everything else that was created

```powershell
kubectl get all -n devops-app
kubectl get deployments -n devops-app
kubectl get services -n devops-app
```

**Screenshot these too.**

### Step 12 - Look inside one Pod

Pick any Pod name from Step 10's output and run:

```powershell
kubectl describe pod <paste-a-pod-name-here> -n devops-app
```

Scroll to the bottom "Events" section - that's the story of what
Kubernetes did to start this Pod. **Screenshot this.**

### Step 13 - Read its logs

```powershell
kubectl logs <paste-a-backend-pod-name-here> -n devops-app
```

For a Flask app this will look like startup lines from the built-in web
server. **Screenshot this.**

### Step 14 - Talk to the app from inside the cluster

This proves frontend can actually reach backend and worker, without
needing the Ingress set up yet. Run a temporary helper Pod:

```powershell
kubectl run curl-test --rm -it --image=curlimages/curl -n devops-app -- sh
```

You'll land inside a shell prompt. Type these one at a time (they test the
exact same routes the real nginx config proxies to):

```sh
curl http://frontend-svc.devops-app.svc.cluster.local/health
curl http://frontend-svc.devops-app.svc.cluster.local/api/health
curl http://frontend-svc.devops-app.svc.cluster.local/worker/health
exit
```

Each should print something like `{"service": "backend", "status": "ok", ...}`.
**Screenshot this whole terminal output** - it's your proof of
frontend-to-backend and frontend-to-worker communication.

### Step 15 - Open it in an actual browser

The simplest way locally (no Ingress controller needed):

```powershell
kubectl port-forward -n devops-app svc/frontend-svc 8080:80
```

Leave that running, then open **http://localhost:8080** in your browser -
you should see the actual CV website. Press `Ctrl+C` in the terminal when
you're done to stop forwarding.

**Screenshot the browser window.** This is your "access via HTTP" proof.

### Step 16 - Test the database write

While the port-forward from Step 15 is still running, open a **second**
terminal and run:

```powershell
curl.exe http://localhost:8080/api/db/init
```

Expected: `{"status": "database initialized and write completed"}` - this
proves backend successfully talked to Postgres (the local stand-in for
RDS). **Screenshot this.**

---

## Part G - The "interesting" Kubernetes behaviors the assignment wants shown

### Step 17 - Kill a Pod and watch Kubernetes bring it back

```powershell
kubectl get pods -n devops-app -l app=backend
```
Copy one backend Pod's name, then:
```powershell
kubectl delete pod <that-pod-name> -n devops-app
kubectl get pods -n devops-app -l app=backend -w
```
Watch it: the old Pod disappears, a **new one** (different random suffix in
its name) appears within a couple of seconds, going
`Pending -> ContainerCreating -> Running`. Press `Ctrl+C` to stop watching.
**Screenshot the before/after.** This is the ReplicaSet self-healing
behavior from assignment 1, Section B, Question 11.

### Step 18 - Break something on purpose (for the CrashLoopBackOff / bad-image demo)

```powershell
kubectl run broken-pod --image=nginx:this-tag-does-not-exist -n devops-app
kubectl get pods -n devops-app -l run=broken-pod
```
You'll see `STATUS` show `ErrImagePull` then `ImagePullBackOff` (this is
what assignment 1 Section C, Question 12 is asking about - it's the
image-not-found equivalent of the crash scenario).

Investigate it the way you would any real failure:
```powershell
kubectl describe pod broken-pod -n devops-app
```
Look at the **Events** section at the bottom - it names the exact image it
couldn't find. **Screenshot this.**

Fix it:
```powershell
kubectl delete pod broken-pod -n devops-app
kubectl run broken-pod --image=nginx:latest -n devops-app
kubectl get pods -n devops-app -l run=broken-pod
```
Now it says `Running`. Clean it up, it was just for the demo:
```powershell
kubectl delete pod broken-pod -n devops-app
```

### Step 19 - Scale up and down

```powershell
kubectl scale deployment worker -n devops-app --replicas=4
kubectl get pods -n devops-app -l app=worker
kubectl scale deployment worker -n devops-app --replicas=2
```
**Screenshot the middle command's output** (showing 4 Pods).

---

## Part H - Clean up

### Step 20 - Delete just the app (keep the cluster for more testing)

```powershell
kubectl delete namespace devops-app
```
One command deletes everything inside it - Deployments, Services,
ConfigMaps, the Secret, all of it.

### Step 21 - Delete the entire local cluster

When you're completely done and don't need to test anymore:

```powershell
kind delete cluster --name cv-platform
```

This removes every Docker container `kind` created. Your laptop is back to
exactly how it was before Part A, Step 2. It has **no effect whatsoever**
on AWS/EKS/RDS - this was always a fully separate, local-only cluster.

### Step 22 (optional) - Remove your temporary local-test copy of the manifests

```powershell
Remove-Item -Recurse -Force k8s-local-test
```

(The real `k8s/` folder was never touched, so there's nothing to restore.)

---

## Quick troubleshooting

| You see | It means | Fix |
|---|---|---|
| `Pending` forever | Not enough resources, or waiting on a PVC | `kubectl describe pod <name> -n devops-app`, read the Events at the bottom |
| `ImagePullBackOff` | Kubernetes can't find/download the image | Confirm Steps 4-5 ran without errors; confirm Part C's find-and-replace worked (`Get-Content k8s-local-test/deployment-backend.yaml \| Select-String image:`) |
| `CrashLoopBackOff` | Container starts then exits | `kubectl logs <name> -n devops-app --previous` |
| `curl: (7) Failed to connect` in Step 14 | A typo in the service DNS name, or the Pod isn't Ready yet | Re-check Step 10 shows `Running` first |
| Docker Desktop not running | `kind create cluster` fails immediately | Start Docker Desktop, wait 30s, retry Step 2 |
