Subject: DevOps on AWS Project 2 Submission - Erez Glik

Hi Aviad,

Please find my DevOps on AWS Project 2 submission.

Repository:
https://github.com/eg185044/DevOps

Project summary:
I created a Terraform + Ansible automated AWS deployment for a 3-service CV platform.

Main components:
- Terraform creates VPC, subnets, EC2, Security Groups, RDS PostgreSQL, S3, SNS and IAM.
- Ansible configures the Linux servers, installs Docker, installs and configures Nginx using a role, deploys backend and worker services, and manages variables/secrets using Ansible Vault.
- Frontend server exposes the CV website through HTTP.

Application URL:
http://<frontend_public_ip>

Attached / included:
- Terraform code
- Ansible code
- README
- Architecture diagram
- CV website source
- Screenshots / command outputs

Thanks,
Erez Glik
