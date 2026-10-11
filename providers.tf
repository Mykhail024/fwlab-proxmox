provider "proxmox" {
  endpoint  = var.pm_endpoint
  api_token = var.pm_api_token
  insecure  = true

  ssh {
    agent    = true
    username = var.pm_ssh_user
  }
}
