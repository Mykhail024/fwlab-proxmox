resource "proxmox_network_linux_bridge" "lab" {
  node_name = var.node_name
  name      = var.lab_bridge
  autostart = true
}
