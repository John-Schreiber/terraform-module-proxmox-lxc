terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.57.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.6.0"
    }
    ansible = {
      version = "~> 1.3.0"
      source  = "ansible/ansible"
    }
  }
}

resource "random_uuid" "name_suffix" {}

locals {
  container_template_file_insecure      = can(regex("^https:\\/\\/.*", var.container_template_file)) ? "false" : "true"
  container_template_file_download      = (can(regex("^https?:\\/\\/.*", var.container_template_file)) && var.migrate_template_file == true) ? 1 : 0
  container_template_file_download_name = local.container_template_file_download == 1 ? format("%s-%s", random_uuid.name_suffix.result, join("", regex("^https?:\\/\\/.*\\/.*?\\/?(.*)", var.container_template_file))) : null
  container_template_file_local         = (local.container_template_file_download == 0 || var.migrate_template_file == false) ? 1 : 0
  container_template                    = (local.container_template_file_download == 1 && var.migrate_template_file == true) ? proxmox_virtual_environment_download_file.container_template[0].id : proxmox_virtual_environment_file.container_template[0].id
}

resource "proxmox_virtual_environment_container" "proxmox_lxc" {
  description = "Managed by Terraform"
  node_name   = var.node_name
  vm_id       = var.vm_id
  initialization {
    hostname = var.container_name
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
    user_account {
      keys = [
        trimspace(tls_private_key.container_key.public_key_openssh)
      ]
      password = random_password.lxc_password.result
    }
  }
  cpu {
    architecture = "amd64"
    cores        = var.cpu_cores
  }
  memory {
    dedicated = var.memory_dedicated
    swap      = var.memory_swap
  }
  disk {
    datastore_id = var.datastore_id
    size         = var.disk_size
  }
  network_interface {
    name = var.network
  }
  operating_system {
    template_file_id = local.container_template
    type             = var.distro
  }
}
resource "proxmox_virtual_environment_file" "container_template" {
  count        = local.container_template_file_local
  content_type = "vztmpl"
  datastore_id = "local"
  node_name    = var.node_name
  source_file {
    path     = var.container_template_file
    insecure = local.container_template_file_insecure
  }
}

resource "proxmox_virtual_environment_download_file" "container_template" {
  count        = local.container_template_file_download
  file_name    = local.container_template_file_download_name
  content_type = "vztmpl"
  datastore_id = "local"
  node_name    = var.node_name
  url          = var.container_template_file
  overwrite    = true
  verify       = local.container_template_file_insecure == "true" ? "false" : "true"
}

resource "random_password" "lxc_password" {
  length           = var.password_length
  override_special = "_%@"
  special          = true
}
resource "tls_private_key" "container_key" {
  algorithm = "ED25519"

}
resource "ansible_host" "host" {
  name   = "${var.node_name}.servers.rosemontmarket.com"
  groups = ["OpenTofu"]
  variables = {
    key-file = pathexpand("~/.ssh/${var.container_name}.pem")

  }
}

resource "local_sensitive_file" "pem_file" {
  filename             = pathexpand("~/.ssh/${var.container_name}.pem")
  file_permission      = "600"
  directory_permission = "700"
  content              = tls_private_key.container_key.private_key_pem
}
