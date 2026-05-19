# Architecture Diagram

```text
+------------------+          HTTP           +----------------------+
| User / Browser   | ----------------------> | EC2 Frontend         |
| Internet         |                         | Nginx + Static CV    |
+------------------+                         +----------+-----------+
                                                       |
                                                       | /api reverse proxy
                                                       v
                                            +----------+-----------+
                                            | EC2 Backend          |
                                            | Docker Flask API     |
                                            +----+---------+-------+
                                                 |         |
                                                 |         +----> SNS Email Topic
                                                 |
                                                 +--------------> RDS PostgreSQL
                                                 |
                                                 +--------------> S3 CV Bucket

                                            +----------------------+
                                            | EC2 Worker           |
                                            | Docker Worker        |
                                            +----------------------+

+------------------------+
| EC2 Ansible Controller |
| Runs ansible-playbook  |
+------------------------+
```

Terraform creates the AWS resources. Ansible configures packages, Docker, Nginx, and application deployment.
