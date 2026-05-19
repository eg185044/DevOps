# Baby-step runbook - Windows 11 + VS Code + AWS + Terraform + Ansible

## Architecture

Your Windows 11 laptop is only the workstation. AWS runs the servers.

```text
Windows 11 + VS Code
  |
  | terraform apply
  v
AWS Cloud
  - Ansible Controller EC2
  - Frontend EC2: nginx role
  - Backend EC2: Docker Flask API
  - Worker EC2: Docker worker
  - Network Load Balancer -> frontend:80
  - Optional RDS PostgreSQL, S3, SNS

Then:
Windows laptop -> SSH to Ansible Controller -> run ansible-playbook -> configure 3 app servers
```

## What you will create

- Terraform infrastructure under `terraform/`
- Ansible controller EC2
- Three Linux EC2 target servers
- `ansible/inventory.ini`
- `ansible/ansible.cfg`
- `ansible/roles/nginx`
- `ansible/nginx-role-playbook.yml`
- `ansible/site.yml`
- `ansible/group_vars/secrets-vault.yml`

## Step 0 - Install tools on Windows 11

Install:

- VS Code
- Git for Windows
- AWS CLI v2
- Terraform

Open VS Code, then open the project folder.

## Step 1 - Configure AWS CLI

In VS Code PowerShell:

```powershell
aws configure
aws sts get-caller-identity
```

## Step 2 - Create or download AWS key pair

AWS Console -> EC2 -> Key Pairs -> Create key pair:

- Name: `aviad-01`
- Type: RSA
- Format: `.pem`

Save as:

```text
C:\Users\YOUR_WINDOWS_USER\.ssh\aviad-01.pem
```

## Step 3 - Prepare Terraform variables

Copy:

```powershell
Copy-Item terraform\terraform.tfvars.example terraform\terraform.tfvars
```

Edit `terraform/terraform.tfvars`:

```hcl
allowed_ssh_cidr = "YOUR_PUBLIC_IP/32"
sns_email        = "glikerez@gmail.com"
db_password      = "CHANGE_ME_STRONG_PASSWORD_123!"
key_name         = "aviad-01"
```

Get your public IP:

```powershell
(Invoke-WebRequest -UseBasicParsing https://checkip.amazonaws.com).Content.Trim()
```

## Step 4 - Create AWS infrastructure

```powershell
cd terraform
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

Type `yes`.

## Step 5 - Save Terraform output

```powershell
terraform output
terraform output -raw ansible_inventory > ..\ansible\inventory.ini
terraform output ansible_controller_public_ip
terraform output website_url_nlb
```

## Step 6 - Copy SSH private key to the Ansible controller

Replace `ANSIBLE_CONTROLLER_PUBLIC_IP` with Terraform output.

```powershell
scp -i $env:USERPROFILE\.ssh\aviad-01.pem $env:USERPROFILE\.ssh\aviad-01.pem ubuntu@ANSIBLE_CONTROLLER_PUBLIC_IP:/home/ubuntu/.ssh/aviad-01.pem
ssh -i $env:USERPROFILE\.ssh\aviad-01.pem ubuntu@ANSIBLE_CONTROLLER_PUBLIC_IP "chmod 600 /home/ubuntu/.ssh/aviad-01.pem"
```

## Step 7 - Copy project to Ansible controller

From the parent folder of this project:

```powershell
scp -i $env:USERPROFILE\.ssh\aviad-01.pem -r .\aws-devops-cv-ansible-project ubuntu@ANSIBLE_CONTROLLER_PUBLIC_IP:/home/ubuntu/project
```

Or push to GitHub and clone from the controller:

```bash
git clone YOUR_REPO_URL /home/ubuntu/project
```

## Step 8 - SSH to Ansible controller

```powershell
ssh -i $env:USERPROFILE\.ssh\aviad-01.pem ubuntu@ANSIBLE_CONTROLLER_PUBLIC_IP
```

Then on the controller:

```bash
cd /home/ubuntu/project
chmod 600 ~/.ssh/aviad-01.pem
ansible --version
```

## Step 9 - Create Ansible Vault secrets file

```bash
cd /home/ubuntu/project/ansible
cp group_vars/secrets-vault.yml.example group_vars/secrets-vault.yml
nano group_vars/secrets-vault.yml
```

Edit passwords.

Create vault password file:

```bash
nano .vault_pass
chmod 600 .vault_pass
```

Encrypt secrets:

```bash
ansible-vault encrypt group_vars/secrets-vault.yml
```

To edit later:

```bash
ansible-vault edit group_vars/secrets-vault.yml
```

## Step 10 - Test Ansible connection

```bash
cd /home/ubuntu/project/ansible
ansible all -m ping
```

Expected: all hosts return `pong`.

## Step 11 - Run only the nginx role goal

```bash
ansible-playbook nginx-role-playbook.yml
```

Test frontend:

```bash
curl http://FRONTEND_PRIVATE_OR_PUBLIC_IP/health
```

## Step 12 - Run full site deployment

```bash
ansible-playbook site.yml
```

## Step 13 - Open website

On Windows, open Terraform output:

```powershell
terraform -chdir=terraform output website_url_nlb
```

Browser:

```text
http://NLB_DNS_NAME
```

## Step 14 - Test API

```bash
curl http://NLB_DNS_NAME/health
curl http://NLB_DNS_NAME/api/health
curl http://NLB_DNS_NAME/api/cv
```

## Step 15 - Destroy when finished

To avoid AWS cost:

```powershell
terraform -chdir=terraform destroy
```
