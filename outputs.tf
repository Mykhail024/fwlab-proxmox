output "server_mgmt_ip" {
  value = proxmox_virtual_environment_vm.server.ipv4_addresses[1][0]
}

output "client_mgmt_ip" {
  value = proxmox_virtual_environment_vm.client.ipv4_addresses[1][0]
}
