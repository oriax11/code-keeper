# Code-Keeper Infrastructure (`code-keeper-infra`)

This repository contains the Infrastructure as Code (IaC) for the **Code-Keeper** microservices platform, provisioning fully symmetric **Staging** and **Production** environments on AWS using Terraform.

---

## Architecture Overview

Both environments are deployed in isolation within the `us-east-1` region:

- **Networking:** Dedicated VPC per environment with 2 Availability Zones (`us-east-1a`, `us-east-1b`), 2 public subnets, 2 private subnets, an Internet Gateway, NAT Gateway, and segregated route tables.
- **Security:** Layered security groups enforcing least-privilege traffic flow between ALB, API Gateway, Inventory App, Billing App, RabbitMQ broker, and PostgreSQL databases.
- **Compute:** ECS Fargate cluster running 6 microservices:
  - `api-gateway` (stateless, autoscaled min 2 / max 4, behind ALB)
  - `inventory-app` (stateless, autoscaled min 2 / max 4, Service Connect discovery)
  - `billing-app` (stateless consumer, autoscaled min 2 / max 4, Service Connect discovery)
  - `rabbit-queue` (RabbitMQ broker, stateful, single task)
  - `inventory-db` (PostgreSQL 15, persistent EFS storage, single task)
  - `billing-db` (PostgreSQL 15, persistent EFS storage, single task)
- **High Availability & Zero Downtime:**
  - Stateless applications use ECS rolling deployments with `deployment_minimum_healthy_percent = 50`, `deployment_maximum_percent = 200`, and `deployment_circuit_breaker { enable = true, rollback = true }`.
- **Storage:** Amazon Elastic File System (EFS) with encryption at rest, automatic transition to Infrequent Access (IA), and segregated access points per database.
- **Authentication & Secrets:** AWS Cognito User Pool with Hosted UI client; AWS Secrets Manager storing database and broker credentials.
- **Observability:** CloudWatch log groups per service (7-day retention) and a CloudWatch Dashboard monitoring service CPU and memory.
- **Cost Governance:** AWS Budget with forecasted and actual threshold alerts.

---

## Directory Structure

```
code-keeper-infra/
├── .gitignore
├── README.md
├── docker/                     # Platform images (PostgreSQL, RabbitMQ)
│   ├── billing-db/
│   ├── inventory-db/
│   └── rabbit-queue/
├── scripts/                    # Automation & helper scripts
└── terraform/                  # Terraform IaC
    ├── backend.tf              # GitLab-managed HTTP remote state backend
    ├── provider.tf             # AWS and TLS provider configuration with default tags
    ├── variables.tf            # Parameterized root variables with validation
    ├── main.tf                 # Child module wiring
    ├── budget.tf               # Environment-scoped AWS budget alerts
    ├── outputs.tf              # Outputs for CD pipelines (ALB DNS, URLs, cluster, services)
    ├── environments/
    │   ├── staging.tfvars.example
    │   └── production.tfvars.example
    └── modules/
        ├── vpc/                # VPC, subnets, IGW, NAT, route tables
        ├── security/           # Inter-service security groups
        ├── efs/                # EFS file system, mount targets, access points, NFS SG
        ├── alb/                # Application Load Balancer, target group, self-signed ACM TLS
        └── ecs/                # ECS cluster, task definitions, services, IAM, Service Connect, CloudWatch
```

---

## Remote State (GitLab HTTP Backend)

Terraform state is stored remotely using the **GitLab-managed Terraform State** backend (`backend "http"`).

In GitLab CI/CD, the backend is automatically configured per environment using the pipeline's credentials:

```bash
terraform init \
  -backend-config="address=${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/terraform/state/${CI_ENVIRONMENT_NAME}" \
  -backend-config="lock_address=${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/terraform/state/${CI_ENVIRONMENT_NAME}/lock" \
  -backend-config="unlock_address=${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/terraform/state/${CI_ENVIRONMENT_NAME}/lock" \
  -backend-config="username=${GITLAB_USER_LOGIN}" \
  -backend-config="password=${GITLAB_TOKEN}" \
  -backend-config="lock_method=POST" \
  -backend-config="unlock_method=DELETE" \
  -backend-config="retry_wait_min=5"
```

Each environment (`staging` and `production`) maintains an isolated, versioned, and locked state.

---

## Local Usage & Testing

1. **Initialize Terraform:**
   ```bash
   cd terraform
   terraform init -backend=false  # or configure local backend for dry-run testing
   ```

2. **Validate Configurations:**
   ```bash
   terraform fmt -check
   terraform validate
   ```

3. **Plan for Staging:**
   ```bash
   terraform plan -var-file=environments/staging.tfvars
   ```

4. **Plan for Production:**
   ```bash
   terraform plan -var-file=environments/production.tfvars
   ```
