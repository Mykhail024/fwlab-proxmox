variable "pm_endpoint" { type = string }
variable "pm_api_token" {
  type      = string
  sensitive = true
}
variable "pm_ssh_user" {
  type    = string
  default = "root"
}

variable "node_name" {
  type    = string
  default = "pve"
}
variable "lab_bridge" {
  type    = string
  default = "vmbr1"
}

variable "ssh_public_key_path" {
  type    = string
  default = "./id_ed25519.pub"
}

variable "iso_datastore" {
  type    = string
  default = "local"
}


variable "vm_datastore" {
  type    = string
  default = "local-lvm"
}
variable "mgmt_bridge" {
  type    = string
  default = "vmbr0"
}
variable "server_lab_ip" {
  type    = string
  default = "10.40.0.20/24"
}

variable "client_lab_ip" {
  type    = string
  default = "10.40.0.10/24"
}
