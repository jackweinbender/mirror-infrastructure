# host_ops role

Configures the standard Debian host environment: baseline packages, users and
sudo, SSH policy, locale and time, console access, and local retention. Tailscale
and logging are separate capabilities composed by `debian-host-ops.yaml`.

Initial account creation during LXC bootstrap imports `tasks/sudo_users.yml`;
full host convergence uses this role through the Debian host-operations profile.
