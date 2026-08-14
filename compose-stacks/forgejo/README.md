# Forgejo

Forgejo runs on `docker0-lxc` and is exposed through the host Traefik at
`https://git.weinbender.io`. The hostname is defined in `.env.template` and
can be changed without modifying the Compose definition.

The stack uses the Forgejo 16.0.2 image and stores repositories and application data
in the named Docker volume `forgejo_data`. On `docker0-lxc`, that volume follows the
host-backed Docker data root at `/srv/guest-volumes/docker`; Compose does not require
or create a per-stack directory on the Proxmox host. Git-over-SSH is available on
host port `2222`; Forgejo advertises that port in its generated clone URLs.

The application assignment is represented by
`deployments/docker0-lxc/.env.template`; remove that assignment to stop the stack
on the host during the next reconciliation. The normal deployment workflow
reconciles `docker-networking` and Traefik before Forgejo.
