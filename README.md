# Azure Load-Balanced Auto-Healing Web Tier

An auto-healing, load-balanced NGINX web tier on Azure, built with Bicep. Losing any single VM instance, or an entire Availability Zone, does not cause downtime.

## Architecture

See hand drawn image

Internet traffic reaches a Standard public IP, then a Standard Load Balancer, which health-probes (HTTP, port 80, `/`) and distributes requests across three VM instances, one per Availability Zone, running NGINX. All three instances are managed by a single Virtual Machine Scale Set registered into the load balancer's backend pool.

## Repository structure

```
azure-load-balanced-auto-healing-web-tier/
├── main.bicep                            orchestrator — wires the three modules together
├── modules/
│   ├── networking/network.bicep          VNet, single subnet
│   ├── load-balancer/loadbalancer.bicep  public IP, load balancer, backend pool, health probe
│   └── compute/compute.bicep             VMSS: zones, upgrade policy, NGINX bootstrap
├── whatif-output.txt                     what-if output (surfaced the missing health probe issue)
├── deploy-run1.txt                       first real deployment — succeeded after the fix
├── deploy-run2.txt                       second identical deployment — proves idempotency
├── architecture-diagram.png
├── .gitignore
└── README.md
```

## How to run

**Prerequisites:** Azure CLI, logged in (`az login`), an Azure subscription.

```powershell
# Create a resource group (not automated in this template — see Design decisions)
az group create --name rg-web-tier-task --location australiaeast

# Validate the deployment plan (no resources are created)
az deployment group what-if `
  --resource-group rg-web-tier-task `
  --template-file main.bicep `
  --parameters adminUsername=azureadmin adminPassword='<a-valid-password>'
```

`adminPassword` must satisfy Azure's complexity requirements (uppercase, lowercase, digit, symbol, 12+ characters) or validation will fail at that field specifically; nothing else in the template carries this constraint.

**To actually deploy (optional — not required for review):**

```powershell
az deployment group create `
  --resource-group rg-web-tier-task `
  --template-file main.bicep `
  --parameters adminUsername=azureadmin adminPassword='<a-valid-password>'
```

Once deployed, the site is reachable at the load balancer's public IP, exposed as the `loadBalancerPublicIp` output.

## Cloud and tool choice

**Azure**, over AWS. In Azure, zone redundancy is configured on the compute resource itself (the VMSS's `zones` property); a single, region-scoped subnet is sufficient regardless of how many zones the instances span. AWS subnets are pinned to a single Availability Zone at creation, so the equivalent AWS design would structurally require a separate subnet per zone. Azure's model matched this task's scope with less network-layer complexity, and it's also where my production experience sits.

**Bicep**, over Terraform. Terraform is the brief's stated preference, and Bicep is explicitly listed as an allowed alternative. I chose Bicep because it's where my seven years of hands-on Azure experience actually is, I wanted every design decision here, zone placement, upgrade batching, network wiring, to reflect genuine architectural judgement rather than syntax I'm still building. I'm actively extending that into Terraform and AWS separately, to become more vendor-neutral, and I'm glad to walk through how this same design would translate.

## Design decisions

**Three instances across three Availability Zones, not two.** The brief states traffic must be "spread across at least two instances" as a standing condition, not a one-time count. With two instances, an automatic health-triggered instance repair (delete-then-create by default) can briefly leave only one instance healthy. With three, at least two remain healthy and serving traffic throughout any single-instance repair or a full zone outage. The added cost of a third small instance is minor set against the impact of a single point of failure.

**Single VNet, single subnet, not one per zone.** In Azure, subnets are region-scoped, not zone-scoped, so one subnet can serve instances spread across all three zones. This is a genuine difference from AWS, where zone redundancy would require multiple, zone-pinned subnets.

**Australia East as the target region.** Chosen specifically because it supports three Availability Zones; some Azure regions only offer two, which would have forced a different instance/zone count.

**Rolling upgrade policy** (`upgradePolicy.mode: Rolling`), not `Manual` or `Automatic`. `Automatic` is explicitly discouraged by Microsoft for no-downtime requirements, since it can update every instance simultaneously with no ordering guarantee. `Manual` provides no automated healing at all. With three instances, a 34% max batch size resolves to exactly one instance per batch regardless of how the platform rounds internally (34% of 3 = 1.02, clearly above the one-instance threshold either way; 33% would leave that rounding ambiguous).

**A real Azure platform requirement surfaced during deployment, not during `what-if`.** The first live deployment attempt failed with: *"Rolling Upgrade mode is not supported for this Virtual Machine Scale Set because a health probe or health extension was not provided."* The load balancer's health probe existed, but the VMSS itself was never told to use it, `Rolling` mode requires the scale set to reference a health probe directly via `virtualMachineProfile.networkProfile.healthProbe`, not just have one exist on the load balancer. `what-if` did not catch this, it validates structural correctness (resource references, dependencies) but not every business-rule constraint Azure enforces at actual creation time. The fix was a `healthProbeId` parameter threaded from the load balancer module's existing `healthProbeId` output into the compute module, then referenced in the VMSS's `networkProfile`. After the fix, deployment succeeded.

**No CPU-based autoscaling.** Scale set capacity is fixed at 3, with no metric-driven trigger. A static NGINX welcome page has no real traffic pattern to scale against; self-healing (replacing a failed instance) is handled independently of scaling.

**NGINX via cloud-init (`customData`)**, not a custom image or VM extension. A base64-encoded cloud-init script installs and enables NGINX on first boot, keeping the base image standard (Ubuntu 24.04 LTS) and avoiding the overhead of maintaining a golden image for a static page.

**Password-based admin authentication, not SSH keys, and no enforced password complexity in the template itself.** A deliberate simplification for this task's scope; SSH access isn't exercised by any of the five requirements. In a production build I'd switch to key-based authentication (`disablePasswordAuthentication: true` with a supplied public key), or at minimum add explicit `@minLength()` / complexity constraints on the password parameter so a weak value fails at validation rather than relying on Azure's own runtime check.

**No DNS or TLS/HTTPS.** The load balancer serves plain HTTP on port 80, matching the "default NGINX welcome page" scope of the task. Production use would need both.

**Resource group creation is not part of the template.** `main.bicep` deploys *into* an existing resource group rather than creating one, this is standard practice (a Bicep deployment targets a resource group, it doesn't typically own its own target's lifecycle). Creating one is a single extra CLI command, shown above.

## Assumptions

- Deployed and validated in Australia East; the design assumes the target region supports at least two Availability Zones.
- `Standard_B1s` is sufficient for a static welcome page; this is not a performance-tuned SKU choice.
- Admin credentials used for validation: username `azureadmin`, password matching Azure's complexity requirements (not hardcoded in the template; supplied at deploy time).
- No DNS or TLS is in scope, per the brief's "default NGINX welcome page" requirement.

## Estimated monthly cost

| Resource | Estimate (AUD/month) |
|---|---|
| Load Balancer (Standard SKU) | ~$25–30 |
| Public IP (Standard SKU) | ~$4 |
| 3 × `Standard_B1s` VM instances | ~$21–24 combined |
| 3 × Standard HDD OS disks | ~$6–9 combined |
| **Total** | **~$56–67** |

This exceeds the brief's AUD 20/month target. The Standard Load Balancer accounts for most of the gap; Standard SKU is required for zone-redundant configurations, so a cheaper Basic SKU wasn't available once zone spread was chosen as the resilience model. A cost-constrained version (single zone, Basic Load Balancer, two instances) could run under $20/month if continuous low-cost operation were the priority over the fuller resilience pattern demonstrated here; happy to discuss that trade-off.

## What was validated

Three pieces of evidence are included in this repo:

- **`whatif-output.txt`** — the initial `what-if` run. It reported the deployment as structurally valid (4 resources to create, all cross-module references resolving correctly), but did not catch the missing health probe wiring, which only surfaced on an actual deploy.
- **`deploy-run1.txt`** — the first successful live deployment, after the health probe fix, all four resources created (`provisioningState: Succeeded`).
- **`deploy-run2.txt`** — an immediately repeated deployment with identical parameters. Same `templateHash` as the first run, `provisioningState: Succeeded`, no resources recreated or modified. This is the empirical proof of idempotency the brief asks for ("one command stands everything up; a second run makes no changes"), not just an architectural claim.

A screenshot of the deployed NGINX welcome page, reached via the load balancer's public IP, is included as further confirmation the tier was genuinely serving traffic. Resources were torn down after validation (`az group delete`) to avoid ongoing cost.