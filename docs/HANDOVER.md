# Handover — Code-Keeper

**Written:** 2026-10-01
**Purpose:** pick this project up cold, on any machine, without reading the full transcript.

Read this first, then `docs/NEW-MACHINE-SETUP.md` to stand a new machine up.

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
(`d1d94d → 098e3d → d79464 → gone`). Get the current URL before doing anything.

Group `code-keeper`:

| id | Project | Role |
|---|---|---|
| 5 | `inventory-app` | app CI → triggers deploy |
| 6 | `billing-app` | app CI → triggers deploy |
| 7 | `api-gateway` | app CI → triggers deploy |
| 8 | `infrastructure-configuration` | **the deployment controller** |

`/groups/10/merge_requests` returns 404 — use per-project endpoints.

Note: group id 10 is not `/groups/10`. Per-project MR endpoints only.

### AWS

Account `006631837921`, region `us-east-1`.

### Remotes — each submodule has two

```
origin  -> GitLab   (authoritative)
github  -> git@github.com:0xlislim/<repo>.git   (mirror)
```

The **umbrella** exists only on GitHub (`git@github.com:oriax11/code-keeper.git`). There is no
umbrella project on GitLab — do not add an `origin` to it.

`main` is **protected** on GitLab. Direct pushes are refused; work goes through branches and MRs.

---

## 3. Live staging state

Cluster `staging-cluster`, 73 Terraform resources. Verified 2026-10-01:

| Service | Replicas | Task def | Image |
|---|---|---|---|
| `staging-inventory-service` | 2/2 `COMPLETED` | `staging-inventory:1` | `@sha256:69a0ee72…` |
| `staging-billing-service` | 2/2 `COMPLETED` | `staging-billing:1` | `@sha256:38a13852…` |
| `staging-api-gateway-service` | 2/2 `COMPLETED` | **`staging-api-gateway:2`** | `:544e47e5…` (CD-deployed) |
| `staging-rabbit-queue` | 1/1 `COMPLETED` | — | — |
| `staging-inventory-db` | 1/1 `COMPLETED` | — | — |
| `staging-billing-db` | 1/1 `COMPLETED` | — | — |

Supporting: ALB `staging-alb-2125783479.us-east-1.elb.amazonaws.com` (HTTP→HTTPS `301`),
EFS `staging-efs`, Cognito `staging-user-pool` (`us-east-1_bPoDPlAhf`), secret `staging/app-secrets`,
one NAT gateway.

**Production has never been applied.** No production resources exist. `apply-production` is
expected to fail with `AccessDenied` — that is the design, not a defect.

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

**All three are fixed.** The path is proven end to end, including §11 isolation:

> Deploying `api-gateway` moved **only** `staging-api-gateway-service` to revision `:2`.
> `inventory` and `billing` stayed on `:1` with unchanged images.

That was the central unproven claim of Phase 6. It is now demonstrated.

Two traps worth remembering, both hit for real:

- **`trigger:variables` does not expand** file-scoped variables. It sends the literal text
  `$IMAGE_NAME`. `test -n` accepted it (a 12-character string is non-empty) and
  `[ "$X" != "latest" ]` accepted it too. Every guard passed; ECS rejected it.
  `$CI_COMMIT_SHA` **does** expand. `trigger:project:` **does** expand.
- **`register-task-definition` rebuilds the task**, so every task-level field Terraform set must be
  supplied again. `cpu`/`memory` live at the task level here; the containers carry none.

---

## 5. ⚠️ Open conflict: Terraform pins digests, CD deploys SHA tags

`staging.tfvars` pins:

```
api_gateway_image = "docker.io/1ee5lim/api-gateway-app@sha256:350d1571…"
```

but the running service now uses `:544e47e5…`.

**The next `apply-staging` will revert every CD deploy.** `plan-staging` will stop reporting
`No changes` and will show the task definition drifting back to the pinned digest.

Digest pinning and per-commit CD are structurally incompatible. The options — have CD write the
new digest back into tfvars, or stop letting Terraform manage the app image — have real
trade-offs. **This needs a deliberate decision before the next infra apply.** It was not resolved
unilaterally.

---

## 6. CI identity

`arn:aws:iam::006631837921:user/gitlab-ci-deploy`

| Policy | Type |
|---|---|
| `ck-deploy` | inline — ECS deploy + `iam:PassRole` on `*ecs*` |
| `ck-deploy-reads` | inline — discovery calls |
| `ck-plan-reads` | customer-managed, **v4** — everything `terraform refresh` reads |

No permissions boundary. No group memberships. `AdministratorAccess` **not** attached.

### ⚠️ A second, unrelated administrator identity exists in the account

`cloud-design-deployer` — created 2026-09-11 by the original project's
`scripts/bootstrap-iam.sh` — holds **`AdministratorAccess`** and has an **active access key**
(`AKIAQDC2J2DQRWRLT2E5`). Last CloudTrail activity 2026-09-17, i.e. it has been idle since.

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
attached `AdministratorAccess` when run bare. Fixed on 2026-10-01: the default is now `scoped`, and
`admin` requires typing `yes-i-understand`.

Verified denied: `ec2:CreateVpc`, `iam:CreateRole`, `cloudwatch:PutDashboard`,
`secretsmanager:PutSecret`.

These policies were originally created by hand and are **not** in Terraform. They are now
committed under `infrastructure-configuration/iam/gitlab-ci-deploy/` with a README giving the
rationale for each permission, and `bootstrap-new-machine.sh` diffs repo vs live and reports drift.

`ck-plan-reads` reached **v4** because each version was forced by a pipeline failing on an
`AccessDenied` naming one missing action. That history is the evidence the policy stayed
least-privilege — worth reading before widening anything.

---

## 7. Credential locations — names only, never values

| Location | Holds |
|---|---|
| `~/.ck-aws-credentials` (0600) | `[code-keeper]` profile — the scoped CI key |
| `~/.ck-secrets` (0600) | `CK_GL_*`, `CK_DOCKERHUB_*` |
| `~/.git-credentials` (0600) | GitLab HTTPS credentials |
| AWS CLI credential store | account root, via `aws login` (**not** `~/.aws/credentials`) |
| GitLab project 8 CI variables | `TF_STATE_TOKEN`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `TF_VAR_*_password` |

**One credential leak happened.** A `cat .terraform/terraform.tfstate` put a Maintainer `api`
token into a chat transcript; its 12-char suffix was then committed in
`docs/code-keeper-phase6-log.md`. The token was rotated. The suffix is still in that file — it is
not usable, but it should not have been written. Extract single fields, never dump a file that
holds credentials.

---

## 8. Open items, in priority order

1. ⬜ **Resolve the digest-pin vs SHA-tag conflict** (§5). Blocks the next `apply-staging`.
2. ⬜ **`scan` has `allow_failure: true`** in all three apps. Two HIGH CVEs shipped inside a green
   pipeline on 2026-09-30. Decide whether findings should block.
3. ⬜ **Deploy `inventory` and `billing`** via the CD path. Only `api-gateway` has actually run it;
   the other two share the code path but are unproven.
4. ⬜ **Production apply** — held behind two manual gates; roughly doubles running cost.
5. ⬜ **`destroy-all.sh --plan`** when staging is no longer needed. Default mode is destructive.
6. ⬜ **Terraform should own the CI IAM user.** Currently hand-created, which is the root of the
   drift problem. Needs a separate bootstrap root module, since the user must exist before
   Terraform can run.
7. ⬜ **Infra images are pinned but not reproducible** — `tools/setup_db.sh` and
   `tools/setup_rq.sh` were never committed (requested from oriax11). 17 CRITICAL / 94 HIGH
   findings in those images are knowingly retained.

---

## 9. Known environmental quirks

- **GitLab node URL changes constantly.** See `NEW-MACHINE-SETUP.md` §0. A dead node surfaces as
  `HTTP remote state endpoint invalid auth`, which looks like a credential problem and is not.
- **Runners are slow and single-concurrency.** Jobs sit `pending`/`runner=none` for minutes.
- **ALB rollout takes ~9 minutes to report `COMPLETED`.** All three services share one target
  group (`staging-app`) and ECS waits for target deregistration. Tasks are `HEALTHY` long before.
- **Node URL is hardcoded** in `ansible/inventory/hosts.yml` (by oriax11) — breaks on re-provision.
- **`gitlab_url` for runners should stay a static IP** (`http://172.16.0.2`), not the public URL
  or a container IP. It survives re-provisioning; the others do not.

---

## 10. Document map

| Document | Contents |
|---|---|
| `docs/code-keeper-plan.md` | master plan, phase status |
| `docs/code-keeper-phase6-log.md` | how the CD path was found broken and fixed |
| `docs/code-keeper-phase5-log.md` | app CI (build/test/scan/containerize) |
| `docs/message.txt` | **authoritative** infra/CD design spec |
| `docs/NEW-MACHINE-SETUP.md` | standing up a new machine |
| `docs/HANDOVER.md` | this file |
| `infrastructure-configuration/iam/gitlab-ci-deploy/README.md` | CI IAM, permission by permission |