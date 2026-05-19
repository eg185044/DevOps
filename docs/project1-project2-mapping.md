# Project 1 + Project 2 Mapping

## Combined idea

This project is a personal CV platform for Erez Glik. The public frontend presents the CV using nginx. The backend and worker are separate microservices deployed to separate EC2 instances.

## Project 1 requirements

| Requirement | Implementation |
|---|---|
| 3 EC2 services | frontend, backend, worker |
| Frontend based on nginx | `ansible/roles/nginx` installs nginx and serves `app/frontend/public` |
| Backend service | Flask API under `app/backend` running as Docker container |
| Worker service | Python worker under `app/worker` running as Docker container |
| RDS | Terraform creates PostgreSQL RDS when `create_rds=true` |
| S3 | Terraform creates private S3 bucket for file upload/demo |
| SNS | Terraform creates SNS topic and email subscription |
| External HTTP access | AWS NLB forwards port 80 to frontend nginx |
| Documentation | README, architecture, runbook, submission checklist |

## Project 2 requirements

| Requirement | Implementation |
|---|---|
| Terraform IaC | `terraform/` creates VPC, EC2, SGs, RDS, S3, SNS, NLB, IAM |
| Variables and outputs | `variables.tf`, `terraform.tfvars.example`, `outputs.tf` |
| State explanation | README and baby steps explain local state for course use |
| Ansible inventory | `terraform output -raw ansible_inventory > ansible/inventory.ini` |
| Ansible roles | `common`, `docker`, `nginx`, `backend`, `worker` |
| nginx role | `ansible/roles/nginx` with tasks, handler, template |
| handlers | nginx reload handler in `roles/nginx/handlers/main.yml` |
| pre_tasks / post_tasks | in `ansible/site.yml` and `nginx-role-playbook.yml` |
| Ansible Vault | `group_vars/secrets-vault.yml.example` |
| Run Terraform from Ansible | `ansible/run-terraform.yml` |
| Docker runtime | `ansible/roles/docker` |
| Microservices | backend and worker Docker containers |
| CV page | frontend static HTML/CSS from Erez CV |
