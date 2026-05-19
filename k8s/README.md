# Kubernetes / CNCF extension

This project deploys the working version with EC2 + Docker runtime + Ansible because the assignment goal is nginx via Ansible role on EC2.

For the CNCF/Kubernetes part of the learning flow, use this folder as the next step:

1. Build backend and worker Docker images.
2. Push them to ECR.
3. Create EKS with Terraform or eksctl.
4. Convert the Docker runtime services into Kubernetes Deployments and Services.
5. Put nginx behind a Kubernetes Ingress Controller.

This folder is intentionally documented as an extension so the EC2/Ansible deliverable stays simple and working.
