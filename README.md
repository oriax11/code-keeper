# Code-Keeper

Three Python microservices on AWS ECS Fargate behind an Application Load Balancer, provisioned by
**Terraform** and deployed exclusively through **GitLab CI**.

The whole design follows from one rule, taken from `docs/message.txt`:

> **App pipelines hold no AWS credentials.** They build, test, scan and containerize an image, then
> *trigger* the infrastructure repo with `APP_NAME` / `IMAGE_NAME` / `IMAGE_TAG`. The infra repo
> deploys exactly the named service, and only that service.

This repository is an **umbrella**: it contains the documentation and pins four submodules. It is not
deployed.

---

## Architecture

```
                              Internet
                                 |
                        +--------v---------+
                        |   ALB (HTTPS)    |  self-signed cert, :80 -> 301 -> :443
                        |  one target grp  |  target port 3000
                        +--------+---------+
                                 |
                        +--------v---------+
                        |   api-gateway    |  :3000  Flask - Cognito JWT - reverse proxy
                        +--------+---------+
                                 |
             +-------------------+-------------------+
             |                                       |
   proxy GET /<path>                      POST /api/billing/
   (valid JWT required)                          |
             |                                       |
   +---------v----------+               +--------v--------+
   |   inventory-app    |               |   rabbit-queue  |  :5672
   |       :8080        |               +--------+--------+
   |  Flask + SQLAlchemy|                        |  consumer
   +---------+----------+                        |
             |                          +--------v--------+
   +---------v----------+               |    billing-app   |  :8080
   |   inventory-db     |               |  Flask, no HTTP  |
   |      :5432         |               +--------+--------+
   |    PostgreSQL      |                        |
   +--------------------+               +--------v--------+
                                          |   billing-db    |
                                          |      :5432      |
                                          |    PostgreSQL   |
                                          +-----------------+

        Cognito user pool + app client  ->  issues the JWTs api-gateway verifies
```

**Request flow.** `GET /` is unauthenticated health. Everything under `/<path>` is proxied to
`inventory-app` **only after** a valid Cognito JWT — enforced by `api-gateway/app/proxy.py`.
`POST /api/billing/` publishes to RabbitMQ, where `billing-app` consumes it and writes to
`billing-db`. Authentication, proxying and the async billing path are three separate claims, each
verified independently — see [Verifying by hand](#verifying-by-hand).

---

## Repository layout

```
code-keeper/                     umbrella — docs only, not deployed
├── docs/                        design spec, handover, phase logs
├── infrastructure-configuration/ THE DEPLOYMENT CONTROLLER
├── inventory-app/
├── billing-app/
└── api-gateway/
```

Every submodule has **two** remotes, and the distinction matters:

| Remote | Points at | Role |
|---|---|---|
| `origin` | `code-keeper/<repo>` on **GitLab** | **Authoritative.** This is the deployment controller. |
| `github` | `0xlislim/<repo>` on GitHub | Mirror. Never authoritative. |

The umbrella exists **only** on GitHub (`oriax11/code-keeper`) — there is no umbrella project on
GitLab, so do not add an `origin` for it.

> **A fix that cannot be pushed to `origin` has not been made.** During this project a security fix
> was committed only to the mirror while GitLab was unreachable, then destroyed locally by a
> `git reset --hard origin/main`. It surfaced only when someone diffed `github/main` against
> `origin/main`. See `docs/HANDOVER.md` §6.

### GitLab projects

| id | Project | Role |
|---|---|---|
| 5 | `inventory-app` | app CI → triggers deploy |
| 6 | `billing-app` | app CI → triggers deploy |
| 7 | `api-gateway` | app CI → triggers deploy |
| 8 | `infrastructure-configuration` | **the deployment controller** |

`main` is protected on every project. All work goes through branches and merge requests.

---

## The two pipelines

### App CI — build → test → scan → containerize

Identical in all three app repos:

```
build → test → scan → containerize
```

Push to `main` and, if everything passes, the app **triggers** the infra repo with
`APP_NAME` / `IMAGE_NAME` / `IMAGE_TAG`. It cannot deploy anything itself — it holds no AWS
credentials.

> ⚠️ `scan` is currently `allow_failure: true`. Two HIGH CVEs once shipped inside a green pipeline.
> Whether findings should block is an open decision (`docs/HANDOVER.md` §9.1).

### Infra CD — the deployment controller

```
init → validate → plan → apply-staging → approval → apply-production
                                                  ↓
                              trigger-validate → deploy-staging
                                                  ↓
                                          pin-image → deploy-approval → deploy-production
```

`verify-image-pins` runs in the `plan` stage for both environments, and `plan-*` declare
`needs: [verify-image-pins]`, so an unpinned image fails the pipeline before anything is applied.

`deploy-staging` resolves the tag to a digest, re-registers **only** the named service's task
definition, waits for it to stabilize, then `pin-image.sh` writes the resulting digest back into the
tracked `.tfvars.example`.

Isolation is proven, not assumed: deploying `api-gateway` moved only `staging-api-gateway-service` to
a new revision while `inventory` and `billing` kept their images untouched.

---

## Image pinning

Images are pinned **by digest** in both the tfvars *and* the ECS task definitions.

- `.tfvars.example` is the **source of truth** — it is tracked, so drift is visible in review. The
  working `.tfvars` is gitignored and regenerated from it.
- `pin-image.sh` reads the digest back **out of the task definition the deploy just wrote**, not
  from the registry. Reading the registry would be a race — the tag can move between deploy and pin.
- `check-image-pins.sh` fails CI if any pin is a tag rather than a digest.

Tags proved mutable here: the tag `544e47e` resolved to two different digests on the same day.

---

## Environments

Two full stacks, provisioned by the same modules: `staging` and `production`.

| | staging | production |
|---|---|---|
| ALB | `staging-alb-2125783479.us-east-1.elb.amazonaws.com` | `production-alb-2141569501` |
| ECS cluster | `staging-cluster` | `production-cluster` |
| Cognito pool | `staging-user-pool` / `us-east-1_bPoDPlAhf` | `production-user-pool` / `us-east-1_u8ECIdGkF` |
| Cognito client | `staging-app-client` | `production-app-client` |
| Secret | `staging/app-secrets` | `production/app-secrets` |
| Terraform resources | 73 | 73 |

Live task definitions — **all images digest-pinned**:

| Service | staging | production |
|---|---|---|
| `staging-api-gateway-service` | 2/2 · `staging-api-gateway:4` | 2/2 · `production-api-gateway:2` |
| `staging-inventory-service` | 2/2 · `staging-inventory:1` | 2/2 · `production-inventory:1` |
| `staging-billing-service` | 2/2 · `staging-billing:3` | 2/2 · `production-billing:1` |
| `rabbit-queue`, `inventory-db`, `billing-db` | 1/1 each | 1/1 each |

Terraform is pinned to **exactly 1.10.5**, matching CI. A newer local Terraform changes plan
behaviour and can disagree with CI.

Both ALBs present a **self-signed** certificate and `301` HTTP→HTTPS. There is no domain to obtain a
real certificate from, so `curl` needs `-k`. This is a lab constraint, documented rather than hidden
— an auditor will notice it.

---

## Quick start

```bash
git clone git@github.com:oriax11/code-keeper.git ~/code-keeper
cd ~/code-keeper && git submodule update --init --recursive

cd ~/code-keeper/infrastructure-configuration
GITLAB_HOST=<current-node-url> ./scripts/bootstrap-new-machine.sh
```

Flags: `--skip-install`, `--skip-clone`, `--verify-only`.

> ⚠️ **The GitLab node URL is ephemeral and changes constantly** — this lab node has been
> re-provisioned at least five times. A dead node surfaces as
> `Failed to load state: HTTP remote state endpoint invalid auth`, which looks exactly like a
> credential problem and is not one. **Check the URL first.** Get it from whoever runs the lab.

Full instructions, credential locations and the traps that have cost real time:
**[`docs/NEW-MACHINE-SETUP.md`](docs/NEW-MACHINE-SETUP.md)**.

### What "verified" looks like

The bootstrap's final step must print all of these:

```
OK   terraform state: 73 resources (expected 73)
OK   AWS identity: arn:aws:iam::006631837921:user/gitlab-ci-deploy
OK   root available via 'aws login' (arn:aws:iam::006631837921:root)
OK   ecs:ListClusters allowed
OK   logs:DescribeLogGroups allowed
OK   secretsmanager:DescribeSecret allowed
OK   cognito-idp:DescribeUserPool allowed
OK   ec2:DescribeVpcs allowed
OK   ec2:CreateVpc correctly DENIED
     ck-deploy        match
     ck-deploy-reads  match
     ck-plan-reads    match (version v4)
```

**`ec2:CreateVpc correctly DENIED` is the one that matters.** If it ever reads `ALLOWED`, the CI
identity can provision infrastructure and the entire least-privilege design is void.

---

## Verifying by hand

Both scripts live in `infrastructure-configuration/scripts/`, both default to staging and take
`--env production`, and both are idempotent.

```bash
./scripts/create-test-user.sh --env staging     # prints an AccessToken to stdout
./scripts/test-api-as-user.sh --env production  # asserts behaviour, exits non-zero on failure
```

`test-api-as-user.sh` asserts four things:

| Check | Expected | Why it matters |
|---|---|---|
| `GET /` | 200 | health, unauthenticated by design |
| `GET /api/movies` **without** a token | **401** | proves the JWT gate is real, not decorative |
| `GET /api/movies` **with** a token | 200 | proves auth works *and* the proxy reaches inventory |
| `POST /api/billing/` with a token | 200 | proves the RabbitMQ path end to end |

The 401-then-200 pair is the whole point: authentication is enforced **and** a legitimate user gets
through. The 401 was confirmed to have teeth — garbage tokens, empty `Bearer` headers and
tampered-signature tokens are all rejected. A 401 assertion that would also pass on a 200 is
worthless.

Tokens go to **stdout only**; everything human-readable goes to stderr, so a token never lands in a
file, in shell history, or in a CI log.

---

## Security model

**CI identity:** `arn:aws:iam::006631837921:user/gitlab-ci-deploy`

| Policy | Type | Purpose |
|---|---|---|
| `ck-deploy` | inline | ECS deploy + `iam:PassRole`, scoped to ECS ARNs |
| `ck-deploy-reads` | inline | discovery calls |
| `ck-plan-reads` | customer-managed, **v4** | everything `terraform refresh` reads |

No permissions boundary. No group memberships. **`AdministratorAccess` is not attached.**

This identity can **deploy to production but cannot build production.** It cannot create a VPC,
cluster, IAM role or secret. Verified denied: `ec2:CreateVpc`, `iam:CreateRole`,
`cloudwatch:PutDashboard`, `secretsmanager:PutSecret`.

> **`apply-production` failing in CI is the expected steady state**, not a regression. Anyone reading
> the pipeline and seeing a red `apply-production` should be told this before they go looking for a
> bug.

`ck-plan-reads` is at **v4** because each version was forced by a pipeline failing on an
`AccessDenied` naming one missing action. That history is the evidence the policy stayed
least-privilege — read it before widening anything.

The policies are committed under `infrastructure-configuration/iam/gitlab-ci-deploy/` with a README
giving the rationale per permission. They are still **applied by hand**; `bootstrap-new-machine.sh`
diffs repo against live and reports drift, warning and continuing, failing only on genuinely missing
permissions.

---

## Traps worth knowing before you touch anything

These are documented in full in `docs/HANDOVER.md` §10 and `docs/NEW-MACHINE-SETUP.md` §6. Each one
has already cost real time here.

1. **The GitLab node URL rots.** See above. The most likely thing to be stale on any given day.
2. **`terraform init -reconfigure` discards the cached backend config.** `backend.tf` is
   deliberately empty, so **all seven `-backend-config` values must be passed together** or it fails
   with `address argument is required`.
3. **A wrong backend `address` silently initialises against brand-new empty state.** A later `apply`
   would try to create the entire stack again. After **every** re-init, confirm
   `terraform state list | wc -l` still prints **73** and that `module.alb.aws_lb.main` has the
   expected `name`.
4. **The AWS CLI credential store beats `AWS_SHARED_CREDENTIALS_FILE`.** After `aws login`, a bare
   `aws ...` authenticates as **root** even with the env var pointing at the scoped key. This caused
   a real incident: a "confirm this is denied" probe ran as root and **created a stray VPC**. Always
   name the profile: `aws ... --profile code-keeper`.
5. **Terraform honours `AWS_PROFILE`, not a `--profile` flag.** To apply as root, unset both.
6. **`trigger:variables` does not expand** file-scoped variables — it sends the literal text
   `$IMAGE_NAME`. `$CI_COMMIT_SHA` and `trigger:project:` *do* expand. Inconsistent, and now guarded.
7. **`register-task-definition` rebuilds the task**, so every task-level field Terraform set must be
   supplied again. `cpu`/`memory` live at the task level; containers carry none.
8. **`git reset --hard origin/main` discards uncommitted work, silently.** It destroyed a security
   fix and a whole script during this project. Commit or stash deliberately first.
9. **`git fetch origin github` is invalid syntax.** It fails with a short `fatal` and leaves
   remote-tracking refs **stale** — a `reset --hard origin/main` right after then rolls you back
   silently. Fetch each remote in its own command and confirm the ref moved.

The general lesson behind 8 and 9: **distinguish "absent" from "could not look", and "denied" from
"empty result".** A tool that fails quietly will eventually be believed.

---

## Documentation

| Document | Contents |
|---|---|
| [`docs/ARCHITECTURE-DIAGRAMS.md`](docs/ARCHITECTURE-DIAGRAMS.md) | **colour-coded Mermaid diagrams + an audit checklist** |
| [`docs/message.txt`](docs/message.txt) | **authoritative** infra/CD design spec |
| [`docs/HANDOVER.md`](docs/HANDOVER.md) | current state — read this first to pick the project up cold |
| [`docs/NEW-MACHINE-SETUP.md`](docs/NEW-MACHINE-SETUP.md) | standing up a new machine, and the traps |
| [`docs/code-keeper-plan.md`](docs/code-keeper-plan.md) | master plan, phase status |
| [`docs/code-keeper-audit.md`](docs/code-keeper-audit.md) | original audit findings |
| [`docs/code-keeper-phase*-log.md`](docs/) | how the CD path was found broken, and fixed |
| `infrastructure-configuration/iam/gitlab-ci-deploy/README.md` | CI IAM, permission by permission |
| `infrastructure-configuration/scripts/check-image-pins.sh` | the digest-pin drift guard |
| `infrastructure-configuration/scripts/pin-image.sh` | pins the deployed digest back into `.example` |
| `infrastructure-configuration/scripts/deploy-service.sh` | resolves tag→digest, then registers |

---

## Open items

Tracked in full, in priority order, in `docs/HANDOVER.md` §9. The ones that matter most:

- `scan` is `allow_failure: true` — decide whether findings should block
- `inventory` has never run the CD path; its task definition is still `:1` in both environments
- a second, unrelated administrator identity (`cloud-design-deployer`) holds `AdministratorAccess`
  with a live access key, idle since 2026-09-17. Not used by this project, **not deleted**
  pending a decision — recommended order is revoke the key first, then the user
- four AWS/GitLab credentials from earlier transcripts were never rotated
- Terraform should own the CI IAM user (needs a bootstrap root module, since the user must exist
  before Terraform can run)
- `urllib3` is pinned only in `api-gateway`; `inventory` and `billing` resolve it transitively

---

## Cost

Staging is left running deliberately at roughly **$5.40/day (~$162/month)** — 9 Fargate tasks 24/7
(~$3.75), a NAT gateway (~$1.08), and the ALB (~$0.54).

```bash
./scripts/destroy-all.sh --plan     # read-only: shows what WOULD be destroyed
```

**`destroy-all.sh` is destructive by default.** Use `--plan`.

---

*Verified against live AWS and GitLab on 2026-10-02. Figures above — 73 resources per environment,
task definition revisions, digest pinning and IAM policy state — were read from the live
infrastructure, not copied from documentation.*