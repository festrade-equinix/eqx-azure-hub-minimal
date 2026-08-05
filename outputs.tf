###############################################################################
# outputs.tf — Values exported after terraform apply
###############################################################################

# ─── Azure data sources ───────────────────────────────────────────────────────

output "azure_resource_group_location" {
  description = "Location of the resource group hosting all created resources."
  value       = data.azurerm_resource_group.this.location
}

output "azure_er_circuit_id" {
  description = "Resource ID of the existing ExpressRoute Circuit."
  value       = data.azurerm_express_route_circuit.this.id
}

output "azure_er_provisioning_state" {
  description = "Service provider provisioning state of the ExpressRoute Circuit."
  value       = data.azurerm_express_route_circuit.this.service_provider_provisioning_state
}

# ─── Equinix data sources ─────────────────────────────────────────────────────

output "equinix_ne_device_id" {
  description = "UUID of the existing Network Edge device (fred-cisco-PA)."
  value       = data.equinix_network_device.this.id
}

output "equinix_ne_device_reported_asn" {
  description = "ASN reported by the equinix_network_device data source (reads 0/unset for fred-cisco-PA — the actual BGP ASN used is var.customer_bgp_asn)."
  value       = data.equinix_network_device.this.asn
}

# ─── Fabric connections ───────────────────────────────────────────────────────

output "fabric_conn_ne_to_azure_primary_id" {
  description = "UUID of the primary Fabric Connection NE → Azure ExpressRoute."
  value       = equinix_fabric_connection.ne_to_azure_primary.id
}

output "fabric_conn_ne_to_azure_primary_status" {
  description = "Equinix status of the primary Fabric Connection."
  value       = one(equinix_fabric_connection.ne_to_azure_primary.operation).equinix_status
}

output "fabric_conn_ne_to_azure_secondary_id" {
  description = "UUID of the secondary Fabric Connection NE → Azure ExpressRoute."
  value       = equinix_fabric_connection.ne_to_azure_secondary.id
}

output "fabric_conn_ne_to_azure_secondary_status" {
  description = "Equinix status of the secondary Fabric Connection."
  value       = one(equinix_fabric_connection.ne_to_azure_secondary.operation).equinix_status
}

output "fabric_redundancy_group_id" {
  description = "Redundancy group shared by the primary and secondary Fabric connections."
  value       = one(equinix_fabric_connection.ne_to_azure_primary.redundancy).group
}

# ─── Azure created resources ──────────────────────────────────────────────────

output "azure_er_private_peering_id" {
  description = "Resource ID of the created ExpressRoute private peering."
  value       = azurerm_express_route_circuit_peering.private.id
}

output "azure_vnet_id" {
  description = "Resource ID of the hub VNet."
  value       = azurerm_virtual_network.hub.id
}

output "azure_vng_id" {
  description = "Resource ID of the Virtual Network Gateway."
  value       = azurerm_virtual_network_gateway.hub.id
}

output "azure_vng_connection_id" {
  description = "Resource ID of the VNet Gateway ↔ ExpressRoute connection."
  value       = azurerm_virtual_network_gateway_connection.er.id
}

output "vm_public_ip" {
  description = "Public IP address of the reference VM."
  value       = azurerm_public_ip.vm.ip_address
}

output "vm_private_ip" {
  description = "Private IP address of the reference VM."
  value       = azurerm_network_interface.vm.private_ip_address
}

output "vm_ssh_key_id" {
  description = "Resource ID of the fred-ssh-key SSH public key registered in Azure."
  value       = azurerm_ssh_public_key.fred.id
}

# ─── Equinix created resources ────────────────────────────────────────────────

output "equinix_ne_bgp_to_azure_primary_state" {
  description = "Provisioning state of the NE BGP peering, primary session."
  value       = equinix_network_bgp.to_azure_primary.provisioning_status
}

output "equinix_ne_bgp_to_azure_secondary_state" {
  description = "Provisioning state of the NE BGP peering, secondary session."
  value       = equinix_network_bgp.to_azure_secondary.provisioning_status
}

# ─── BGP summary ──────────────────────────────────────────────────────────────

output "bgp_summary" {
  description = "BGP configuration applied to both NE ↔ Azure peerings."
  value = {
    primary = {
      local_ip   = cidrhost(var.azure_primary_peer_subnet, 1)
      remote_ip  = cidrhost(var.azure_primary_peer_subnet, 2)
      local_asn  = var.customer_bgp_asn
      remote_asn = var.azure_microsoft_bgp_asn
      vlan       = var.azure_vlan_id
    }
    secondary = {
      local_ip   = cidrhost(var.azure_secondary_peer_subnet, 1)
      remote_ip  = cidrhost(var.azure_secondary_peer_subnet, 2)
      local_asn  = var.customer_bgp_asn
      remote_asn = var.azure_microsoft_bgp_asn
      vlan       = var.azure_vlan_id
    }
    er_circuit = var.azure_er_circuit_name
  }
}

# ─── Locals ───────────────────────────────────────────────────────────────────

output "common_tags" {
  description = "Common tags applied to all created resources."
  value       = local.common_tags
}
