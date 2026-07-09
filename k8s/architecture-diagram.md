# Kubernetes Architecture

Replaces the EC2 + Ansible topology in [docs/architecture.md](../docs/architecture.md).
Same external services (RDS, S3, SNS), same three application tiers - now
running as Pods in a single EKS cluster/namespace instead of three EC2
instances.

```mermaid
flowchart TB
    User["User / Browser<br/>(Internet)"]

    subgraph AWS["AWS Account - eu-west-1"]
        subgraph VPC["VPC (terraform/main.tf)"]
            subgraph Public["Public subnets"]
                LB["AWS Load Balancer<br/>(ALB/NLB, provisioned by the<br/>Ingress controller or AWS LB Controller)"]
            end

            subgraph Private["Private subnets - EKS worker node group(s)"]
                subgraph EKS["EKS Cluster"]
                    subgraph NS["Namespace: devops-app"]
                        ING["Ingress: cv-platform-ingress<br/>(only route into the cluster)"]

                        subgraph FE["tier=frontend (frontend-sa)"]
                            FESVC["Service: frontend-svc :80"]
                            FEPODS["Pods: frontend x3<br/>(anti-affinity: 1 per node)"]
                        end

                        subgraph BE["tier=backend (backend-sa + IRSA)"]
                            BESVC["Service: backend-svc :5000<br/>ClusterIP - internal only"]
                            BEPODS["Pods: backend x2"]
                        end

                        subgraph WK["tier=worker (worker-sa + IRSA)"]
                            WKSVC["Service: worker-svc :5002<br/>ClusterIP - internal only"]
                            WKPODS["Pods: worker x2"]
                        end

                        subgraph CACHE["tier=cache - bonus (redis-sa)"]
                            RDSVC["Service: redis-svc :6379"]
                            RDPOD["Pod: redis-cache x1"]
                            PVC[("PVC: redis-data 1Gi<br/>(EBS gp3)")]
                        end

                        CM["ConfigMaps:<br/>app-config, frontend-nginx-conf"]
                        SEC["Secret: db-credentials"]
                        JOB["Job: db-migration (one-off)"]
                        CRON["CronJob: cache-cleanup (nightly)"]
                    end
                end
            end

            RDS[("RDS PostgreSQL<br/>private subnet, SG-restricted")]
        end

        S3[("S3 bucket<br/>CV storage")]
        SNS["SNS Topic<br/>events"]
    end

    User -->|HTTPS/HTTP| LB
    LB --> ING --> FESVC --> FEPODS
    FEPODS -->|"/api/* (NetworkPolicy allowed)"| BESVC --> BEPODS
    FEPODS -->|"/worker/* (NetworkPolicy allowed)"| WKSVC --> WKPODS
    BEPODS -->|"IRSA temp creds"| S3
    BEPODS -->|"IRSA temp creds"| SNS
    BEPODS -->|"5432, NetworkPolicy egress unrestricted,<br/>SG-restricted at VPC layer"| RDS
    WKPODS -->|"IRSA temp creds"| S3
    BEPODS -.->|"optional, unused today"| RDSVC
    RDSVC --> RDPOD --- PVC
    JOB -->|"schema init, runs once"| RDS
    CRON -->|"nightly FLUSHDB"| RDSVC
    CM -.->|env vars / mounted file| FEPODS & BEPODS & WKPODS
    SEC -.->|env vars| BEPODS
```

## Security boundaries

| Zone | What lives there | Reachable from |
|---|---|---|
| **Public** | AWS Load Balancer (created by the Ingress controller / AWS LB Controller) | The internet |
| **Private (VPC)** | EKS worker nodes, all Pods, RDS instance | Only the Load Balancer (frontend Pods) and Pods that call out (RDS/S3/SNS) |
| **Internal (cluster-only, NetworkPolicy-enforced)** | backend-svc, worker-svc, redis-svc | Only frontend Pods (backend/worker) and backend/worker Pods (redis) - see `k8s/network-policies/` |

Only the **frontend** tier is reachable from outside the cluster (via
`ingress.yaml` -> `frontend-svc`). backend, worker and redis-cache have no
Ingress, are `type: ClusterIP`, and are further locked down by
`network-policies/` so only the intended caller can reach each one - this is
the concrete answer to "which components are internal and which are exposed"
required by the assignment.

If deployed on EKS: node groups sit in the **private** subnets created by
`terraform/main.tf` (`aws_subnet.private_a/b`); the Load Balancer sits in the
**public** subnets (`aws_subnet.public_a/b`). RDS already lives in a private
subnet group (`aws_db_subnet_group.main`) reachable only from the `app`
security group. S3 and SNS are regional AWS services reached over the
internet gateway/NAT (or, as a hardening step, via VPC Gateway/Interface
Endpoints - see the "Trade-offs" section of `k8s/README.md`).
