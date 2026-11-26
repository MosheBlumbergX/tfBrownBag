# Managing Confluent Cloud with Terraform

A brownbag demo. One `make up` builds a realistic AWS landing zone and a
private Confluent Cloud Enterprise cluster, and stops at the edge: a Kubernetes
cluster that can reach Kafka over PrivateLink. Every Terraform concept the
session covers has a real file you can point at while you talk.

```
                 AWS                                      Confluent Cloud
┌──────────────────────────────┐                  ┌──────────────────────────────┐
│ spoke VPC 10.42.0.0/16       │                  │ environment  tf-brownbag     │
│  EKS (the clients)           │                  │                              │
│                              │                  │  ingress PrivateLink gateway │
└───────────────┬──────────────┘                  │  access point                │
                │                                 │                              │
        Transit Gateway                           │  Enterprise cluster          │
                │                                 │                              │
┌───────────────┴──────────────┐                  └──────────────┬───────────────┘
│ hub VPC 10.40.0.0/16         │                                 │
│  interface VPC endpoint ─────┼──────────  AWS PrivateLink ─────┘
│  Route53 private zone        │
│  *.<access-point-domain>     │
└──────────────────────────────┘
```

Nothing is exposed publicly: the Kafka cluster is private-only, reached from
EKS across the Transit Gateway through a single PrivateLink endpoint in the hub.

---

## Quick start

```bash
cp .env.example .env         # paste your Confluent Cloud API key + secret
aws sso login                # any admin-level AWS credentials
make preflight               # 20 seconds: quotas, SCPs, credentials
make up                      # ~25 min
make verify                  # prove the private path from a pod in EKS
```

`make verify` runs a throwaway pod in the spoke VPC that resolves the cluster's
bootstrap host (it must land on a private address in the hub range, 10.40.x.x)
and opens a TCP connection to port 9092. That is the finish line: the whole
chain of Terraform-built networking works.

To use kubectl against the demo cluster: `export KUBECONFIG=$PWD/.kubeconfig`.

| | Command | What happens |
|---|---|---|
| 0 | `make preflight` | Checks the target account can actually do this: VPC/EIP/TGW/IGW quota headroom, service control policies, and that the Confluent Cloud key works |
| 1 | `make infra` | `terraform apply`: VPCs, TGW, EKS, PrivateLink, Confluent Cloud environment + Enterprise cluster |
| 2 | `make status` | Terraform outputs and EKS nodes |
| 3 | `make verify` | Resolve and connect to the private cluster from inside the VPC |

Tear it all down with `make down`. If you set up CI, also run
`terraform -chdir=bootstrap destroy` (see section 9).

### Prerequisites

`terraform` ≥ 1.6, `aws` CLI v2, `kubectl`, `jq`, `curl`, `make`.

- AWS credentials that can create VPCs, a Transit Gateway, EKS and IAM roles.
- A Confluent Cloud org with a payment method on file and a
  **Cloud resource management** API key owned by an `OrganizationAdmin`.

---

## The brownbag, section by section

Every topic below maps to a file you can open on screen.

### 1. Terraform basics - `terraform/versions.tf`

What Terraform is: you describe the end state, it works out the actions. The
`terraform` block declares the CLI version, the providers and where they come
from. `terraform init` downloads them and pins the exact versions into
`.terraform.lock.hcl`, which is committed - that lock file is what makes your
plan and CI's plan the same plan.

Two providers, one workflow:

```hcl
aws       = { source = "hashicorp/aws",          version = "~> 6.0"  }
confluent = { source = "confluentinc/confluent", version = "~> 2.50" }
```

Confluent Cloud is not a special case. Same resources, same plan, same state.

### 2. Terraform configuration - `terraform/*.tf`

Files in a directory are one configuration; Terraform concatenates them, so
the split is purely for humans:

| File | |
|---|---|
| `network.tf` | hub and spoke VPCs, via the community VPC module |
| `tgw.tf` | the Transit Gateway and the routes between them |
| `eks.tf` | the EKS cluster, addons and node group |
| `privatelink.tf` | the Confluent gateway → VPC endpoint → access point → Route53 chain |
| `confluent.tf` | environment and Enterprise cluster |
| `locals.tf` | the mandatory tag set, defined once |
| `outputs.tf` | what the rest of the repo is allowed to read |

Three things worth saying out loud:

- **Dependencies are discovered, not declared.** `aws_vpc_endpoint.ccloud`
  refers to `confluent_gateway.ingress...vpc_endpoint_service_name`, so Terraform
  knows the Confluent gateway must exist first. `depends_on` is only for the
  rare case where the ordering is real but invisible, like
  `confluent_kafka_cluster.demo` needing the access point that nothing in its
  arguments mentions.
- **Modules are just folders of .tf files.** `module "eks"` is the community
  module, pinned with `version = "~> 21.0"`.
- **`for_each` keys must be known at plan time.** `aws_route.spoke_to_hub` in
  `tgw.tf` is the error everyone meets once, with the fix next to it. Route
  table IDs do not exist until apply, so `for_each = toset(module.spoke_vpc.private_route_table_ids)`
  fails with *"the for_each set includes values derived from resource
  attributes that cannot be determined until apply"*. Keys are how Terraform
  addresses instances in state, so they have to be static: build a map whose
  keys are the index and whose values are the apply-time IDs.

Run `make graph` to render the dependency graph if you want a picture.

### 3. Terraform state - `terraform.tfstate`, `terraform/backend.tf.example`

State is Terraform's memory: the map from your config to real resource IDs.

```bash
terraform -chdir=terraform state list
terraform -chdir=terraform state show confluent_kafka_cluster.demo
```

**`state list`** prints one line per thing Terraform is tracking: 132 here. A
trimmed sample (the EKS and VPC modules account for most of the rest):

```
data.confluent_schema_registry_cluster.demo
aws_ec2_transit_gateway.this
aws_route.hub_to_spoke["0"]
aws_vpc_endpoint.ccloud
confluent_access_point.hub
confluent_gateway.ingress
confluent_kafka_cluster.demo
confluent_tag_binding.this["cflt_keep_until/cluster"]
module.eks.aws_eks_cluster.this[0]
```

How to read an address, `[module.<name>.][data.]<type>.<name>[<key>]`:

- `aws_...` and `confluent_...` are the two providers: one state file, two clouds.
- `data.` entries are read, not created. Terraform looks them up (Schema Registry,
  availability zones) and destroys nothing when you run `make down`.
- `module.eks....` is a resource inside a module. The module is the community
  EKS module, so its internals appear under that prefix.
- `["0"]` and `["cflt_keep_until/cluster"]` are `count` and `for_each` instances.
  The key is how Terraform addresses each copy, which is why `for_each` keys
  must be known at plan time (section 2).
- If a resource is missing from this list, Terraform does not know it exists. It
  will not update it, and it will not destroy it.

**`state show`** prints what Terraform recorded for one resource (the
`rbac_crn` line, which carries your organisation ID, is left out here):

```
# confluent_kafka_cluster.demo:
resource "confluent_kafka_cluster" "demo" {
    availability        = "LOW"
    cloud               = "AWS"
    deletion_protection = false
    display_name        = "tf-brownbag"
    id                  = "lkc-gq2nr3v"
    region              = "eu-central-1"
    bootstrap_endpoint  = "lkc-gq2nr3v.eu-central-1.aws.private.confluent.cloud:9092"
    endpoints           = [
        { access_point_id = "PRIVATE_LINK", connection_type = "PRIVATE_LINK", ... },
        { access_point_id = "ap-8m67qz",    connection_type = "PRIVATE_LINK",
          bootstrap_endpoint = "lkc-gq2nr3v-ap8m67qz.eu-central-1.aws.accesspoint.glb.confluent.cloud:9092", ... },
    ]
    enterprise { max_ecku = 32 }
    environment { id = "env-g7p8rr" }
    network { id = null }
}
```

- **Two kinds of attribute.** `availability`, `cloud`, `region` and `display_name`
  are what `confluent.tf` set. `id` (`lkc-...`), the endpoints and `max_ecku` were
  filled in by Confluent after the create. That is why they are `(known after
  apply)` in a plan, and why `outputs.tf` can publish them.
- **Two endpoints, one cluster.** The first is Confluent's default private
  endpoint. The second belongs to our access point (`ap-8m67qz`) and is the one
  that resolves to the hub VPC. `locals.cluster_endpoint` in `confluent.tf` picks
  it by `access_point_id`, so this one line of state is what `make verify` ends
  up connecting to.
- **`null` blocks.** `network { id = null }` and `byok_key` are unused: an
  Enterprise cluster has no dedicated network to attach.
- **`deletion_protection = false`** is why `make down` can remove the cluster.

The state itself is a single object in S3. To see it there (this needs your AWS
credentials, for example `AWS_PROFILE=<your profile>`):

```bash
aws s3 ls s3://tfbrownbag-tfstate-mblumberg/tf-brownbag/terraform.tfstate --region eu-central-1
```

Two things people learn the hard way:

- **State contains secrets in plain text.** Provider credentials and
  anything marked sensitive end up in there. Marking an output `sensitive` hides it from the CLI, not from
  the file.
- **Local state does not scale past one person.** This repo's
  `terraform/backend.tf` stores state in a versioned, KMS-encrypted, private S3
  bucket with native locking (`use_lockfile = true`, no DynamoDB table any more).
  The bucket is created by `bootstrap/` (`state.tf`), because a configuration
  cannot keep its state in a bucket it has not created yet. CI and your laptop
  share the one state file, or they would each plan to rebuild the other's work.
  `backend.tf.example` is the template for your own project. Moving from local to
  S3 is `terraform init -migrate-state`.

### 4. Terraform variables - `terraform/variables.tf`

Inputs with types, descriptions, defaults and validation. Precedence, lowest
to highest:

```
default in variables.tf  <  terraform.tfvars  <  TF_VAR_<name>  <  -var on the CLI
```

`scripts/lib.sh` exports `TF_VAR_region` from `DEMO_REGION` in `.env`, so the
whole demo moves region without editing a `.tf` file:

```bash
echo 'DEMO_REGION=eu-west-1' >>.env && make plan
```

`cflt_keep_until` has a `validation` block: a typo becomes a plan-time error
instead of an untagged, un-reaped cluster.

### 5. Terraform output - `terraform/outputs.tf`

Outputs are this configuration's published interface, and the only way the
rest of the repo learns anything about the cloud:

```bash
terraform -chdir=terraform output
terraform -chdir=terraform output -raw ccloud_cluster_id
```

`scripts/verify.sh` reads the bootstrap host and the hub CIDR from them. No
generated endpoint is ever copy-pasted or committed.

### 6. `terraform plan` - `make plan`

A plan is a three-way diff: config vs state vs what the cloud actually looks
like now.

```bash
make plan      # writes terraform/tfplan
make apply     # applies exactly that file
```

Saving the plan is the habit to teach. What you reviewed is what gets applied,
even if someone edits a `.tf` while you are reading. Try the loop live:

```bash
# change node_count to 3 in terraform/terraform.tfvars
make plan      # 1 to change, 0 to add, 0 to destroy
```

### 7. `terraform apply` - `make infra`

Apply walks the graph and builds independent resources in parallel. It takes
about 20 minutes, almost all of it EKS and the PrivateLink chain. Mid-apply is
a good moment to show the Confluent Cloud UI filling in.

Apply is also the repair tool: delete the Route53 record by hand, run
`make plan`, and watch Terraform notice the drift and offer to put it back.

### 8. `terraform destroy` - `make down`

Everything here is owned by Terraform, so `make down` is just `terraform
destroy`: the graph walked backwards (cluster, access point, endpoint, EKS,
TGW, VPCs).

**Terraform only destroys what Terraform created.** Anything added by hand
(a topic, a workload that leaves a load balancer or volume behind) is not in
state and will either survive or block the destroy. Worth saying out loud.

### 9. GitHub integration - `.github/workflows/terraform.yml`

The same commands, moved to where the team can see them:

- **Pull request** → `fmt -check`, `validate`, `plan`, and the plan posted as a
  PR comment that updates in place.
- **Merge to main** → `apply`, gated behind a GitHub Environment with required
  reviewers, applying the exact plan artifact the PR produced.
- **OIDC, no static AWS keys.** The workflow assumes an IAM role; Confluent
  credentials come from repository secrets.

The comments at the top of the workflow list the variables, secrets and
environment to create.

#### One-off setup: the AWS role (`bootstrap/`)

CI needs an IAM role before it can run `terraform/`, so the role cannot be
created by the pipeline that depends on it. `bootstrap/` is a tiny separate
configuration with its own local state, applied once by hand:

```bash
export AWS_PROFILE=<your sandbox profile>
terraform -chdir=bootstrap init
terraform -chdir=bootstrap apply
gh secret set AWS_ROLE_ARN -R <owner>/<repo> --body "$(terraform -chdir=bootstrap output -raw role_arn)"
```

It creates these, all tagged (plus the state bucket described in section 3):

- the GitHub **OIDC provider** (`token.actions.githubusercontent.com`). An
  account can have only one. If yours already does, apply with
  `-var create_oidc_provider=false`.
- the **role** `tfBrownBag-github-actions`, whose trust policy allows only this
  repo (`var.github_repo`) and only two contexts: `pull_request` (the plan job)
  and `environment:production` (the apply job, behind required reviewers).
- an `AdministratorAccess` attachment, because the demo builds VPCs, a Transit
  Gateway, EKS and IAM roles. Fine for a short-lived demo role, not for
  anything real.

`AWS_ROLE_ARN` is a repository **secret**, not a variable, so the account ID in
it is masked in public workflow logs. The other settings:

| Where | Name |
|---|---|
| Variable | `AWS_REGION` |
| Secrets | `AWS_ROLE_ARN`, `CONFLUENT_CLOUD_API_KEY`, `CONFLUENT_CLOUD_API_SECRET` |
| Environment | `production`, with required reviewers |

Anyone with write access to this repo can open a PR from a branch and get the
role during the plan job. This is a personal repo with a single collaborator
(its owner), so today that is one person; **adding a collaborator extends the
role to them.** Fork PRs cannot obtain an OIDC token, and outside contributors'
workflow runs need the owner's approval (Settings > Actions > General). The
third-party actions in the workflow are pinned to commit SHAs, so a moved tag
cannot change what runs with the role.

**Tearing it down.** `make down` does not touch `bootstrap/`, because it has a
separate state. Destroy it last, once nothing else needs CI. This also deletes
the state bucket (`force_destroy`), so run `make down` first:

```bash
terraform -chdir=bootstrap destroy
```

Destroy it before the `cflt_keep_until` date.

---

## Design notes

### Why there is no topic

It would be a `confluent_kafka_topic` on a public cluster. This cluster's Admin
REST endpoint is PrivateLink-only, so Terraform - on a laptop or on a GitHub
runner - cannot reach it. Topics and clients are the next layer's job, run from
somewhere inside the VPC. This demo deliberately stops before that.

### Networking: Enterprise clusters and Transit Gateway

A Confluent Cloud *Enterprise* cluster is serverless and private-only, reached
over PrivateLink (or PNI). A **native** Confluent Cloud Transit Gateway
network is a *Dedicated*-cluster feature and a different resource set
(`confluent_network` with `connection_type = "TRANSITGATEWAY"`, an AWS RAM
share, `confluent_transit_gateway_attachment`).

So the TGW here does what it does at most customers: it is *their* fabric. The
PrivateLink endpoint lives once in a hub VPC, the Route53 private zone is
associated with both VPCs, and every spoke reaches Confluent through the hub
over the Transit Gateway. Adding a second spoke costs one TGW attachment, not
another endpoint.

The resolution path, worth drawing on a whiteboard:

```
pod in the spoke
  → *.ap-xxxx.eu-central-1.aws.accesspoint.confluent.cloud   (Route53 private zone)
  → CNAME to the VPC endpoint's regional DNS name
  → private IPs of the ENIs in the hub's subnets
  → Transit Gateway
  → AWS PrivateLink → Confluent Cloud
```

---

## Tagging

Every AWS resource carries the mandatory tag set, defined once in
`terraform/locals.tf` and applied through the provider's `default_tags`:

```
owner_email, owner_name, cflt_service, cflt_managed_by, cflt_managed_id, cflt_keep_until
```

`default_tags` does not reach resources AWS launches on our behalf, so two
places pass them explicitly:

- `module.eks.tags` → the launch template → EC2 instances and root volumes
- the EBS CSI addon's `extraVolumeTags` → volumes created for PVCs

Confluent Cloud has its own tags (Stream Catalog tags), set in `terraform/tags.tf`
with `confluent_tag` and `confluent_tag_binding`. They differ from AWS tags:

- A tag is a bare label with no value, so key and value are folded into the
  name: `cflt_keep_until_2026_12_03`, `cflt_managed_id_tf_brownbag`, and so on.
- They are stored in Schema Registry, so Terraform needs a Schema Registry API
  key (from a small `catalog` service account) and the cluster must exist first.
- They bind to the environment (`cf_environment`) and the cluster
  (`kafka_logical_cluster`). Service accounts and API keys cannot be tagged, so
  their descriptions carry the project name and keep-until date.
- Each binding takes about 2 minutes to create. On `make down` the first
  destroy can fail with `409 Conflict` deleting the tags, because binding
  removal is asynchronous. Wait a minute and run it again.

`owner_email` and `owner_name` have no Confluent tag, since `@` and `.` in a tag
name are untested.

---

## Layout

```
terraform/          AWS + Confluent Cloud. The subject of the talk.
bootstrap/          One-off: the GitHub OIDC provider and the CI role.
scripts/            infra, plan, preflight, status, verify, down.
slides/             Slidev deck for the session (make slides).
.github/workflows/  plan on PR, apply on merge.
```

---

## Troubleshooting

```bash
export KUBECONFIG=$PWD/.kubeconfig
kubectl get nodes
make verify
```

- **`make verify` fails to resolve, or resolves to a public address** - the
  Route53 zone is not associated with the spoke VPC, or the wildcard record
  is missing. The answer must be a private IP in the **hub** range (10.40.x.x).
- **`make verify` resolves but the connection times out** - check the TGW
  routes in `tgw.tf` and the endpoint's security group in `privatelink.tf`
  (ports 80, 443, 9092 from both VPC ranges).
- **`AccessDeniedException ... explicit deny in a service control policy`** -
  the account forbids `eks:CreateCluster`, `ec2:CreateNatGateway` or
  `ec2:CreateVpcEndpoint`. A `terraform plan` will not catch this: a plan asks
  what would change, not whether you are allowed to change it. Run
  `make preflight` and pick another account. This is not hypothetical - it is
  why `scripts/preflight.sh` exists.
- **`TransitGatewayLimitExceeded`** - the default quota is 5 per account per
  region and shared internal accounts are often already past it.
  `make preflight` prints used-vs-limit for all four of the usual suspects.
- **`VpcLimitExceeded`** - the demo builds two VPCs. Pick a region with
  headroom (`DEMO_REGION=eu-west-1`) or raise the quota. If an apply fails
  part-way, destroy in the *same* region before switching.

## Security notes

- No credentials in the repo: `.env`, `*.tfvars`, state and `.kubeconfig` are
  git-ignored.
- Terraform state is local by default and **contains secrets**. Move it to the
  encrypted S3 backend before anyone else touches this.
