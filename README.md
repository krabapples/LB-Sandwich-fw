# LB-Sandwich-fw

Terraform deployment for Palo Alto Networks VM-Series firewalls in an Azure **load balancer sandwich** (transit VNet) topology. This repository deploys the firewall layer only — it is designed to sit on top of existing network infrastructure, either provisioned by [LB-Sandwich-infra](https://github.com/krabapples/LB-Sandwich-infra) or any other Azure deployment.

---

## Architecture

```
                        Internet
                           │
                    ┌──────▼──────┐
                    │  Public LB  │  (external, deployed here)
                    └──────┬──────┘
                           │
              ┌────────────┴────────────┐
              │                         │
       ┌──────▼──────┐           ┌──────▼──────┐
       │  VM-Series  │           │  VM-Series  │
       │  Firewall 1 │           │  Firewall 2 │
       │  (Zone 1)   │           │  (Zone 2)   │
       └──────┬──────┘           └──────┬──────┘
              │                         │
              └────────────┬────────────┘
                    ┌──────▼──────┐
                    │  Private LB │  (internal, deployed here)
                    └──────┬──────┘
                           │
                    Private workloads
```

Each firewall has three network interfaces:

| Interface | Subnet      | Purpose                                          |
|-----------|-------------|--------------------------------------------------|
| mgmt      | management  | SSH / HTTPS management access (public IP)        |
| public    | public      | Untrust (internet-facing); registered to public LB backend pool; public IP for outbound SNAT |
| private   | private     | Trust (internal); registered to private LB backend pool |

---

## What this repository deploys

| Resource | Description |
|---|---|
| `azurerm_linux_virtual_machine` | Two VM-Series NGFW instances, one per Availability Zone |
| `azurerm_network_interface` | Three NICs per firewall (management, public, private) |
| `azurerm_public_ip` | One public IP per management NIC and one per public NIC |
| `azurerm_lb` (public) | External Azure Load Balancer with a public frontend IP |
| `azurerm_lb` (private) | Internal Azure Load Balancer with a static private frontend IP |
| `azurerm_lb_backend_address_pool` | One backend pool per load balancer; both firewalls registered |
| `azurerm_lb_rule` / `azurerm_lb_probe` | Load balancing rules and health probes |
| `random_password` | Auto-generated admin password (if not explicitly provided) |
| `azurerm_availability_set` | Optional; used when Availability Zones are not available |
| Log Analytics Workspace + Application Insights | Optional; enabled via `ngfw_metrics` variable |
| Azure Storage Account + File Share | Optional; used for full PAN-OS bootstrap via `bootstrap_storages` |

---

## Prerequisites

### 1. Existing network infrastructure

This repository does **not** create virtual networks, subnets, route tables, or NSGs. Those must already exist before deploying. You need:

- A **management subnet** — for firewall management interfaces
- A **public (untrust) subnet** — for firewall public interfaces
- A **private (trust) subnet** — for firewall private interfaces
- A **public NSG** attached to the public subnet (used for LB auto-rules)
- A **resource group** that will contain all resources deployed here

If you are using [LB-Sandwich-infra](https://github.com/krabapples/LB-Sandwich-infra), all of the above are created for you.

### 2. Subnet resource IDs

You need the Azure resource ID of each subnet. These look like:

```
/subscriptions/<subscription-id>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<subnet-name>
```

**From LB-Sandwich-infra:**
```bash
terraform output subnet_ids
```

**From az CLI (any existing deployment):**
```bash
az network vnet subnet list \
  --resource-group <resource-group> \
  --vnet-name <vnet-name> \
  --query "[].{name:name, id:id}" -o table
```

**From the Azure Portal:**
Go to **Virtual Networks** → select your VNet → **Subnets** → click a subnet → copy the **Resource ID** from the Properties blade.

### 3. Public NSG name

The public load balancer uses `nsg_auto_rules_settings` to automatically add inbound Allow rules to a Network Security Group. You need the **name** of the NSG attached to the public subnet.

**From LB-Sandwich-infra:** the NSG name follows the pattern `<name_prefix>public-nsg` (e.g. `example-public-nsg`).

**From az CLI:**
```bash
az network nsg list --resource-group <resource-group> --query "[].name" -o table
```

### 4. Terraform and Azure authentication

- Terraform >= 1.5
- Azure CLI authenticated (`az login`) **or** environment variable `ARM_SUBSCRIPTION_ID` set

---

## Usage

### Step 1 — Clone the repository

```bash
git clone https://github.com/krabapples/LB-Sandwich-fw.git
cd LB-Sandwich-fw
```

### Step 2 — Create your tfvars file

Copy the example and fill in the required values:

```bash
cp example.tfvars terraform.tfvars
```

Open `terraform.tfvars` and fill in:

| Field | Required | Description |
|---|---|---|
| `subscription_id` | Yes* | Azure Subscription ID. Can be omitted if `ARM_SUBSCRIPTION_ID` env var is set |
| `region` | Yes | Azure region (must match the region of your existing network infrastructure) |
| `resource_group_name` | Yes | Name of the existing resource group to deploy into |
| `name_prefix` | No | Prefix added to all resource names. Default: `""` |
| `subnet_ids.management` | Yes | Resource ID of the management subnet |
| `subnet_ids.public` | Yes | Resource ID of the public (untrust) subnet |
| `subnet_ids.private` | Yes | Resource ID of the private (trust) subnet |
| `load_balancers.public.nsg_auto_rules_settings.nsg_name` | Yes | Name of the NSG on the public subnet |
| `load_balancers.public.nsg_auto_rules_settings.source_ips` | Yes | Public IPs allowed to reach the load balancer (CIDR list) |
| `vmseries_universal.version` | Yes | PAN-OS version to deploy (e.g. `"11.2.8"`) |
| `vmseries` | Yes | Map of firewall instances to deploy |

### Step 3 — Initialize Terraform

```bash
terraform init
```

This will download the VM-Series, loadbalancer, and ngfw_metrics modules from the PaloAltoNetworks GitHub repository (pinned to `v3.5.1`).

### Step 4 — Review the plan

```bash
terraform plan -var-file=terraform.tfvars
```

### Step 5 — Deploy

```bash
terraform apply -var-file=terraform.tfvars
```

### Step 6 — Retrieve outputs

After a successful apply:

```bash
# Firewall management IP addresses
terraform output vmseries_mgmt_ips

# Admin username per firewall
terraform output usernames

# Auto-generated admin password (sensitive)
terraform output -raw passwords

# Load balancer frontend IPs
terraform output lb_frontend_ips
```

---

## Variable reference

### General

| Variable | Type | Default | Description |
|---|---|---|---|
| `subscription_id` | `string` | — | Azure Subscription ID |
| `name_prefix` | `string` | `""` | Prefix added to all resource names |
| `resource_group_name` | `string` | — | Existing resource group to deploy into |
| `region` | `string` | — | Azure region |
| `tags` | `map(string)` | `{}` | Tags applied to all resources |

### Network references

| Variable | Type | Description |
|---|---|---|
| `subnet_ids` | `map(string)` | Map of logical subnet keys to Azure subnet resource IDs. Keys referenced by `subnet_key` in `vmseries` interfaces |

### Load balancers

| Variable | Type | Default | Description |
|---|---|---|---|
| `load_balancers` | `map(object)` | `{}` | Public and private Azure Load Balancers to deploy alongside the firewalls |

Each load balancer entry supports:
- `name` — resource name
- `zones` — availability zones for frontend IPs (default: `["1", "2", "3"]`)
- `backend_name` — name for the backend pool (default: `"vmseries_backend"`)
- `health_probes` — map of health probe definitions
- `nsg_auto_rules_settings` — auto-populates an existing NSG with Allow rules; requires `nsg_name` (the NSG must already exist in the same resource group or specify `nsg_resource_group_name`)
- `frontend_ips` — map of frontend IP configurations with `in_rules` (inbound LB rules) and `out_rules` (outbound rules); use `subnet_key` for internal LBs to resolve the subnet via `var.subnet_ids`

### VM-Series

| Variable | Type | Default | Description |
|---|---|---|---|
| `vmseries_universal` | `object` | `{}` | Common settings applied to all firewalls (version, size, bootstrap). Can be overridden per-VM in `vmseries` |
| `vmseries` | `map(object)` | `{}` | Map of firewall instances. Each entry defines interfaces, zone, bootstrap, and authentication |
| `availability_sets` | `map(object)` | `{}` | Optional; use when Availability Zones are not available in your region |

#### Firewall interface order

The order of entries in `interfaces` matters — the **first interface is always management**:

```hcl
interfaces = [
  { name = "mgmt",   subnet_key = "management", ... },  # index 0 — management (ip_forwarding disabled)
  { name = "public", subnet_key = "public",     ... },  # index 1+ — dataplane (ip_forwarding enabled)
  { name = "private", subnet_key = "private",   ... },
]
```

### Bootstrap options

Three bootstrap methods are supported (mutually exclusive):

| Method | How to configure |
|---|---|
| **User-data (basic)** | Set `bootstrap_options` in `vmseries_universal` with `type = "dhcp-client"` and any PAN-OS bootstrap key-value pairs |
| **Panorama / SCM** | Extend `bootstrap_options` with `panorama-server`, `tplname`, `dgname`, and auth credentials |
| **Full bootstrap (Storage Account)** | Uncomment and configure `bootstrap_storages` and set `bootstrap_package` in `vmseries_universal`; a Storage Account and File Shares are created automatically |

The `example.tfvars` contains commented-out examples for all three methods.

### Optional features

| Variable | Description |
|---|---|
| `ngfw_metrics` | Creates a Log Analytics Workspace and Application Insights instance per firewall for PAN-OS metrics |
| `bootstrap_storages` | Creates Azure Storage Account(s) with File Shares for full PAN-OS bootstrap packages |

---

## Outputs

| Output | Sensitive | Description |
|---|---|---|
| `usernames` | No | Admin username per firewall |
| `passwords` | Yes | Admin password per firewall (auto-generated if not set) |
| `vmseries_mgmt_ips` | No | Public IP of each firewall's management interface |
| `lb_frontend_ips` | No | Frontend IP configurations for each load balancer |
| `lb_backend_pool_ids` | No | Backend pool resource IDs (useful if chaining other deployments) |
| `metrics_instrumentation_keys` | Yes | Application Insights instrumentation keys per firewall |
| `bootstrap_storage_urls` | Yes | Bootstrap file share URLs per storage account |

---

## Relationship with LB-Sandwich-infra

This repository is designed as a companion to [LB-Sandwich-infra](https://github.com/krabapples/LB-Sandwich-infra), which deploys the underlying network (VNet, subnets, NSGs, route tables). The split allows you to:

- Deploy or update the network layer independently from the firewall layer
- Drop these firewalls into any existing Azure VNet, not just one created by LB-Sandwich-infra

When using both repositories together, the typical workflow is:

```
1. terraform apply  (in LB-Sandwich-infra)  →  network ready
2. terraform output subnet_ids              →  copy subnet IDs
3. Fill subnet_ids into terraform.tfvars    (in LB-Sandwich-fw)
4. terraform apply  (in LB-Sandwich-fw)     →  firewalls and LBs ready
```

---

## Module sources

All PAN-OS modules are sourced directly from the upstream repository, pinned to a specific release:

```
github.com/PaloAltoNetworks/terraform-azurerm-swfw-modules//modules/vmseries?ref=v3.5.1
github.com/PaloAltoNetworks/terraform-azurerm-swfw-modules//modules/loadbalancer?ref=v3.5.1
github.com/PaloAltoNetworks/terraform-azurerm-swfw-modules//modules/bootstrap?ref=v3.5.1
github.com/PaloAltoNetworks/terraform-azurerm-swfw-modules//modules/ngfw_metrics?ref=v3.5.1
```

To upgrade to a newer release, update the `?ref=` tag in `main.tf` and run `terraform init -upgrade`.
