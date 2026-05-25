# Erez Glick AWS DevOps CV Platform 1

## https://www.linkedin.com/in/erezglik/

### https://marstick.com/en/

One refined project made from **Project12**.

The goal is to create a complete AWS DevOps flow :

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
AWS Cloud
  |-- VPC, subnets, route tables, security groups
  |-- IAM role for EC2 access to S3 and SNS
  |-- EC2 Ansible Controller
  |-- EC2 Frontend: nginx + CV page
  |-- EC2 Backend: Flask API in Docker
  |-- EC2 Worker: Python worker in Docker
  |-- Network Load Balancer -> Frontend nginx
  |-- RDS PostgreSQL
  |-- S3 bucket
  |-- SNS topic + email subscription
```

---

## What Terraform creates

Terraform creates the AWS infrastructure:

- VPC
- Public subnets
- Internet Gateway
- Route table
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

## Folder structure

```text
terraform/                 AWS infrastructure as code
ansible/                   Configuration management
ansible/roles/nginx        nginx package role with handler/template
ansible/run-terraform.yml  Optional playbook to run terraform from ansible
app/frontend/public        CV website
app/backend                Flask backend Docker service
app/worker                 Worker Docker service
docs                       Runbook, architecture, mapping, checklist
scripts                    Windows and controller helper scripts
k8s                        CNCF/Kubernetes extension placeholder
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

## Important security notes

Do not commit:

- `terraform.tfvars`
- `.pem` private keys
- `ansible/group_vars/secrets-vault.yml` unless encrypted
- `.vault_pass`

Use example files only in Git.

