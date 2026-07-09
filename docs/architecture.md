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

For the Kubernetes migration of this same application (frontend/backend/worker as Pods instead of EC2 instances, same RDS/S3/SNS), see [../k8s/README.md](../k8s/README.md) and [../k8s/architecture-diagram.md](../k8s/architecture-diagram.md).
