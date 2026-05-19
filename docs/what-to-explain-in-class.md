# What to Explain in Class

1. I created a CV platform instead of a generic demo app.
2. Terraform creates all AWS resources so the environment is repeatable.
3. Ansible Controller is used because my laptop is Windows 11; the controller runs Ansible against Linux EC2 servers.
4. Frontend, backend, and worker are separate services on separate EC2 instances.
5. nginx is installed through an Ansible role, not manually.
6. Backend and worker run as Docker containers.
7. RDS stores application data.
8. S3 stores uploaded files/events.
9. SNS sends email notifications.
10. Secrets are handled by Ansible Vault example files and are not committed in plaintext.
11. The NLB exposes the nginx frontend to the internet.
12. Security groups are minimal: SSH through controller/admin IP, RDS only from app security group.
