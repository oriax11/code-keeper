# Code-Keeper

Three Python microservices on AWS ECS Fargate behind an Application Load Balancer, provisioned by **Terraform** and deployed exclusively through **GitLab CI**.

The whole design follows from one rule, taken from `docs/design.md`:

> **App pipelines hold no AWS credentials.** They build, test, scan and containerize an image, then *trigger* the infrastructure repo with `APP_NAME` / `IMAGE_NAME` / `IMAGE_TAG`. The infra repo deploys exactly the named service, and only that service.

This repository is an **umbrella**: it contains the documentation and pins four submodules. It is not deployed.

---

## Table of contents

- [Architecture](#architecture)
- [Repository layout](#repository-layout)
- [The two pipelines](#the-two-pipelines)
- [Who owns the container image](#who-owns-the-container-image)
- [Environments](#environments)
- [Recreating the project](#recreating-the-project)
- [Quick start](#quick-start)
- [Verifying by hand](#verifying-by-hand)
- [Security model](#security-model)
- [Traps worth knowing before you touch anything](#traps-worth-knowing-before-you-touch-anything)
- [Documentation](#documentation)
- [Open items](#open-items)
- [Cost](#cost)

---

## Architecture

```text
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
   +---------v----------+               |   billing-app   |  :8080
   |    inventory-db    |               |  Flask, no HTTP |
   |       :5432        |               +--------+--------+
   |     PostgreSQL     |                        |
   +--------------------+               +--------v--------+
                                        |   billing-db    |
                                        |      :5432      |
                                        |   PostgreSQL    |
                                        +-----------------+

        Cognito user pool + app client  ->  issues the JWTs api-gateway verifies
```

**Request flow.** `GET /` is unauthenticated health. Everything under `/<path>` is proxied to `inventory-app` **only after** a valid Cognito JWT, enforced by `api-gateway/app/proxy.py`. `POST /api/billing/` publishes to RabbitMQ, where `billing-app` consumes it and writes to `billing-db`. Authentication, proxying and the async billing path are three separate claims, each verified independently. See [Verifying by hand](#verifying-by-hand).

---

## Repository layout

```text
code-keeper/                      umbrella: docs only, not deployed
├── docs/                         design spec, handover, phase logs
├── infrastructure-configuration/ THE DEPLOYMENT CONTROLLER
├── inventory-app/
├── billing-app/
└── api-gateway/
```

Every submodule has **two** remotes, and the distinction matters:

| Remote   | Points at                  | Role                                                     |
|----------|----------------------------|----------------------------------------------------------|
| `origin` | `code-keeper/<repo>` on **GitLab** | **Authoritative.** This is the deployment controller. |
| `github` | `0xlislim/<repo>` on GitHub        | Mirror. Never authoritative.                          |

The umbrella exists **only** on GitHub (`oriax11/code-keeper`). There is no umbrella project on GitLab, so do not add an `origin` for it.

> **A fix that cannot be pushed to `origin` has not been made.** During this project a security fix was committed only to the mirror while GitLab was unreachable, then destroyed locally by a `git reset --hard origin/main`. It surfaced only when someone diffed `github/main` against `origin/main`.

### GitLab projects

| id | Project                        | Role                            |
|----|--------------------------------|---------------------------------|
| 5  | `inventory-app`                | app CI → triggers deploy        |
| 6  | `billing-app`                  | app CI → triggers deploy        |
| 7  | `api-gateway`                  | app CI → triggers deploy        |
| 8  | `infrastructure-configuration` | **the deployment controller**   |

`main` is protected on every project. All work goes through branches and merge requests.

---

## The two pipelines

### App CI: build → test → scan → containerize

Identical in all three app repos:

```text
build → test → scan → containerize
```

Push to `main` and, if everything passes, the app **triggers** the infra repo with `APP_NAME` / `IMAGE_NAME` / `IMAGE_TAG`. It cannot deploy anything itself, because it holds no AWS credentials.

> ⚠️ `scan` is currently `allow_failure: true`. Two HIGH CVEs once shipped inside a green pipeline. Whether findings should block is an open decision.

### Infra CD: the deployment controller

Infrastructure pipeline:

```text
init → validate → plan → apply-staging → approval → apply-production
```

Deploy path (triggered by an app pipeline):

```text
trigger-validate → deploy-staging → deploy-approval → deploy-production
```

`deploy-staging` resolves the tag to a digest, re-registers **only** the named service's task
definition, waits for it to stabilize, then asserts the service actually runs the digest it intended.
`deploy-approval` is a manual gate before production.

Isolation is proven, not assumed: deploying `api-gateway` moved only `staging-api-gateway-service` to a new revision while `inventory` and `billing` kept their images untouched.

---

## Who owns the container image

**CD owns it.** Terraform creates the ECS service and then ignores `container_definitions` for the
rest of its life:

```hcl
lifecycle { ignore_changes = [container_definitions] }
```

That single line is what stops the two systems fighting. Terraform will not revert a CD deploy,
because it no longer considers the image something it manages.

This replaced an earlier scheme in which the deployed digest was written back into
`.tfvars.example` by `pin-image.sh` and policed by `check-image-pins.sh`. Both are removed. They
failed repeatedly in ways that were hard to see:

- `pin-image.sh` used `diff`, which the CI image does not contain — it exited 127, printed nothing,
  and the change-count guard read that empty output as "0 lines changed".
- It then used `git`, which the CI image also does not contain. One run failed hard; another
  **succeeded**, because `git status` failing returned empty output and the job's "did anything
  change?" test read empty as "no changes".
- A `terraform apply` running between deploy and pin reverted the task definition, and the pin
  recorded that reverted digest as truth — a rollback made to look deliberate.

Three failures, one root cause: commands that were never executed in the image CI actually used.
Assigning ownership to a single actor removes the conflict instead of policing it.

The digest is still resolved from the registry and written into the task definition, so every running
task is pinned to immutable bytes. What is gone is the second writer.

---

## Environments

Two full stacks, provisioned by the same modules: `staging` and `production`.

|                     | staging                                               | production                                        |
|---------------------|-------------------------------------------------------|---------------------------------------------------|
| ALB                 | `staging-alb-2125783479.us-east-1.elb.amazonaws.com`  | `production-alb-2141569501`                       |
| ECS cluster         | `staging-cluster`                                     | `production-cluster`                              |
| Cognito pool        | `staging-user-pool` / `us-east-1_bPoDPlAhf`           | `production-user-pool` / `us-east-1_u8ECIdGkF`    |
| Cognito client      | `staging-app-client`                                  | `production-app-client`                           |
| Secret              | `staging/app-secrets`                                 | `production/app-secrets`                          |
| Terraform resources | 73                                                    | 73                                                |

Live task definitions, every image digest-pinned:

| Service                                 | staging                          | production                          |
|-----------------------------------------|----------------------------------|-------------------------------------|
| `staging-api-gateway-service`           | 2/2 · `staging-api-gateway:4`    | 2/2 · `production-api-gateway:2`    |
| `staging-inventory-service`             | 2/2 · `staging-inventory:12`     | 2/2 · `production-inventory:6`     |
| `staging-billing-service`               | 2/2 · `staging-billing:3`        | 2/2 · `production-billing:1`        |
| `staging-rabbit-queue`                  | 1/1 · `:1`                       | 1/1 · `production-rabbit-queue:1`  |
| `staging-inventory-db` / `-billing-db`  | 1/1 · `:1` each                  | 1/1 · `:1` each                     |

`inventory`'s high revision count is the record of it running the CD path in both environments —
it is the only service that has done so in production.

Terraform is pinned to **exactly 1.10.5**, matching CI. A newer local Terraform changes plan behaviour and can disagree with CI.

Both ALBs present a **self-signed** certificate and `301` HTTP→HTTPS. There is no domain to obtain a real certificate from, so `curl` needs `-k`. This is a lab constraint, documented rather than hidden. An auditor will notice it.

---

## Recreating the project

This project has two distinct layers:

1. **Iximiuz Playground** provides the temporary Linux machines used to host GitLab and the GitLab Runner.
2. **AWS** provides the application infrastructure deployed by the GitLab infrastructure pipeline.

The Iximiuz machines are a **lab control plane**, not part of the AWS application architecture. The GitLab node stores the Git repositories and coordinates CI/CD; the runner executes the pipelines and uses Docker for the jobs.

### 1. Iximiuz Playground

The project was developed and tested using an Iximiuz Playground environment. The machine manifest creates two machines:

| Playground machine | Group           | Purpose                              |
|--------------------|-----------------|--------------------------------------|
| `gitlab-01`        | `gitlab`        | GitLab EE server and GitLab API      |
| `runner-01`        | `gitlab_runner` | GitLab Runner with Docker executor   |

The Ansible inventory used by the project maps these machines to the corresponding groups:

```text
gitlab
└── gitlab-01

gitlab_runner
└── runner-01
```

The machines are intentionally separated. GitLab is the control plane while the runner is the execution host.

> **Iximiuz URLs are ephemeral.** A Playground re-provision can change the GitLab hostname. Any command or Git remote containing an old `node-*.iximiuz.com` hostname must be updated after the machine is recreated.

### 2. GitLab machine

`gitlab-01` was provisioned as an Ubuntu 24.04 (Noble) machine.

The GitLab installation is managed through the Ansible role:

```text
infrastructure-configuration/
└── ansible/
    ├── inventory
    ├── gitlab.yml
    ├── group_vars/
    │   └── all/
    │       └── gitlab.yml
    └── roles/
        ├── gitlab/
        └── gitlab_runner/
```

The GitLab role configures:

- GitLab EE `19.4.1`
- the current Iximiuz external URL
- HTTP on port `80`
- HTTPS disabled inside the lab
- forwarded proxy headers
- GitLab API access used by the runner/bootstrap automation

The external URL is deliberately supplied from the current Playground node rather than hard-coded, because the node can be recreated.

Example:

```bash
export GITLAB_HOST="https://<current-iximiuz-gitlab-host>"
```

Then run the Ansible playbook from the infrastructure repository:

```bash
cd ~/code-keeper/infrastructure-configuration/ansible

ansible-playbook -i inventory gitlab.yml
```

If the lab has been recreated, update the GitLab URL variables first and rerun the playbook rather than manually repairing the GitLab installation.

### 3. GitLab projects

The GitLab instance contains four projects:

| Project                        | Purpose                                      |
|--------------------------------|----------------------------------------------|
| `inventory-app`                | Inventory microservice and application CI    |
| `billing-app`                  | Billing microservice and application CI      |
| `api-gateway`                  | API gateway and application CI               |
| `infrastructure-configuration` | Terraform/Ansible deployment controller      |

They are grouped under:

```text
Code Keeper
└── code-keeper
    ├── inventory-app
    ├── billing-app
    ├── api-gateway
    └── infrastructure-configuration
```

The relevant GitLab project paths are therefore:

```text
code-keeper/inventory-app
code-keeper/billing-app
code-keeper/api-gateway
code-keeper/infrastructure-configuration
```

The project configuration used for the lab includes:

- private projects
- protected `main`
- merge-request based changes
- application repositories triggering the infrastructure repository
- the infrastructure repository acting as the deployment controller

The project users configured for the lab were:

| User        | Access level |
|-------------|--------------|
| `yaouzddou` | Maintainer   |
| `aesslima`  | Developer    |

`main` is protected, so normal work happens through branches and merge requests.

### 4. GitLab Runner machine

`runner-01` is the separate CI execution machine.

The runner stack used by the project is:

```text
Ubuntu
└── Docker 29.7.2
    └── GitLab Runner 19.4.1
```

The runner uses the **Docker executor** and is configured with the project tags:

```text
code-keeper
docker
```

The runner is registered as a project runner for the application/infrastructure repositories. Docker-in-Docker operations require the runner to use privileged mode.

The Ansible role responsible for this machine is:

```text
roles/gitlab_runner/
```

After provisioning the runner machine:

```bash
cd ~/code-keeper/infrastructure-configuration/ansible

ansible-playbook -i inventory gitlab.yml
```

Runner registration is performed against the current GitLab instance. Do not reuse an old runner registration after an Iximiuz node has been destroyed and recreated: the old registration can remain visible in GitLab even though its local authentication is no longer valid.

To inspect local runners:

```bash
sudo gitlab-runner list
```

To inspect the GitLab-side state, use the GitLab UI/API and remove stale project runners before registering replacements.

### 5. GitLab runner registration model

The project does not rely on a permanent runner token embedded in the repository.

The automation creates project runners through the GitLab API and then registers the returned authentication token locally.

The important properties are:

```text
runner_type = project_type
run_untagged = false
locked = true
tags = code-keeper,docker
```

This keeps jobs attached to the intended runner instead of allowing arbitrary untagged jobs to consume it.

When recreating the lab, treat the GitLab runner as disposable:

```text
new Iximiuz GitLab
        │
        ├── create/verify GitLab projects
        │
        └── create/register new project runners
                         │
                         └── new local runner configuration
```

Do not assume runner IDs from the previous Playground instance are reusable.

### 6. Clone the complete project

The umbrella repository is hosted on GitHub. The four operational repositories are Git submodules.

The shortest way to recreate the working tree is:

```bash
git clone --recurse-submodules \
  git@github.com:oriax11/code-keeper.git \
  ~/code-keeper

cd ~/code-keeper
```

If the repository was already cloned without submodules:

```bash
cd ~/code-keeper

git submodule sync --recursive
git submodule update --init --recursive
```

Verify the complete tree:

```bash
git submodule status --recursive
```

Expected layout:

```text
~/code-keeper/
├── docs/
├── infrastructure-configuration/
├── inventory-app/
├── billing-app/
└── api-gateway/
```

### 7. Git remotes and submodules

The umbrella repository is GitHub-only:

```text
oriax11/code-keeper
```

Each operational submodule has two remotes:

```text
origin  -> current Code Keeper GitLab project
github  -> 0xlislim/<repo> GitHub mirror
```

`origin` is authoritative for the deployment workflow.

Check every submodule:

```bash
git submodule foreach --recursive '
  echo "=== $name ==="
  git remote -v
'
```

The expected model is:

```text
inventory-app
  origin  -> GitLab / code-keeper/inventory-app
  github  -> GitHub / 0xlislim/inventory-app

billing-app
  origin  -> GitLab / code-keeper/billing-app
  github  -> GitHub / 0xlislim/billing-app

api-gateway
  origin  -> GitLab / code-keeper/api-gateway
  github  -> GitHub / 0xlislim/api-gateway

infrastructure-configuration
  origin  -> GitLab / code-keeper/infrastructure-configuration
  github  -> GitHub / 0xlislim/infrastructure-configuration
```

The GitLab hostname is the part that changes when the Playground is recreated.

For a new hostname, update the GitLab remote in each submodule:

```bash
export GITLAB_HOST="https://<current-iximiuz-gitlab-host>"

git -C infrastructure-configuration remote set-url origin \
  "$GITLAB_HOST/code-keeper/infrastructure-configuration.git"

git -C inventory-app remote set-url origin \
  "$GITLAB_HOST/code-keeper/inventory-app.git"

git -C billing-app remote set-url origin \
  "$GITLAB_HOST/code-keeper/billing-app.git"

git -C api-gateway remote set-url origin \
  "$GITLAB_HOST/code-keeper/api-gateway.git"
```

Verify:

```bash
git submodule foreach --recursive 'git remote -v'
```

Do **not** add a GitLab `origin` to the umbrella repository. Its authoritative copy is:

```text
git@github.com:oriax11/code-keeper.git
```

### 8. Recreate the infrastructure repository

Once the GitLab machine is available and the submodule remotes point to it:

```bash
cd ~/code-keeper/infrastructure-configuration
```

The repository contains the Ansible configuration used to rebuild the GitLab/runner lab and the Terraform configuration used for AWS.

For a fresh machine, the bootstrap helper can be used:

```bash
GITLAB_HOST="$GITLAB_HOST" ./scripts/bootstrap-new-machine.sh
```

Available modes:

```bash
./scripts/bootstrap-new-machine.sh --skip-install
./scripts/bootstrap-new-machine.sh --skip-clone
./scripts/bootstrap-new-machine.sh --verify-only
```

Use `--verify-only` after repairing or recreating a lab node to check the environment without repeating the installation.

### 9. Recreate the complete workflow

The intended order is:

```text
1. Create Iximiuz Playground machines
       │
       ├── gitlab-01
       └── runner-01
       │
2. Configure GitLab with Ansible
       │
3. Configure/register GitLab Runner
       │
4. Clone umbrella repository with submodules
       │
5. Point submodule origin remotes at the new GitLab hostname
       │
6. Verify GitLab projects/users/protected branches
       │
7. Push/update application repositories
       │
8. Run application CI
       │
9. Application pipeline triggers infrastructure-configuration
       │
10. Infrastructure pipeline plans/applies AWS
       │
11. Verify the affected ECS service
```

This separation is important: **Iximiuz provides the GitLab CI control plane; AWS provides the deployed application platform.**

### 10. Fresh-clone command sequence

For a completely new working directory, the core sequence is:

```bash
# 1. Clone the umbrella and all submodules
git clone --recurse-submodules \
  git@github.com:oriax11/code-keeper.git \
  ~/code-keeper

cd ~/code-keeper

# 2. Make sure all nested submodules are present
git submodule sync --recursive
git submodule update --init --recursive

# 3. Set the current Iximiuz GitLab hostname
export GITLAB_HOST="https://<current-iximiuz-gitlab-host>"

# 4. Point operational repositories at the new GitLab
git -C infrastructure-configuration remote set-url origin \
  "$GITLAB_HOST/code-keeper/infrastructure-configuration.git"

git -C inventory-app remote set-url origin \
  "$GITLAB_HOST/code-keeper/inventory-app.git"

git -C billing-app remote set-url origin \
  "$GITLAB_HOST/code-keeper/billing-app.git"

git -C api-gateway remote set-url origin \
  "$GITLAB_HOST/code-keeper/api-gateway.git"

# 5. Verify repository structure and remotes
git submodule status --recursive
git submodule foreach --recursive 'git remote -v'

# 6. Enter the infrastructure repository
cd infrastructure-configuration

# 7. Verify/bootstrap the current lab machine
GITLAB_HOST="$GITLAB_HOST" ./scripts/bootstrap-new-machine.sh
```

After this, configure the current GitLab/Runner credentials required by the infrastructure repository and verify the GitLab API, runner, Terraform backend, and AWS identity before attempting a deployment.

> **Important:** the commands above recreate the repository and lab control plane, but they do not recreate AWS resources from nothing unless the Terraform backend and AWS credentials/state described by `docs/NEW-MACHINE-SETUP.md` are also available. The Terraform state is the source of truth for the existing AWS deployment.

---

## Quick start

For an already-provisioned lab, the minimum command sequence is:

```bash
git clone --recurse-submodules \
  git@github.com:oriax11/code-keeper.git \
  ~/code-keeper

cd ~/code-keeper

git submodule sync --recursive
git submodule update --init --recursive

git submodule status --recursive
```

Then configure the current Iximiuz GitLab hostname in the four operational submodules:

```bash
export GITLAB_HOST="https://<current-iximiuz-gitlab-host>"

for repo in \
  infrastructure-configuration \
  inventory-app \
  billing-app \
  api-gateway
do
  git -C "$repo" remote set-url origin \
    "$GITLAB_HOST/code-keeper/$repo.git"
done
```

Verify:

```bash
git submodule foreach --recursive 'git remote -v'
```

Finally:

```bash
cd ~/code-keeper/infrastructure-configuration

GITLAB_HOST="$GITLAB_HOST" ./scripts/bootstrap-new-machine.sh --verify-only
```

The complete fresh-machine procedure is documented above and in [`docs/NEW-MACHINE-SETUP.md`](docs/NEW-MACHINE-SETUP.md).

> ⚠️ **The GitLab node URL is ephemeral and changes constantly.** A dead Iximiuz node can surface as Terraform remote-state authentication errors. Check the current Playground URL before debugging credentials.

---

## Verifying by hand

Both scripts live in `infrastructure-configuration/scripts/`, both default to staging and take `--env production`, and both are idempotent.

```bash
./scripts/create-test-user.sh --env staging     # prints an AccessToken to stdout
./scripts/test-api-as-user.sh --env production  # asserts behaviour, exits non-zero on failure
```

`test-api-as-user.sh` asserts four things:

| Check                                | Expected | Why it matters                                      |
|--------------------------------------|----------|-----------------------------------------------------|
| `GET /`                              | 200      | health, unauthenticated by design                   |
| `GET /api/movies` **without** a token | **401** | proves the JWT gate is real, not decorative         |
| `GET /api/movies` **with** a token    | 200     | proves auth works *and* the proxy reaches inventory |
| `POST /api/billing/` with a token    | 200      | proves the RabbitMQ path end to end                 |

The 401-then-200 pair is the whole point: authentication is enforced **and** a legitimate user gets through. The 401 was confirmed to have teeth: garbage tokens, empty `Bearer` headers and tampered-signature tokens are all rejected. A 401 assertion that would also pass on a 200 is worthless.

Tokens go to **stdout only**; everything human-readable goes to stderr, so a token never lands in a file, in shell history, or in a CI log.

---

## Security model

**CI identity:** `arn:aws:iam::006631837921:user/gitlab-ci-deploy`

| Policy            | Type                    | Purpose                                         |
|-------------------|-------------------------|-------------------------------------------------|
| `ck-deploy`       | inline                  | ECS deploy + `iam:PassRole`, scoped to ECS ARNs |
| `ck-deploy-reads` | inline                  | discovery calls                                 |
| `ck-plan-reads`   | customer-managed, **v4** | everything `terraform refresh` reads           |

No permissions boundary. No group memberships. **`AdministratorAccess` is not attached.**

This identity can **deploy to production but cannot build production.** It cannot create a VPC, cluster, IAM role or secret. Verified denied: `ec2:CreateVpc`, `iam:CreateRole`, `cloudwatch:PutDashboard`, `secretsmanager:PutSecret`.

> **`apply-production` failing in CI is the expected steady state**, not a regression. Anyone reading the pipeline and seeing a red `apply-production` should be told this before they go looking for a bug.

`ck-plan-reads` is at **v4** because each version was forced by a pipeline failing on an `AccessDenied` naming one missing action. That history is the evidence the policy stayed least-privilege. Read it before widening anything.

The policies are committed under `infrastructure-configuration/iam/gitlab-ci-deploy/` with a README giving the rationale per permission. They are still **applied by hand**; `bootstrap-new-machine.sh` diffs repo against live and reports drift, warning and continuing, failing only on genuinely missing permissions.

---

## Traps worth knowing before you touch anything

These are documented in full in `docs/NEW-MACHINE-SETUP.md` §6. Each one has already cost real time here.

1. **The GitLab node URL rots.** See above. The most likely thing to be stale on any given day.
2. **`terraform init -reconfigure` discards the cached backend config.** `backend.tf` is deliberately empty, so **all seven `-backend-config` values must be passed together** or it fails with `address argument is required`.
3. **A wrong backend `address` silently initialises against brand-new empty state.** A later `apply` would try to create the entire stack again. After **every** re-init, confirm `terraform state list | wc -l` still prints **73** and that `module.alb.aws_lb.main` has the expected `name`.
4. **The AWS CLI credential store beats `AWS_SHARED_CREDENTIALS_FILE`.** After `aws login`, a bare `aws ...` authenticates as **root** even with the env var pointing at the scoped key. This caused a real incident: a "confirm this is denied" probe ran as root and **created a stray VPC**. Always name the profile: `aws ... --profile code-keeper`.
5. **Terraform honours `AWS_PROFILE`, not a `--profile` flag.** To apply as root, unset both.
6. **`trigger:variables` does not expand** file-scoped variables. It sends the literal text `$IMAGE_NAME`. `$CI_COMMIT_SHA` and `trigger:project:` *do* expand. Inconsistent, and now guarded.
7. **`register-task-definition` rebuilds the task**, so every task-level field Terraform set must be supplied again. `cpu`/`memory` live at the task level; containers carry none.
8. **`git reset --hard origin/main` discards uncommitted work, silently.** It destroyed a security fix and a whole script during this project. Commit or stash deliberately first.
9. **`git fetch origin github` is invalid syntax.** It fails with a short `fatal` and leaves remote-tracking refs **stale**; a `reset --hard origin/main` right after then rolls you back silently. Fetch each remote in its own command and confirm the ref moved.

The general lesson behind 8 and 9: **distinguish "absent" from "could not look", and "denied" from "empty result".** A tool that fails quietly will eventually be believed.

---

## Documentation

| Document | Contents |
|----------|----------|
| [`docs/design.md`](docs/design.md) | **authoritative** infra/CD design spec |
| [`docs/NEW-MACHINE-SETUP.md`](docs/NEW-MACHINE-SETUP.md) | standing up a new machine, and the traps |
| [`docs/code-keeper-plan.md`](docs/code-keeper-plan.md) | master plan, phase status |
| [`docs/code-keeper-audit.md`](docs/code-keeper-audit.md) | original audit findings |
| [`docs/code-keeper-phase*-log.md`](docs/) | how the CD path was found broken, and fixed |
| `infrastructure-configuration/iam/gitlab-ci-deploy/README.md` | CI IAM, permission by permission |
| `infrastructure-configuration/scripts/deploy-service.sh` | resolves tag→digest, then registers |

---

## Open items

The ones that matter most:

- `scan` is `allow_failure: true`. Decide whether findings should block.
- Two files still carry stale node URLs, and both rot on every re-provision: `bootstrap-new-machine.sh` defaults `GITLAB_HOST` to a dead node, and `ansible/group_vars/all/gitlab.yml` hardcodes one two generations old despite its own comment saying it must not. Pass `GITLAB_HOST=` / `GITLAB_EXTERNAL_URL=` instead of editing them.
- A second, unrelated administrator identity (`cloud-design-deployer`) holds `AdministratorAccess` with a live access key, idle since 2026-09-17. Not used by this project, **not deleted** pending a decision. Recommended order: revoke the key first, then the user.
- Four AWS/GitLab credentials from earlier transcripts were never rotated.
- Terraform should own the CI IAM user (needs a bootstrap root module, since the user must exist before Terraform can run).
- `urllib3` is pinned only in `api-gateway`; `inventory` and `billing` resolve it transitively.

---

## Cost

Staging is left running deliberately at roughly **$5.40/day (~$162/month)**: 9 Fargate tasks 24/7 (~$3.75), a NAT gateway (~$1.08), and the ALB (~$0.54).

```bash
./scripts/destroy-all.sh --plan     # read-only: shows what WOULD be destroyed
```

**`destroy-all.sh` is destructive by default.** Use `--plan`.

---

*Verified against live AWS and GitLab on 2026-10-02. Figures above (73 resources per environment, task definition revisions, digest pinning and IAM policy state) were read from the live infrastructure, not copied from documentation.*