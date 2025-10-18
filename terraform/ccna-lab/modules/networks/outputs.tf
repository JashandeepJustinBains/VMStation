# Networks Module - Outputs

output "management_network_id" {
  description = "ID of management network"
  value       = libvirt_network.management.id
}

output "management_network_name" {
  description = "Name of management network"
  value       = libvirt_network.management.name
}

output "router_network_id" {
  description = "ID of router network"
  value       = libvirt_network.routers.id
}

output "router_network_name" {
  description = "Name of router network"
  value       = libvirt_network.routers.name
}

output "client_network_id" {
  description = "ID of client network"
  value       = libvirt_network.clients.id
}

output "client_network_name" {
  description = "Name of client network"
  value       = libvirt_network.clients.name
}

output "practice_network_ids" {
  description = "IDs of practice networks"
  value       = libvirt_network.practice[*].id
}

output "practice_network_names" {
  description = "Names of practice networks"
  value       = libvirt_network.practice[*].name
}

output "internet_gateway_id" {
  description = "ID of internet gateway network (if enabled)"
  value       = var.enable_internet ? libvirt_network.internet_gateway[0].id : null
}

output "isolation_applied" {
  description = "Whether network isolation rules have been applied"
  value       = true
  depends_on  = [null_resource.network_isolation_rules]
}
