# Example: one hardened LXC instantiated from this module, including the
# recommended pattern for supplying `template_file_id` — download the OS
# template once here (the caller's responsibility, not the module's; see
# ../../README.md) and pass its `.id` through.
#
# Placeholder values throughout (node name, storage IDs, SSH key) — this
# example exists to validate the module's wiring (`terraform validate`), not
# to be applied against real infrastructure.

resource "proxmox_download_file" "debian_13" {
  content_type = "vztmpl"
  datastore_id = "local"
  node_name    = "pve-example"
  url          = "http://download.proxmox.com/images/system/debian-13-standard_13.6-1_amd64.tar.zst"
}

module "lxc_base_example" {
  source = "../.."

  node_name         = "pve-example"
  disk_datastore_id = "local-lvm"
  hostname          = "lxc-base-example"
  template_file_id  = proxmox_download_file.debian_13.id

  ssh_public_keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExamplePlaceholderKeyReplaceMe example@placeholder.invalid",
  ]
}
