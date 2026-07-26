# Throwaway test instantiation of the lxc-base module (see
# modules/lxc-base/README.md) — proves the module applies cleanly against
# real Proxmox infrastructure. Not a service; nothing depends on this
# container; safe to `terraform destroy` at any time.

resource "proxmox_download_file" "debian_13" {
  content_type = "vztmpl"
  datastore_id = "local-zfs"
  node_name    = "caba-host"
  url          = "http://download.proxmox.com/images/system/debian-13-standard_13.6-1_amd64.tar.zst"
}

module "lxc_base_test" {
  source = "./modules/lxc-base"

  node_name         = "caba-host"
  disk_datastore_id = "local-zfs"
  hostname          = "lxc-base-test"
  description       = "Throwaway test instantiation of lxc-base — see modules/lxc-base/README.md. Safe to destroy."
  template_file_id  = proxmox_download_file.debian_13.id

  ssh_public_keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEmJPl4KFClzE9kbnkate3cS1IVv9OR/Vshs8nSqFvwa jack@weinbender.io",
  ]
}
