###############################################################################
# Azure Hub (Dublin) — Equinix Network Edge → Azure ExpressRoute
#
# ┌──────────────────────────────────────────────────────────────────────────┐
# │  EXISTING resources (data sources — never modified by Terraform)         │
# │  EQX   : Network Edge device fred-cisco-PA (Paris) — remote/cross-metro  │
# │  Azure : ExpressRoute Circuit fred-er-dublin (peering location: Dublin)  │
# │  Azure : Resource Group frederic.estrade_rg                              │
# ├──────────────────────────────────────────────────────────────────────────┤
# │  CREATED by this Terraform                                               │
# │  EQX   : Fabric Connection NE → Azure ER, PRIMARY   (EVPL_VC / VD a-side)│
# │          Fabric Connection NE → Azure ER, SECONDARY (redundancy group)   │
# │          NE BGP peering is NOT managed here — see README section 7,     │
# │          Manual BGP config (NE devices are self-managed/BYOL by default)│
# │  Azure : ExpressRoute private peering (primary + secondary /30)          │
# │          VNet + GatewaySubnet + workload subnet                          │
# │          Virtual Network Gateway (ExpressRoute)                          │
# │          VNet Gateway ↔ ER Circuit connection                            │
# │          Linux VM + NIC + public IP                                      │
# │          NSG (allow SSH + ICMP) on the workload subnet                   │
# │          Route table (BGP propagation enabled) on the workload subnet    │
# └──────────────────────────────────────────────────────────────────────────┘
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.90"
    }
    equinix = {
      source  = "equinix/equinix"
      version = ">= 1.20, < 5.0"
    }
  }
}

###############################################################################
# Providers
###############################################################################

provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
  # tenant_id     = var.azure_tenant_id     # uncomment for service principal auth (disables az login)
  # client_id     = var.azure_client_id     # uncomment for service principal auth (disables az login)
  # client_secret = var.azure_client_secret # uncomment for service principal auth (disables az login)
}

provider "equinix" {
  client_id     = var.equinix_client_id
  client_secret = var.equinix_client_secret
}

###############################################################################
# DATA SOURCES — Azure existing resources
###############################################################################

data "azurerm_resource_group" "this" {
  name = var.azure_resource_group_name
}

# Existing ExpressRoute Circuit (provider = Equinix, peering location = Dublin Metro)
# Its service key is NOT read from this data source — provided explicitly
# via var.azure_er_service_key (TF_VAR_azure_er_service_key in .env) instead.
data "azurerm_express_route_circuit" "this" {
  name                = var.azure_er_circuit_name
  resource_group_name = data.azurerm_resource_group.this.name
}

###############################################################################
# DATA SOURCES — Equinix existing resources
###############################################################################

# Existing Network Edge device (fred-cisco-PA, Paris) — remote connection to
# the Dublin-peered Azure ExpressRoute circuit over the Equinix backbone.
data "equinix_network_device" "this" {
  uuid = var.equinix_ne_device_uuid
}

# Azure ExpressRoute service profile in the Equinix Fabric marketplace.
# connection_redundancy_required = true on this profile — Azure requires a
# primary + secondary connection pair, hence the redundancy group below.
data "equinix_fabric_service_profile" "azure_er" {
  uuid = var.equinix_sp_azure_er_uuid
}

###############################################################################
# 1. Equinix Fabric — Network Edge → Azure ExpressRoute, PRIMARY
#    (EVPL_VC, VD a-side, interface auto-assigned)
###############################################################################

resource "equinix_fabric_connection" "ne_to_azure_primary" {
  name      = "${var.equinix_connection_prefix}-azure-pri"
  type      = "EVPL_VC"
  bandwidth = var.ne_azure_bandwidth_mbps

  a_side {
    access_point {
      type = "VD"
      virtual_device {
        type = "EDGE"
        uuid = var.equinix_ne_device_uuid
      }
    }
  }

  z_side {
    access_point {
      type         = "SP"
      peering_type = "PRIVATE"
      profile {
        type = "L2_PROFILE"
        uuid = data.equinix_fabric_service_profile.azure_er.id
      }
      location {
        metro_code = var.equinix_azure_metro_code
      }
      seller_region      = data.azurerm_express_route_circuit.this.service_provider_properties[0].peering_location
      authentication_key = var.azure_er_service_key
    }
  }

  notifications {
    type   = "ALL"
    emails = var.notification_emails
  }

  order {
    purchase_order_number = var.po_number
  }

  redundancy {
    priority = "PRIMARY"
  }

  lifecycle {
    ignore_changes = [order]
  }
}

###############################################################################
# 2. Equinix Fabric — Network Edge → Azure ExpressRoute, SECONDARY
#    Joins the redundancy group created by the primary connection above.
###############################################################################

resource "equinix_fabric_connection" "ne_to_azure_secondary" {
  name      = "${var.equinix_connection_prefix}-azure-sec"
  type      = "EVPL_VC"
  bandwidth = var.ne_azure_bandwidth_mbps

  a_side {
    access_point {
      type = "VD"
      virtual_device {
        type = "EDGE"
        uuid = var.equinix_ne_device_uuid
      }
    }
  }

  z_side {
    access_point {
      type         = "SP"
      peering_type = "PRIVATE"
      profile {
        type = "L2_PROFILE"
        uuid = data.equinix_fabric_service_profile.azure_er.id
      }
      location {
        metro_code = var.equinix_azure_metro_code
      }
      seller_region      = data.azurerm_express_route_circuit.this.service_provider_properties[0].peering_location
      authentication_key = var.azure_er_service_key
    }
  }

  notifications {
    type   = "ALL"
    emails = var.notification_emails
  }

  order {
    purchase_order_number = var.po_number
  }

  redundancy {
    priority = "SECONDARY"
    group    = one(equinix_fabric_connection.ne_to_azure_primary.redundancy).group
  }

  lifecycle {
    ignore_changes = [order]
  }

  depends_on = [equinix_fabric_connection.ne_to_azure_primary]
}

###############################################################################
# 3. Azure — ExpressRoute Circuit Private Peering
#    Primary and secondary /30 subnets for the two redundant BGP sessions.
###############################################################################

resource "azurerm_express_route_circuit_peering" "private" {
  peering_type               = "AzurePrivatePeering"
  express_route_circuit_name = data.azurerm_express_route_circuit.this.name
  resource_group_name        = data.azurerm_resource_group.this.name

  vlan_id  = var.azure_vlan_id
  peer_asn = var.customer_bgp_asn

  primary_peer_address_prefix   = var.azure_primary_peer_subnet
  secondary_peer_address_prefix = var.azure_secondary_peer_subnet

  shared_key   = var.bgp_auth_key != "" ? var.bgp_auth_key : null
  ipv4_enabled = true

  depends_on = [
    equinix_fabric_connection.ne_to_azure_primary,
    equinix_fabric_connection.ne_to_azure_secondary,
  ]
}

###############################################################################
# 4. Azure — Hub VNet + subnets
###############################################################################

resource "azurerm_virtual_network" "hub" {
  name                = "${var.project_name}-vnet"
  location            = var.azure_region
  resource_group_name = data.azurerm_resource_group.this.name
  address_space       = [var.vnet_address_space]

  tags = local.common_tags
}

# Name must be exactly "GatewaySubnet" — Azure requirement for VNet Gateways.
resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = data.azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.gateway_subnet_prefix]
}

resource "azurerm_subnet" "workload" {
  name                 = "${var.project_name}-snet-workload"
  resource_group_name  = data.azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.workload_subnet_prefix]
}

###############################################################################
# 5. Azure — Virtual Network Gateway (ExpressRoute)
###############################################################################

resource "azurerm_virtual_network_gateway" "hub" {
  name                = "${var.project_name}-vng"
  location            = var.azure_region
  resource_group_name = data.azurerm_resource_group.this.name

  type     = "ExpressRoute"
  sku      = var.vng_sku
  vpn_type = "RouteBased"

  # ExpressRoute gateways do not take a public IP (azurerm v5 rejects it —
  # older provider/API versions required one, the current API does not).
  ip_configuration {
    name                          = "vnetGatewayConfig"
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway.id
  }

  tags = local.common_tags
}

###############################################################################
# 6. Azure — VNet Gateway ↔ ExpressRoute Circuit connection
###############################################################################

resource "azurerm_virtual_network_gateway_connection" "er" {
  name                = "${var.project_name}-vng-conn-er"
  location            = var.azure_region
  resource_group_name = data.azurerm_resource_group.this.name

  type                         = "ExpressRoute"
  virtual_network_gateway_id   = azurerm_virtual_network_gateway.hub.id
  express_route_circuit_id     = data.azurerm_express_route_circuit.this.id
  express_route_gateway_bypass = var.azure_er_fastpath_enabled
  authorization_key            = var.azure_er_authorization_key != "" ? var.azure_er_authorization_key : null

  routing_weight = 10

  tags = local.common_tags

  depends_on = [azurerm_express_route_circuit_peering.private]
}

###############################################################################
# 7. Azure — NSG (allow SSH + ICMP) on the workload subnet
###############################################################################

resource "azurerm_network_security_group" "workload" {
  name                = "${var.project_name}-nsg-workload"
  location            = var.azure_region
  resource_group_name = data.azurerm_resource_group.this.name

  tags = local.common_tags
}

resource "azurerm_network_security_rule" "allow_ssh" {
  name                        = "allow-ssh"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = var.admin_source_cidr
  destination_address_prefix  = "*"
  resource_group_name         = data.azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.workload.name
}

resource "azurerm_network_security_rule" "allow_icmp" {
  name                        = "allow-icmp"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Icmp"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = var.admin_source_cidr
  destination_address_prefix  = "*"
  resource_group_name         = data.azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.workload.name
}

resource "azurerm_network_security_rule" "allow_icmp_onprem" {
  name                        = "allow-icmp-onprem"
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Icmp"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = var.onprem_test_prefix
  destination_address_prefix  = "*"
  resource_group_name         = data.azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.workload.name
}

resource "azurerm_subnet_network_security_group_association" "workload" {
  subnet_id                 = azurerm_subnet.workload.id
  network_security_group_id = azurerm_network_security_group.workload.id
}

###############################################################################
# 8. Azure — Route table (BGP propagation enabled) on the workload subnet
###############################################################################

resource "azurerm_route_table" "workload" {
  name                          = "${var.project_name}-rt-workload"
  location                      = var.azure_region
  resource_group_name           = data.azurerm_resource_group.this.name
  bgp_route_propagation_enabled = true

  tags = local.common_tags
}

resource "azurerm_subnet_route_table_association" "workload" {
  subnet_id      = azurerm_subnet.workload.id
  route_table_id = azurerm_route_table.workload.id
}

###############################################################################
# 9. Azure — Reference VM
###############################################################################

resource "azurerm_ssh_public_key" "fred" {
  name                = "fred-ssh-key"
  location            = var.azure_region
  resource_group_name = data.azurerm_resource_group.this.name
  public_key          = var.admin_ssh_public_key

  tags = local.common_tags
}

resource "azurerm_public_ip" "vm" {
  name                = "${var.project_name}-pip-vm"
  location            = var.azure_region
  resource_group_name = data.azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = local.common_tags
}

resource "azurerm_network_interface" "vm" {
  name                = "${var.project_name}-nic-vm"
  location            = var.azure_region
  resource_group_name = data.azurerm_resource_group.this.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.workload.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }

  tags = local.common_tags
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                  = "${var.project_name}-vm"
  location              = var.azure_region
  resource_group_name   = data.azurerm_resource_group.this.name
  size                  = var.vm_size
  admin_username        = var.vm_admin_username
  network_interface_ids = [azurerm_network_interface.vm.id]

  disable_password_authentication = true

  admin_ssh_key {
    username   = var.vm_admin_username
    public_key = azurerm_ssh_public_key.fred.public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  tags = local.common_tags
}

###############################################################################
# Locals
###############################################################################

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner
    Region      = "Dublin"
  }
}
