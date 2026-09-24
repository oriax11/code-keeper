# Code-Keeper Implementation Plan

Plan for building the Code-Keeper CI/CD project on top of the existing
`cloud-design` AWS stack.

> Status: planning. No implementation started.
> Source of truth: `docs/code-keeper.md` (subject) and
> `docs/code-keeper-audit.md` (audit).

---

## 1. Context

`cloud-design/` is a complete, deployed AWS stack: VPC (2 AZs), ECS Fargate
(6 services / 9 tasks), ALB + self-signed ACM certificate, Cognito JWT,
Secrets Manager, EFS, CloudWatch, autoscaling and an AWS Budget. Terraform is
modular (`modules/{vpc,security,efs,alb,ecs}`), but **single-environment** and
uses **local state**. Images are published to Docker Hub (`1ee5lim/*`,
`oriax11/*`).

Code-Keeper requires the CI/CD layer on top of that: a second environment,
an independent infrastructure repository with a pipeline, per-application
CI/CD repositories, and a GitLab instance + runners deployed with Ansible.

### Current vs required

| Code-Keeper requirement | Status today |
|---|---|
| App runs on AWS infra | Done |
| Terraform IaC exists | Done, but single env, local state |
| Staging + production environments | Missing |
| Infra repo + pipeline (Init/Validate/Plan/Apply Staging/Approval/Apply Prod) | Missing |
| CI per app (Build/Test/Scan/Containerization) | Missing |
| CD per app (Deploy Staging/Approval/Deploy Prod) | Missing |
| Each app in its own repo | Missing (all source in one repo) |
| GitLab + runners via Ansible | Missing |
| Tests | Missing (no test files exist) |
| Security (protected branches, creds off code, least privilege, updates) | Partial |
| README | cloud-design README only |

---

## 2. Locked decisions

| # | Area | Decision |
|---|---|---|
| 1 | Environments | **Full symmetric** staging + production (same design/resources/services), ~$140 / 15 days |
| 2 | Terraform state | **GitLab-managed HTTP backend** |
| 3 | AWS auth from runner | **GitLab OIDC → assume IAM role** (no long-lived keys) |
| 4 | DB/queue images | **Keep `oriax11/*`**, document the 17 CRITICAL / 94 HIGH finding |
| 5 | Existing stack | Already destroyed → **recreate both envs clean** |
| 6 | GitLab host | **iximiuz Labs**: 10 GB RAM, 800 GB disk, persistent (inbound port TBD) |
| 7 | Ansible location | **inside `code-keeper-infra`** |
| 8 | Repos | Split into **4 new repos** (infra + 3 apps) |

---

## 3. Repository topology

```
code-keeper/                (umbrella — existing remote)
├── docs/                   subject + audit + this plan
├── cloud-design/           frozen reference (old single-env stack)
└── README.md               Code-Keeper overview + links to the 4 repos

code-keeper-infra/          (new)
├── terraform/              environment-aware
│   ├── backend.tf          GitLab HTTP backend
│   ├── provider.tf
│   ├── variables.tf        + environment
│   ├── main.tf             modules wired; names use "${var.environment}"
│   ├── environments/
│   │   ├── staging.tfvars.example
│   │   └── production.tfvars.example
│   └── modules/{vpc,security,efs,alb,ecs}
├── docker/                 platform images (postgres, rabbit) — kept as-is
├── ansible/                GitLab CE + runner roles  ← headline deliverable
│   ├── site.yml
│   ├── inventory.ini
│   └── roles/{gitlab,gitlab-runner}
├── scripts/
├── .gitlab-ci.yml          infra pipeline (+ optional tfsec/Infracost)
└── README.md

inventory-app/              (new) source + Dockerfile + tests + CI/CD
billing-app/                (new) source + Dockerfile + tests + CI/CD
api-gateway-app/            (new) source + Dockerfile + tests + CI/CD
```

Notes:

- The three **applications** per the subject are inventory, billing and
  api-gateway → one repo each.
- `inventory-db`, `billing-db` and `rabbit-queue` are dependencies/broker, not
  "applications"; their Dockerfiles stay in `code-keeper-infra/docker/`.
- After the split, `code-keeper/cloud-design/` is frozen as reference.

---

## 4. Pipeline designs

### Infrastructure pipeline (`code-keeper-infra`)

`Init` → `Validate` → `Plan` → `Apply to Staging` → **`Approval`** (manual,
protected) → `Apply to Production`.

- Separate state per environment (GitLab HTTP backend).
- `resource_group` to serialize applies.
- Optional bonus jobs: `tfsec`, `Infracost`.

### App CI (per app repo)

`Build` → `Test` (pytest) → `Scan` (Trivy) → `Containerization`
(push `<app>:<sha>` + `staging`/`production` tags).

- Runs on every push / merge request.
- Registry push restricted to protected branches.

### App CD (per app repo)

`Deploy to Staging` → **`Approval`** (manual, protected) → `Deploy to
Production`.

- CD mechanism: CI pushes an immutable tag → task-definition image updated →
  `aws ecs update-service --force-new-deployment` → wait for stable.
- Zero downtime via ECS rolling deployment + deployment circuit breaker.
- Satisfies: any source change rebuilds and redeploys to staging, then to
  production after manual approval.

---

## 5. Ansible on iximiuz

Host: iximiuz Labs, 10 GB RAM / 800 GB disk, persistent. Inbound port TBD.

- Run **GitLab + runner on the same host** (10 GB is comfortable).
- Role `gitlab`: install GitLab CE omnibus, set `external_url` + port,
  configure settings, create groups/projects (`code-keeper-infra`,
  `inventory-app`, `billing-app`, `api-gateway-app`), enable container
  registry, configure protected branches.
- Role `gitlab-runner`: install runner, docker executor, register with a
  runner token, configure concurrent jobs.
- Audit evidence: `ansible-playbook --list-tasks`, `systemctl status
  gitlab-ruby` / `gitlab-runner`.

---

## 6. Phase-by-phase build plan

### Phase 1 — Terraform two-environment refactor (`code-keeper-infra`)

Add an `environment` variable, rename resources to `${var.environment}-*`,
split env config into `staging.tfvars` / `production.tfvars`, and configure the
GitLab HTTP remote backend.

### Phase 2 — Split repositories

Create `code-keeper-infra`, `inventory-app`, `billing-app`,
`api-gateway-app`. Move source + Dockerfiles + Terraform accordingly.

### Phase 3 — Tests

Add pytest suites per app (gateway auth/proxy/queue, inventory CRUD, billing
consumer) plus a light integration test.

### Phase 4 — Infrastructure pipeline

`.gitlab-ci.yml` with the six stages, per-env state, `resource_group`
serialization, manual protected approval; optional tfsec/Infracost.

### Phase 5 — CI pipeline per app

Build → Test → Scan → Containerization, triggered on push/MR, pushes
restricted to protected branches.

### Phase 6 — CD pipeline per app

Deploy to Staging → Approval → Deploy to Production via ECS rolling
deployment.

### Phase 7 — Ansible: GitLab + runners

Deploy GitLab CE and a runner to the iximiuz host; configure projects,
registry and protected branches.

### Phase 8 — Security hardening

Protected branches + protected/masked CI variables; least-privilege deployer
IAM scoped per env; GitLab OIDC → IAM role; dependency update automation.

### Phase 9 — Documentation & audit prep

Code-Keeper `README.md` (architecture diagrams, pipeline design, setup, usage)
and role-play prep for the audit questions; collect pipeline/Ansible/Terraform
evidence.

---

## 7. Audit-checklist mapping

| Audit item | Delivered by |
|---|---|
| Files present (pipelines, Ansible, README) | Phases 2, 4–7, 9 |
| GitLab + runners deployed via Ansible | Phase 7 |
| Infra pipeline stages correct | Phase 4 |
| CI Build/Test/Scan/Containerization per repo | Phases 5 + 3 |
| CD Staging/Approval/Production per repo | Phase 6 |
| Pipelines actually update app + infra | Phases 4–6 (live demo) |
| Protected branches / creds / least privilege / updates | Phase 8 |
| README complete with diagrams | Phase 9 |
| Bonus (tfsec, Infracost, Terragrunt, own crud-master) | optional in Phases 4 / 1 |

---

## 8. Open items

1. **iximiuz inbound port** — to be supplied; needed for `external_url` and
   runner/web reachability. Interim testing via SSH tunnel.
2. **Trivy gate policy** — fail the pipeline on findings, or `allow_failure`
   + report (we are knowingly keeping vulnerable DB images).
3. **Dependency updates** — include Dependabot/Renovate or skip.
4. **Protected branch names** on the GitLab instance (`main` + env/tag refs).
