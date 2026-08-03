# Azure Hub (Dublin) — via Equinix Network Edge (Paris)

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│  EQUINIX  (Paris PA)                                                     │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │  Network Edge — fred-cisco-PA  [existing]                          │ │
│  │                                                                    │ │
│  │   ├── EVPL_VC PRIMARY   ──────────────────────► Azure ExpressRoute │ │
│  │   │   auth_key = ER Circuit service_key (remote, Paris → Dublin)   │ │
│  │   │   BGP: 172.20.0.2/30 ↔ 172.20.0.1  ASN <device> ↔ 12076        │ │
│  │   │                                                                │ │
│  │   └── EVPL_VC SECONDARY ──────────────────────► Azure ExpressRoute │ │
│  │       redundancy group = primary's group                          │ │
│  │       BGP: 172.20.0.6/30 ↔ 172.20.0.5  ASN <device> ↔ 12076        │ │
│  └────────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────┬──────────────────────────────────────────┘
                                 │ Cross-connect (remote / cross-metro)
                                 ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  Azure  (North Europe — Dublin)                                          │
│                                                                          │
│  ┌────────────────────────────┐                                        │
│  │  ExpressRoute Circuit       │  fred-er-dublin  [existing]            │
│  │  Provider: Equinix          │                                        │
│  │  Peering location: Dublin   │                                        │
│  └──────────────┬───────────────┘                                        │
│                 │                                                        │
│  ┌──────────────▼───────────────┐                                        │
│  │  Private Peering  [new]      │  Primary:   172.20.0.0/30              │
│  │                               │  Secondary: 172.20.0.4/30              │
│  └──────────────┬───────────────┘                                        │
│                 │                                                        │
│  ┌──────────────▼───────────────┐                                        │
│  │  VNet Gateway Connection [new]│                                       │
│  └──────────────┬───────────────┘                                        │
│                 │                                                        │
│  ┌──────────────▼───────────────┐                                        │
│  │  Virtual Network Gateway [new]│  SKU: Standard, type: ExpressRoute    │
│  └──────────────┬───────────────┘                                        │
│                 │                                                        │
│  ┌──────────────▼───────────────┐                                        │
│  │  VNet fred-vnet-hub-dublin[new]│ 192.168.11.0/24                      │
│  │   ├─ GatewaySubnet             │ 192.168.11.0/27                      │
│  │   └─ fred-snet-workload-dublin │ 192.168.11.128/25                    │
│  │        ├─ NSG (SSH + ICMP)     │ [new]                                │
│  │        ├─ Route table (BGP     │ [new]                                │
│  │        │   propagation on)     │                                     │
│  │        └─ fred-vm-dublin (VM)  │ [new]                                │
│  └────────────────────────────────┘                                     │
└──────────────────────────────────────────────────────────────────────────┘

[existing] = data source — never modified by Terraform
[new]      = resource   — created by Terraform
```

## Resource inventory

| # | Resource | Provider | Action |
|---|---|---|---|
| | ExpressRoute Circuit (fred-er-dublin) | Azure | `data` — by name + RG |
| | Resource Group | Azure | `data` — frederic.estrade_rg |
| | Network Edge device (fred-cisco-PA) | Equinix | `data` — by UUID |
| | Azure ER service profile | Equinix | `data` — by UUID |
| 1 | **Fabric Connection NE → Azure ER, PRIMARY** | **Equinix** | **resource — EVPL_VC, VD a-side, redundancy priority PRIMARY** |
| 2 | **Fabric Connection NE → Azure ER, SECONDARY** | **Equinix** | **resource — EVPL_VC, joins PRIMARY's redundancy group** |
| 3 | **NE BGP → Azure ER, primary session** | **Equinix** | **resource — equinix_network_bgp** |
| 4 | **NE BGP → Azure ER, secondary session** | **Equinix** | **resource — equinix_network_bgp** |
| 5 | **ExpressRoute Private Peering** | **Azure** | **resource — primary + secondary /30 subnets** |
| 6 | **Hub VNet + GatewaySubnet + workload subnet** | **Azure** | **resource** |
| 7 | **Virtual Network Gateway** | **Azure** | **resource — type ExpressRoute, SKU Standard** |
| 8 | **VNet Gateway ↔ ER Circuit connection** | **Azure** | **resource** |
| 9 | **NSG (allow SSH + ICMP)** | **Azure** | **resource — associated to workload subnet** |
| 10 | **Route table (BGP propagation enabled)** | **Azure** | **resource — associated to workload subnet** |
| 11 | **Linux VM + NIC + public IP** | **Azure** | **resource** |

## Prerequisites

| Tool | Min version |
|---|---|
| Terraform | >= 1.5.0 |
| Azure CLI | >= 2.x (used for `az login`) |
| Equinix Fabric account | Network Edge device provisioned (fred-cisco-PA) |

## Why this device + circuit

- **fred-cisco-PA** (uuid `371987e0-43fe-4328-a251-039bdc598c0a`) is an existing
  Network Edge device in the Paris (PA) metro. Its connections to Azure in
  Dublin are **remote / cross-metro** — supported because the Azure
  ExpressRoute service profile has `allowRemoteConnections = true`.
- **fred-er-dublin** is a pre-existing Azure ExpressRoute Circuit
  (`frederic.estrade_rg`, `northeurope`, provider Equinix, peering location
  "Dublin Metro"). Its `service_key` is read automatically via the
  `azurerm_express_route_circuit` data source and used as the Equinix Fabric
  `authentication_key`.
- The Azure ExpressRoute service profile has
  `connection_redundancy_required = true`, so **both a primary and a
  secondary Fabric connection are mandatory** — the secondary joins the
  redundancy group Equinix assigns to the primary
  (`one(equinix_fabric_connection.ne_to_azure_primary.redundancy).group`).

## Deployment

### 0. Credentials

```bash
source .env   # TF_VAR_equinix_client_id/secret, TF_VAR_bgp_auth_key, TF_VAR_azure_subscription_id
az login      # azurerm provider picks up the CLI session automatically
```

### 1. Configure variables

```bash
cp terraform.tfvars.example terraform.tfvars
# Review admin_source_cidr — restrict SSH/ICMP to your own public IP.
```

### 2. Init, plan, apply

```bash
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

### 2 (alternative) — Step-by-step with `-target`

Mirrors the 10 manual steps this repo automates:

```bash
source .env
terraform init
terraform validate

# Step 1 — Equinix: primary + secondary Fabric VC (NE → Azure ER, redundancy group)
terraform apply -target=equinix_fabric_connection.ne_to_azure_primary
terraform apply -target=equinix_fabric_connection.ne_to_azure_secondary

# Step 2 — Azure: ER private peering (needs connections PROVISIONED first)
terraform apply -target=azurerm_express_route_circuit_peering.private

# Step 3 — Equinix: NE BGP routing (primary + secondary)
terraform apply -target=equinix_network_bgp.to_azure_primary
terraform apply -target=equinix_network_bgp.to_azure_secondary

# Step 4 — Azure: VNet + subnets + GatewaySubnet
terraform apply -target=azurerm_subnet.gateway -target=azurerm_subnet.workload

# Step 5 — Azure: Virtual Network Gateway (30-45 minutes)
terraform apply -target=azurerm_virtual_network_gateway.hub

# Step 6 — Azure: VNet Gateway ↔ ER connection
terraform apply -target=azurerm_virtual_network_gateway_connection.er

# Step 7 — Azure: VM, NSG, route table + subnet association
terraform apply

# Final check — confirm no remaining drift
terraform plan
```

### 3. Post-deployment checks

```bash
terraform output fabric_conn_ne_to_azure_primary_status
terraform output fabric_conn_ne_to_azure_secondary_status
terraform output equinix_ne_bgp_to_azure_primary_state
terraform output equinix_ne_bgp_to_azure_secondary_state
terraform output bgp_summary

az network express-route peering show \
  --circuit-name fred-er-dublin \
  --resource-group frederic.estrade_rg \
  --name AzurePrivatePeering

az network vpn-connection show \
  --resource-group frederic.estrade_rg \
  --name fred-vng-conn-er-dublin

# SSH to the VM (key auto-generated at generated_ssh_key.pem unless
# admin_ssh_public_key was set)
ssh -i generated_ssh_key.pem fredadmin@$(terraform output -raw vm_public_ip)
```

## Key design notes

- **Redundancy is mandatory** — the Azure ExpressRoute service profile sets
  `connection_redundancy_required = true`; there is no non-redundant path.
- **Cross-metro connection** — fred-cisco-PA sits in Paris; the Fabric
  connections to the Dublin-peered Azure circuit traverse the Equinix
  backbone (`is_remote = true` on both connections).
- **VLAN** — `azure_vlan_id` (300) must be unique on the fred-cisco-PA port
  and must match between the Fabric connection negotiation and the Azure
  private peering `vlan_id`.
- **Azure auth** — the `azurerm` provider uses `az login` by default.
  Uncomment `tenant_id`, `client_id`, `client_secret` in the provider block
  to switch to service principal auth.
- **GatewaySubnet** — name is hardcoded; Azure requires this exact name for
  any subnet hosting a Virtual Network Gateway.
- **Route table BGP propagation** — `bgp_route_propagation_enabled = true`
  on the workload subnet's route table, so on-prem/Equinix-advertised routes
  reach the VM via the VNet Gateway.
- **SSH/ICMP source** — `admin_source_cidr` scopes the NSG rules; defaults
  to the deploying operator's detected public IP. Widen only if needed.
- **NE BGP (equinix_network_bgp)** — works natively on the Cisco NE device
  via the Equinix Network Edge API; no SSH/Ansible workaround required.

## Teardown

```bash
# ⚠️  This immediately disrupts hybrid connectivity to Azure and deletes the VM.
terraform destroy
```
