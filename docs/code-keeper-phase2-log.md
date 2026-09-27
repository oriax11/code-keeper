# Code-Keeper: Phase 2 Implementation & Execution Log

**Log Date:** 2026-09-27  
**Project:** Code-Keeper  
**Phase:** Phase 2 — Split Repositories (`code-keeper-infra`, `inventory-app`, `billing-app`, `api-gateway-app`)  
**Status:** Completed

---

## 1. Overview & Objective

The objective of Phase 2 is to split the monolithic `cloud-design` repository into **four independent repositories** as required by the subject:
- `code-keeper-infra` — Terraform infrastructure (already created in Phase 1)
- `inventory-app` — Inventory microservice
- `billing-app` — Billing microservice  
- `api-gateway-app` — API Gateway microservice

Each application must exist in a single repository with its own CI/CD pipeline, Dockerfile, tests, and documentation.

---

## 2. Detailed Execution Log

### Step 2.1: Create Repository Directories
- **Action:** Created three new top-level directories alongside `code-keeper/`:
  - `/home/aesslima/inventory-app/`
  - `/home/aesslima/billing-app/`
  - `/home/aesslima/api-gateway-app/`
- **Explanation:** These will become independent Git repositories. The existing `code-keeper-infra/` (created in Phase 1) completes the set of four.

### Step 2.2: Copy Application Source Code
- **Action:** Copied source from `cloud-design/srcs/<app>/` to each new repo:
  - `inventory-app/` ← `cloud-design/srcs/inventory-app/`
  - `billing-app/` ← `cloud-design/srcs/billing-app/`
  - `api-gateway-app/` ← `cloud-design/srcs/api-gateway-app/`
- **Explanation:** Preserves all application logic (Flask routes, SQLAlchemy models, Cognito JWT auth, RabbitMQ consumer/producer, proxy logic).

### Step 2.3: Copy Dockerfiles
- **Action:** Copied Dockerfiles from `cloud-design/docker/<app>/Dockerfile` to each repo root.
- **Explanation:** Each app now owns its containerization definition. All three use `python:3.12-alpine` base, install requirements, copy source, and run via `waitress`.

### Step 2.4: Add Development Dependencies (`requirements-dev.txt`)
- **Action:** Created `requirements-dev.txt` per repo with test tooling:
  - **inventory-app / api-gateway-app:** `pytest`, `pytest-flask`, `responses`, `coverage`
  - **billing-app:** `pytest`, `pytest-mock`, `responses`, `coverage`
- **Explanation:** Enables `Test` stage in CI pipelines. `pytest-flask` provides Flask test client; `responses` mocks HTTP; `pytest-mock` for billing consumer tests.

### Step 2.5: Create Test Suites
- **Action:** Created `tests/` directory with `conftest.py` + test modules:

| Repo | Test File | Coverage |
|------|-----------|----------|
| inventory-app | `test_movies.py` | 9 tests: CRUD, filtering, error cases |
| billing-app | `test_orders.py` | 3 tests: order creation, model, multiple orders |
| api-gateway-app | `test_gateway.py` | 6 tests: root health, auth enforcement, token validation, OPTIONS |

- **Explanation:** All tests use in-memory SQLite (inventory/billing) or mocked dependencies (gateway). No external services required.

### Step 2.6: Verify Tests Pass
- **Action:** Created virtual environments, installed deps, ran pytest.
- **Results:**
  - `inventory-app`: **9 passed** (0.06s)
  - `billing-app`: **3 passed** (0.02s)
  - `api-gateway-app`: **6 passed** (0.03s)
- **Explanation:** All test suites pass locally, confirming the test infrastructure works before CI integration.

### Step 2.7: Create CI/CD Pipelines (`.gitlab-ci.yml`)
- **Action:** Created identical 7-stage pipeline for each app repo:

```yaml
stages:
  - build        # Syntax check (python -m py_compile)
  - test         # pytest with coverage
  - scan         # Trivy fs + image scan (HIGH/CRITICAL, allow_failure)
  - containerize # Docker build, tag (SHA + staging), push to registry
  - deploy-staging  # aws ecs update-service --force-new-deployment + wait stable
  - approval        # Manual gate (when: manual, protected environment)
  - deploy-production # Same as staging but on prod cluster
```

- **Key features:**
  - `rules:` restrict containerize/deploy to `main` branch only
  - `environment:` blocks define staging/production for GitLab UI
  - `allow_failure: true` on scan (DB images have known vulnerabilities)
  - Variables parameterize ECS cluster/service names per environment

### Step 2.8: Create Documentation (`README.md`)
- **Action:** Wrote comprehensive README per repo covering:
  - Architecture diagram (text-based)
  - Endpoint table with auth requirements
  - Environment variable reference
  - Local development instructions
  - Docker build/run commands
  - CI/CD pipeline stage descriptions

### Step 2.9: Create `.gitignore`
- **Action:** Standard Python/Docker/IDE ignores + `.venv/` exclusion.

### Step 2.10: Initialize Git Repositories
- **Action:** Initialized git repos in all four directories, created initial commits on `main` branch:
  - `inventory-app`: commit `2ec1632` — 12 files, 592 insertions
  - `billing-app`: commit `79e995a` — 11 files, 444 insertions
  - `api-gateway-app`: commit `cd995b5` — 13 files, 617 insertions
  - `code-keeper-infra`: commit `ead9e31` — 46 files, 3743 insertions
- **Action:** Updated `code-keeper-infra/.gitignore` to exclude `.terraform/`, `*.tfstate`, `*.tfplan`, `*.tfvars` (except `.example`)
- **Explanation:** Each repo is now a proper Git repository ready for GitLab push when the instance is deployed (Phase 7).

### Step 2.11: Move Ansible to infra repo & Update Repo Names
- **Action:** Copied `code-keeper/ansible/` → `code-keeper-infra/ansible/`
- **Action:** Updated `code-keeper-infra/ansible/group_vars/all/gitlab.yml`:
  - Repo names: `api-gateway-app` (was `api-gateway`), `code-keeper-infra` (was `infrastructure-configuration`)
  - Group path: `code-keeper` (was `core-keeper`)
- **Explanation:** Aligns Ansible with the actual 4 repo names and group structure.

### Step 2.12: Configure Git Remotes (iximiuz GitLab)
- **Action:** Added GitLab remote `origin` to all 4 repos:
  - `inventory-app` → `https://6ab7e5f2330452d9e06766c5-36e164.node-eu-d241.iximiuz.com/code-keeper/inventory-app.git`
  - `billing-app` → `https://6ab7e5f2330452d9e06766c5-36e164.node-eu-d241.iximiuz.com/code-keeper/billing-app.git`
  - `api-gateway-app` → `https://6ab7e5f2330452d9e06766c5-36e164.node-eu-d241.iximiuz.com/code-keeper/api-gateway-app.git`
  - `code-keeper-infra` → `https://6ab7e5f2330452d9e06766c5-36e164.node-eu-d241.iximiuz.com/code-keeper/code-keeper-infra.git`

### Step 2.13: Add Submodules to Umbrella Repo
- **Action:** Added 3 app submodules to `code-keeper/` with GitLab URLs:
  - `.gitmodules` entries for `inventory-app`, `billing-app`, `api-gateway-app`
  - Submodules cloned locally from source directories for development
- **Note:** `code-keeper-infra` is already a subdirectory of `code-keeper/`, not a submodule.
- **Explanation:** Umbrella repo tracks all components; submodules will pull from GitLab after Phase 7 deploys the instance.

---

## 3. Repository Structures (Final)

### inventory-app/
```
inventory-app/
├── .gitignore
├── .gitlab-ci.yml
├── Dockerfile
├── README.md
├── requirements.txt
├── requirements-dev.txt
├── server.py
├── app/
│   ├── __init__.py
│   ├── extensions.py
│   └── movies.py
└── tests/
    ├── conftest.py
    └── test_movies.py
```
Remote: `https://6ab7e5f2330452d9e06766c5-36e164.node-eu-d241.iximiuz.com/code-keeper/inventory-app.git`
Submodule in `code-keeper/inventory-app/`

### billing-app/
```
billing-app/
├── .gitignore
├── .gitlab-ci.yml
├── Dockerfile
├── README.md
├── requirements.txt
├── requirements-dev.txt
├── server.py
├── app/
│   ├── consume_queue.py
│   └── orders.py
└── tests/
    ├── conftest.py
    └── test_orders.py
```
Remote: `https://6ab7e5f2330452d9e06766c5-36e164.node-eu-d241.iximiuz.com/code-keeper/billing-app.git`
Submodule in `code-keeper/billing-app/`

### api-gateway-app/
```
api-gateway-app/
├── .gitignore
├── .gitlab-ci.yml
├── Dockerfile
├── README.md
├── requirements.txt
├── requirements-dev.txt
├── server.py
├── app/
│   ├── __init__.py
│   ├── auth.py
│   ├── proxy.py
│   └── queue_sender.py
└── tests/
    ├── conftest.py
    └── test_gateway.py
```
Remote: `https://6ab7e5f2330452d9e06766c5-36e164.node-eu-d241.iximiuz.com/code-keeper/api-gateway-app.git`
Submodule in `code-keeper/api-gateway-app/`

### code-keeper-infra/ (from Phase 1)
```
code-keeper-infra/
├── .gitignore
├── README.md
├── ansible/          # ← MOVED HERE (GitLab + runner deployment)
│   ├── gitlab.yml
│   ├── inventory/hosts.yml
│   ├── group_vars/all/gitlab.yml
│   ├── group_vars/all/vault.yml
│   └── roles/{gitlab,gitlab_runner}/
├── docker/
│   ├── billing-db/
│   ├── inventory-db/
│   └── rabbit-queue/
├── scripts/
└── terraform/
    ├── backend.tf
    ├── provider.tf
    ├── variables.tf
    ├── main.tf
    ├── budget.tf
    ├── outputs.tf
    ├── environments/
    │   ├── staging.tfvars.example
    │   └── production.tfvars.example
    └── modules/{vpc,security,efs,alb,ecs}/
```
Remote: `https://6ab7e5f2330452d9e06766c5-36e164.node-eu-d241.iximiuz.com/code-keeper/code-keeper-infra.git`
Directory at `code-keeper/code-keeper-infra/`

---

## 4. Exit Criteria Verification

| Check | Requirement | Result | Status |
|-------|-------------|--------|--------|
| 1 | Four independent repos exist | `code-keeper-infra`, `inventory-app`, `billing-app`, `api-gateway-app` | **PASSED** |
| 2 | Each app in single repo | Source, Dockerfile, tests, CI/CD, README all present | **PASSED** |
| 3 | Tests exist and pass | 9 + 3 + 6 = 18 tests, all passing locally | **PASSED** |
| 4 | CI/CD pipeline per repo | 7-stage `.gitlab-ci.yml` in each app repo | **PASSED** |
| 5 | Dockerfile per app | Copied from cloud-design, at repo root | **PASSED** |
| 6 | Documentation per repo | README.md with architecture, endpoints, env vars, local dev, CI/CD | **PASSED** |
| 7 | No hardcoded references to old paths | All imports use local package structure | **PASSED** |
| 8 | Git repos initialized | 4 repos, initial commits on `main` branch | **PASSED** |
| 9 | Ansible in infra repo | `code-keeper-infra/ansible/` with updated repo names | **PASSED** |
| 10 | GitLab remotes configured | All 4 repos point to iximiuz GitLab URLs | **PASSED** |
| 11 | Submodules in umbrella | 3 app submodules in `code-keeper/` | **PASSED** |

---

## 5. Phase 2 Sign-Off

Phase 2 has been completed successfully. All four repositories are structured, tested, and pipeline-ready.

**Next:** Phase 3 — Add integration tests (optional) → Phase 4 — Infrastructure Pipeline in `code-keeper-infra/.gitlab-ci.yml`.
