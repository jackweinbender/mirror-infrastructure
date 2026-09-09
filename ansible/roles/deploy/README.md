# deploy role

Creates the local account used by GitHub Actions to connect over Tailscale SSH.

This role does not manage SSH keys or Tailscale. Tailscale SSH provides remote
access, while the Docker role can add `deploy` to the Docker group on Docker
hosts.

On Docker hosts, the role also installs `stackctl` and its systemd template for
reconciling the existing Compose deployment layout:

- live stacks: `/etc/compose-stacks/<stack>`
- Compose file: `docker-compose.yaml`
- managed-state records: `/var/lib/stackctl/managed/<stack>`
- service instances: `docker-compose@<stack>.service`

The deployment workflow remains responsible for publishing stack directories;
`stackctl` can be installed independently before that workflow is integrated
with it.
