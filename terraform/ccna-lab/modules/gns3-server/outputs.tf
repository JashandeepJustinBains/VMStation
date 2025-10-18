# GNS3 Server Module - Outputs

output "server_id" {
  description = "ID of GNS3 server VM"
  value       = libvirt_domain.gns3_server.id
}

output "server_name" {
  description = "Name of GNS3 server VM"
  value       = libvirt_domain.gns3_server.name
}

output "server_ip" {
  description = "IP address of GNS3 server"
  value       = var.server_ip
}

output "web_ui_url" {
  description = "URL for GNS3 web UI"
  value       = "http://${var.server_ip}:${var.web_port}"
}

output "api_url" {
  description = "URL for GNS3 REST API"
  value       = "http://${var.server_ip}:${var.api_port}/v3"
}

output "ssh_command" {
  description = "SSH command to connect to GNS3 server"
  value       = "ssh -i ${var.ssh_public_key == "" ? "${path.root}/.ssh/gns3_server_id_rsa" : var.ssh_private_key_path} ubuntu@${var.server_ip}"
}

output "ssh_private_key_path" {
  description = "Path to generated SSH private key"
  value       = var.ssh_public_key == "" ? local_file.gns3_private_key[0].filename : var.ssh_private_key_path
  sensitive   = true
}

output "cisco_images_path" {
  description = "Path to Cisco images on GNS3 server"
  value       = var.cisco_images_path
}

output "server_ready" {
  description = "Whether GNS3 server is ready"
  value       = true
  depends_on  = [null_resource.configure_dynamips]
}
