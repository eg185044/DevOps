# Submission Checklist

## Files to submit

- [ ] Full project ZIP or Git repository
- [ ] README.md
- [ ] Terraform folder
- [ ] Ansible folder
- [ ] App folder
- [ ] Architecture diagram
- [ ] Screenshots or command outputs

## Required command outputs / screenshots

```bash
terraform init
terraform plan
terraform apply
terraform output
terraform output -raw ansible_inventory > ansible/inventory.ini
ansible all -m ping
ansible-playbook nginx-role-playbook.yml --ask-vault-pass
ansible-playbook site.yml --ask-vault-pass
```

## Required AWS screenshots

- [ ] EC2 instances: ansible controller, frontend, backend, worker
- [ ] NLB and target group health
- [ ] RDS PostgreSQL
- [ ] S3 bucket
- [ ] SNS topic and email subscription
- [ ] Security groups
- [ ] IAM role/policy for S3/SNS access

## Required app screenshots

- [ ] Browser showing Erez CV page through NLB URL
- [ ] `/health` on frontend
- [ ] `/api/health` backend through nginx reverse proxy
- [ ] `/api/db/init`
- [ ] `/api/db/events`
- [ ] `/api/s3/upload`
- [ ] `/api/sns/publish`

## Security checks

- [ ] No `.pem` key in Git/ZIP unless explicitly required by class and protected
- [ ] No real `terraform.tfvars`
- [ ] No unencrypted `secrets-vault.yml`
- [ ] `admin_ip_cidr` is your IP `/32`, not `0.0.0.0/0`
