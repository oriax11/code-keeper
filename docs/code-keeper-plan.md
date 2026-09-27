# Code-Keeper Implementation Plan

Plan for building the Code-Keeper CI/CD project on top of the existing
`cloud-design` AWS stack.

> Status: **implementation in progress** — Phases 1, 2 and 2.5 done; GitLab
> instance is live on iximiuz with the 4 projects created.
> Source of truth: `docs/code-keeper.md` (subject) and
> `docs/code-keeper-audit.md` (audit).
> Execution logs: `docs/code-keeper-phase1-log.md`, `docs/code-keeper-phase2-log.md`.

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
| Terraform IaC exists | Done — refactored to 2 symmetric envs + GitLab HTTP backend (Phase 1) |
| Staging + production environments | Terraform ready; not yet applied (needs pipeline) |
| Infra repo + pipeline (Init/Validate/Plan/Apply Staging/Approval/Apply Prod) | Repo done; **pipeline pending (Phase 4)** |
| CI per app (Build/Test/Scan/Containerization) | Pipeline files written; **not yet run on GitLab (Phase 5)** |
| CD per app (Deploy Staging/Approval/Deploy Prod) | Pipeline files written; **not yet run on GitLab (Phase 6)** |
| Each app in its own repo | Done — 4 GitLab projects in `core-keeper` group (Phase 2) |
| GitLab + runners via Ansible | GitLab live; Ansible moved into infra repo (Phase 7 — verify evidence) |
| Tests | Done — 18 pytest tests, all passing (Phase 2 / 3) |
| Security (protected branches, creds off code, least privilege, updates) | Partial — **Phase 8** |
| README | Pending — **Phase 9** |

---

## 2. Locked decisions

| # | Area | Decision |
|---|---|---|
| 1 | Environments | **Full symmetric** staging + production (same design/resources/services), ~$140 / 15 days |
| 2 | Terraform state | **GitLab-managed HTTP backend** |
| 3 | AWS auth from runner | **GitLab OIDC → assume IAM role** (no long-lived keys) |
| 4 | DB/queue images | **Keep `oriax11/*`**, document the 17 CRITICAL / 94 HIGH finding |
| 5 | Existing stack | Already destroyed → **recreate both envs clean** |
| 6 | GitLab host | **iximiuz Labs**: 10 GB RAM / 800 GB disk, persistent — **live** at `https://6ab7e5f2330452d9e06766c5-36e164.node-eu-d241.iximiuz.com` |
| 7 | Ansible location | **inside the infra repo** (`infrastructure-configuration/ansible/`) |
| 8 | Repos | **4 repos**, named exactly as the existing GitLab projects (see §3) |
| 9 | GitLab group | **`core-keeper`** (path), display name "Code Keeper" |
| 10 | Trivy scan gate | **`allow_failure: true` + report** (we knowingly keep vulnerable DB images); filesystem scan runs with `--exit-code 1` for HIGH/CRITICAL, image scan reports only |
| 11 | Protected branch | **`main`** — push: no one (0), merge: Maintainer (40), no force-push |
| 12 | Umbrella remotes | `origin` = `https://learn.zone01oujda.ma/git/yaouzddou/code-keeper.git` (submission); `github` = `oriax11/code-keeper` |

---

## 3. Repository topology (matches GitLab reality)

GitLab: `https://6ab7e5f2330452d9e06766c5-36e164.node-eu-d241.iximiuz.com/core-keeper`

```
code-keeper/                (umbrella — learn.zone01oujda.ma remote)
├── docs/                   subject + audit + plan + phase logs
├── cloud-design/           frozen reference (old single-env stack)
├── README.md               Code-Keeper overview + links to the 4 repos
└── submodules:             (SSH URLs → core-keeper/*)
    ├── inventory-app/
    ├── billing-app/
    ├── api-gateway/
    └── infrastructure-configuration/

infrastructure-configuration/     (sibling working copy — GitLab: core-keeper/infrastructure-configuration)
├── terraform/              environment-aware, GitLab HTTP backend
│   ├── environments/       staging.tfvars.example / production.tfvars.example
│   └── modules/{vpc,security,efs,alb,ecs}
├── docker/                 platform images (postgres, rabbit) — kept as-is
├── ansible/                GitLab CE + runner roles  ← headline deliverable
│   ├── gitlab.yml          playbook (hosts: gitlab, gitlab_runner)
│   ├── inventory/hosts.yml gitlab-01, runner-01
│   ├── group_vars/all/     gitlab.yml (config) + vault.yml (encrypted)
│   └── roles/{gitlab,gitlab_runner}/
├── scripts/
├── .gitlab-ci.yml          infra pipeline (+ optional tfsec/Infracost)  ← Phase 4
└── README.md

inventory-app/              sibling working copy — GitLab: core-keeper/inventory-app
billing-app/                sibling working copy — GitLab: core-keeper/billing-app
api-gateway/                sibling working copy — GitLab: core-keeper/api-gateway
```

Notes:

- **Local sibling directories** (`/home/aesslima/<repo>`) are the canonical
  working copies; the umbrella holds them as **submodules** with the GitLab
  SSH URLs.
- The three **applications** per the subject are inventory, billing and
  api-gateway → one repo each. GitLab project name for the gateway is
  `api-gateway` (not `api-gateway-app`).
- `inventory-db`, `billing-db` and `rabbit-queue` Dockerfiles live in
  `infrastructure-configuration/docker/` (they are dependencies, not apps).
- After the split, `code-keeper/cloud-design/` is frozen as reference.

---

## 4. Pipeline designs

### Infrastructure pipeline (`infrastructure-configuration`)

`Init` → `Validate` → `Plan` → `Apply to Staging` → **`Approval`** (manual,
protected) → `Apply to Production`.

- Separate state per environment (GitLab HTTP backend, per-env state name).
- `resource_group` to serialize applies.
- Optional bonus jobs: `tfsec`, `Infracost`.

### App CI (per app repo)

`Build` → `Test` (pytest) → `Scan` (Trivy, allow_failure per decision #10) →
`Containerization` (push `<app>:<sha>` + `staging`/`production` tags).

- Runs on every push / merge request.
- Registry push restricted to protected branches.

### App CD (per app repo)

`Deploy to Staging` → **`Approval`** (manual, protected) → `Deploy to
Production`.

- CD mechanism: CI pushes an immutable tag → task-definition image updated →
  `aws ecs update-service --force-new-deployment` → wait for stable.
- Zero downtime via ECS rolling deployment + deployment circuit breaker.
- **Target names must match Terraform** (verified Phase 2.5):
  - cluster: `${env}-cluster`
  - services: `${env}-inventory-service`, `${env}-billing-service`,
    `${env}-api-gateway-service`
  - (infra outputs: `cluster_name`, `inventory_service_name`,
    `billing_service_name`, `api_gateway_service_name`)

---

## 5. Ansible on iximiuz

Host: iximiuz Labs, 10 GB RAM / 800 GB disk, persistent.
**Live external URL:** `https://6ab7e5f2330452d9e06766c5-36e164.node-eu-d241.iximiuz.com`
(was previously `…node-eu-10a1…` — group_vars updated in Phase 2.5).

- Runs **GitLab + runner on the same host** (10 GB is comfortable).
- Playbook `ansible/gitlab.yml`:
  - Role `gitlab`: install GitLab EE/CE omnibus, `external_url`, create root
    API tokens, users, group **`core-keeper`**, the 4 projects, project
    members, protected branch `main`.
  - Role `gitlab-runner`: Docker CE + gitlab-runner, docker executor,
    registers **one locked project runner per repo** (tags: `code-keeper`,
    `docker`).
- Audit evidence: `ansible-playbook --list-tasks`, `systemctl status
  gitlab-ruby` / `gitlab-runner`.

---

## 6. Phase-by-phase build plan

| Phase | Scope | Status |
|---|---|---|
| 1 | Terraform two-environment refactor (env var, `${env}-` names, GitLab HTTP backend) | ✅ Done |
| 2 | Split repositories — 4 repos with source, Dockerfiles, tests, CI/CD files, READMEs | ✅ Done |
| 2.5 | **Repo reconciliation** — match GitLab reality (group `core-keeper`, repo names), rebuild infra as standalone repo, move Ansible into it, 4 submodules in umbrella, restore umbrella origin, fix CD service names, fix ansible `external_url` | ✅ Done |
| 3 | Tests — pytest suites per app | ✅ Done (in Phase 2) — 18 tests passing |
| 4 | Infrastructure pipeline (`.gitlab-ci.yml`: Init/Validate/Plan/Apply Staging/Approval/Apply Prod) | ⬜ Pending |
| 5 | CI pipeline per app — run Build/Test/Scan/Containerization **on GitLab** | ⬜ Pending (files exist) |
| 6 | CD pipeline per app — Deploy Staging/Approval/Deploy Prod **on GitLab** | ⬜ Pending (files exist) |
| 7 | Ansible: GitLab + runners — GitLab is live; re-verify playbook matches current instance, collect `--list-tasks` evidence | 🔶 Partially done — verify |
| 8 | Security hardening — AWS OIDC role + masked CI vars, least-privilege IAM, dependency updates | ⬜ Pending |
| 9 | Documentation & audit prep — umbrella README, role-play prep, evidence collection | ⬜ Pending |

---

## 7. Audit-checklist mapping

| Audit item | Delivered by |
|---|---|
| Files present (pipelines, Ansible, README) | Phases 2, 4–7, 9 |
| GitLab + runners deployed via Ansible | Phase 7 (verify + evidence) |
| Infra pipeline stages correct | Phase 4 |
| CI Build/Test/Scan/Containerization per repo | Phases 5 + 3 |
| CD Staging/Approval/Production per repo | Phase 6 |
| Pipelines actually update app + infra | Phases 4–6 (live demo) |
| Protected branches / creds / least privilege / updates | Phases 2 (branch) + 8 |
| README complete with diagrams | Phase 9 |
| Bonus (tfsec, Infracost, Terragrunt, own crud-master) | optional in Phases 4 / 1 |

---

## 8. Open items

1. **SSH access to GitLab** — local public key
   (`ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIItsSkXKowosv8+Qicayd0G1Y8PGt9D4CJIzz0zWgZkS aesslima@talentMachine`)
   must be added in GitLab (User Settings → SSH Keys), then push the 4 repos
   and the umbrella. Until then the submodules are local-only.
2. **Dependency updates** — include Dependabot/Renovate or a manual
   documented process (audit: "update dependencies and tools regularly").
3. **AWS OIDC design** — GitLab OIDC provider in AWS, IAM role
   (`AWS_ROLE_ARN` CI variable) — details land in Phase 8.
4. **Phase 7 verification** — confirm the live GitLab matches the playbook
   (it was created from an earlier revision) and capture audit evidence.
