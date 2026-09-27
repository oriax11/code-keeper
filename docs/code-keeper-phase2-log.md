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

### Step 2.11: Move Ansible to infra repo & Align Repo Names
- **Action:** Copied `code-keeper/ansible/` → infra repo (as `code-keeper-infra/` at the time).
- **Action:** Edited `group_vars/all/gitlab.yml` repo names/group — **as first done this diverged from the live GitLab group path** (`core-keeper`); corrected in Phase 2.5.
- **Explanation:** Goal: align Ansible with the 4 repos. Final canonical result lives in `infrastructure-configuration/ansible/` (see Phase 2.5).

### Step 2.12: Configure Git Remotes (iximiuz GitLab)
- **Action:** Added `origin` remotes to the app repos. First attempt used HTTPS URLs under a `code-keeper` group — **wrong scheme and group**. Final remotes (corrected in Phase 2.5) are SSH:
  - `inventory-app` → `git@6ab7e5f2330452d9e06766c5-36e164.node-eu-d241.iximiuz.com:core-keeper/inventory-app.git`
  - `billing-app` → `git@6ab7e5f2330452d9e06766c5-36e164.node-eu-d241.iximiuz.com:core-keeper/billing-app.git`
  - `api-gateway` → `git@6ab7e5f2330452d9e06766c5-36e164.node-eu-d241.iximiuz.com:core-keeper/api-gateway.git`
  - `infrastructure-configuration` → `git@6ab7e5f2330452d9e06766c5-36e164.node-eu-d241.iximiuz.com:core-keeper/infrastructure-configuration.git`

### Step 2.13: Add Submodules to Umbrella Repo
- **Action:** Added submodules to `code-keeper/`. The first attempt (HTTPS URLs, path mismatch `api-gateway-app` vs `api-gateway`, no gitlinks) was broken; **rebuilt correctly in Phase 2.5** — 4 submodules with SSH GitLab URLs and registered gitlinks.
- **Explanation:** Umbrella repo tracks all components as submodules under the `core-keeper` group.

---

## 3. Repository Structures (Final — after Phase 2.5 reconciliation)

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
Remote: `git@…iximiuz.com:core-keeper/inventory-app.git`
Working copy: `/home/aesslima/inventory-app/` · Submodule: `code-keeper/inventory-app/`

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
Remote: `git@…iximiuz.com:core-keeper/billing-app.git`
Working copy: `/home/aesslima/billing-app/` · Submodule: `code-keeper/billing-app/`

### api-gateway/
```
api-gateway/
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
Remote: `git@…iximiuz.com:core-keeper/api-gateway.git`
Working copy: `/home/aesslima/api-gateway/` · Submodule: `code-keeper/api-gateway/`

### infrastructure-configuration/
```
infrastructure-configuration/
├── .gitignore
├── README.md
├── ansible/                # ← GitLab + runner deployment (decision #7)
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
    ├── backend.tf          # GitLab HTTP backend
    ├── provider.tf
    ├── variables.tf        # + environment
    ├── main.tf
    ├── budget.tf
    ├── outputs.tf
    ├── environments/
    │   ├── staging.tfvars.example
    │   └── production.tfvars.example
    └── modules/{vpc,security,efs,alb,ecs}/
```
Remote: `git@…iximiuz.com:core-keeper/infrastructure-configuration.git`
Working copy: `/home/aesslima/infrastructure-configuration/` · Submodule: `code-keeper/infrastructure-configuration/`

---

## 4. Exit Criteria Verification (as corrected by Phase 2.5)

| Check | Requirement | Result | Status |
|-------|-------------|--------|--------|
| 1 | Four independent repos exist | `infrastructure-configuration`, `inventory-app`, `billing-app`, `api-gateway` | **PASSED** |
| 2 | Each app in single repo | Source, Dockerfile, tests, CI/CD, README all present | **PASSED** |
| 3 | Tests exist and pass | 9 + 3 + 6 = 18 tests, all passing locally | **PASSED** |
| 4 | CI/CD pipeline per repo | 7-stage `.gitlab-ci.yml` in each app repo (service names corrected in 2.5.3) | **PASSED** |
| 5 | Dockerfile per app | Copied from cloud-design, at repo root | **PASSED** |
| 6 | Documentation per repo | README.md with architecture, endpoints, env vars, local dev, CI/CD | **PASSED** |
| 7 | No hardcoded references to old paths | All imports use local package structure | **PASSED** |
| 8 | Git repos initialized | 4 repos, commits on `main` branch | **PASSED** |
| 9 | Ansible in infra repo | `infrastructure-configuration/ansible/`, names/URL match live GitLab | **PASSED** (Phase 2.5) |
| 10 | GitLab remotes configured | 4 repos → `git@…:core-keeper/<repo>.git` SSH URLs | **PASSED** (Phase 2.5) |
| 11 | Submodules in umbrella | 4 submodules (3 apps + infra) with SSH URLs, gitlinks registered | **PASSED** (Phase 2.5) |
| 12 | Umbrella origin restored | `learn.zone01oujda.ma/git/yaouzddou/code-keeper.git` | **PASSED** (Phase 2.5) |
| 13 | Push to GitLab | Blocked — local SSH key not registered (plan open item #1) | **PENDING USER** |

---

## 5. Phase 2.5 — Repo Reconciliation (post-review fix)

**Log Date:** 2026-09-27
**Trigger:** Plan review found that Phase 2's exit criteria were recorded as
passing while the working tree and GitLab reality did not match.

### Mistakes found (Phase 2 as first executed)

| # | Mistake | Impact |
|---|---------|--------|
| 1 | Repo names diverged from the **already-created GitLab projects** (group `core-keeper`, projects `infrastructure-configuration`, `api-gateway`) | Remotes and `.gitmodules` pointed at non-existent paths (`code-keeper` group, `api-gateway-app`, HTTPS scheme) |
| 2 | Umbrella `origin` clobbered — pointed at `…/code-keeper/code-keeper-infra.git` instead of the `learn.zone01oujda.ma` submission remote | Would have pushed the umbrella to the wrong repo |
| 3 | `code-keeper-infra/` working tree destroyed during submodule fumbling; two broken replacements created (` infrastructure-configuration` with a leading space, and `infrastructure-configuration` containing the **old pre-refactor** Terraform) | Risk of losing the Phase 1 refactor; wrong Terraform could have been committed |
| 4 | `.gitmodules` declared path `api-gateway-app` while the directory was `api-gateway`; submodules never registered as gitlinks (`git submodule status` empty) | Umbrella could not clone its own submodules |
| 5 | CD pipelines hardcoded wrong ECS service names (`staging-inventory-app-service` vs actual `staging-inventory-service`, same for billing + api-gateway) | **All three CD deploys would fail** with *service not found* |
| 6 | Ansible `external_url` still pointed at the old host `…node-eu-10a1…` while GitLab now lives at `…node-eu-d241…` | Re-running the playbook would misconfigure GitLab |
| 7 | Duplicate repos (sibling dirs **and** local clones inside the umbrella) with no declared source of truth | Ambiguity about where commits belong |

### Remediation actions

#### Step 2.5.1: Rebuild the infrastructure repo (canonical)
- **Action:** Extracted the Phase 1 refactored tree from umbrella git history
  (`git archive 893fda6` — verified identical to the surviving copy, 46 files)
  into `/home/aesslima/infrastructure-configuration/`.
- **Action:** Moved `code-keeper/ansible/` →
  `infrastructure-configuration/ansible/` (plan decision #7).
- **Action:** `git init --initial-branch=main`, initial commit `a8fc881`
  (57 files: terraform + docker + scripts + ansible + README + .gitignore).
- **Action:** Remote set to
  `git@6ab7e5f2…iximiuz.com:core-keeper/infrastructure-configuration.git`.
- **Explanation:** The old `code-keeper-infra` in-tree copy was removed from
  the umbrella index (still in history); content now lives once, as the
  standalone repo GitLab already expects.

#### Step 2.5.2: Match local repo names to GitLab
- **Action:** Renamed `/home/aesslima/api-gateway-app` →
  `/home/aesslima/api-gateway` (GitLab project is `api-gateway`).
- **Action:** Confirmed `inventory-app`, `billing-app` remotes →
  `core-keeper/*` SSH URLs (set earlier the same day).

#### Step 2.5.3: Fix CD service names in the 3 app pipelines
- **Action:** Corrected `.gitlab-ci.yml` variables to the actual Terraform
  resource names:

| Repo | Before (wrong) | After (matches Terraform) |
|---|---|---|
| inventory-app | `staging-inventory-app-service` | `staging-inventory-service` |
| billing-app | `staging-billing-app-service` | `staging-billing-service` |
| api-gateway | `staging-api-gateway-app-service` | `staging-api-gateway-service` |

- Cluster names (`staging-cluster` / `production-cluster`) verified correct
  against `ecs_cluster.tf` (`${var.environment}-cluster`).
- **Commits:** `9948d66`, `fe16f90`, `544872f` (one per app repo).

#### Step 2.5.4: Rebuild umbrella submodules
- **Action:** Restored umbrella `origin` →
  `https://learn.zone01oujda.ma/git/yaouzddou/code-keeper.git` (kept `github`
  remote `oriax11/code-keeper`).
- **Action:** Deleted broken state — stale local clones, the space-named
  directory, the old-Terraform directory, tracked `code-keeper-infra/` files
  (removed from index), old `.gitmodules`.
- **Action:** Registered **4 proper submodules** (gitlinks):
  `inventory-app`, `billing-app`, `api-gateway`,
  `infrastructure-configuration` — all cloned from the sibling canonical
  repos at their current HEADs.
- **Action:** Set `.gitmodules` URLs and each submodule clone's `origin` to
  the **SSH GitLab URLs** (`git@…:core-keeper/<repo>.git`).
- **Commit (umbrella):** `fb74eee`.

#### Step 2.5.5: Fix Ansible to match the live instance
- **Action:** `infrastructure-configuration/ansible/group_vars/all/gitlab.yml`
  `gitlab_external_url` → `https://6ab7e5f2330452d9e06766c5-36e164.node-eu-d241.iximiuz.com`.
- **Verified correct already (no change):** group path `core-keeper`,
  repository list (`inventory-app`, `billing-app`, `api-gateway`,
  `infrastructure-configuration`), protected branch `main`.

#### Step 2.5.6: Update plan document
- **Action:** Rewrote `docs/code-keeper-plan.md` — status header, decisions
  #9–#12 (group name, Trivy policy, protected branch, umbrella remotes),
  topology matching GitLab reality, phase table with statuses, open items
  (SSH key, dependency updates, OIDC design, Phase 7 verification).

### Phase 2.5 exit criteria

| Check | Result | Status |
|---|---|---|
| Umbrella origin = submission remote | `learn.zone01oujda.ma/git/yaouzddou/code-keeper.git` | **PASSED** |
| 4 submodules with GitLab SSH URLs, gitlinks registered | `git submodule status` shows 4 at correct SHAs | **PASSED** |
| Infra standalone repo restored + ansible inside | `infrastructure-configuration` @ `a8fc881`, 57 files | **PASSED** |
| Local names match GitLab projects | `inventory-app`, `billing-app`, `api-gateway`, `infrastructure-configuration` | **PASSED** |
| CD service names match Terraform | 3 CI files fixed + committed | **PASSED** |
| Ansible `external_url` = live host | updated; group/repos/branch verified | **PASSED** |
| Push to GitLab | **BLOCKED — SSH key not registered** (see plan open item #1) | **PENDING USER** |

---

## 6. Phase 2 Sign-Off

Phase 2 + 2.5 complete: four repositories structured, tested, pipeline-ready,
and reconciled with the live GitLab instance (`core-keeper` group).

**Remaining before push:** add the local public key to GitLab, then
`git push -u origin main` in each sibling repo + the umbrella.

**Next:** Phase 4 — Infrastructure Pipeline in
`infrastructure-configuration/.gitlab-ci.yml` (Phase 3 already satisfied by
Phase 2 test suites).
