# deploy role

Creates the local account used by GitHub Actions to connect over Tailscale SSH.

This role does not manage SSH keys or Tailscale. Tailscale SSH provides remote
access, while the Docker role can add `deploy` to the Docker group on Docker
hosts.
