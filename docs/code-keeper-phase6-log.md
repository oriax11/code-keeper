# Code-Keeper: Phase 6 Implementation & Execution Log

**Log Date:** 2026-09-30
**Project:** Code-Keeper
**Phase:** Phase 6 — CD as the infrastructure deployment controller
**Status:** ✅ Staging live and reconciled — `plan-staging` reports *No changes*, `apply-staging` is a no-op. Production blocked at the manual approval gate by design.

---

## 1. Overview & Objective

Phase 6 makes the **infrastructure repository the sole deployment controller**. App pipelines do
not hold AWS credentials (§14 of `docs/message.txt`); instead they trigger the infra pipeline with
`APP_NAME` / `IMAGE_NAME` / `IMAGE_TAG`, and the infra repo deploys exactly the named service.

This log records the work of bringing the staging stack up on AWS and, more importantly, proving
that **CI and AWS agree about what exists** — the Terraform state handoff and the read permissions
that make it verifiable.

Outcome: staging running 6 ECS services in `staging-cluster`, and GitLab pipeline #86 green with
`plan-staging` → *No changes* and `apply-staging` → `0 added, 0 changed, 0 destroyed`.

---

## 2. Staging Stack — Live

Verified against AWS account `006631837921`, region `us-east-1`:

| Resource | Value |
|---|---|
| Cluster | `staging-cluster` |
| ALB | `staging-alb-2125783479.us-east-1.elb.amazonaws.com` (HTTP→HTTPS `301`, both targets healthy) |
| EFS | `staging-efs` |
| Cognito | `staging-user-pool` (`us-east-1_bPoDPlAhf`) |
| Secret | `staging/app-secrets` |
| NAT gateway | `staging-nat` — largest recurring cost item, ~$32/month plus per-GB |

Service rollout state, all at desired count with `COMPLETED` deployments:

```
staging-inventory-service      2/2  COMPLETED
staging-billing-service        2/2  COMPLETED
staging-api-gateway-service    2/2  COMPLETED
staging-rabbit-queue           1/1  COMPLETED
staging-inventory-db           1/1  COMPLETED
staging-billing-db             1/1  COMPLETED
```

**Digest pinning confirmed in the live task definition** — the running container is on the
immutable image, not a mutable tag:

```
inventory-app → docker.io/1ee5lim/inventory-app@sha256:69a0ee72f4e4fc0d645581d15ab56fb2aabda207983bd3f4d996b2fdd951333e
```

---

## 3. Terraform State Handoff — Corrected Diagnosis

### Step 6.1: A wrong call I made, and the correction

- **Action:** After the bootstrap apply I reported that state had *not* reached the GitLab HTTP
  backend, and that CI would therefore plan `70 to add` and collide with the running stack.
- **Why it was wrong:** I based that on a GitLab API read of
  `/projects/8/terraform/state/staging` which I interpreted as `resources: 0`. The real state was
  fine — the successful apply had pushed it correctly, and `terraform state list` returned **73**
  resources read over the network.
- **Correction:** The `resources: 0` reading was my misinterpretation of the API response, not
  evidence of an empty backend. The bootstrap apply performed as root had already uploaded state.

### Step 6.2: State is remote and shared

- **Action:** Confirmed no local `terraform.tfstate` exists in `terraform/`, and
  `terraform state list` returns 73 resources.
- **Explanation:** With an `http` backend there is no local state file; every read goes to GitLab.
  CI and local runs therefore share one source of truth, which is the property the whole phase
  depends on.

### Step 6.3: Placeholder left in the local backend config

- **Action:** Found `username` in the local backend config set to the literal string
  `<your-gitlab-username>`.
- **Explanation:** A placeholder from my own earlier instruction had been substituted verbatim. It
  happens to work because the token authenticates, but it is wrong and will break confusingly.
  Should be re-initialised with `username=aesslima`.

---

## 4. Credential Exposure — Outstanding

- **Action:** A diagnostic command I ran (`cat .terraform/terraform.tfstate`) dumped the backend
  config, which persists the GitLab state token in plaintext. The token
  (`glpat-…`, `api` scope, Maintainer on the infra project) appeared in a transcript.
- **Status:** ⬜ Not yet revoked. The user acknowledged and intends to rotate later.
- **Required action:** Revoke the token ending `0w0xhvwo5`, recreate with the same scope, update the
  `TF_STATE_TOKEN` CI variable, and re-run `terraform init -reconfigure` locally.
- **Process note:** Extracting only the needed fields (`backend.type`, `backend.config.address`)
  would have answered the question without exposing the secret. Reading a file that is known to
  contain credentials should be done field-by-field, not wholesale.

---

## 5. CI Read Permissions for `terraform refresh` — The Bulk of This Phase

`plan-staging` failed repeatedly. Each failure was a *permission* problem, not a state problem: the
state was being read correctly, but refresh could not read the live resources to check for drift.

The policy converged over four versions, one denial class at a time:

| Pipeline | Denial | Fix |
|---|---|---|
| #81 | `acm:DescribeCertificate` | initial `ck-plan-reads` inline policy (21 actions) |
| #82 | `secretsmanager:GetResourcePolicy`, `efs:DescribeLifecycleConfiguration`, `ec2:DescribeVpcAttribute` | moved to a **customer-managed** policy — the inline cap is 2048 bytes and the document was 2459 |
| #83 | `cognito-idp:GetUserPoolMfaConfig`, `servicediscovery:GetNamespace`, `secretsmanager:GetSecretValue` | added `Get*` for Cognito and Cloud Map, plus `GetSecretValue` |
| #85 | `application-autoscaling:ListTagsForResource` | added `autoscaling:List*`, `application-autoscaling:List*` |
| #86 | `cloudwatch:GetDashboard` | added `cloudwatch:Describe*`, `cloudwatch:Get*`, `cloudwatch:List*` |

### Step 5.x lessons worth keeping

1. **Inline user policies cap at 2048 bytes.** The first attempt failed with `LimitExceeded` and
   changed nothing. A customer-managed policy (6144 bytes) is the right home for anything this size.
2. **Terraform refresh reads tags on every resource.** Drift detection calls `ListTagsForResource`
   / `ListTagsForCertificate` in addition to the obvious `Describe*` calls. A read policy built only
   from `Describe*` is always incomplete.
3. **Wildcards have blind spots across services.** Cognito and Cloud Map expose reads as `Get*`, not
   `Describe*`. A uniform `Describe*` scheme misses them.
4. **IAM propagation churn mimics a policy defect.** Rapid create/modify/delete cycles produced
   `AccessDenied` for actions that were demonstrably in the current policy version. I chased this
   for several rounds — including attaching the AWS-managed `CloudWatchReadOnlyAccess` as a
   comparison, and building a minimal policy to bisect — before concluding that the denials were
   transient and resolved on their own after the policy set stopped changing. **Lesson: make one
   policy change, then wait, before concluding anything from an `AccessDenied`.**

### A mistake I made here, and the cleanup

- **Action:** While verifying that write access was still denied, I ran `aws ec2 create-vpc`. The
  command was intended as a negative test and I expected `AccessDenied`.
- **What happened:** It **succeeded** — it created `vpc-0344221b878ee143b`. The AWS CLI credential
  store takes precedence over `AWS_SHARED_CREDENTIALS_FILE` when no profile is named, so the call
  ran as **account root**, not as the scoped user. The negative test was meaningless *and* mutating.
- **Cleanup:** Deleted the VPC immediately. Verified `InvalidVpcID.NotFound` and confirmed only the
  two original VPCs remain (`vpc-0530f7377b0063020` default, `vpc-07872771e17f9a02c` staging).
- **Correction to my own method:** a negative test must pin the identity explicitly
  (`AWS_PROFILE=code-keeper`), and a "confirm it is denied" probe should prefer a harmless
  read-only-invalid call over any create. The scoped identity was re-confirmed afterwards
  (`arn:aws:iam::006631837921:user/gitlab-ci-deploy`).

### Two more false alarms in my own diagnostics

- `logs:ListTagsForResource` and `application-autoscaling:ListTagsForResource` were reported as
  denied. They were not — the local AWS CLI is too old to have those subcommands and rejected the
  invocation with a usage error. My harness counted any non-zero exit as a denial.
- `acm describe-certificates` was likewise not a valid subcommand; the real one is `list-certificates`.

A verification harness that treats "non-zero exit" as "AccessDenied" will manufacture findings.

---

## 6. Final Verified Posture

Read surface (`ck-plan-reads` v4, managed policy, 38 actions, `Resource: "*"`, all read-only):

```
acm:DescribeCertificate              ALLOWED      ec2:DescribeVpcs                ALLOWED
acm:ListTagsForCertificate           ALLOWED      ec2:DescribeVpcAttribute        ALLOWED
elasticloadbalancing:Describe*       ALLOWED      cloudwatch:GetDashboard         ALLOWED
elasticfilesystem:Describe*          ALLOWED      cloudwatch:ListDashboards       ALLOWED
cognito-idp:Describe*                ALLOWED      ecs:Describe* / ecs:List*       ALLOWED
cognito-idp:GetUserPoolMfaConfig     ALLOWED      servicediscovery:Get*           ALLOWED
secretsmanager:Describe*/List*       ALLOWED      application-autoscaling:*       ALLOWED
secretsmanager:GetSecretValue        ALLOWED      logs:Describe*                  ALLOWED
iam:Get* / iam:List*                 ALLOWED
```

Write surface — confirmed still denied, which is the point:

```
ec2:CreateVpc              DENIED (UnauthorizedOperation)
iam:CreateRole             DENIED (AccessDenied)
cloudwatch:PutDashboard    DENIED (AccessDenied)
```

IAM posture of `gitlab-ci-deploy`:

| Check | Result |
|---|---|
| `AdministratorAccess` attached | **none** ✅ |
| Access keys | 1 active (`AKIAQDC2J2DQ4ZD7BKXT`) |
| Inline policies | `ck-deploy`, `ck-deploy-reads` |
| Managed policies | `ck-plan-reads` (v4) |
| Permissions boundary | none |
| Group memberships | none |
| Leftover test policies | none (all probes cleaned up) |

`secretsmanager:GetSecretValue` is a deliberate widening — refresh must read the secret version to
confirm it has not drifted. It is read-only but does expose secret material to the CI identity.
Flagged here as a conscious acceptance, not an oversight.

---

## 7. Pipeline #86 — Green

```
init               success
validate           success
plan-staging       success   No changes. Your infrastructure matches the configuration.
plan-production    success   Plan: 72 to add, 0 to change, 0 to destroy
apply-staging      success   Apply complete! Resources: 0 added, 0 changed, 0 destroyed.
approval           manual    ← production gate
apply-production   created
```

The decisive line:

```
No changes. Your infrastructure matches the configuration.
```
…preceded by 72 `Refreshing state…` operations. That is the proof the bootstrap apply handed off
cleanly: CI found every resource, read it live, and found zero drift.

`plan-production` correctly reports `72 to add` — no production stack exists yet.

`approval` sitting in `manual` is the designed behaviour (§ manual approval before production), not
a stall.

---

## 8. Open Items

1. ⬜ **Revoke the exposed GitLab state token** and update `TF_STATE_TOKEN` (Section 4).
2. ⬜ **Re-init the local backend** with `username=aesslima` instead of the placeholder (Step 6.3).
3. ⬜ **Production apply** — blocked at `approval`. Expect roughly double the running cost.
4. ⬜ **`destroy-all.sh --plan`** — read-only teardown check for the idle period. Default mode is
   *not* read-only; use the flag deliberately.
5. ⬜ **CD path not yet exercised end-to-end.** `plan-staging`/`apply-staging` are the *provisioning*
   half. The §11 service-isolation claim — that triggering a deploy for one app changes only that
   service — is still unproven. That is the real remaining Phase 6 deliverable.
6. ⬜ **Infra images are pinned but not reproducible** — `tools/setup_db.sh` and `tools/setup_rq.sh`
   were never committed (requested from oriax11). The 17 CRITICAL / 94 HIGH findings in those images
   are knowingly retained (decision #4).

---

## 9. Day 2 — CD Path Fixed and Proven End to End

**Log Date:** 2026-10-01

Yesterday the app→infra handoff had never executed. Today it did, repeatedly, and each attempt
exposed a distinct defect. All are now fixed and the path is proven.

### Step 9.1 — What the first real runs revealed

Three consecutive failures, each one layer deeper than the last:

| Infra pipeline | Symptom | Actual cause |
|---|---|---|
| #93 | `ClientException: ... must also specify a value for 'executionRoleArn'` | `register-task-definition` omitted `--execution-role-arn` |
| #96 | `ClientException: Container.image contains invalid characters` | image was the literal `$IMAGE_NAME:$IMAGE_TAG` |
| #106 | `Invalid setting for container ... At least one of 'memory' or 'memoryReservation'` | task-level `cpu`/`memory` not passed back |

The first was found and fixed by oriax11 (`317b6ef`) before I started.

**Root cause of the second: `trigger:variables` does not expand variables defined in the file's
own `variables:` block.** The app sent the text `$IMAGE_NAME`; `test -n` accepted it because the
string is non-empty, and `[ "$IMAGE_TAG" != "latest" ]` accepted it because it isn't the word
"latest". Every guard passed and the failure only surfaced inside ECS. All three apps were affected
identically, not just inventory.

`$CI_COMMIT_SHA` **does** expand — verified, not assumed. Observed downstream:
`docker.io/1ee5lim/api-gateway-app:544e47e521bd8c1d1914dda3a86bbd90ed9fe825`.

### Step 9.2 — Guards: convert a silent wrong deploy into a loud stop

`trigger-validate` previously could not detect the failure it existed to prevent. It now:

- rejects any residual `$` in `APP_NAME`/`IMAGE_NAME`/`IMAGE_TAG`;
- validates `IMAGE_NAME` against an image-reference grammar;
- requires `IMAGE_TAG` to be a hex commit SHA (7–64 chars), not merely "not the word latest".

Regression-tested **10/10**, including the exact `$IMAGE_NAME`/`$IMAGE_TAG` pair that caused this,
plus `latest`, `main`, `v1.2.3`, an empty value, an unknown service and a space in the image name.

### Step 9.3 — Second production gate

`apply-production` gained `when: manual` on main. Previously any push put production one stray
click away — and on 09-30 and 10-01 it was clicked twice, failing on `AccessDenied` both times.

### Step 9.4 — Task-level settings must be passed back

`register-task-definition` rebuilds the task from scratch. Only `--family`,
`--execution-role-arn` and `--container-definitions` were supplied, but `cpu` (256) and `memory`
(512) live at the **task** level here — the containers carry none — so ECS could not account for
them. The script now reads `taskRoleArn`, `networkMode`, `cpu`, `memory` and
`requiresCompatibilities` from the live revision and passes them through, so it stays correct if
Terraform ever retunes sizing.

**Two bugs I introduced and caught before they reached CI:**

1. `TD_ARGS` was built ~30 lines before `$WORKDIR/patched.json` exists, so the container-definitions
   path would have resolved to `file:///patched.json`.
2. I first parsed the settings with `cut` on `--output text`. `requiresCompatibilities` is a *list*
   and renders on its own line, so tab-splitting folded `FARGATE` into the `networkMode`/`cpu`/
   `memory` values. Caught by testing the parsing against live AWS before trusting it, and rewritten
   with `jq`, which the script already depends on.

Verified by registering a real revision (`staging-inventory:2`) with exactly these arguments:
accepted, `256/512/awsvpc`. The service still pointed at `:1`; `:2` was inert.

### Step 9.5 — Also fixed

- `.gitignore`: `*.tfplan` never matched CI's extensionless `tfplan-<env>`, so a resource-bearing
  plan file was committable.
- api-gateway `urllib3` 2.7.0 → 2.8.0, clearing two HIGH findings: CVE-2026-97687 (traffic
  interception via HTTPS proxy TLS config override) and CVE-2026-97689 (DoS via unbounded memory
  in the chunk parser). `scan` is now clean.

### Step 9.6 — End-to-end proof, including §11 isolation

`api-gateway` main push → `build/test/scan/containerize` → trigger → infra #116:

```
trigger-validate  success   guards passed
capture-image     success
deploy-staging    success
  registered new task definition revision: staging-api-gateway:2
  updated staging-api-gateway-service to staging-api-gateway:2
  OK staging-api-gateway-service is stable on ...:544e47e5...
deploy-approval   manual    ← production gate holding
```

**Final state — only the named service moved:**

| Service | Revision | Image | State |
|---|---|---|---|
| `staging-inventory-service` | `:1` | `inventory-app@sha256:69a0ee72…` | `COMPLETED` 2/2 — **untouched** |
| `staging-billing-service` | `:1` | `billing-app@sha256:38a13852…` | `COMPLETED` 2/2 — **untouched** |
| `staging-api-gateway-service` | `:2` | `api-gateway-app:544e47e5…` | `COMPLETED` 2/2 — **deployed** |

§11 isolation is no longer an untested claim. Deploying one app changed exactly that app.

The rollout took ~9 minutes to report `COMPLETED` because the three app services share one target
group (`staging-app`) and ECS waits for target deregistration. One target sat in `draining` /
`Target.DeregistrationInProgress` for several minutes. Both tasks were `RUNNING`/`HEALTHY` well
before that. Not a fault, but a slow gate worth knowing about.

### Step 9.7 — New conflict: Terraform pins digests, CD deploys SHA tags

`staging.tfvars` pins `api_gateway_image` to an immutable digest:

```
api_gateway_image = "docker.io/1ee5lim/api-gateway-app@sha256:350d1571…"
```

but the service now runs `…/api-gateway-app:544e47e5…`. **The next `apply-staging` will revert
every CD deploy** — `plan-staging` will stop reporting `No changes` and will show the task
definition drifting back to the pinned digest.

Digest pinning (Phase 5/6 decision) and per-commit CD deployment are structurally in conflict.
This needs a deliberate decision before the next infra apply; it is not a bug I should pick a
resolution for unilaterally.

---

## 10. Phase 6 Sign-Off

**Met:** the staging stack is live and healthy on AWS; its state is in the GitLab HTTP backend and
shared with CI; CI has least-privilege read access sufficient to verify it and provably cannot
provision; the production approval gate is in place and holds on both the Terraform and CD paths.

**Met since yesterday:** the CD path is no longer theoretical. App pipeline → infra pipeline →
single-service deploy is proven end to end, and **§11 isolation is demonstrated**: deploying
`api-gateway` left `inventory` and `billing` on their original revisions and images.

**Not met:** production has never been applied, and `destroy-all.sh --plan` has not been run.

### Open items

1. ⬜ **Resolve the digest-pin vs SHA-tag conflict** (Step 9.7) before the next `apply-staging`,
   which will otherwise revert every CD deploy.
2. ⬜ **`scan` has `allow_failure: true`** in all three apps. Two HIGH CVEs shipped in a green
   pipeline yesterday. Worth deciding whether findings should block.
3. ⬜ **Production apply** — held at the gate; roughly double the running cost.
4. ⬜ **`destroy-all.sh --plan`** for the idle teardown; the default mode is *not* read-only.
5. ⬜ **CD path unproven for `inventory` and `billing`** — only `api-gateway` has been deployed this
   way. All three share one script and one code path, but only one has actually run.
6. ⬜ **Infra images are pinned but not reproducible** — `tools/setup_db.sh` and `tools/setup_rq.sh`
   were never committed (requested from oriax11).

**Next:** decide the digest/tag question, deploy the remaining two apps to confirm the path, then
production, then `destroy-all.sh --plan` for the idle period.
