---
theme: default
title: Terraform for Confluent Cloud
info: Brownbag - managing Confluent Cloud with Terraform, on AWS, from landing zone to a private Kafka cluster
colorSchema: dark
transition: slide-left
mdc: true
fonts:
  sans: Inter
  mono: JetBrains Mono
layout: cover
class: cover
---

<div class="eyebrow">Brownbag</div>

# Terraform for<br/><span class="grad">Confluent Cloud</span>

<div class="sub">
One workflow for the cloud account, the Kafka cluster and everything in between
</div>

<div class="chips">
  <span>Terraform</span><span>Confluent Cloud · Enterprise</span><span>AWS · EKS</span><span>Transit Gateway</span><span>PrivateLink</span>
</div>

<!--
Thirty minutes of concepts, then we watch it build live.

Everything on these slides exists as a file in the repo - I'll name the file
every time, so you can go read it afterwards.
-->

---
layout: center
class: text-center
---

# The thing we all do

<div class="grid grid-cols-3 gap-6 mt-10 text-left">
<div v-click class="card">
  <div class="card-k">Monday</div>
  <h3>Click it together</h3>
  <p>Environment, cluster, service account, API key, a network. Twelve minutes in the console.</p>
</div>
<div v-click class="card">
  <div class="card-k">Thursday</div>
  <h3>Do it again</h3>
  <p>Someone needs the same thing in another region. Nobody remembers which boxes were ticked.</p>
</div>
<div v-click class="card warn">
  <div class="card-k">Three months later</div>
  <h3>Who owns this?</h3>
  <p>No tags, no owner, no keep-until, and nobody dares delete it.</p>
</div>
</div>

<div v-click class="statement mt-12">
The fix is not discipline. It is <span class="grad">putting it in a repo</span>.
</div>

<!--
Ask the room: who has a cluster running right now that they cannot account for?
Usually a few hands. That's the hook.
-->

---

# What we are building today

<div class="arch mt-6">
  <div class="zone eks" style="grid-column:1;grid-row:1/6"></div>
  <div class="zone cloud" style="grid-column:3;grid-row:1/6"></div>

  <div class="zlabel" style="grid-column:1;grid-row:1">AWS · spoke VPC · EKS</div>
  <div class="zlabel" style="grid-column:3;grid-row:1">Confluent Cloud · env tf-brownbag</div>

  <div class="box main" style="grid-column:1;grid-row:2">EKS nodes</div>
  <div class="wire" style="grid-column:2;grid-row:2"><span>Transit Gateway</span></div>
  <div class="box cl main" style="grid-column:3;grid-row:2">Enterprise cluster</div>

  <div class="box" style="grid-column:1;grid-row:3">Route53 private zone</div>
  <div class="wire" style="grid-column:2;grid-row:3"><span>PrivateLink · 9092</span></div>
  <div class="box cl" style="grid-column:3;grid-row:3">ingress gateway</div>

  <div class="box" style="grid-column:1;grid-row:4">hub VPC endpoint</div>
  <div class="wire" style="grid-column:2;grid-row:4"><span>registered with</span></div>
  <div class="box cl" style="grid-column:3;grid-row:4">access point</div>

  <div class="mini" style="grid-column:1;grid-row:5">
    <span>spoke VPC</span><span>hub VPC</span><span>NAT</span>
  </div>
  <div class="mini" style="grid-column:3;grid-row:5">
    <span>environment</span><span>cluster</span>
  </div>
</div>

<div class="foot">Two providers, one <code>terraform apply</code>, one state file.</div>

<!--
Left half is AWS, right half is Confluent Cloud, and the interesting part is
that Terraform treats them identically.

The Kafka cluster is private-only. Nothing in this picture has a public
endpoint except the EKS API server.
-->

---
layout: center
class: text-center
---

# Terraform in one sentence

<div class="statement mt-8">
You describe the <span class="grad">end state</span>.<br/>
Terraform works out the <span class="grad">actions</span>.
</div>

<div class="term mt-12">
<span class="p">$</span> terraform init     <span class="c"># download providers, pin versions</span><br/>
<span class="p">$</span> terraform plan     <span class="c"># what would change, and why</span><br/>
<span class="p">$</span> terraform apply    <span class="c"># make it so</span><br/>
<span class="p">$</span> terraform destroy  <span class="c"># and take it away again</span>
</div>

<div class="note">Four commands. Everything else is detail.</div>

<!--
Declarative, not imperative: you never write "create then update then delete".
You write what should exist, and the diff is computed for you.
-->

---

# Two providers, one workflow

<div class="grid grid-cols-2 gap-8 mt-4">
<div>

```hcl
# terraform/versions.tf
terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.50"
    }
  }
}
```

</div>
<div>

<div v-click class="card">
  <div class="card-k">The point of the session</div>
  <h3>Confluent Cloud is not a special case</h3>
  <p>Same resources, same data sources, same plan, same state file, same CI pipeline as the AWS half.</p>
</div>

<div v-click class="card mt-4">
  <div class="card-k">init writes a lock file</div>
  <h3><code>.terraform.lock.hcl</code></h3>
  <p>Commit it. It is what makes your plan and CI's plan the same plan.</p>
</div>

<div v-click class="card mt-4">
  <div class="card-k">Credentials</div>
  <h3>Never in a <code>.tf</code> file</h3>
  <p><code>CONFLUENT_CLOUD_API_KEY</code> / <code>_SECRET</code> come from the environment.</p>
</div>

</div>
</div>

<!--
"~> 6.0" means ">= 6.0, < 7.0": take the bug fixes, don't take the breaking
change on a Friday afternoon.
-->

---

# Configuration is just files

<div class="grid grid-cols-2 gap-10 mt-6">
<div class="files">
<b>versions.tf</b>  <span>providers and their versions</span><br/>
<b>variables.tf</b>  <span>inputs, with types and validation</span><br/>
<b>locals.tf</b>  <span>the mandatory tag set, once</span><br/>
<b>network.tf</b>  <span>hub and spoke VPCs</span><br/>
<b>tgw.tf</b>  <span>Transit Gateway + routes</span><br/>
<b>eks.tf</b>  <span>cluster, addons, node group</span><br/>
<b>privatelink.tf</b>  <span>gateway → endpoint → access point → DNS</span><br/>
<b>confluent.tf</b>  <span>environment, cluster, identities</span><br/>
<b>outputs.tf</b>  <span>the published interface</span>
</div>
<div>

<div v-click class="card">
  <div class="card-k">Terraform does not care</div>
  <h3>One directory = one configuration</h3>
  <p>The files are concatenated. The split is for humans reading a diff, nothing else.</p>
</div>

<div v-click class="card accent mt-4">
  <div class="card-k">The part that surprises people</div>
  <h3>Ordering is discovered, not declared</h3>
  <p><code>aws_vpc_endpoint</code> refers to an attribute of <code>confluent_gateway</code>, so the gateway is built first. You never write the order.</p>
</div>

<div v-click class="card mt-4">
  <div class="card-k">The exception</div>
  <h3><code>depends_on</code></h3>
  <p>For ordering that is real but invisible. Our Enterprise cluster needs the access point, and says so in no other way.</p>
</div>

</div>
</div>

<!--
make graph renders the dependency graph as an SVG if someone wants to see it.
-->

---

# The error everyone meets once

<div class="grid grid-cols-2 gap-8 mt-4">
<div>

```hcl
# looks obvious, fails at plan time
resource "aws_route" "spoke_to_hub" {
  for_each = toset(
    module.spoke_vpc.private_route_table_ids
  )
  ...
}
```

<div class="card warn mt-4">
  <div class="card-k">terraform plan</div>
  <p><code>The "for_each" set includes values derived from resource attributes that cannot be determined until apply</code></p>
</div>

</div>
<div>

<div v-click class="card">
  <div class="card-k">Why</div>
  <h3>Keys are addresses in state</h3>
  <p><code>aws_route.spoke_to_hub["rtb-0a1b…"]</code> is how Terraform remembers this instance. It cannot name it after something that does not exist yet.</p>
</div>

<div v-click class="card accent mt-4">
  <div class="card-k">The fix</div>
  <h3>Static keys, apply-time values</h3>

```hcl
for_each = {
  for i, rt in module.spoke_vpc
    .private_route_table_ids :
      tostring(i) => rt
}
```

</div>

</div>
</div>

<div class="foot"><code>terraform/tgw.tf</code> - the fix and the explanation are in the comments.</div>

<!--
This slide buys back an hour for everyone in the room the first time they hit
it. It is also a clean way to explain what state addresses actually are.
-->

---

# State: Terraform's memory

<div class="grid grid-cols-2 gap-8 mt-6">
<div>

<div class="card">
  <div class="card-k">What it is</div>
  <h3>config ⟷ real resource IDs</h3>
  <p>Without it, Terraform cannot tell "create a cluster" from "you already have that cluster".</p>
</div>

```bash
terraform state list
terraform state show \
  confluent_kafka_cluster.demo
```

</div>
<div>

<div v-click class="card warn">
  <div class="card-k">Gotcha 1</div>
  <h3>State holds secrets in plain text</h3>
  <p>Every API key this config created is in that file. <code>sensitive = true</code> hides an output from the terminal, not from the state.</p>
</div>

<div v-click class="card warn mt-4">
  <div class="card-k">Gotcha 2</div>
  <h3>Local state does not survive a second person</h3>
  <p>Your apply is invisible to their plan, and nothing stops two applies at once.</p>
</div>

<div v-click class="card accent mt-4">
  <div class="card-k">The fix, once</div>
  <h3>S3 backend</h3>
  <p>Versioned, encrypted, <code>use_lockfile = true</code>. No DynamoDB table any more. See <code>backend.tf.example</code>.</p>
</div>

</div>
</div>

<!--
If you take one thing away: state is a secret, and it belongs in an encrypted
bucket before a second person touches the repo.
-->

---

# Variables, and who wins

<div class="ladder mt-8">
  <div class="rung">default in variables.tf <span class="why">the sane fallback, committed</span></div>
  <div class="rung" v-click>terraform.tfvars <span class="why">your laptop, git-ignored</span></div>
  <div class="rung" v-click>TF_VAR_region=eu-west-1 <span class="why">what scripts and CI set</span></div>
  <div class="rung win" v-click>terraform apply -var region=... <span class="why">wins, every time</span></div>
</div>

<div v-click class="grid grid-cols-2 gap-6 mt-8">
<div class="card">
  <div class="card-k">In this repo</div>
  <h3>Move region without editing code</h3>

```bash
echo 'DEMO_REGION=eu-west-1' >>.env
make plan
```

</div>
<div class="card">
  <div class="card-k">Validation earns its keep</div>
  <h3><code>cflt_keep_until</code></h3>
  <p>A <code>validation</code> block turns a typo into a plan-time error, instead of an untagged cluster nobody reaps.</p>
</div>
</div>

<!--
The tagging policy is a nice live example: six mandatory tags, declared once in
locals.tf, applied by the provider's default_tags, validated at plan time.
-->

---

# Outputs: the published interface

<div class="grid grid-cols-2 gap-8 mt-6">
<div>

```hcl
output "ccloud_bootstrap" {
  description = "Private bootstrap endpoint"
  value       = local.cluster_endpoint.bootstrap_endpoint
}

output "ccloud_cluster_id" {
  description = "Enterprise Kafka cluster ID (lkc-...)."
  value       = confluent_kafka_cluster.demo.id
}
```

```bash
terraform output
terraform output -raw ccloud_cluster_id
terraform output -json | jq .
```

</div>
<div>

<div v-click class="card accent">
  <div class="card-k">Why it matters here</div>
  <h3>Nothing downstream is hard-coded</h3>
  <p>The <code>lkc-</code> and the private endpoints do not exist until apply. Scripts, CI and people read them from <code>terraform output</code>.</p>
</div>

<div v-click class="flow mt-6">
  <div class="seg"><b>outputs</b>bootstrap, IDs</div>
  <div class="sep">→</div>
  <div class="seg"><b>make verify</b>pod in the VPC</div>
</div>

</div>
</div>

<!--
Outputs are how the rest of the world learns what Terraform built. make verify
reads the bootstrap host from here and tests it from inside the VPC.
-->

---

# plan: a three-way diff

<div class="flow mt-10">
  <div class="seg"><b>your config</b>what you wrote</div>
  <div class="sep">↔</div>
  <div class="seg"><b>state</b>what Terraform built last time</div>
  <div class="sep">↔</div>
  <div class="seg"><b>reality</b>what the API says right now</div>
</div>

<div class="grid grid-cols-2 gap-8 mt-10">
<div v-click>

```bash
make plan     # -> terraform/tfplan
make apply    # applies exactly that file
```

<div class="card mt-4">
  <div class="card-k">Habit worth teaching</div>
  <h3>Save the plan, apply the file</h3>
  <p>What you reviewed is what runs, even if someone edits a <code>.tf</code> while you read it.</p>
</div>

</div>
<div v-click>

<div class="card accent">
  <div class="card-k">Plan is also the drift detector</div>
  <h3>Delete something by hand</h3>
  <p>Remove the Route53 record in the console, run <code>make plan</code>, and Terraform offers to put it back. Same mechanism, no extra tool.</p>
</div>

<div class="card mt-4">
  <div class="card-k">Read the symbols</div>
  <p><code>+</code> create · <code>~</code> update in place · <code>-/+</code> replace · <code>-</code> destroy</p>
  <p>The one to read twice is <code>-/+</code>.</p>
</div>

</div>
</div>

<!--
A plan is read-only but it does need credentials: it calls the APIs to refresh.
That matters for CI permissions.
-->

---

# apply, and destroy

<div class="grid grid-cols-2 gap-8 mt-6">
<div>

<div class="card">
  <div class="card-k">apply</div>
  <h3>Walks the graph, in parallel</h3>
  <p>Independent resources go at once. ~20 minutes here, almost all of it EKS and the PrivateLink chain.</p>
</div>

<div v-click class="card mt-4">
  <div class="card-k">apply is also the repair tool</div>
  <h3>Converge, don't reinstall</h3>
  <p>Re-running on a healthy stack is a no-op. On a drifted one it puts things back.</p>
</div>

</div>
<div>

<div v-click class="card">
  <div class="card-k">destroy</div>
  <h3>Reverse order, automatically</h3>
  <p>Same graph, walked backwards.</p>
</div>

<div v-click class="card warn mt-4">
  <div class="card-k">The honest caveat</div>
  <h3>Terraform destroys only what Terraform created</h3>
  <p>Here that is everything, so <code>make down</code> is one command. Anything added by hand (a topic, a pod, a console click) is not in state and will not be cleaned up, or will block the destroy.</p>
</div>

</div>
</div>

<div v-click class="foot">Anything outside state is paid for at teardown. Keep the list short, and say so out loud in design reviews.</div>

<!--
This is the slide people remember. Half-deleted demos are how orgs end up with
mystery spend.
-->

---

# GitHub: the same commands, in the open

<div class="steps mt-8">
  <div class="step"><b>pull request</b><div>
    <div><code>fmt -check</code> · <code>validate</code> · <code>plan</code> · plan posted as a PR comment</div>
    <p>Read-only. The reviewer sees the diff in cloud terms, not just in HCL.</p>
  </div></div>
  <div class="step" v-click><b>merge to main</b><div>
    <div><code>apply</code>, gated by a GitHub Environment with required reviewers</div>
    <p>Applies the exact plan artifact the PR produced. Merging is not the same act as applying.</p>
  </div></div>
  <div class="step" v-click><b>auth</b><div>
    <div>OIDC role assumption, no long-lived AWS keys in the repo</div>
    <p>Confluent Cloud key stays a repository secret.</p>
  </div></div>
  <div class="step" v-click><b>prerequisite</b><div>
    <div>Remote state</div>
    <p>CI and your laptop must share one state file, or each plans to rebuild the other's work.</p>
  </div></div>
</div>

<div class="foot"><code>.github/workflows/terraform.yml</code></div>

<!--
The PR comment is the part that changes team behaviour: infrastructure review
stops being "I trust you" and becomes a readable diff.
-->

---
layout: center
class: text-center
---

# Where Terraform stops

<div class="flow mt-12 text-left">
  <div class="seg"><b>Terraform</b>VPCs, TGW, EKS, PrivateLink, Route53, Confluent Cloud environment and Enterprise cluster</div>
  <div class="sep">→</div>
  <div class="seg"><b>Your workloads</b>topics, clients, connectors - the next layer, deployed however you like</div>
</div>

<div v-click class="statement mt-12">
Terraform builds the <span class="grad">road</span>. What drives on it is a separate decision.
</div>

<div v-click class="note">
The finish line for this demo is a pod in EKS resolving the cluster to a private
address in the hub VPC and opening a TCP connection to it.
</div>

<!--
Live bit: make verify. The pod resolves the bootstrap host to 10.40.x.x and
connects on 9092, all over the TGW and PrivateLink.
-->

---

# Two things that look odd, and why

<div class="grid grid-cols-2 gap-8 mt-8">
<div class="card">
  <div class="card-k">The topic</div>
  <h3>Not a <code>confluent_kafka_topic</code></h3>
  <p>On a public cluster it would be. This cluster's Admin REST endpoint is PrivateLink-only, so Terraform - on a laptop or a GitHub runner - cannot reach it.</p>
  <p>Topics are the next layer's job: something that runs inside the VPC.</p>
</div>
<div class="card">
  <div class="card-k">The <code>depends_on</code></div>
  <h3>The one ordering Terraform cannot see</h3>
  <p>Nothing in the cluster's arguments mentions the access point, but the cluster must be created after it or it gets no private endpoint.</p>
</div>
</div>

<div v-click class="statement mt-10 text-center">
Private networking is not an edge case. <span class="grad">Design for it.</span>
</div>

<!--
Both of these cost an hour of confusion the first time. Worth ten seconds here.
-->

---

# Access as data, contracts as files

<div class="grid grid-cols-2 gap-8 mt-8">
<div class="card accent">
  <div class="card-k">access.tf</div>
  <h3>A PR is an access request</h3>
  <p><code>teams.yaml</code> becomes service accounts and role bindings with <code>yamldecode</code> and <code>for_each</code>. The plan lists exactly the identities and permissions the YAML creates.</p>
</div>
<div class="card">
  <div class="card-k">schemas.tf</div>
  <h3>A breaking schema never applies</h3>
  <p>Every <code>.avsc</code> file is a subject, pinned to <code>BACKWARD</code>. A new required field fails the <em>plan</em>, on the PR.</p>
</div>
</div>

<div v-click class="statement mt-10 text-center">
Review the <span class="grad">plan</span>, not the click-path.
</div>

<!--
Live: add the analytics team in a PR, show the 3-resource plan comment, merge,
approve. Then break the schema and show the PR failing.
-->

---

# Networking: hub, spoke, and one door

<div class="chain mt-10">
  <div class="node">pod<br/><small>spoke VPC</small></div>
  <div class="link">→</div>
  <div class="node">Route53<br/><small>private zone</small></div>
  <div class="link">→</div>
  <div class="node hl">Transit<br/>Gateway</div>
  <div class="link">→</div>
  <div class="node">VPC endpoint<br/><small>hub VPC</small></div>
  <div class="link">→</div>
  <div class="node">PrivateLink<br/><small>Confluent Cloud</small></div>
</div>

<div class="grid grid-cols-2 gap-8 mt-10">
<div v-click class="card">
  <div class="card-k">Why this shape</div>
  <h3>One endpoint, many spokes</h3>
  <p>The private zone is associated with both VPCs. A second spoke costs one TGW attachment, not another endpoint.</p>
</div>
<div v-click class="card warn">
  <div class="card-k">Know the difference</div>
  <h3>TGW <em>to</em> Confluent is a Dedicated feature</h3>
  <p>Enterprise clusters are PrivateLink or PNI. A native Confluent TGW network needs <code>confluent_network</code>, a RAM share and a Dedicated cluster.</p>
</div>
</div>

<!--
Most customers already have a TGW fabric. The question is never "TGW or
PrivateLink", it is "where does the one endpoint live".
-->

---
layout: center
class: text-center
---

# Let's run it

<div class="term mt-10">
<span class="p">$</span> cp .env.example .env   <span class="c"># Confluent Cloud API key</span><br/>
<span class="p">$</span> make up                <span class="c"># ~25 min</span><br/>
<span class="p">$</span> make status            <span class="c"># outputs + EKS nodes</span><br/>
<span class="p">$</span> make verify            <span class="c"># the private path, from a pod</span><br/>
<span class="p">$</span> make down              <span class="c"># and nothing left behind</span>
</div>

<div class="note">
github.com/MosheBlumbergX · the repo is the handout
</div>

<!--
Demo order that works well:
  1. make plan, read the summary line
  2. terraform state list while apply runs
  3. Confluent Cloud UI filling in
  4. make verify
  5. make down
-->

---
layout: center
class: text-center
---

# Three things to take away

<div class="grid grid-cols-3 gap-6 mt-12 text-left">
<div v-click class="card">
  <div class="num">01</div>
  <h3>Confluent Cloud is just another provider</h3>
  <p>Same plan, same state, same review. No reason for it to live outside the repo.</p>
</div>
<div v-click class="card">
  <div class="num">02</div>
  <h3>State is a secret and a shared resource</h3>
  <p>Encrypted remote backend before the second person joins. Not after.</p>
</div>
<div v-click class="card accent">
  <div class="num">03</div>
  <h3>Private networking is the real work</h3>
  <p>The cluster is a few lines. The hub, the TGW, the endpoint and the DNS are what make it reachable.</p>
</div>
</div>

<div v-click class="statement mt-14">
Questions?
</div>
