variable "node_name" {
  type        = string
  description = "Name of the Proxmox node the container is created on. No default: every instantiation must supply the real node explicitly."
}

variable "disk_datastore_id" {
  type        = string
  description = "Proxmox storage ID the container's root filesystem (disk block) is created on (e.g. \"local-lvm\"). No default: every instantiation must supply the real storage backend explicitly."
}

variable "template_file_id" {
  type        = string
  description = <<-EOT
    The OS template this container is built from, in `<datastore_id>:<content_type>/<file_name>` form
    (e.g. "local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"), or the `.id` of a
    `proxmox_download_file` resource.

    This module deliberately does NOT create its own download resource: that resource is identified by
    `datastore_id` + file name, so if every module instantiation created its own, multiple containers
    built from the same OS/version would fight over ownership of the same remote file. Create the
    download once, elsewhere (see this module's README and examples/basic/), and pass its `.id` in here.
  EOT
}

variable "hostname" {
  type        = string
  description = "Hostname for the container (initialization.hostname). Must be a valid DNS name."
}

variable "ssh_public_keys" {
  type        = list(string)
  description = "SSH public keys authorized for the root account (initialization.user_account.keys). Root's password is never set, so SSH keys are the only way in — this list cannot be empty."

  validation {
    condition     = length(var.ssh_public_keys) > 0
    error_message = "ssh_public_keys must contain at least one key. This module never sets a root password (not even a generated one) — an empty list would leave the container completely unreachable."
  }
}

variable "vm_id" {
  type        = number
  default     = null
  description = "Proxmox VMID for the container. Leave null to let Proxmox auto-assign the next available ID."
}

variable "description" {
  type        = string
  default     = "Managed by Terraform"
  description = "Description shown in the Proxmox UI for this container."
}

variable "tags" {
  type        = list(string)
  default     = []
  description = "Tags applied to the container. Proxmox tags are a flat list of strings (unlike this repo's AWS key/value tags) and Proxmox always lowercases and re-sorts them server-side — this module ignores drift on this attribute (see main.tf's lifecycle block)."
}

variable "unprivileged" {
  type        = bool
  default     = true
  description = "Whether the container runs as unprivileged on the host. Defaults to true (hardened default); set to false only when a specific workload requires root-equivalent host access."
}

variable "cores" {
  type        = number
  default     = 1
  description = "Number of CPU cores assigned to the container."
}

variable "memory" {
  type        = number
  default     = 512
  description = "Dedicated memory in megabytes."
}

variable "swap" {
  type        = number
  default     = 0
  description = "Swap size in megabytes."
}

variable "disk_size" {
  type        = number
  default     = 4
  description = "Root filesystem size in gigabytes."
}

variable "bridge" {
  type        = string
  default     = "vmbr0"
  description = "Name of the network bridge the container's network interface attaches to."
}

variable "features_nesting" {
  type        = bool
  default     = false
  description = "Allow nested containers (required for e.g. Docker-in-LXC). Defaults to false (minimal feature surface); a future Docker-in-LXC service module would set this true."
}

variable "features_keyctl" {
  type        = bool
  default     = false
  description = "Allow the keyctl() syscall inside the container. Defaults to false (minimal feature surface)."
}

variable "features_fuse" {
  type        = bool
  default     = false
  description = "Allow FUSE filesystem mounts inside the container. Defaults to false (minimal feature surface)."
}

variable "features_mknod" {
  type        = bool
  default     = false
  description = "Allow the mknod() syscall inside the container. Defaults to false (minimal feature surface)."
}

variable "firewall_enabled" {
  type        = bool
  default     = true
  description = <<-EOT
    Master firewall switch, wired to BOTH the per-NIC network_interface.firewall flag and the
    proxmox_virtual_environment_firewall_options.enabled attribute (both are required for filtering to
    actually apply — see firewall.tf). Defaults to true.
  EOT
}

variable "allowed_tcp_ports" {
  type        = list(number)
  default     = [22]
  description = "TCP ports to ACCEPT inbound when firewall_enabled is true; one firewall rule is created per port. Defaults to [22] (SSH only)."
}

variable "start_on_boot" {
  type        = bool
  default     = true
  description = "Whether the container automatically starts when the Proxmox host boots."
}

variable "started" {
  type        = bool
  default     = true
  description = "Whether Terraform should start the container after creating/updating it."
}
