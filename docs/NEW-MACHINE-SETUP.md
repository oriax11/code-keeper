# New Machine Setup — Code-Keeper

**Purpose:** take a fresh machine from bare OS to a verified, working Code-Keeper dev environment.

The automated part is `infrastructure-configuration/scripts/bootstrap-new-machine.sh`. This
document covers what the script deliberately does **not** do, and the traps that have actually
cost time on this project.

---

## 0. Before you start — what you must already have

| Item | Where it comes from | Notes |
|---|---|---|
| AWS account root access | `aws login` on the account | Not a file. Interactive. |
| New access key for `gitlab-ci-deploy` | AWS IAM console or CLI | **Rotate, do not copy** (see §4) |
| GitLab PAT, `api` scope, project 8 | GitLab → Settings → Access Tokens | Needed as `TF_STATE_TOKEN` |
| Docker Hub token | Docker Hub → Access Tokens | |
| GitLab username + PAT for `git` | same GitLab account | |
| **Current GitLab node URL** | ask whoever runs the lab | **It changes constantly** (see §1) |

### The single most likely thing to be stale: the GitLab URL

This node has been re-provisioned **at least four times in one day**:
`d1d94d → 098e3d → d79464 → gone`.

A dead node does not produce a helpful error. Terraform reports:

```
Failed to load state: HTTP remote state endpoint invalid auth
```

which looks exactly like a credential problem and is not one. If you see that, **check the URL
first.** The bootstrap script probes the host in preflight and says so explicitly.

```bash
GITLAB_HOST=<current-url> ./scripts/bootstrap-new-machine.sh
```

Every place the URL is baked in and will need updating when the node changes:

| Location | What to change |
|---|---|
| `bootstrap-new-machine.sh` | `GITLAB_HOST` (or pass it as an env var) |
| `terraform/.terraform/terraform.tfstate` | re-init, see §3 |
| `ansible/inventory/hosts.yml` | oriax hardcoded a node URL here — will break |
| `ansible/roles/gitlab_runner/defaults/main.yml` | `gitlab_url` — keep it a **static IP**, see §6 |

---

## 1. Run the bootstrap

```bash
git clone git@github.com:oriax11/code-keeper.git ~/code-keeper
cd ~/code-keeper
git submodule update --init --recursive

cd ~/code-keeper/infrastructure-configuration
GITLAB_HOST=<current-url> ./scripts/bootstrap-new-machine.sh
```

Flags: `--skip-install`, `--skip-clone`, `--verify-only`.

**Terraform is pinned to exactly 1.10.5** and the script will replace any other version. This is
deliberate: CI is pinned to 1.10.5, and a newer local Terraform changes plan behaviour and can
disagree with CI.

---

## 2. Fill in the credential files

The script creates empty `0600` files. It never embeds a value. Fill them by hand.

**Do not paste secrets into a shell command, a chat transcript, or a commit.** On 2026-09-30 a
`cat .terraform/terraform.tfstate` put the GitLab state token — a Maintainer `api` token — into a
transcript, and the 12-character suffix of it ended up committed in
`docs/code-keeper-phase6-log.md`. That is the single worst habit in this project's history.

### `~/.ck-aws-credentials` (0600)

```ini
[code-keeper]
aws_access_key_id = AKIA...
aws_secret_access_key = ...
region = us-east-1
output = text
```

This is the **scoped** CI identity. It can read what `terraform refresh` needs and deploy one ECS
service. It cannot provision anything.

### `~/.ck-secrets` (0600)

```
CK_GL_ORIAX_USER=
CK_GL_ORIAX_PASS=
CK_DOCKERHUB_USER=
CK_DOCKERHUB_TOKEN=
```

### `~/.git-credentials` (0600)

Standard git credential-store format, one line per host:

```
https://<user>:<pat>@<gitlab-host>
```

---

## 3. Terraform backend

`terraform/backend.tf` is deliberately **empty**:

```hcl
terraform {
  backend "http" {}
}
```

Every value comes from `-backend-config` flags. This has a sharp edge:

> `terraform init -reconfigure` **discards the cached backend config** and re-asks for it. With an
> empty `backend.tf` and no TTY, that fails with `Error: address argument is required`.

So `-reconfigure` always needs **all seven values together**:

```bash
cd ~/code-keeper/infrastructure-configuration/terraform
export TF_STATE_TOKEN='<gitlab PAT, api scope>'
export GITLAB_STATE_BASE="https://<gitlab-host>/api/v4/projects/8/terraform/state"

terraform init -input=false -reconfigure \
  -backend-config="address=${GITLAB_STATE_BASE}/staging" \
  -backend-config="lock_address=${GITLAB_STATE_BASE}/staging/lock" \
  -backend-config="unlock_address=${GITLAB_STATE_BASE}/staging/lock" \
  -backend-config="username=<your-gitlab-username>" \
  -backend-config="password=${TF_STATE_TOKEN}" \
  -backend-config="lock_method=POST" \
  -backend-config="unlock_method=DELETE"
```

> **Danger:** if `address` is wrong, Terraform will happily init against a **brand-new empty
> state**. You will no longer see the 73 live resources, and a subsequent `apply` would try to
> create the entire stack again. Always confirm immediately afterwards:
>
> ```bash
> terraform state list | wc -l    # must print 73
> ```

If you are only *reading* and the cached config is still valid, plain `terraform init` (no
`-reconfigure`) reuses the cache and is enough.

---

## 4. Rotate, do not copy

After the new machine works:

```bash
# create a new key for the scoped CI identity
aws iam create-access-key --user-name gitlab-ci-deploy --profile root
# install it on the NEW machine, verify, THEN:
aws iam delete-access-key --user-name gitlab-ci-deploy --access-key-id <OLD> --profile root
```

Never leave two live keys on two disks. An audit will find it, and rightly.

---

## 5. What "verified" looks like

The script's step 6 must print all of these:

```
OK   terraform state: 73 resources (expected 73)
OK   AWS identity: arn:aws:iam::006631837921:user/gitlab-ci-deploy
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

The `CreateVpc DENIED` line is the important one. If it ever reads `ALLOWED`, the CI identity can
provision infrastructure and the whole least-privilege design is void.

---

## 6. Traps, in the order they will bite you

**1. The AWS CLI credential store beats `AWS_SHARED_CREDENTIALS_FILE`.**
After `aws login`, a bare `aws ...` authenticates as **root** even with
`AWS_SHARED_CREDENTIALS_FILE` pointing at the scoped key. This already caused a real incident: a
"confirm this is denied" probe ran as root and **created a stray VPC**. Always name the profile:

```bash
aws ecs list-services --profile code-keeper     # scoped
aws iam get-user --profile root                 # admin
```

**2. Terraform ignores `--profile`.** It honours `AWS_PROFILE` / `AWS_SHARED_CREDENTIALS_FILE`,
not the CLI flag. To apply as root, `unset` both.

**3. IAM propagation churn mimics a broken policy.** Rapid create/modify/delete cycles produce
`AccessDenied` for actions that are demonstrably in the current policy version. Make one change,
then wait, before concluding anything. Hours were lost chasing this.

**4. Inline IAM user policies cap at 2048 bytes.** `ck-plan-reads` is 1873 bytes and **would not
fit inline** — it must stay a customer-managed policy. The failed attempt returned
`LimitExceeded` and correctly changed nothing.

**5. `trigger:variables` does not expand** variables from the same file's `variables:` block. It
sends the literal text. `$CI_COMMIT_SHA` (predefined) *does* expand; a file-scoped variable does
not. `trigger:` keyword values like `project:` **do** expand. Inconsistent, and now guarded.

**6. Runners are slow and single-concurrency.** Jobs sit `pending` with `runner=none` for minutes
because another job on the same project runner holds the slot. `docker ps` on your workstation
shows nothing and means nothing — the runners are remote VMs.

**7. `podman push` cannot copy images with gzip layers.** Use
`skopeo copy --preserve-digests`.

---

## 7. Cost — staging is left running deliberately

~$5.40/day (~$162/month):

| Item | Cost |
|---|---|
| 9 Fargate tasks, 24/7 | ~$3.75/day — the dominant cost |
| NAT gateway `staging-nat` | ~$1.08/day + per-GB |
| ALB `staging-alb` | ~$0.54/day |
| EFS (103 MB) | negligible |

To tear down later, **use the read-only flag** — the default mode is destructive:

```bash
./scripts/destroy-all.sh --plan     # read-only: shows what WOULD be destroyed
```

---

## 8. Related documents

- `README.md` — project state and architecture, for picking up cold
- `docs/design.md` — the authoritative infra/CD design spec
- `docs/ARCHITECTURE-DIAGRAMS.md` — colour-coded diagrams and the audit checklist
- `docs/code-keeper-plan.md` — master plan and phase status
- `infrastructure-configuration/iam/gitlab-ci-deploy/README.md` — CI identity, permission by permission