# lxc-base

Reusable Terraform module that declares one reasonably-hardened Proxmox LXC
container per instantiation — the building block for every home-lab service
in this repo. One `module "foo" { source = "./modules/lxc-base" ... }` call
is one full, independent container (not a Proxmox template/clone workflow).

## Usage

```hcl
resource "proxmox_download_file" "debian_13" {
  content_type = "vztmpl"
  datastore_id = "local"
  node_name    = "pve1"
  url          = "http://download.proxmox.com/images/system/debian-13-standard_13.6-1_amd64.tar.zst"
}

module "my_service" {
  source = "./modules/lxc-base"

  node_name         = "pve1"
  disk_datastore_id = "local-lvm"
  hostname          = "my-service"
  template_file_id  = proxmox_download_file.debian_13.id
  ssh_public_keys   = [file("~/.ssh/id_ed25519.pub")]
}
```

See `examples/basic/` for a runnable (validate-only) copy of this pattern.

## Design decisions

- **Base distro**: Debian 13 (trixie). This module has no opinion baked in
  about the template file itself — see "OS template ownership" below.
- **Networking**: DHCP only. Static IP is left to whatever forks or extends
  this module for a specific service.
- **Hardening posture**:
  - `unprivileged = true` by default.
  - Feature/syscall surface is minimal by default (`features_nesting` /
    `features_keyctl` / `features_fuse` / `features_mknod` all default
    `false`), independently overridable per instantiation — e.g. a
    Docker-in-LXC service sets `features_nesting = true`.
  - **SSH-key-only root access**: `ssh_public_keys` is required and
    validated non-empty; the container's `password` is never set (not even a
    generated one), which disables root password login entirely — console
    and SSH alike.
  - **Firewall on by default** (`firewall_enabled = true`): both the per-NIC
    firewall flag and a `proxmox_virtual_environment_firewall_options`
    resource (`input_policy = "DROP"`, `output_policy = "ACCEPT"`) plus one
    ACCEPT rule per port in `allowed_tcp_ports` (default `[22]`, SSH only).
    All three are wired from the same `firewall_enabled` variable so they
    can't drift apart — see `firewall.tf`.
  - Tags are a flat `list(string)` (the Proxmox model — not a key/value map
    like this repo's AWS tags) with `lifecycle { ignore_changes = [tags] }`,
    since Proxmox lowercases and re-sorts tags server-side.

## OS template ownership (important)

This module does **not** create a `proxmox_download_file` resource. That
resource is identified by `datastore_id` + file name — if every module
instantiation created its own, multiple containers built from the same
OS/version would fight over ownership of the same remote file.

Instead, `template_file_id` is a required input. Create the download once,
elsewhere (a good spot: alongside whatever calls this module for the first
container of a given OS version), and pass its `.id` in — or reference an
existing template already present on the storage by its
`<datastore_id>:vztmpl/<file_name>` string directly.

## What this module does NOT do

- **No OS-level hardening.** Terraform/the Proxmox API has no first-class
  lever for arbitrary in-guest configuration on an LXC (no cloud-init
  equivalent the way Proxmox VMs have one). sshd config, fail2ban,
  unattended-upgrades, etc. are out of scope for this module — configure
  them some other way (e.g. a config-management pass after boot).
- **No real instantiation.** This module is the building block; wiring it up
  against real node/storage/SSH-key values is separate, later work.

## Requirements

- `bpg/proxmox` provider `~> 0.111` (matching `../../terraform.tf`'s pin).

## Inputs

| Name               | Required | Default                  | Description                                                          |
|--------------------|----------|---------------------------|------------------------------------------------------------------------|
| `node_name`         | yes      | —                          | Proxmox node to place the container on.                                |
| `disk_datastore_id` | yes      | —                          | Storage backend for the container's root filesystem.                   |
| `template_file_id`  | yes      | —                          | OS template locator or `proxmox_download_file.<x>.id` — see above.     |
| `hostname`          | yes      | —                          | Container hostname.                                                    |
| `ssh_public_keys`   | yes      | —                          | Root's authorized SSH keys (must be non-empty).                        |
| `vm_id`             | no       | `null` (auto-assign)       | Proxmox VMID.                                                          |
| `description`       | no       | `"Managed by Terraform"`   | Proxmox UI description.                                                |
| `tags`              | no       | `[]`                       | Flat list of tag strings.                                              |
| `unprivileged`      | no       | `true`                     | Run as an unprivileged container.                                      |
| `cores`             | no       | `1`                        | CPU cores.                                                             |
| `memory`            | no       | `512`                      | Dedicated memory (MB).                                                 |
| `swap`              | no       | `0`                        | Swap (MB).                                                             |
| `disk_size`         | no       | `4`                        | Root filesystem size (GB).                                            |
| `bridge`            | no       | `"vmbr0"`                  | Network bridge.                                                        |
| `features_nesting`  | no       | `false`                    | Allow nested containers (e.g. Docker-in-LXC).                          |
| `features_keyctl`   | no       | `false`                    | Allow the `keyctl()` syscall.                                          |
| `features_fuse`     | no       | `false`                    | Allow FUSE mounts.                                                     |
| `features_mknod`    | no       | `false`                    | Allow the `mknod()` syscall.                                          |
| `firewall_enabled`  | no       | `true`                     | Master firewall switch (see "Hardening posture" above).                |
| `allowed_tcp_ports` | no       | `[22]`                     | TCP ports to ACCEPT inbound when the firewall is enabled.              |
| `start_on_boot`     | no       | `true`                     | Auto-start on Proxmox host boot.                                       |
| `started`           | no       | `true`                     | Whether Terraform should start the container.                          |

## Outputs

| Name             | Description                                              |
|-------------------|-----------------------------------------------------------|
| `vm_id`           | The Proxmox VMID of the container.                        |
| `ipv4_addresses`  | Map of IPv4 addresses per network device (once booted).   |

## References

- [`proxmox_virtual_environment_container`](https://github.com/bpg/terraform-provider-proxmox/blob/main/docs/resources/virtual_environment_container.md)
- [`proxmox_virtual_environment_firewall_options`](https://github.com/bpg/terraform-provider-proxmox/blob/main/docs/resources/virtual_environment_firewall_options.md)
- [`proxmox_virtual_environment_firewall_rules`](https://github.com/bpg/terraform-provider-proxmox/blob/main/docs/resources/virtual_environment_firewall_rules.md)
- [`proxmox_download_file`](https://github.com/bpg/terraform-provider-proxmox/blob/main/docs/resources/download_file.md)
