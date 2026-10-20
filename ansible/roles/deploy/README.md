# deploy role

Implements application-stack reconciliation with one host-local c5e controller
per `deployment_hosts` member. The controller uses that host's short inventory
name, local Docker socket, and `/var/lib/c5e-live` worktree (mounted at the same
absolute path); assignments are reconciled only for that host.

It prepares the c5e image/worktree and manages the systemd service. It does not
adopt foreign Docker resources based on project-name matches; ownership conflicts
block operations. The `retain` removal policy preserves removed assignments and
orphans.

The `secrets` capability owns the root-only c5e credential file. This role
consumes that file and skips service setup until it exists. Initialize credentials
with `playbooks/c5e-reconciler.yaml --limit <host>`, one host per invocation;
proxy-network migration IDs must be inspected and supplied per local Docker daemon.

When exact network migration IDs are supplied, the role retains them in a
root-only `proxy-network-migration.json` file so routine convergence cannot
remove the approval before c5e accepts the network. After verifying acceptance,
run the targeted stack-host playbook with
`-e deploy_proxy_network_migration_clear=true` to remove the approval and restart
c5e without migration flags.
