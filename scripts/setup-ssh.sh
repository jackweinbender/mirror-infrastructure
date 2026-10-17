#!/usr/bin/env bash
# Bootstrap Tailscale and configure SSH for deployment hosts.
#
# Must be called from a CI runner that has TS_OAUTH_CLIENT_SECRET set.
# Sets up ~/.ssh/config to route all connections through Tailscale.
# Run once per CI job before any deploy-stack.sh calls.

set -euo pipefail

echo "[setup-ssh] starting Tailscale"

mkdir -p ~/.ssh
tailscaled --tun=userspace-networking --socks5-server=localhost:1055 --state=/tmp/tailscale.state >/tmp/tailscaled.log 2>&1 &

for i in $(seq 1 30); do
  [ -S /var/run/tailscale/tailscaled.sock ] && break
  sleep 1
done

[ -S /var/run/tailscale/tailscaled.sock ] || { cat /tmp/tailscaled.log; exit 1; }

tailscale up \
  --auth-key="${TS_OAUTH_CLIENT_SECRET}?preauthorized=true&ephemeral=true" \
  --advertise-tags=tag:ci \
  --timeout=30s

tailscale status >/dev/null 2>&1 || { cat /tmp/tailscaled.log; exit 1; }

printf 'Host *\n  ProxyCommand tailscale nc %%h %%p\n' > ~/.ssh/config
chmod 600 ~/.ssh/config

echo "[setup-ssh] Tailscale connected; SSH ready"