# Both of these resources, plus the per-NIC `network_interface.firewall` flag
# on the container resource (main.tf), are required for firewall filtering to
# actually apply — all three are wired from the same firewall_enabled
# variable so they can't drift apart.

resource "proxmox_virtual_environment_firewall_options" "this" {
  node_name    = var.node_name
  container_id = proxmox_virtual_environment_container.this.vm_id

  enabled       = var.firewall_enabled
  input_policy  = "DROP"
  output_policy = "ACCEPT"
}

resource "proxmox_virtual_environment_firewall_rules" "this" {
  node_name    = var.node_name
  container_id = proxmox_virtual_environment_container.this.vm_id

  dynamic "rule" {
    for_each = var.allowed_tcp_ports
    content {
      type    = "in"
      action  = "ACCEPT"
      proto   = "tcp"
      dport   = tostring(rule.value)
      comment = "Allow inbound TCP ${rule.value}"
    }
  }
}
