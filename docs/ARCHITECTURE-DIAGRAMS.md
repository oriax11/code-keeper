# Architecture Diagrams

Colour-coded Mermaid diagrams for audit review. Every diagram is drawn from the Terraform source and
the live infrastructure, not from the prose docs — where they disagree, the code wins.

**Legend** is consistent across all diagrams:

| Colour | Meaning |
|---|---|
| 🟠 amber | Internet-facing / trust boundary edge |
| 🟡 yellow | Public subnet |
| 🔵 blue | Private subnet compute (no public IP) |
| 🟢 green | Persistent data store |
| 🟣 purple | Message queue |
| 🔴 pink | Identity / authentication |
| ⚪ grey | CI/CD control plane |
| 🔴 red | Explicitly denied |

---

## 1. Runtime request flow

What a request actually does, end to end. The dashed red edge is the security control that matters
most: `api-gateway` refuses an unauthenticated call before it ever touches `inventory-app`.

```mermaid
flowchart TB
    U(["Client<br/>browser or curl"])

    subgraph EDGE["Trust boundary — internet"]
        ALB["ALB · staging-alb-2125783479<br/>self-signed TLS · :80 → 301 → :443"]
        POOL["Cognito user pool<br/>us-east-1_bPoDPlAhf<br/>issues + signs JWTs"]
    end

    subgraph PRIV["VPC private subnets — assign_public_ip = false"]
        GW["api-gateway · Fargate :3000<br/>verify JWT, then proxy"]
        INV["inventory-app · Fargate :8080<br/>Flask + SQLAlchemy"]
        BILL["billing-app · Fargate :8080<br/>queue consumer, no inbound"]
        RMQ[["rabbit-queue · :5672"]]
        IDB[("inventory-db<br/>PostgreSQL :5432")]
        BDB[("billing-db<br/>PostgreSQL :5432")]
    end

    U -->|"HTTPS :443"| ALB
    U -.->|"obtain a token"| POOL
    POOL -.->|"JWT"| U
    ALB --> GW
    GW -->|"proxy GET, valid JWT"| INV
    GW -->|"publish event"| RMQ
    RMQ -->|"consume"| BILL
    INV --> IDB
    BILL --> BDB

    NOPROXY["❌ without a JWT → 401<br/>no request ever reaches inventory-app"]
    U -.-> NOPROXY

    classDef edge fill:#fff3e0,stroke:#e65100,stroke-width:2px,color:#000
    classDef auth fill:#fce4ec,stroke:#c2185b,stroke-width:2px,color:#000
    classDef app fill:#e3f2fd,stroke:#1565c0,stroke-width:2px,color:#000
    classDef data fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px,color:#000
    classDef queue fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px,color:#000
    classDef deny fill:#ffebee,stroke:#c62828,stroke-width:2px,color:#c62828

    class U,ALB edge
    class POOL auth
    class GW,INV,BILL app
    class IDB,BDB data
    class RMQ queue
    class NOPROXY deny
```

**The billing path is asynchronous.** `POST /api/billing/` returns as soon as the event is on the
queue; `billing-app` writes to `billing-db` afterwards. A 200 from that endpoint proves the publish
worked, not that the write completed.

---

## 2. Network trust boundaries

Only the ALB is reachable from the internet. Every service-to-service hop is permitted by **security
group reference**, not by CIDR — so the rules survive IP changes and cannot be satisfied by an
unexpected source address.

```mermaid
flowchart TB
    INET(["Internet"])

    subgraph PUB["Public subnets — 2 AZs"]
        ALB["ALB<br/>sg: alb"]
    end

    subgraph PRIV["Private subnets — 2 AZs · no public IP"]
        GW["api-gateway :3000<br/>sg: api_gateway"]
        INV["inventory-app :8080<br/>sg: inventory_app"]
        BILL["billing-app :8080<br/>sg: billing_app"]
        RMQ[["rabbit-queue :5672<br/>sg: rabbitmq"]]
        IDB[("inventory-db :5432<br/>sg: inventory_db")]
        BDB[("billing-db :5432<br/>sg: billing_db")]
    end

    INET -->|"80, 443 only<br/>from 0.0.0.0/0"| ALB
    ALB -->|"3000"| GW
    GW -->|"8080"| INV
    GW -->|"5672"| RMQ
    RMQ -->|"5672"| BILL
    INV -->|"5432"| IDB
    BILL -->|"5432"| BDB

    NOIN["billing-app has NO ingress rule<br/>it consumes; nothing connects in"]

    classDef edge fill:#fff3e0,stroke:#e65100,stroke-width:2px,color:#000
    classDef app fill:#e3f2fd,stroke:#1565c0,stroke-width:2px,color:#000
    classDef data fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px,color:#000
    classDef queue fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px,color:#000
    classDef deny fill:#ffebee,stroke:#c62828,stroke-width:1px,color:#c62828

    class INET,ALB edge
    class GW,INV,BILL app
    class IDB,BDB data
    class RMQ queue
    class NOIN deny
```

### Ingress matrix — the complete list

| Security group | Port | Permitted source |
|---|---|---|
| `alb` | 80 | `0.0.0.0/0` |
| `alb` | 443 | `0.0.0.0/0` |
| `api_gateway` | 3000 | **sg:alb** |
| `inventory_app` | 8080 | **sg:api_gateway** |
| `inventory_db` | 5432 | **sg:inventory_app** |
| `rabbitmq` | 5672 | **sg:api_gateway, sg:billing_app** |
| `billing_db` | 5432 | **sg:billing_app** |
| `billing_app` | — | *no ingress rule at all* |

That is every ingress rule in the stack. Six hops, each referencing the previous security group. An
auditor should confirm this list is reproduced exactly by
`terraform plan` — any additional rule is a finding.

---

## 3. CI/CD control plane

The central design rule: **app pipelines hold no AWS credentials.** They build and push an image,
then *trigger* the infrastructure repo. Only the infra repo can change AWS.

```mermaid
flowchart LR
    subgraph APP["App pipelines — projects 5, 6, 7 · NO AWS CREDENTIALS"]
        B["build"] --> T["test"] --> S["scan"] --> C["containerize"]
        S -.->|"allow_failure: true<br/>⚠️ open risk"| SCAN["findings do not block"]
    end

    C -->|"push image<br/>1ee5lim/app:tag"| REG[("Docker Hub")]
    C -->|"trigger project 8<br/>APP_NAME / IMAGE_NAME / IMAGE_TAG"| INF

    subgraph INF["infrastructure-configuration — project 8 · THE DEPLOYMENT CONTROLLER"]
        direction TB
        I["init"] --> V["validate"]
        subgraph PLAN["plan"]
            PS["plan-staging"] --> PP["plan-production"]
        end
        AS["apply-staging"] --> APPR["approval · manual"] --> AP["apply-production"]
        PS --> AS
        PP --> AP
        DS["deploy-staging<br/>resolves tag → digest,<br/>registers ONE service"] --> DA["deploy-approval · manual"] --> DP["deploy-production"]
    end

    IGN["Terraform ignores container_definitions after create<br/>so CD and Terraform never fight over the image"]
    DS -.-> IGN
    INF --> AWS[("AWS us-east-1<br/>006631837921")]

    FAIL["⚠️ apply-production only fails when it has real changes to make<br/>a no-op plan needs no write permissions"]
    AP -.-> FAIL

    classDef appci fill:#eceff1,stroke:#455a64,stroke-width:2px,color:#000
    classDef cd fill:#e8eaf6,stroke:#3949ab,stroke-width:2px,color:#000
    classDef store fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px,color:#000
    classDef deny fill:#ffebee,stroke:#c62828,stroke-width:1px,color:#c62828
    classDef warn fill:#fff8e1,stroke:#f9a825,stroke-width:2px,color:#000

    class B,T,S,C,SCAN appci
    class I,V,PS,PP,AS,APPR,AP,DS,DA,DP cd
    class REG,AWS store
    class FAIL,IGN deny
    class S warn
```

### Three things an auditor will ask about

**`scan` is `allow_failure: true`.** Two HIGH CVEs shipped inside a green pipeline on 2026-09-30.
Findings are reported but do not fail the build. This is a known, open decision.

**`apply-production` is not reliably red.** The CI identity cannot *provision* in production, so an
apply with real changes to make fails on `AccessDenied`. But an apply whose plan is **empty** needs
no write permissions at all, and succeeds. Expect this job to go green on a no-op plan. That is not
evidence the identity can write to production — verify with the `ec2:CreateVpc` probe below, not by
reading this job's colour.

---

## 4. Identity model — who can do what

The audit-defining diagram. One scoped identity deploys; it cannot provision.

```mermaid
flowchart TB
    DEV(["Developer<br/>human, interactive"])

    subgraph IAM["AWS IAM · account 006631837921"]
        ROOT["root<br/>AdministratorAccess<br/>⚠️ see note"]
        CI["gitlab-ci-deploy<br/>ck-deploy · ck-deploy-reads · ck-plan-reads v4"]
        APPUSER["cloud-design-deployer<br/>AdministratorAccess<br/>⚠️ unused, live key"]
    end

    subgraph OK["✅ PERMITTED — scoped CI identity"]
        O1["ecs:RegisterTaskDefinition"]
        O2["ecs:DeregisterTaskDefinition"]
        O3["iam:PassRole (scoped to ecs ARNs)"]
        O4["terraform refresh reads"]
        O5["ecs:TagResource (ECS ARNs)"]
    end

    subgraph NO["🔴 DENIED — verified by probe"]
        D1["ec2:CreateVpc"]
        D2["iam:CreateRole"]
        D3["secretsmanager:PutSecret"]
        D4["cloudwatch:PutDashboard"]
    end

    CI --> OK
    CI -.-> NO
    ROOT -->|"manual only<br/>IAM drift checks"| OK
    ROOT --> NO
    DEV -->|"aws login"| ROOT

    NOTE["Least privilege is only meaningful if it is verified.<br/>bootstrap-new-machine.sh probes each denial and reports ALLOWED vs DENIED.<br/>If ec2:CreateVpc ever reads ALLOWED, the model is void."]

    classDef root fill:#ffebee,stroke:#c62828,stroke-width:3px,color:#000
    classDef ci fill:#e3f2fd,stroke:#1565c0,stroke-width:3px,color:#000
    classDef ok fill:#e8f5e9,stroke:#2e7d32,stroke-width:1px,color:#000
    classDef no fill:#ffebee,stroke:#c62828,stroke-width:2px,color:#c62828
    classDef note fill:#fff8e1,stroke:#f9a825,color:#000

    class ROOT,APPUSER root
    class CI ci
    class O1,O2,O3,O4,O5 ok
    class D1,D2,D3,D4 no
    class DEV,NOTE note
```

### ⚠️ Two identities that will be raised

| Identity | Status | Required action |
|---|---|---|
| `root` | Account owner. Used for IAM drift checks only. | Expected. |
| `cloud-design-deployer` | **`AdministratorAccess` + an active access key**, created 2026-09-11 by an earlier bootstrap script. **Not used by Code-Keeper.** Last CloudTrail activity 2026-09-17. | **Not deleted** — deletion is destructive and it may be wanted as evidence. Recommended: revoke the key **first**, then the user, so there is never a window with neither. |

The related script `bootstrap-iam.sh` defaulted to `POLICY_MODE=admin` and attached
`AdministratorAccess` when run bare. The default is now `scoped`, and `admin` requires typing
`yes-i-understand`.

> **Near-miss worth recording:** that fix was committed only to the GitHub mirror while GitLab was
> unreachable, then destroyed locally by `git reset --hard origin/main`. For a period the
> authoritative remote still shipped the dangerous default. It was found only by diffing
> `github/main` against `origin/main`. **A security fix that cannot be pushed to the authoritative
> remote has not been made.**

---

## 5. Authentication decision

The control that the audit will test, and the one with a documented proof that it has teeth.

```mermaid
flowchart TB
    REQ(["GET /api/movies"]) --> BR{"Authorization<br/>header present?"}
    BR -->|"no"| E1["401 Unauthorized"]
    BR -->|"yes"| SIG{"Signature valid<br/>and unexpired?"}
    SIG -->|"garbage token"| E1
    SIG -->|"empty Bearer"| E1
    SIG -->|"tampered signature"| E1
    SIG -->|"valid"| INV["proxy to inventory-app"]
    INV --> OKR["200 OK"]

    HEALTH(["GET /"]) -->|"no auth required<br/>by design"| H["200 OK · health"]

    PROOF["The 401 is confirmed to have teeth:<br/>garbage, empty and tampered tokens are all rejected.<br/>A 401 assertion that would also pass on a 200 is worthless."]

    E1 --> PROOF

    classDef req fill:#eceff1,stroke:#455a64,color:#000
    classDef deny fill:#ffebee,stroke:#c62828,stroke-width:2px,color:#c62828
    classDef ok fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px,color:#000
    classDef note fill:#fff8e1,stroke:#f9a825,color:#000

    class REQ,HEALTH req
    class BR,SIG deny
    class E1,INV,OKR,H ok
    class PROOF note
```

Reproduce with `scripts/test-api-as-user.sh`, which asserts all four cases and exits non-zero on
failure.

---

## 6. Deployment isolation

The property that makes the trigger design safe: deploying one service must not disturb the others.

```mermaid
flowchart LR
    subgraph BEFORE["Before — all three on their current revisions"]
        GI["api-gateway :4"]
        BI["billing :3"]
        II["inventory :1"]
    end

    TRIGGER["push to api-gateway main<br/>→ trigger APP_NAME=api-gateway"]

    subgraph AFTER["After — exactly one task definition changes"]
        GA["api-gateway :5 ✅ new"]
        BA["billing :3 ⬜ unchanged"]
        IA["inventory :1 ⬜ unchanged"]
    end

    BEFORE --> TRIGGER --> AFTER
    GA -.->|"same image digest"| GA
    BA -.->|"untouched"| BA
    IA -.->|"untouched"| IA

    RULE["The infra repo deploys exactly the named service, and only that service.<br/>Demonstrated live — not assumed."]

    classDef app fill:#e3f2fd,stroke:#1565c0,stroke-width:2px,color:#000
    classDef same fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px,color:#000
    classDef note fill:#fff8e1,stroke:#f9a825,color:#000

    class GI,BI,II,TRIGGER app
    class GA,BA,IA same
    class RULE note
```

---

## 7. Who owns the container image

CD owns the image. Terraform creates the service and then **ignores** `container_definitions`
afterwards, so the two can no longer fight over it.

This replaces the earlier digest-pinning scheme (`pin-image.sh` + `check-image-pins.sh`), which is
removed. Those two scripts failed repeatedly — `diff` missing from the CI image, `git` missing from
it, and a `terraform apply` reverting a deploy so the recorded pin became a rollback made to look
intentional. Moving ownership to one actor removed the conflict instead of policing it.

```mermaid
flowchart TB
    SRC(["Source commit<br/>on main"]) --> BUILD["CI builds image"]
    BUILD --> TAGGED["tag pushed<br/>1ee5lim/app:&lt;sha&gt;"]
    TAGGED --> TRIG["trigger infra pipeline<br/>APP_NAME / IMAGE_NAME / IMAGE_TAG"]
    TRIG --> RESOLVE["deploy-service.sh<br/>resolves tag → digest at deploy time"]
    RESOLVE --> REG["register-task-definition<br/>container_definitions set by digest"]
    REG --> RUN["ECS runs the digest-pinned image"]

    TF["Terraform<br/>creates the service once"] -.->|"lifecycle ignore_changes<br/>= [container_definitions]"| REG

    OWN["Single owner per field:<br/>CD owns the image after creation.<br/>Terraform owns everything else."]

    REG -.-> OWN

    NOTE(["No pin to record, so no drift to police.<br/>Nothing reverts a deploy, because<br/>Terraform no longer manages the image."])

    OWN -.-> NOTE

    classDef step fill:#e8eaf6,stroke:#3949ab,stroke-width:1px,color:#000
    classDef ok fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px,color:#000
    classDef tf fill:#eceff1,stroke:#455a64,stroke-width:2px,color:#000
    classDef note fill:#fff8e1,stroke:#f9a825,color:#000

    class SRC,BUILD,TAGGED,TRIG,RESOLVE,REG step
    class RUN ok
    class TF tf
    class OWN,NOTE note
```

The digest is still resolved from the registry and written into the task definition, so a running task
is always pinned to immutable bytes. What is gone is the second writer that used to overwrite it.

**Chain of custody for auditors:** every running task definition names an immutable `@sha256`
digest, and `deploy-service.sh` records the resolved digest and asserts the service actually runs it
before the job is allowed to succeed. To verify, read the task definition directly:

```bash
aws ecs describe-services --cluster staging-cluster \
  --services staging-inventory-service \
  --query 'services[0].taskDefinition' --output text
```

There is deliberately no tracked file to compare it against. The earlier pin comparison is gone, so
the task definition itself is the record.

---

## 8. Environment parity

`staging` and `production` are built from the **same modules**. There is no environment-specific
Terraform code — the difference is entirely in `environments/*.tfvars.example`.

```mermaid
flowchart LR
    MOD["terraform/modules<br/>alb · ecs · efs · security · vpc<br/>single source for both envs"]
    STG["staging.tfvars.example<br/>tracked · authoritative"]
    PRD["production.tfvars.example<br/>tracked · authoritative"]
    IGN["*.tfvars<br/>gitignored · regenerated from .example"]

    MOD --> STG
    MOD --> PRD
    STG -.->|"generate"| IGN
    PRD -.->|"generate"| IGN
    IGN --> STGLIVE["staging: 73 resources<br/>7 ECS services · 3 DBs"]
    IGN --> PRDLIVE["production: 73 resources<br/>7 ECS services · 3 DBs"]

    DRIFT["⚠️ Past failure: the gitignored .tfvars silently drifted from the tracked .example,<br/>including an OLDER urllib3 — a production CVE downgrade no diff against main would show.<br/>Rule now: .example is the source of truth and CI regenerates from it."]

    IGN -.-> DRIFT

    classDef mod fill:#e8eaf6,stroke:#3949ab,stroke-width:2px,color:#000
    classDef tf fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px,color:#000
    classDef ign fill:#eceff1,stroke:#455a64,stroke-width:1px,color:#000
    classDef note fill:#ffebee,stroke:#c62828,color:#c62828

    class MOD mod
    class STG,PRD,STGLIVE,PRDLIVE tf
    class IGN ign
    class DRIFT note
```

---

## Audit checklist

Each item is reproducible with a command, so the audit does not depend on a human assertion.

| # | Claim | How to verify |
|---|---|---|
| 1 | Both environments match their configuration | `terraform plan` → `No changes` |
| 2 | State is the shared state, not an empty one | `terraform state list \| wc -l` → **73** |
| 3 | ALB identity is correct | `terraform state show module.alb.aws_lb.main` → expected `name` |
| 4 | Every running image is digest-pinned | `aws ecs describe-task-definition` → image ends `@sha256:` |
| 5 | CI identity cannot provision | `aws ec2 create-vpc --profile code-keeper` → **DENIED** |
| 6 | CI identity is not root | `aws sts get-caller-identity --profile code-keeper` → `…:user/gitlab-ci-deploy` |
| 7 | IAM matches the repo | `./scripts/bootstrap-new-machine.sh --verify-only` → three policies `match` |
| 8 | Auth is enforced, not decorative | `scripts/test-api-as-user.sh` → 401 then 200, 4/4 |
| 9 | Deploys are isolated | observe one service revision moves, others do not |
| 10 | Terraform is pinned | `terraform version` → exactly **1.10.5**, same as CI |
| 11 | Terraform will not revert a CD deploy | `terraform plan` after a deploy proposes **no** image change |

Run item 7 first. It is the cheapest check that covers the most, and it reports drift rather than
asserting absence.

---

*Diagrams generated from `infrastructure-configuration/terraform` and verified against live AWS on
2026-10-02. Regenerate if the modules change.*