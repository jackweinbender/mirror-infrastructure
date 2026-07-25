output "vm_id" {
  description = "The Proxmox VMID of the container."
  value       = proxmox_virtual_environment_container.this.vm_id
}

output "ipv4_addresses" {
  description = "Map of IPv4 addresses per network device, as reported by Proxmox (populated once the container has booted and acquired a DHCP lease)."
  value       = proxmox_virtual_environment_container.this.ipv4
}
