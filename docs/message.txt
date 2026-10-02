# Code-Keeper CI/CD — Infrastructure Deployment Design

## 1. Objective

Implement a GitLab CI/CD architecture with two types of pipelines:

1. **Application pipelines**
   - Build the application.
   - Run tests.
   - Run security scans.
   - Build and push an immutable Docker image.
   - Trigger the infrastructure repository with the image information.

2. **Infrastructure pipeline**
   - Handle infrastructure repository changes normally.
   - When triggered by an application repository, deploy **only the service that triggered the pipeline**.
   - Never deploy unrelated services.
   - Promote the exact same immutable image from staging to production.

Current services:

- `inventory`
- `billing`
- `api-gateway`

---

# 2. Repository Architecture

## Application repositories

Each application has its own GitLab repository:

```text
inventory-app
billing-app
api-gateway
```

Each application repository owns:

```text
source code
tests
security scanning
Docker image
application CI
```

The application repository does **not** directly modify ECS infrastructure.

---

## Infrastructure repository

Repository:

```text
infrastructure-configuration
```

It owns:

```text
AWS infrastructure
ECS clusters
ECS services
ECS task definitions
staging deployment
production deployment
infrastructure validation
```

The infrastructure repository is the only repository responsible for deploying to ECS.

---

# 3. Artifact Strategy

Docker images must use immutable commit-based tags.

Example:

```text
docker.io/1ee5lim/inventory-app:7f83b165a4d8...
```

The application pipeline must:

1. Build the image.
2. Tag it with `$CI_COMMIT_SHA`.
3. Push that tag.
4. Pass the same SHA to the infrastructure pipeline.

Do not use `latest` for deployments.

The following pattern is prohibited:

```text
build → latest → staging
build again → latest → production
```

The required pattern is:

```text
build once
    ↓
inventory-app:<commit-sha>
    ↓
staging
    ↓
approval
    ↓
production
```

Production must use the exact artifact that was deployed to staging.

---

# 4. Application Pipeline

Each application pipeline should follow:

```text
build
  ↓
test
  ↓
security scan
  ↓
containerize
  ↓
trigger infrastructure pipeline
```

Example variables passed to the infrastructure repository:

```yaml
variables:
  APP_NAME: "inventory"
  IMAGE_NAME: "docker.io/1ee5lim/inventory-app"
  IMAGE_TAG: "$CI_COMMIT_SHA"
```

For billing:

```yaml
variables:
  APP_NAME: "billing"
  IMAGE_NAME: "docker.io/1ee5lim/billing-app"
  IMAGE_TAG: "$CI_COMMIT_SHA"
```

For API Gateway:

```yaml
variables:
  APP_NAME: "api-gateway"
  IMAGE_NAME: "docker.io/1ee5lim/api-gateway-app"
  IMAGE_TAG: "$CI_COMMIT_SHA"
```

The infrastructure pipeline must not use its own `$CI_COMMIT_SHA` as the application image tag.

Important distinction:

```text
Application CI_COMMIT_SHA
        │
        ▼
IMAGE_TAG
        │
        ▼
Infrastructure pipeline
```

The infrastructure repository's own commit SHA is unrelated to the application image version.

---

# 5. Infrastructure Pipeline Sources

The infrastructure pipeline must distinguish between different pipeline sources.

## Direct infrastructure push

```text
CI_PIPELINE_SOURCE=push
```

This represents a developer changing the infrastructure repository.

This pipeline should perform the normal infrastructure workflow.

Example:

```text
validate
  ↓
plan
  ↓
manual approval
  ↓
apply
```

It must not automatically deploy every application service merely because the infrastructure repository changed.

---

## Application-triggered pipeline

When an application repository triggers the infrastructure repository:

```text
CI_PIPELINE_SOURCE=pipeline
```

The pipeline receives:

```text
APP_NAME
IMAGE_NAME
IMAGE_TAG
```

Example:

```text
APP_NAME=inventory
IMAGE_NAME=docker.io/1ee5lim/inventory-app
IMAGE_TAG=7f83b165a4d8...
```

The pipeline must deploy only `inventory`.

It must not deploy:

```text
billing
api-gateway
```

---

# 6. Service Selection

The infrastructure pipeline must use `APP_NAME` to select the deployment target.

Supported values:

```text
inventory
billing
api-gateway
```

Unknown values must cause the pipeline to fail.

Example:

```bash
case "$APP_NAME" in
  inventory)
    # inventory deployment
    ;;

  billing)
    # billing deployment
    ;;

  api-gateway)
    # API Gateway deployment
    ;;

  *)
    echo "Unsupported APP_NAME: $APP_NAME"
    exit 1
    ;;
esac
```

Do not silently fall back to deploying all services.

---

# 7. Service Configuration

Each service should have explicit infrastructure configuration.

Example:

```text
infrastructure-configuration/
├── ecs/
│   ├── inventory/
│   │   └── task-definition.json
│   ├── billing/
│   │   └── task-definition.json
│   └── api-gateway/
│       └── task-definition.json
│
├── scripts/
│   └── deploy.sh
│
└── .gitlab-ci.yml
```

Avoid hard-coding service-specific deployment logic throughout `.gitlab-ci.yml`.

Prefer a common deployment mechanism with service-specific configuration.

---

# 8. ECS Deployment

The deployment process must update the ECS task definition with:

```text
IMAGE_NAME:IMAGE_TAG
```

For example:

```text
docker.io/1ee5lim/inventory-app:7f83b165a4d8...
```

Then:

1. Retrieve the existing task definition.
2. Replace only the appropriate container image.
3. Register a new ECS task definition revision.
4. Update the appropriate ECS service to the new revision.
5. Wait for ECS deployment stability.
6. Fail the pipeline if ECS does not become stable.

Do not rely on:

```bash
aws ecs update-service --force-new-deployment
```

alone.

`--force-new-deployment` does not change the image referenced by the task definition.

---

# 9. Staging Deployment

For an application-triggered pipeline:

```text
Application image
      ↓
Infrastructure pipeline
      ↓
Update service task definition
      ↓
Deploy staging
      ↓
Wait for stable
```

Example:

```text
inventory-app:7f83b165
        ↓
inventory-staging
```

Only the corresponding service should be changed.

---

# 10. Production Promotion

Production requires manual approval.

Required flow:

```text
deploy staging
      ↓
staging stable
      ↓
manual approval
      ↓
deploy production
```

The production deployment must use the **same `IMAGE_NAME` and `IMAGE_TAG`** received from the application pipeline.

Do not rebuild the image.

Do not generate a new tag.

Do not use `latest`.

Example:

```text
Staging:

docker.io/1ee5lim/inventory-app:7f83b165


Production:

docker.io/1ee5lim/inventory-app:7f83b165
```

---

# 11. Prevent Cross-Service Deployment

A triggered inventory pipeline must never modify:

```text
billing
api-gateway
```

A triggered billing pipeline must never modify:

```text
inventory
api-gateway
```

A triggered API Gateway pipeline must never modify:

```text
inventory
billing
```

The selected service should be derived exclusively from:

```text
APP_NAME
```

and validated against an explicit allowlist.

---

# 12. Main Infrastructure Pipeline

The infrastructure repository must also support normal infrastructure development.

When:

```text
CI_PIPELINE_SOURCE=push
```

the pipeline should run infrastructure validation.

Expected conceptual workflow:

```text
validate
   ↓
plan
   ↓
manual approval
   ↓
apply
```

Depending on the existing infrastructure tooling, validation may include:

```text
Terraform validate
Terraform plan
Ansible syntax check
Ansible lint
task-definition validation
security checks
```

Do not automatically interpret a normal infrastructure repository push as an application deployment.

---

# 13. Pipeline Rules

The infrastructure `.gitlab-ci.yml` should distinguish jobs using rules similar to:

```yaml
rules:
  - if: '$CI_PIPELINE_SOURCE == "pipeline" && $APP_NAME == "inventory"'
```

and:

```yaml
rules:
  - if: '$CI_PIPELINE_SOURCE == "pipeline" && $APP_NAME == "billing"'
```

For general infrastructure jobs:

```yaml
rules:
  - if: '$CI_PIPELINE_SOURCE == "push"'
```

Avoid duplicated jobs where a common deployment script can handle multiple services.

---

# 14. Security Requirements

Application repositories must never receive AWS credentials simply to deploy ECS.

AWS credentials should remain associated with the infrastructure deployment pipeline.

The application repository only needs permission to trigger the infrastructure pipeline.

The infrastructure pipeline receives:

```text
APP_NAME
IMAGE_NAME
IMAGE_TAG
```

Do not pass:

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_SESSION_TOKEN
```

from application repositories.

Docker Hub credentials remain in the application repository as protected CI/CD variables:

```text
DOCKERHUB_USERNAME
DOCKERHUB_TOKEN
```

---

# 15. Variable Validation

The infrastructure pipeline must validate required variables before deployment.

For application-triggered pipelines:

```text
APP_NAME
IMAGE_NAME
IMAGE_TAG
```

must exist.

Example validation:

```bash
test -n "$APP_NAME" || exit 1
test -n "$IMAGE_NAME" || exit 1
test -n "$IMAGE_TAG" || exit 1
```

Also validate that `APP_NAME` is supported.

---

# 16. Expected End-to-End Example

Developer pushes a change to `inventory-app`.

Application pipeline:

```text
inventory-app
    │
    ├── build
    ├── test
    ├── scan
    │
    └── containerize
            │
            ▼
    docker.io/1ee5lim/inventory-app:
    7f83b165a4d8...
            │
            ▼
    trigger infrastructure pipeline
```

Variables:

```text
APP_NAME=inventory
IMAGE_NAME=docker.io/1ee5lim/inventory-app
IMAGE_TAG=7f83b165a4d8...
```

Infrastructure pipeline:

```text
receive trigger
      ↓
validate variables
      ↓
select inventory
      ↓
update inventory task definition
      ↓
deploy inventory-staging
      ↓
wait for stable
      ↓
manual approval
      ↓
update/deploy inventory-production
      ↓
wait for stable
```

Billing and API Gateway remain untouched.

---

# 17. Failure Behavior

If application tests fail:

```text
Do not build/push image.
Do not trigger infrastructure.
```

If security scanning fails and the scan is configured as non-blocking:

```text
Continue according to the existing project policy.
```

If Docker push fails:

```text
Do not trigger infrastructure.
```

If infrastructure validation fails:

```text
Do not deploy.
```

If staging deployment fails:

```text
Do not allow production deployment.
```

If production deployment fails:

```text
Pipeline fails and ECS deployment status must be visible in logs.
```

---

# 18. Design Principles

The implementation should preserve these principles:

### Build once

An application image is built exactly once for a release.

### Immutable artifacts

Use:

```text
$CI_COMMIT_SHA
```

as the Docker image tag.

### Deploy the same artifact

Staging and production use the same image tag.

### Infrastructure ownership

Only the infrastructure repository deploys ECS.

### Service isolation

An application-triggered pipeline changes only that application.

### Explicit service selection

Use:

```text
APP_NAME
```

rather than guessing the service from repository names or branches.

### Least privilege

Application pipelines trigger infrastructure deployment but do not receive AWS credentials.

### Fail closed

Unknown services, missing variables, failed validation, and failed deployments must stop the pipeline.

---

# 19. Target Architecture

```text
                    ┌─────────────────────┐
                    │    inventory-app     │
                    └──────────┬──────────┘
                               │
                    IMAGE_TAG=$CI_COMMIT_SHA
                               │
                               ▼
                    ┌─────────────────────┐
                    │ infrastructure-     │
                    │ configuration       │
                    └──────────┬──────────┘
                               │
                         APP_NAME=inventory
                               │
                               ▼
                    ┌─────────────────────┐
                    │ Inventory deployment│
                    └──────────┬──────────┘
                               │
                         ECS staging
                               │
                         manual approval
                               │
                         ECS production


                    ┌─────────────────────┐
                    │     billing-app     │
                    └──────────┬──────────┘
                               │
                         APP_NAME=billing
                               │
                               ▼
                    infrastructure repo
                               │
                               ▼
                       Billing only


                    ┌─────────────────────┐
                    │    api-gateway      │
                    └──────────┬──────────┘
                               │
                       APP_NAME=api-gateway
                               │
                               ▼
                    infrastructure repo
                               │
                               ▼
                    API Gateway only
```

The infrastructure repository therefore acts as the **deployment controller**, while each application repository owns its own application lifecycle and immutable artifact.