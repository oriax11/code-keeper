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

## 9. Phase 6 Sign-Off — Partial

**Met:** the staging stack is live and healthy on AWS; its state is in the GitLab HTTP backend and
shared with CI; CI has least-privilege read access sufficient to verify it and provably cannot
provision; the production approval gate is in place and holding.

**Not met:** the CD mechanism itself — app pipeline triggers infra pipeline with
`APP_NAME`/`IMAGE_NAME`/`IMAGE_TAG`, infra deploys only the named service — has been built and
committed but **never executed**. Section 11 isolation remains an untested claim. Production has
not been applied.

**Next:** trigger an app deploy end-to-end and confirm exactly one service's task definition
changes; then the production apply; then `destroy-all.sh --plan` for the idle teardown.
