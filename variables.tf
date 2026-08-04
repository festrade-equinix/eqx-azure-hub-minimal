###############################################################################
# variables.tf — Azure Hub (Dublin) via Equinix Network Edge — North Europe
###############################################################################

# ─── Project ──────────────────────────────────────────────────────────────────

variable "project_name" {
  description = "Prefix applied to all resource names created by this module."
  type        = string
  default     = "fred-azure-hub-dublin"
}

variable "environment" {
  description = "Target environment (prod, staging, dev, …)."
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Team or individual responsible for these resources."
  type        = string
  default     = "fred"
}

# ─── Azure — Provider ─────────────────────────────────────────────────────────

variable "azure_subscription_id" {
  description = "Azure subscription ID."
  type        = string
  sensitive   = true
}

variable "azure_tenant_id" {
  description = "Service Principal tenant ID. Leave null when using az login."
  type        = string
  sensitive   = true
  default     = null
}

variable "azure_client_id" {
  description = "Service Principal client ID (appId). Leave null when using az login."
  type        = string
  sensitive   = true
  default     = null
}

variable "azure_client_secret" {
  description = "Service Principal client secret. Leave null when using az login."
  type        = string
  sensitive   = true
  default     = null
}

variable "azure_region" {
  description = "Azure region for the hub. North Europe = Dublin, Ireland."
  type        = string
  default     = "northeurope"
}

# ─── Azure — Existing resources (data sources) ────────────────────────────────

variable "azure_resource_group_name" {
  description = "Existing Resource Group to deploy into."
  type        = string
  default     = "frederic.estrade_rg"
}

variable "azure_er_circuit_name" {
  description = "Name of the existing ExpressRoute Circuit (provider = Equinix, peering location = Dublin Metro)."
  type        = string
  default     = "fred-er-dublin"
}

# ─── Azure — New Hub network (created resources) ─────────────────────────────

variable "vnet_address_space" {
  description = "Address space for the new hub VNet."
  type        = string
  default     = "192.168.11.0/24"
}

variable "gateway_subnet_prefix" {
  description = "Address prefix for the mandatory GatewaySubnet."
  type        = string
  default     = "192.168.11.0/27"
}

variable "workload_subnet_prefix" {
  description = "Address prefix for the workload subnet hosting the VM."
  type        = string
  default     = "192.168.11.128/25"
}

# ─── Azure — Virtual Network Gateway (created resource) ──────────────────────

variable "vng_sku" {
  description = "SKU of the Virtual Network Gateway. Must support ExpressRoute (Standard, HighPerformance, UltraPerformance, ErGw1AZ, ErGw2AZ, ErGw3AZ)."
  type        = string
  default     = "Standard"
}

variable "azure_er_fastpath_enabled" {
  description = "Enable ExpressRoute FastPath. Requires ErGw3AZ or UltraPerformance gateway SKU."
  type        = bool
  default     = false
}

variable "azure_er_authorization_key" {
  description = "Authorization key — only required when the ER circuit is in a different Azure subscription than the VNet Gateway."
  type        = string
  sensitive   = true
  default     = ""
}

# ─── Azure — VM (created resource) ────────────────────────────────────────────

variable "vm_size" {
  description = "VM size for the reference Linux VM."
  type        = string
  default     = "Standard_B1s"
}

variable "vm_admin_username" {
  description = "Admin username for the reference VM."
  type        = string
  default     = "fredadmin"
}

variable "admin_ssh_public_key" {
  description = "SSH public key for the VM admin user, registered in Azure as the fred-ssh-key resource so it can be reused across VMs."
  type        = string
}

variable "admin_source_cidr" {
  description = "CIDR allowed to reach the VM over SSH/ICMP on the NSG. Defaults to the operator's detected public IP /32 — restrict further or widen as needed."
  type        = string
}

variable "onprem_test_prefix" {
  description = "On-prem (NE-side) prefix allowed to ping the VM over the ExpressRoute path, for BGP connectivity testing. E.g. a loopback on fred-cisco-PA advertised into BGP."
  type        = string
  default     = "10.11.0.1/32"
}

# ─── Equinix — Provider ───────────────────────────────────────────────────────

variable "equinix_client_id" {
  description = "Equinix Fabric API Client ID (developer.equinix.com)."
  type        = string
  sensitive   = true
}

variable "equinix_client_secret" {
  description = "Equinix Fabric API Client Secret."
  type        = string
  sensitive   = true
}

variable "equinix_azure_metro_code" {
  description = "Equinix metro code where the Azure ExpressRoute circuit is peered. Dublin = \"DB\"."
  type        = string
  default     = "DB"
}

# ─── Equinix — Existing Network Edge device (data source) ────────────────────

variable "equinix_ne_device_uuid" {
  description = "UUID of the existing Network Edge device (fred-cisco-PA, Paris metro). Connections to Azure in Dublin are remote/cross-metro."
  type        = string
  default     = "371987e0-43fe-4328-a251-039bdc598c0a"
}

variable "equinix_sp_azure_er_uuid" {
  description = "UUID of the Azure ExpressRoute service profile in the Equinix Fabric marketplace (public profile, connection redundancy required)."
  type        = string
  default     = "a1390b22-bbe0-4e93-ad37-85beef9d254d"
}

# ─── Equinix — Fabric Connections (created resources) ────────────────────────

variable "ne_azure_bandwidth_mbps" {
  description = "Bandwidth for each Fabric Connection NE → Azure ExpressRoute (Mbps). Matches the ER circuit's provisioned bandwidth."
  type        = number
  default     = 50
}

variable "azure_vlan_id" {
  description = "DOT1Q VLAN ID for the ExpressRoute private peering (must be unique on the NE device port)."
  type        = number
  default     = 300

  validation {
    condition     = var.azure_vlan_id >= 1 && var.azure_vlan_id <= 4094
    error_message = "VLAN ID must be between 1 and 4094."
  }
}

# ─── Equinix NE BGP — Azure ExpressRoute peering (primary + secondary) ───────

variable "azure_primary_peer_subnet" {
  description = "/30 subnet for the primary BGP session on the ExpressRoute private peering. Azure takes .1, the NE device takes .2."
  type        = string
  default     = "172.20.0.0/30"
}

variable "azure_secondary_peer_subnet" {
  description = "/30 subnet for the secondary BGP session on the ExpressRoute private peering. Azure takes .1, the NE device takes .2."
  type        = string
  default     = "172.20.0.4/30"
}

variable "azure_microsoft_bgp_asn" {
  description = "Microsoft BGP ASN for ExpressRoute private peering. Always 12076 for standard circuits."
  type        = number
  default     = 12076
}

variable "customer_bgp_asn" {
  description = "BGP ASN of the Network Edge device (customer side, fred-cisco-PA = 65001). The equinix_network_device data source reports asn = 0 (unset), so this is supplied explicitly rather than read back."
  type        = number
  default     = 65001
}

variable "bgp_auth_key" {
  description = "Optional MD5 key shared across all BGP sessions. Leave empty to disable MD5 auth."
  type        = string
  sensitive   = true
  default     = ""
}

# ─── Notifications & Billing ──────────────────────────────────────────────────

variable "notification_emails" {
  description = "Email addresses for Equinix Fabric notifications."
  type        = list(string)
  default     = ["frederic.estrade@eu.equinix.com"]
}

variable "po_number" {
  description = "Purchase order number for Equinix billing."
  type        = string
  default     = "PO-000001"
}
