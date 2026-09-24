# Code-Keeper CI/CD Lab

CI/CD infrastructure for the **Code-Keeper** project.

The Iximiuz playground provides the GitLab server, GitLab Runner, and development environment.
**Application staging and production environments are hosted in AWS**, using the Cloud Design infrastructure.

---

## Architecture

```text
                         Code-Keeper CI/CD
                                │
                                │ git push
                                ▼
                       ┌─────────────────┐
                       │    dev-01       │
                       │ Developer       │
                       │ Workstation     │
                       └────────┬────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │   gitlab-01     │
                       │                 │
                       │ GitLab          │
                       │ Git repository  │
                       │ CI/CD           │
                       └────────┬────────┘
                                │
                         Pipeline trigger
                                │
                                ▼
                       ┌─────────────────┐
                       │   runner-01     │
                       │                 │
                       │ Build           │
                       │ Test            │
                       │ Security scan   │
                       │ Docker          │
                       │ Terraform      │
                       │ Deployment      │
                       └────────┬────────┘
                                │
                         AWS credentials
                                │
                                ▼
                 ┌─────────────────────────────┐
                 │             AWS             │
                 │                             │
                 │  ┌───────────────────────┐  │
                 │  │       Staging         │  │
                 │  │                       │  │
                 │  │ ECS / Fargate         │  │
                 │  │ ALB                   │  │
                 │  │ Application services  │  │
                 │  └───────────────────────┘  │
                 │                             │
                 │  ┌───────────────────────┐  │
                 │  │      Production       │  │
                 │  │                       │  │
                 │  │ ECS / Fargate         │  │
                 │  │ ALB                   │  │
                 │  │ Application services  │  │
                 │  └───────────────────────┘  │
                 └─────────────────────────────┘
```

---

## Playground Machines

### `gitlab-01`

The central GitLab server.

Responsibilities:

* Host the Code-Keeper Git repository
* Run GitLab CI/CD
* Store pipeline configuration
* Manage GitLab users and projects
* Coordinate GitLab Runners

This machine **does not run the application**.

---

### `runner-01`

The GitLab Runner responsible for executing CI/CD jobs.

Typical pipeline operations include:

```text
Checkout
   ↓
Test
   ↓
Build Docker images
   ↓
Security scanning
   ↓
Push images
   ↓
Deploy to AWS staging
   ↓
Integration tests
   ↓
Deploy to AWS production
```

Tools installed on the runner may include:

* Docker
* Git
* AWS CLI
* Terraform
* Ansible
* Security scanning tools

The runner is a **CI/CD worker**, not a production server.

---

### `dev-01`

A simulated developer workstation.

It represents the environment from which a developer works with the GitLab repository.

Typical workflow:

```bash
git clone <gitlab-repository>
cd code-keeper

# modify code

git add .
git commit -m "..."
git push
```

The push triggers the GitLab pipeline.

`dev-01` is not required for AWS deployment itself. It exists to reproduce a more realistic development workflow inside the lab.

---

## AWS Environments

The actual application environments are outside the Iximiuz playground.

The existing **Cloud Design** AWS infrastructure provides the deployment platform.

### Staging

Used to validate a new version before production.

```text
AWS
└── Staging
    ├── ECS / Fargate
    ├── ALB
    ├── API Gateway
    ├── Inventory
    ├── Billing
    ├── Databases
    └── RabbitMQ
```

### Production

Runs the production version of Code-Keeper.

```text
AWS
└── Production
    ├── ECS / Fargate
    ├── ALB
    ├── API Gateway
    ├── Inventory
    ├── Billing
    ├── Databases
    └── RabbitMQ
```

Staging and production should be isolated environments while sharing the same reusable Terraform infrastructure modules.

---

## CI/CD Flow

The intended deployment flow is:

```text
Developer
    │
    │ git push
    ▼
GitLab
    │
    │ pipeline
    ▼
GitLab Runner
    │
    ├── Test
    ├── Build
    ├── Security Scan
    ├── Push Image
    │
    ▼
AWS Staging
    │
    ├── Deploy
    └── Integration Tests
    │
    ▼
AWS Production
```

Production deployment can be protected by a manual approval step in GitLab.

---

## Terraform

Terraform manages the AWS infrastructure.

The infrastructure should be designed around reusable modules rather than duplicated staging and production configurations.

Example:

```text
terraform/
├── modules/
│   ├── networking/
│   ├── ecs/
│   ├── alb/
│   └── databases/
│
├── staging/
│   └── main.tf
│
└── production/
    └── main.tf
```

The same modules can be used for both environments with different configuration.

For example:

```text
staging
  → cloud-design module
  → smaller resources / desired count

production
  → cloud-design module
  → production resources / desired count
```

This demonstrates infrastructure reuse while keeping the environments isolated.

---

## Purpose of the Iximiuz Playground

The playground is intentionally limited to the **CI/CD infrastructure**.

It provides:

* GitLab
* GitLab Runner
* Developer workstation
* An isolated environment for testing Ansible configuration
* An isolated environment for testing CI/CD pipelines

It does **not** represent the production infrastructure.

Production workloads run in AWS.

---

## Machine Summary

| Machine        | Role                       | Runs application? |
| -------------- | -------------------------- | ----------------- |
| `dev-01`       | Developer workstation      | No                |
| `gitlab-01`    | GitLab server              | No                |
| `runner-01`    | CI/CD execution            | No                |
| AWS Staging    | Pre-production environment | Yes               |
| AWS Production | Production environment     | Yes               |

---

## Design Principle

The project intentionally separates **CI infrastructure** from **application infrastructure**:

```text
Iximiuz Playground
        │
        └── CI/CD

AWS
        │
        ├── Staging
        └── Production
```

This allows the same CI/CD system to deploy the application to real cloud environments instead of treating the playground machines as production servers.
