# Handover — Code-Keeper

**Written:** 2026-10-02 (rewritten; supersedes the 2026-10-01 version)
**Purpose:** pick this project up cold, on any machine, without reading the full transcript.

Read this first, then `docs/NEW-MACHINE-SETUP.md` to stand a new machine up.

Every figure below was re-verified against live AWS on 2026-10-02 unless a line says otherwise.

---

## 1. What this project is

Three microservices (`inventory-app`, `billing-app`, `api-gateway`) on AWS ECS Fargate, fronted by
an ALB, deployed by **Terraform**, with **GitLab CI** as the only deployment controller.

The central design rule, from `docs/message.txt`:

> **App pipelines hold no AWS credentials.** They build, test, scan and containerize an image, then
> *trigger* the infrastructure repo with `APP_NAME` / `IMAGE_NAME` / `IMAGE_TAG`. The infra repo
> deploys exactly the named service, and only that service.

---

## 2. Topology

### GitLab

⚠️ **The host URL is ephemeral.** It has changed at least four times in one day
(`d1d94d → 098e3d → d79464 → gone`), and again since. Get the current URL before doing anything.

Group `code-keeper`:

| id | Project | Role |
|---|---|---|
| 5 | `inventory-app` | app CI → triggers deploy |
| 6 | `billing-app` | app CI → triggers deploy |
| 7 | `api-gateway` | app CI → triggers deploy |
| 8 | `infrastructure-configuration` | **the deployment controller** |

`main` is **protected**. Direct pushes are refused; work goes through branches and MRs. That is not
bypassable, and should not be — every change in this project went via MR.

### AWS

Account `006631837921`, region `us-east-1`. Terraform pinned to exactly **1.10.5**.

### Remotes — each submodule has two

```
origin  -> GitLab   (authoritative)
github  -> git@github.com:0xlislim/<repo>.git   (mirror)
```

The **umbrella** exists only on GitHub (`git@github.com:oriax11/code-keeper.git`). There is no
umbrella project on GitLab — do not add an `origin` to it.

### Current commit alignment

GitLab `main`, the GitHub mirror, and the umbrella gitlink all point at the same commit for every
submodule:

| Submodule | SHA |
|---|---|
| `infrastructure-configuration` | `86202d7` |
| `inventory-app` | `64d2db0` |
| `billing-app` | `c6bd1a9` |
| `api-gateway` | `40479a1` |

The work that was on `lee` — including this file — has been merged into umbrella `main`, so a clone
gets the docs and the submodules in one step. `lee` still exists; it is no longer the place to look
for anything.

> **Order matters if you ever re-sync.** Push the submodule mirror to GitHub *first*, then bump the
> umbrella gitlink. The reverse leaves the umbrella pointing at commits GitHub does not have, and a
> fresh clone fails to resolve the submodule.

---

## 3. Live state — both environments are up

**73 Terraform resources in staging, 73 in production.** Both were re-planned on 2026-10-02 and
both returned `No changes. Your infrastructure matches the configuration.`

| Service | staging | production |
|---|---|---|
| `inventory-service` | 2/2 `ACTIVE`, `staging-inventory:1` | 2/2 `ACTIVE`, `production-inventory:1` |
| `billing-service` | 2/2 `ACTIVE`, **`staging-billing:3`** | 2/2 `ACTIVE`, `production-billing:1` |
| `api-gateway-service` | 2/2 `ACTIVE`, **`staging-api-gateway:4`** | 2/2 `ACTIVE`, **`production-api-gateway:2`** |
| `rabbit-queue` | 1/1 `ACTIVE` | 1/1 `ACTIVE` |
| `inventory-db` | 1/1 `ACTIVE` | 1/1 `ACTIVE` |
| `billing-db` | 1/1 `ACTIVE` | 1/1 `ACTIVE` |

Bold task definitions are ones the **CD path** created. Every task definition references its image
**by digest**, not by tag.

Supporting resources:

| | staging | production |
|---|---|---|
| ALB | `staging-alb-2125783479` | `production-alb-2141569501` |
| Cognito pool | `staging-user-pool` / `us-east-1_bPoDPlAhf` | `production-user-pool` / `us-east-1_u8ECIdGkF` |
| Cognito client | `staging-app-client` / `40dps18qv1t51lm8hbhtp8puap` | `production-app-client` / `1m73gppq20k3c4drnr15dcg9pf` |
| Secret | `staging/app-secrets` | `production/app-secrets` |

Both ALBs present a **self-signed** certificate and `301` HTTP→HTTPS. `curl` needs `-k`; there is no
domain to obtain a real certificate from. This is a lab constraint, not a defect — but an auditor
will notice it, so it is documented rather than hidden.

Neither Cognito app client has a secret. Both enable `ALLOW_ADMIN_USER_PASSWORD_AUTH`, which is what
makes the test-user script in §7 work without one.

Each pool now contains exactly one user, `audituser` (`CONFIRMED`), created by the test script.

---

## 4. The CD path — proven, after being broken three times

App `main` push → `build`/`test`/`scan`/`containerize` → trigger → infra `deploy-staging` →
`deploy-approval` (manual) → `deploy-production`.

The first real runs of this path each failed one layer deeper than the last:

| Infra pipeline | Error | Cause |
|---|---|---|
| #93 | `must also specify a value for 'executionRoleArn'` | `--execution-role-arn` not passed |
| #96 | `Container.image contains invalid characters` | image was the literal `$IMAGE_NAME` |
| #106 | `At least one of 'memory' or 'memoryReservation' must be specified` | task-level `cpu`/`memory` not passed back |

**All three are fixed.** The path is proven end to end, including isolation:

> Deploying `api-gateway` moved **only** `staging-api-gateway-service` to a new revision.
> `inventory` and `billing` stayed put with unchanged images.

That was the central unproven claim of Phase 6. It is demonstrated.

Three traps worth remembering, all hit for real:

- **`trigger:variables` does not expand** file-scoped variables. It sends the literal text
  `$IMAGE_NAME`. `test -n` accepted it (a 12-character string is non-empty) and
  `[ "$X" != "latest" ]` accepted it too. Every guard passed; ECS rejected it.
  `$CI_COMMIT_SHA` **does** expand. `trigger:project:` **does** expand.
- **`register-task-definition` rebuilds the task**, so every task-level field Terraform set must be
  supplied again. `cpu`/`memory` live at the task level here; the containers carry none.
- **`tfvars` vs `tfvars.example` divergence.** The tracked `.example` and the gitignored `.tfvars`
  are supposed to match. They silently did not, and the working copy had an **older urllib3** than
  the tracked one — i.e. a production CVE downgrade that no diff against `main` would have shown.
  The rule now: **`.example` is the source of truth, CI regenerates the working tfvars from it.**

---

## 5. ✅ Resolved: digest pinning vs CD

The 2026-10-01 handover led with this as an unresolved conflict. **It is now closed**, and the
resolution was to pin digests everywhere rather than abandon pinning.

The rules, and why each exists:

1. **Digest pinning everywhere** — tfvars *and* ECS task definitions. Tags proved mutable: the tag
   `544e47e` resolved to two different digests on the same day.
2. **Pin from ECS, not from the registry.** `pin-image.sh` reads the digest back out of the task
   definition the deploy just wrote. Reading it from the registry instead would be a race — the tag
   can move between the deploy and the pin.
3. **`.tfvars.example` is authoritative.** It is tracked, so drift is visible in review.
4. **`check-image-pins.sh` guards it in CI.** The `verify-image-pins` job runs in the `plan` stage
   for both environments, and `plan-*` declare `needs: [verify-image-pins]`. It fails when a pin is
   a tag rather than a digest.

Verified 2026-10-02: every pin in `staging.tfvars.example` and `production.tfvars.example` is an
exact `@sha256:` match for the image running in the corresponding live task definition. Both plans
return `No changes`.

`pin-image.sh` rewrites the tracked `.example`; it must never commit the gitignored `.tfvars`. It
had that bug once.

---

## 6. CI identity

`arn:aws:iam::006631837921:user/gitlab-ci-deploy`

| Policy | Type |
|---|---|
| `ck-deploy` | inline — ECS deploy + `iam:PassRole` on `*ecs*` |
| `ck-deploy-reads` | inline — discovery calls |
| `ck-plan-reads` | customer-managed, **v4** — everything `terraform refresh` reads |

No permissions boundary. No group memberships. `AdministratorAccess` **not** attached.

The identity can **deploy to production but cannot build production.** It cannot create a VPC,
cluster, IAM role, or secret. `apply-production` in CI is therefore **expected to be red** — that
is the steady state, not a regression. Anyone reading the pipeline and seeing a failing
`apply-production` should be told this before they go looking for a bug.

`ck-deploy` gained `ecs:DeregisterTaskDefinition` and `ecs:TagResource` (scoped to ECS ARNs, not
`*`) so CD can clean up its own task definition revisions. Both are needed; neither widens the
identity into provisioning.

`ck-plan-reads` reached **v4** because each version was forced by a pipeline failing on an
AccessDenied naming one missing action. That history is the evidence the policy stayed
least-privilege — worth reading before widening anything.

The policies were originally created by hand and are **not** in Terraform. They are now committed
under `infrastructure-configuration/iam/gitlab-ci-deploy/` with a README giving the rationale for
each permission, and `bootstrap-new-machine.sh` diffs repo vs live and reports drift — it
**warns and continues** on drift, and fails only on missing permissions.

### ⚠️ A second, unrelated administrator identity exists in the account

`cloud-design-deployer` — created 2026-09-11 by the original project's
`scripts/bootstrap-iam.sh` — holds **`AdministratorAccess`** and has an **active access key**
(`AKIAQDC2J2DQRWRLT2E5`). Re-confirmed still present and still `Active` on 2026-10-02. Last
CloudTrail activity 2026-09-17, i.e. idle since.

It is not used by Code-Keeper. It is nevertheless a full-account administrator with a live key,
which is exactly what an audit flags. **Not deleted** — that is destructive and it may be wanted as
evidence. Recommended action, subject to your call:

```bash
aws iam delete-access-key --user-name cloud-design-deployer \
  --access-key-id AKIAQDC2J2DQRWRLT2E5 --profile root   # do this first
aws iam delete-user --user-name cloud-design-deployer --profile root
```

Revoke the key before the user, so there is never a window with neither.

`scripts/bootstrap-iam.sh` — the script that created it — defaulted to `POLICY_MODE=admin` and
attached `AdministratorAccess` when run bare. The default is now `scoped`, and `admin` requires
typing `yes-i-understand`.

> **That fix nearly did not exist.** It was committed only to the GitHub mirror while GitLab was
> unreachable, and was then destroyed locally by a `git reset --hard origin/main`. For a while
> GitLab — the deployment controller and the authoritative source — still shipped the dangerous
> default. It was only found by diffing `github/main` against `origin/main` during a routine mirror
> sync. **If a security fix cannot be pushed to the authoritative remote, treat it as not made.**

Verified denied: `ec2:CreateVpc`, `iam:CreateRole`, `cloudwatch:PutDashboard`,
`secretsmanager:PutSecret`.

---

## 7. Verifying the deployment by hand

Two scripts, both in `infrastructure-configuration/scripts/`, both staging-by-default with an
`--env production` flag, both idempotent:

```bash
./scripts/create-test-user.sh --env staging     # prints an AccessToken to stdout
./scripts/test-api-as-user.sh --env production  # asserts API behaviour, exits non-zero on failure
```

`create-test-user.sh` discovers the pool and app client **by name**, so it survives Terraform
recreating them. It runs `admin_create_user` → `admin_set_user_password --permanent` (so no
confirmation code is ever needed) → `admin_initiate_auth`. It works from the CLI because the client
allows `ADMIN_USER_PASSWORD_AUTH` and has no secret, so no `SECRET_HASH` is required. The token goes
to **stdout only**; everything human-readable goes to stderr, so the token never lands in a file,
the shell history, or a CI log.

`test-api-as-user.sh` asserts four things:

| Check | Expected | Why it matters |
|---|---|---|
| `GET /` | 200 | health, unauthenticated by design |
| `GET /api/movies` **without** a token | **401** | proves the JWT gate is real, not decorative |
| `GET /api/movies` **with** a token | 200 | proves auth works *and* the proxy reaches inventory-app |
| `POST /api/billing/` with a token | 200 | proves the rabbitmq path end to end |

The 401-then-200 pair is the whole point: authentication is enforced, **and** a legitimate user gets
through. Confirmed 4/4 on both environments on 2026-10-02.

The 401 was also confirmed to have teeth — garbage tokens, empty Bearer headers, and tokens with a
valid shape but a tampered signature are all rejected. A 401 assertion that would also pass on a
200 is worthless, so this was checked rather than assumed.

Both scripts require `aws login` (root) for the Cognito admin calls only; the HTTP requests
themselves carry no AWS credentials. The `cognito-idp:Admin*` permissions are **deliberately not**
granted to `gitlab-ci-deploy`.

Known rough edge: `test-api-as-user.sh` discards `create-test-user.sh`'s stderr, so a token failure
surfaces only as `could not mint a Cognito token`. Run `create-test-user.sh` directly to see why.

---

## 8. Bugs found and fixed along the way

Listed because each was invisible from the outside — a green pipeline, or a passing test, or a clean
`plan`, while the thing was broken.

| Symptom | Actual cause |
|---|---|
| Container image rejected as invalid characters | `trigger:variables` sent the literal `$IMAGE_NAME` |
| Task definition rejected for missing `executionRoleArn` | `--execution-role-arn` not threaded through |
| Task definition rejected for missing `memory` | task-level `cpu`/`memory` not re-supplied on re-register |
| `pipefail` reporting `ALLOWED` when it was not | pipeline ran without `set -o pipefail` |
| Drift check reporting `NOT ATTACHED` | it checked the wrong identifier |
| CVE downgrade invisible in review | gitignored `.tfvars` had drifted from tracked `.example` |
| `pin-image` committing a gitignored file | it staged `.tfvars` instead of `.example` |
| `verify-image-pins` exiting 127 | the `hashicorp/terraform` image has neither bash nor the aws CLI |
| `verify-image-pins` exiting 2 | `$TF_ENV` empty in that job |
| Billing crash-looping on cold start | it dialled the database with no retry; **fixed in app code**, not `container_dependencies`, because every task definition here is single-container so there is nothing to order within a task |

---

## 9. Open items, in priority order

1. ⬜ **`scan` has `allow_failure: true`** in all three apps (`.gitlab-ci.yml` line 109 in each). Two
   HIGH CVEs shipped inside a green pipeline on 2026-09-30. Decide whether findings should block.
2. ⬜ **`inventory` has never run the CD path.** Its task definition is still `:1` in both
   environments — it has only ever been deployed by Terraform apply. `billing` and `api-gateway`
   have both been CD-deployed in staging, and `api-gateway` in production. The code path is shared,
   but `inventory` is unproven end to end.
3. ⬜ **Revoke the `cloud-design-deployer` key**, then the user. See §6.
4. ⬜ **Four AWS/GitLab credentials remain exposed in transcripts** from earlier in this project. Not
   rotated — the call was that this is an educational lab, not real production. Worth a conscious
   decision rather than drift.
5. ⬜ **Terraform should own the CI IAM user.** The policies are now in the repo and drift is
   reported, but they are still applied by hand. A separate bootstrap root module is needed, since
   the user must exist before Terraform can run.
6. ⬜ **Infra images are pinned but not reproducible** — `tools/setup_db.sh` and `tools/setup_rq.sh`
   were never committed (requested from oriax11). 17 CRITICAL / 94 HIGH findings in those images
   are knowingly retained.
7. ⬜ **`urllib3` is pinned to 2.8.0 in `api-gateway/requirements.txt` only.** `inventory` and
   `billing` have no `urllib3` line at all, so they resolve it transitively and unpinned.
8. ⬜ **`test-api-as-user.sh` swallows the reason for token failures.** Cosmetic, but it will cost
   someone an hour the first time Cognito misbehaves.

`destroy-all.sh --plan` is available for when staging is no longer needed. **Default mode is
destructive.**

---

## 10. Known environmental quirks

- **GitLab node URL changes constantly.** See `NEW-MACHINE-SETUP.md` §0. A dead node surfaces as
  `HTTP remote state endpoint invalid auth`, which looks like a credential problem and is not.
- **`terraform init -reconfigure` discards the cached backend config** and re-asks for it. With an
  empty `backend.tf` and no TTY that fails with `address argument is required`, so **all seven
  `-backend-config` values must be passed together**.
- **If `address` is wrong, Terraform will happily init against brand-new empty state**, and the next
  `apply` would try to create the whole stack again. After every re-init, confirm
  `terraform state list | wc -l` still prints **73** and that `module.alb.aws_lb.main` has the
  expected `name`. A planning run against the wrong backend once produced a phantom
  "63 to destroy".
- **Terraform honours `AWS_PROFILE`, not a `--profile root` flag.** Unset both `AWS_PROFILE` and
  `AWS_PROFILE=root`-style overrides to apply as root.
- **Runners are slow and single-concurrency.** Jobs sit `pending`/`runner=none` for minutes.
- **ALB rollout takes ~9 minutes to report `COMPLETED`.** All services share one target group per
  environment and ECS waits for target deregistration. Tasks are `HEALTHY` long before.
- **Node URL is hardcoded** in `ansible/inventory/hosts.yml` (by oriax11) — breaks on re-provision.
- **`gitlab_url` for runners should stay a static IP** (`http://172.16.0.2`), not the public URL or a
  container IP. It survives re-provisioning; the others do not.

### Git habits that cost real time here

Both of these destroyed work during this project, and both failed **silently**:

- **`git reset --hard origin/main` discards uncommitted work.** It wiped a security fix once and a
  whole script another time, restoring whatever the remote happened to hold. If something is
  uncommitted, commit it before any reset — or stash deliberately.
- **`git fetch origin github` is not valid syntax.** It fails, prints a short `fatal`, and leaves
  the remote-tracking refs **stale**. A `reset --hard origin/main` immediately afterwards then trusts
  the stale ref and silently rolls you back. Fetch each remote in its own command, and check the ref
  moved.

The general lesson behind both: **distinguish "absent" from "could not look", and "denied" from
"empty result".** A tool that fails quietly will eventually be believed.

---

## 11. Credential locations — names only, never values

| Location | Holds |
|---|---|
| `~/.ck-aws-credentials` (0600) | `[code-keeper]` profile — the scoped CI key |
| `~/.ck-secrets` (0600) | `CK_GL_*`, `CK_DOCKERHUB_*` |
| `~/.git-credentials` (0600) | GitLab HTTPS credentials |
| AWS CLI credential store | account root, via `aws login` (**not** `~/.aws/credentials`) |
| GitLab project 8 CI variables | `TF_STATE_TOKEN`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `TF_VAR_*_password` ×3 (protected **and** masked) |
| AWS Secrets Manager | `staging/app-secrets`, `production/app-secrets` — the three DB/queue passwords |

To run Terraform locally you need the three `TF_VAR_*_password` values. They are not in any local
file; pull them from Secrets Manager into the environment and never print them.

**One credential leak happened, plus four exposures.** A `cat .terraform/terraform.tfstate` put a
Maintainer `api` token into a chat transcript; its 12-char suffix was then committed in
`docs/code-keeper-phase6-log.md`. The token was rotated. The suffix is still in that file — it is
not usable, but it should not have been written. **Extract single fields, never dump a file that
holds credentials.** A short-lived Cognito test token was also printed to the terminal during
verification on 2026-10-02; it was a 1-hour lab token, but the habit is the problem.

---

## 12. Document map

| Document | Contents |
|---|---|
| `docs/message.txt` | **authoritative** infra/CD design spec |
| `docs/NEW-MACHINE-SETUP.md` | standing up a new machine, and the traps |
| `docs/code-keeper-audit.md` | the original audit findings |
| `docs/code-keeper-plan.md` | master plan, phase status |
| `docs/code-keeper-phase6-log.md` | how the CD path was found broken and fixed |
| `docs/code-keeper-phase5-log.md` | app CI (build/test/scan/containerize) |
| `docs/HANDOVER.md` | this file |
| `infrastructure-configuration/iam/gitlab-ci-deploy/README.md` | CI IAM, permission by permission |
| `infrastructure-configuration/scripts/check-image-pins.sh` | the digest-pin drift guard |
| `infrastructure-configuration/scripts/pin-image.sh` | pins the deployed digest back into `.example` |
| `infrastructure-configuration/scripts/deploy-service.sh` | resolves tag→digest, then registers |