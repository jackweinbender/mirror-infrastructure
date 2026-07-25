resource "proxmox_virtual_environment_container" "this" {
  node_name     = var.node_name
  vm_id         = var.vm_id
  description   = var.description
  tags          = var.tags
  unprivileged  = var.unprivileged
  start_on_boot = var.start_on_boot
  started       = var.started

  # Proxmox always lowercases and re-sorts tags server-side, so Terraform
  # would otherwise see permanent drift on every plan.
  lifecycle {
    ignore_changes = [tags]
  }

  features {
    nesting = var.features_nesting
    keyctl  = var.features_keyctl
    fuse    = var.features_fuse
    mknod   = var.features_mknod
  }

  cpu {
    cores = var.cores
  }

  memory {
    dedicated = var.memory
    swap      = var.swap
  }

  disk {
    datastore_id = var.disk_datastore_id
    size         = var.disk_size
  }

  network_interface {
    name     = "eth0"
    bridge   = var.bridge
    firewall = var.firewall_enabled
  }

  operating_system {
    template_file_id = var.template_file_id
    type             = "debian"
  }

  initialization {
    hostname = var.hostname

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    # No `password` argument is set here, deliberately: omitting it entirely
    # disables root password login (console and SSH alike), leaving SSH keys
    # as the only way in. The ssh_public_keys variable's validation (see
    # variables.tf) refuses an empty list so this can't produce an
    # unreachable container.
    user_account {
      keys = var.ssh_public_keys
    }
  }
}
