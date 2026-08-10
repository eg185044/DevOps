# Erez Glick AWS DevOps PWA_CV Platform.

## https://www.linkedin.com/in/erezglik/

### https://marstick.com/en/

One refined project made from **Erez Glick Project**.

The Main goal is to create a complete AWS DevOps flow :

```text
AWS -> IAM -> EC2 -> Terraform -> Ansible Controller -> Docker Runtime -> Microservices -> nginx Role -> CV Page
```

The final public page presents **Erez Glik's CV** through nginx on EC2 behind an AWS Network Load Balancer.

---



## Architecture


```text
Windows 11 + VS Code
  |
  | Terraform
  v
AWS Cloud  (VPC 10.20.0.0/16)
  |
  |-- PUBLIC TIER (Internet-facing)
  |     |-- Internet Gateway
  |     |-- NAT Gateway (outbound for private tier)
  |     |-- Public Subnet A (10.20.1.0/24, eu-west-1a)
  |     |     |-- EC2 Ansible Controller  [Terraform + Ansible]
  |     |     |-- EC2 Frontend: nginx + CV page
  |     |-- Public Subnet B (10.20.2.0/24, eu-west-1b)
  |     |-- Network Load Balancer -> Frontend nginx (port 80)
  |
  |-- PRIVATE TIER (No direct internet access)
  |     |-- Private Subnet A (10.20.3.0/24, eu-west-1a)
  |     |     |-- EC2 Backend: Flask API in Docker (port 5000)
  |     |     |-- RDS PostgreSQL (port 5432)
  |     |-- Private Subnet B (10.20.4.0/24, eu-west-1b)
  |           |-- EC2 Worker: Python worker in Docker (port 5002)
  |           |-- RDS PostgreSQL (Multi-AZ standby)
  |
  |-- IAM role for EC2 access to S3 and SNS
  |-- S3 bucket (CV file storage)
  |-- SNS topic + email subscription (events)

Security group rules:
  Frontend SG  <- HTTP :80 from 0.0.0.0/0, SSH :22 from Ansible SG + your IP
  App SG       <- :5000/:5002 from Frontend SG, SSH :22 from Ansible SG only
  RDS SG       <- :5432 from App SG only
  Ansible SG   <- SSH :22 from your IP only
```

---

## What Terraform creates

Terraform creates the AWS infrastructure:

- VPC
- Public subnets (frontend, Ansible Controller, NLB)
- Private subnets (backend, worker, RDS)
- Internet Gateway
- NAT Gateway (outbound internet for private instances)
- Route tables (public and private)
- Security groups
- IAM role and instance profile
- Ansible Controller EC2
- Frontend EC2
- Backend EC2
- Worker EC2
- Network Load Balancer
- RDS PostgreSQL
- S3 bucket
- SNS topic and email subscription
- Dynamic Ansible inventory output

---

## What Ansible does

Ansible configures the servers:

- Installs common Linux packages
- Installs Docker runtime
- Deploys backend Docker microservice
- Deploys worker Docker microservice
- Installs nginx from the nginx role
- Copies the CV frontend page
- Configures nginx reverse proxy to backend
- Uses Ansible Vault for DB/app secrets

---

## Extended explanation - how everything fits together (plain English)

This section is the "explain it to a new teammate" version of this project -
read this first if the sections above feel like too much detail too fast.

### One-sentence summary

A personal CV (resume) website, built the way a real production app would be:
three small services, deployable to AWS two different ways, with an
automated build pipeline in front of it.

### The analogy

- **Terraform** = construction crew - builds the building itself (servers,
  network, load balancer).
- **Ansible** = the crew that installs equipment inside each room (installs
  Docker, nginx, deploys the apps onto the servers Terraform built).
- **Docker** = pre-packaged meal kits - the app code boxed up so it runs
  identically anywhere.
- **Kubernetes** = a newer, self-managing restaurant that runs those meal
  kits directly, without needing a separate building per kit.
- **Jenkins** = the automatic assembly line that builds and checks every
  meal kit before it is allowed to reach a restaurant.

### The application itself - just 3 small services (`app/`)

| Service    | What it is    | What it does                                              |
|------------|---------------|------------------------------------------------------------|
| `frontend` | nginx         | Serves the CV webpage - the only thing a visitor talks to  |
| `backend`  | Flask (Python)| API: CV data, health checks, DB, S3, SNS                   |
| `worker`   | Python        | Background/async jobs                                      |

`frontend` proxies `/api/*` to `backend` and `/worker/*` to `worker`. That is
the entire application - everything else in this repo exists to build,
configure, and run these three pieces.

### Two ways to deploy the same 3 services

**Path A - classic AWS (`terraform/` + `ansible/`)**, documented step-by-step
above and in `docs/baby-steps-runbook.md`: Terraform creates a VPC, subnets,
4 EC2 instances (Ansible controller + frontend + backend + worker), an NLB,
RDS, S3, and SNS. Ansible then SSHes in from the controller and installs
Docker/nginx and deploys the three services onto those EC2 instances.

**Path B - Kubernetes (`k8s/`)**: the same 3 services, containerized, running
as Pods in one cluster (EKS, or a free local `kind` cluster for practice -
see `docs/local-kind-runbook.md`) instead of on 3 separate EC2 instances
glued together by Ansible. Full detail in `k8s/README.md`, including
Deployments/Services, an Ingress as the only door open to the internet,
NetworkPolicies (deny-by-default firewall between Pods), least-privilege
RBAC/ServiceAccounts, Helm charts (`k8s/helm/`), and GitOps via ArgoCD
(`k8s/argocd/`) so the cluster stays in sync with Git automatically instead
of requiring manual `kubectl`/`helm` commands. RDS/S3/SNS stay outside the
cluster either way - Kubernetes only replaces the "3 EC2 instances" part,
not the AWS data services.

### CI/CD: Jenkins running inside Kubernetes (Mission 4)

Jenkins itself runs as a Pod inside the same EKS cluster as Path B,
installed entirely from code (Helm + JCasC - no manual UI setup). Two
separate pipelines, matching the CI/CD separation principle: `ci-Jenkinsfile`
(checkout, lint, unit tests, Docker build via kaniko, Trivy scan, push to
ECR with an immutable `<commit-sha>-b<build-number>` tag, never `latest`)
and `cd-Jenkinsfile` (takes that exact tag, `helm upgrade --install`s
`k8s/helm/cv-platform`, waits for rollout, runs a smoke test, prints
rollback instructions on failure). CI never deploys; CD never rebuilds an
image. Full details, architecture diagrams, and the security write-up
live in **[jenkins/README.md](jenkins/README.md)**.

### End-to-end flow, in order

1. Code lives in GitHub.
2. Jenkins (running in-cluster - see `jenkins/`) lints, tests, builds and
   scans it on every push (`ci-Jenkinsfile`), then `cd-Jenkinsfile` deploys
   the exact image that passed CI.
3. Infrastructure gets created either the old way (Terraform + Ansible +
   EC2) or the new way (`kubectl`/Helm/ArgoCD + Kubernetes).
4. Either way, it is the same 3 containers, and the same external
   RDS/S3/SNS.
5. A visitor hits the Load Balancer (Path A) or Ingress (Path B) -> nginx
   frontend -> proxies to backend/worker -> CV renders, API calls work.
6. `terraform destroy` or `kubectl delete namespace devops-app` tears it
   down when finished, so nothing keeps costing money.

---

## Folder structure

```text
terraform/                 AWS infrastructure as code (Path A)
ansible/                   Configuration management (Path A)
ansible/roles/nginx        nginx package role with handler/template
ansible/run-terraform.yml  Optional playbook to run terraform from ansible
app/frontend/public        CV website
app/backend                Flask backend Docker service
app/worker                 Worker Docker service
docs                       Runbook, architecture, mapping, checklist
scripts                    Windows and controller helper scripts
k8s                        Kubernetes deployment (Path B): manifests, Helm charts, ArgoCD GitOps
jenkins                    Jenkins-on-Kubernetes: Helm values, JCasC, RBAC, install/verify scripts
ci-Jenkinsfile             CI pipeline: lint, test, build (kaniko), scan (Trivy), push to ECR
cd-Jenkinsfile             CD pipeline: helm upgrade to k8s/helm/cv-platform, rollout, smoke test
```

---

## Baby steps from Windows 11 + VS Code

### 1. Open project

```powershell
code .
```

### 2. Configure AWS CLI

```powershell
aws configure
```

### 3. Prepare your SSH key

Put your key here:

```powershell
mkdir $env:USERPROFILE\.ssh -Force
copy C:\path\to\erezg01.pem $env:USERPROFILE\.ssh\erezg01.pem
icacls $env:USERPROFILE\.ssh\erezg01.pem /inheritance:r
icacls $env:USERPROFILE\.ssh\erezg01.pem /grant:r "$env:USERNAME:R"
```

### 4. Create Terraform variables

```powershell
copy terraform\terraform.tfvars.example terraform\terraform.tfvars
notepad terraform\terraform.tfvars
```

Update:

```hcl
key_name              = "erezg01"
ssh_private_key_path  = "~/.ssh/erezg01.pem"
allowed_ssh_cidr      = "YOUR_PUBLIC_IP/32"
sns_email             = "your.mail@example.com"
db_password           = "StrongPasswordHere!"
```

### 5. Run Terraform

```powershell
terraform -chdir=terraform init
terraform -chdir=terraform plan -out=tfplan
terraform -chdir=terraform apply tfplan
terraform -chdir=terraform output
terraform -chdir=terraform output -raw ansible_inventory > ansible\inventory.ini
```

### 6. Copy the project to the Ansible Controller

```powershell
$controller = terraform -chdir=terraform output -raw ansible_controller_public_ip
.\scripts\copy-to-controller.ps1 -ControllerIp $controller -KeyPath "$env:USERPROFILE\.ssh\erezg01.pem"
```

### 7. SSH to the Ansible Controller

```powershell
ssh -i "$env:USERPROFILE\.ssh\erezg01.pem" ubuntu@$controller
```

### 8. Bootstrap controller

```bash
cd ~/aws-devops-cv-platform
bash scripts/controller_bootstrap.sh
```

### 9. Create and encrypt secrets vault

```bash
cd ansible
cp group_vars/secrets-vault.yml.example group_vars/secrets-vault.yml
ansible-vault encrypt group_vars/secrets-vault.yml
```

### 10. Test connection

```bash
ansible all -m ping --ask-vault-pass
```

### 11. Run nginx role only

```bash
ansible-playbook nginx-role-playbook.yml --ask-vault-pass
```

### 12. Run full project

```bash
ansible-playbook site.yml --ask-vault-pass
```

### 13. Open CV page

From Windows:

```powershell
terraform -chdir=terraform output -raw website_url_nlb
```

Open that URL in your browser.

---

## Optional: run Terraform from Ansible

This matches the flow in your VS Code screenshot.

```bash
cd ansible
ansible-playbook run-terraform.yml -e terraform_action=plan
ansible-playbook run-terraform.yml -e terraform_action=apply
```

---

## Static inventory using your IPs

If you already have these three servers, use `ansible/inventory.ini.example`:

```text
51.85.75.88 = frontend
51.85.75.87 = backend
51.85.75.86 = worker
```

But if Terraform creates the servers, generate `inventory.ini` from Terraform output.

---

## Useful test URLs

```text
http://NLB_DNS_NAME/
http://NLB_DNS_NAME/health
http://NLB_DNS_NAME/api/health
http://NLB_DNS_NAME/api/db/init
http://NLB_DNS_NAME/api/db/events
http://NLB_DNS_NAME/api/s3/upload
http://NLB_DNS_NAME/api/sns/publish
```

---

## Destroy environment

```powershell
terraform -chdir=terraform destroy
```

---

## Terraform state

### This project (local state)

By default Terraform stores state in `terraform/terraform.tfstate` on your local machine. This is fine for a single-developer course project: it is simple, requires no extra infrastructure, and state is never shared. The file is excluded from Git via `.gitignore` to avoid leaking resource IDs and sensitive output values.

### Production recommendation (remote state)

In a team or production environment, local state causes conflicts when multiple engineers run Terraform simultaneously and is lost if the workstation is destroyed. The standard AWS pattern is an S3 backend with DynamoDB locking:

```hcl
# Add to terraform/providers.tf before running terraform init
terraform {
  backend "s3" {
    bucket         = "my-org-terraform-state"
    key            = "erez-cv-devops/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
```

Create the S3 bucket and DynamoDB table once (manually or with a bootstrap Terraform module), then run `terraform init` to migrate existing local state to the remote backend. With this setup, state is encrypted at rest, versioned, and locked during operations so concurrent runs cannot corrupt it.

---

## Important security notes

Do not commit:

- `terraform.tfvars`
- `.pem` private keys
- `ansible/group_vars/secrets-vault.yml` unless encrypted
- `.vault_pass`

Use example files only in Git.
