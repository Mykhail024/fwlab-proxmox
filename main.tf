locals {
  ssh_public_key = trimspace(
    file(pathexpand(var.ssh_public_key_path))
  )
}

resource "proxmox_download_file" "ubuntu" {
  content_type = "import"          # тип вмісту для імпорту диска.
  datastore_id = var.iso_datastore # сховище для завантаженого образу.
  node_name    = var.node_name

  url = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"

  file_name = "noble-server-cloudimg-amd64.qcow2" # назва імпортованого файлу в сховищі Proxmox
}

resource "proxmox_virtual_environment_file" "server_init" {
  content_type = "snippets"
  datastore_id = var.iso_datastore
  node_name    = var.node_name

  source_raw {
    data = templatefile(
      "${path.module}/cloud-init/server.yaml.tftpl",
      {
        ssh_public_key = local.ssh_public_key
      }
    )

    file_name = "fw-server.yaml"
  }
}

resource "proxmox_virtual_environment_file" "client_init" {
  content_type = "snippets"
  datastore_id = var.iso_datastore
  node_name    = var.node_name

  source_raw {
    data = templatefile(
      "${path.module}/cloud-init/client.yaml.tftpl",
      {
        ssh_public_key = local.ssh_public_key
      }
    )

    file_name = "fw-client.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "server" {
  name            = "fw-server"
  node_name       = var.node_name
  stop_on_destroy = true

  agent { enabled = true }
  cpu { cores = 2 }
  memory { dedicated = 2048 }
  serial_device { device = "socket" }

  disk {
    datastore_id = var.vm_datastore
    import_from  = proxmox_download_file.ubuntu.id
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = 20
  }

  network_device {
    bridge = var.mgmt_bridge
  }

  network_device {
    bridge = proxmox_network_linux_bridge.lab.name
  }

  initialization {
    datastore_id = var.vm_datastore

    ip_config {
      ipv4 { address = "dhcp" }
    }

    ip_config {
      ipv4 { address = var.server_lab_ip }
    }

    user_data_file_id = proxmox_virtual_environment_file.server_init.id
  }
}

resource "proxmox_virtual_environment_vm" "client" {
  name            = "fw-client"
  node_name       = var.node_name
  stop_on_destroy = true

  agent { enabled = true }
  cpu { cores = 1 }
  memory { dedicated = 1024 }
  serial_device { device = "socket" }

  disk {
    datastore_id = var.vm_datastore
    import_from  = proxmox_download_file.ubuntu.id
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = 12
  }

  network_device {
    bridge = var.mgmt_bridge
  }

  network_device {
    bridge = proxmox_network_linux_bridge.lab.name
  }

  initialization {
    datastore_id = var.vm_datastore

    ip_config {
      ipv4 { address = "dhcp" }
    }

    ip_config {
      ipv4 { address = var.client_lab_ip }
    }

    user_data_file_id = proxmox_virtual_environment_file.client_init.id
  }
}
