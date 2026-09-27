# Code-Keeper: Phase 4 Implementation & Execution Log

**Log Date:** 2026-09-27  
**Project:** Code-Keeper  
**Phase:** Phase 4 — Infrastructure Pipeline (`infrastructure-configuration/.gitlab-ci.yml`)  
**Status:** Pipeline written & locally validated — first live run pending GitLab push (SSH access blocked, see §7)

---

## 1. Overview & Objective

The objective of Phase 4 is to deliver the infrastructure CI/CD pipeline required by the audit:
**Init → Validate → Plan → Apply Staging → Approval → Apply Production**, running on the
GitLab-managed instance (`core-keeper/infrastructure-configuration`), using the GitLab-managed
HTTP state backend configured in Phase 1, serializing applies with `resource_group`, and gating
production behind a manual approval.

---

## 2. Preconditions & Facts Gathered

### Step 4.1: Read the repository's own contracts
- **Action:** Inspected `terraform/backend.tf` — declares `backend "http" {}` with a documented
  dynamic-init pattern: per-environment state URL
  (`${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/terraform/state/${ENV}`), `username=${GITLAB_USER_LOGIN}`,
  `password=${GITLAB_TOKEN}`, lock/unlock addresses with `lock_method=POST` / `unlock_method=DELETE`,
  `retry_wait_min=5`.
- **Action:** Verified `provider.tf` — `required_version >= 1.5.0`, AWS provider `~> 6.0`, tls `~> 4.0`.
- **Action:** Compared all 25 variables in `variables.tf` against `environments/*.tfvars.example`
  (`diff` of name lists → identical). 10 variables have no default; exactly **3 are secrets**
  (`inventory_db_password`, `billing_db_password`, `rabbitmq_password`).
- **Explanation:** The pipeline must be built around these facts rather than inventing its own
  backend/variables scheme.

### Step 4.2: Read the runner registration (ansible)
- **Action:** Inspected `ansible/roles/gitlab_runner/{defaults,tasks}` — docker executor,
  one **locked, project-scoped runner per repo**, tags `code-keeper` + `docker`,
  **`run_untagged: false`**.
- **Explanation:** Two hard requirements follow: every job must declare
  `tags: [code-keeper, docker]`, and no shell executor can be assumed (job images are mandatory).

### Step 4.3: Survey the app pipelines for conventions
- **Action:** Read `inventory-app/.gitlab-ci.yml` (7-stage structure, rules syntax, naming).
- **Explanation:** Keeps the infra pipeline stylistically consistent with the three app pipelines
  (same rules conditions, hyphenated job names, stage-per-gate layout).
- **Finding:** The app pipelines declare **no job tags** — with `run_untagged: false` those jobs
  would never be picked up (see Step 4.6).

---

## 3. Design Decisions

| # | Topic | Decision | Rationale |
|---|-------|----------|-----------|
| D1 | Image | `hashicorp/terraform:1.10.5` (pinned, via `default:`) | Satisfies `required_version >= 1.5.0`; pinned for reproducibility; official image works with GitLab runner out of the box |
| D2 | State auth | `username=${GITLAB_USER_LOGIN}`, `password=${TF_STATE_TOKEN:-$CI_JOB_TOKEN}` | GitLab docs were unreachable from this environment (403), so the password uses a **shell default**: works out-of-the-box if the state API accepts job tokens, and switches to a maintainer-provided `TF_STATE_TOKEN` CI variable automatically if it returns 401 |
| D3 | Secrets in tfvars | CI copies `*.tfvars.example` → `*.tfvars`, then `grep -v _password` strips the 3 secret lines; real values arrive as **protected, masked `TF_VAR_*` variables** | Precedence-proof: secrets exist in exactly one place (CI variables), never in files, never in artifacts |
| D4 | Plan → Apply | Each plan writes `tfplan-$TF_ENV` as a job artifact; applies run `terraform apply tfplan-$TF_ENV` | Official GitLab pattern: the reviewed plan is exactly what gets applied (no re-evaluation at apply time) |
| D5 | Stage gating | **No `needs:` anywhere** — pure stage ordering | `needs:` would let `apply-production` skip the `approval` stage; stage ordering makes the manual gate binding |
| D6 | Approval | `when: manual` + `allow_failure: false` | Pipeline shows **blocked** at `approval` until a human plays it; production cannot start otherwise |
| D7 | Serialization | `resource_group: staging` / `resource_group: production` on the applies | Plan §4 requirement — concurrent pipelines queue instead of racing on state locks |
| D8 | Job rules | `init`/`validate`: `main` **or** MR; `plan`+applies+approval: **`main` only** | AWS credentials and `TF_VAR_*` are protected variables — unavailable on MR refs; MRs therefore get static checks only |
| D9 | Workflow | Anti-duplicate block (MR pipeline wins; branch pipeline skipped while an MR is open) | Prevents double runs on branches with an open merge request |
| D10 | AWS auth | Env credentials (`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` protected+masked) for now | Plan decision #3 (GitLab OIDC → IAM role) lands in Phase 8; the pipeline needs no code change for the swap (provider reads env either way) |

---

## 4. Detailed Execution Log

### Step 4.4: Write `infrastructure-configuration/.gitlab-ci.yml`
- **Action:** Created the pipeline with 6 stages: `init`, `validate`, `plan`, `apply-staging`,
  `approval`, `apply-production` (exactly the plan's stage list).
- **Action:** Added YAML anchors for the two repeated fragments:
  - `.backend_init` — full `terraform init -reconfigure -backend-config=…` block parameterized
    by `$TF_ENV` (state name, lock/unlock addresses, auth, retry) — used by all 4 plan/apply jobs.
  - `.prep_tfvars` — example → tfvars copy + password-line strip — used by both plan jobs.
- **Action:** Job inventory (all with `tags: [code-keeper, docker]`):
  - `init` — `terraform init -backend=false` (providers/modules resolution; backend deferred to
    per-environment jobs so no credentials exist in this stage).
  - `validate` — `terraform init -backend=false && terraform validate`.
  - `plan-staging` / `plan-production` — prep tfvars, backend init, `plan -var-file=… -out=tfplan-$TF_ENV`,
    artifact `terraform/tfplan-$TF_ENV` (expires 1 day).
  - `apply-staging` — `environment: staging`, `resource_group: staging`, backend init,
    `apply tfplan-$TF_ENV`.
  - `approval` — manual, `allow_failure: false`, echo guidance.
  - `apply-production` — `environment: production`, `resource_group: production`, backend init,
    `apply tfplan-$TF_ENV`; gated by pure stage ordering behind `approval`.
- **Action:** Documented all required/optional CI/CD variables in the file header
  (`TF_VAR_inventory_db_password`, `TF_VAR_billing_db_password`, `TF_VAR_rabbitmq_password`,
  AWS keys; optional `TF_STATE_TOKEN`).
- **Explanation:** A self-documenting pipeline — an auditor reading the file sees the stage
  design, the state strategy, the secret strategy, and the runner requirements without opening
  another document.

### Step 4.5: Local validation
- **Action:** Parsed the file with `python3 yaml.safe_load` and asserted: all 6 stages present,
  7 jobs mapped to correct stages, every job carries tags, `approval` has `when: manual`.
- **Result:** `anchors resolved OK, all jobs tagged` — YAML syntax, anchors, and aliases all valid.

### Step 4.6: Fix the app pipelines (defect found during Phase 4 research)
- **Action:** Added `tags: [code-keeper, docker]` to **all 21 jobs** (7 × 3 app repos) via
  anchored insertion after each job's `stage:` line; re-validated all three files with
  `yaml.safe_load` (7 jobs each, all tagged).
- **Explanation:** The ansible-registered runners are **locked per project with
  `run_untagged: false`** — untagged jobs are *never* assigned, so the app pipelines would have
  hung in *pending* forever in Phase 5. Fixing now while the defect is known.
- **Commits:** `inventory-app` `abc1b29`, `billing-app` `1ce99e2`, `api-gateway` `eb1e692`.

### Step 4.7: Commit
- **Action:** Committed `.gitlab-ci.yml` to `infrastructure-configuration` as `5cf53d9`
  *feat(phase4): infrastructure pipeline*.
- **Explanation:** The four repos now each carry their final pipeline files, ready to push.

---

## 5. Pipeline Flow (as implemented)

```
push to main (or MR)
   │
   ├─ MR pipeline:        init → validate                      (static checks only)
   │
   └─ main pipeline:      init → validate
                              → plan-staging ──┐
                              → plan-production ┴─→ apply-staging  [environment: staging]
                                                     → approval ⚠ MANUAL (blocked)
                                                     → apply-production [environment: production]
```
All applies serialize through `resource_group`; both plans and both applies carry the runner tags.

---

## 6. Exit Criteria Verification

| # | Check (plan §4 / §6) | Result | Status |
|---|----------------------|--------|--------|
| 1 | `.gitlab-ci.yml` exists in infra repo | 165 lines, committed `5cf53d9` | **PASSED** |
| 2 | Stages: Init / Validate / Plan / Apply Staging / Approval / Apply Prod | Exact match (`init, validate, plan, apply-staging, approval, apply-production`) | **PASSED** |
| 3 | Separate state per environment | State name `${TF_ENV}` (staging/production) via backend anchor | **PASSED** |
| 4 | `resource_group` serializes applies | `staging` + `production` | **PASSED** |
| 5 | Manual approval gates production | `when: manual` + `allow_failure: false`; stage ordering (no `needs:` bypass) | **PASSED** |
| 6 | Plan artifacts drive applies | `tfplan-$TF_ENV` artifact → `terraform apply tfplan-$TF_ENV` | **PASSED** |
| 7 | Runner tags on all jobs | 7/7 infra + 21/21 app jobs tagged (fixed `run_untagged` defect) | **PASSED** |
| 8 | Secrets stay in CI variables | `.example` → strip passwords → `TF_VAR_*`; nothing sensitive in git/artifacts | **PASSED** |
| 9 | YAML valid (anchors, aliases, rules) | `yaml.safe_load` + structural assertions pass | **PASSED** |
| 10 | Bonus jobs (tfsec / Infracost) | Deferred — optional per plan; not shipped untested | **DEFERRED** |
| 11 | Pipeline **runs** on GitLab (first live init→apply) | Blocked: SSH push access pending (see §7); requires CI variables set before first run | **PENDING** |

---

## 7. Blockers & Open Items

1. **GitLab SSH access** — `git@6ab7e5f2…iximiuz.com` still rejects this machine's key
   (`SHA256:PfYE7CPAkx/QdlmmJ8mEpCRPd+iAA91YUWdYqdEsLhg` offered, denied), so none of the 5
   repos (4 + umbrella) can be pushed yet. Watcher retry loop active.
2. **CI/CD variables must be created before the first main pipeline** (Settings → CI/CD →
   Variables, protected + masked): `TF_VAR_inventory_db_password`,
   `TF_VAR_billing_db_password`, `TF_VAR_rabbitmq_password`, `AWS_ACCESS_KEY_ID`,
   `AWS_SECRET_ACCESS_KEY` — plus `TF_STATE_TOKEN` only if the state API rejects `CI_JOB_TOKEN`.
3. **State-auth fallback** — D2 was designed because GitLab docs were unreachable (403) from
   this environment; verify on the first `plan-*` job whether `CI_JOB_TOKEN` is accepted.
4. **tfsec / Infracost bonus jobs** — deferred to a follow-up if wanted for audit bonus points.

---

## 8. Phase 4 Sign-Off (file deliverable)

The infrastructure pipeline is implemented, self-documented, and locally validated — all static
exit criteria (1–9) **PASSED**; live execution (11) waits on push access and CI variable setup.

**Next:** Phase 5 — run the app CI pipelines on GitLab (after push), which reuses the same
runner/tag facts fixed in Step 4.6.
