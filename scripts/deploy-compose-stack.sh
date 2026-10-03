#!/usr/bin/env bash
set -eu

: "${STACK:?STACK must be set}"

export GITHUB_REPOSITORY="$CI_REPO" GITHUB_SHA="$CI_COMMIT_SHA" GITHUB_RUN_ID="$CI_PIPELINE_NUMBER" GITHUB_RUN_ATTEMPT=1 GITHUB_RUN_NUMBER="$CI_PIPELINE_NUMBER" DOCKER_USER=deploy
mkdir -p ~/.ssh
tailscaled --tun=userspace-networking --socks5-server=localhost:1055 --state=/tmp/tailscale.state >/tmp/tailscaled.log 2>&1 &
for i in $(seq 1 30); do
  [ -S /var/run/tailscale/tailscaled.sock ] && break
  sleep 1
done
[ -S /var/run/tailscale/tailscaled.sock ] || { cat /tmp/tailscaled.log; exit 1; }
tailscale up --auth-key="$TS_OAUTH_CLIENT_SECRET?preauthorized=true&ephemeral=true" --advertise-tags=tag:ci --timeout=30s
tailscale status >/dev/null 2>&1 || { cat /tmp/tailscaled.log; exit 1; }
printf 'Host *\n  ProxyCommand tailscale nc %%h %%p\n' > ~/.ssh/config
chmod 600 ~/.ssh/config
ruby scripts/discover-deploy-hosts.rb ansible/inventory.yaml > /tmp/deploy-hosts.json
ruby -c scripts/reconcile-host.rb
ruby -rjson -e 'JSON.parse(File.read("/tmp/deploy-hosts.json")).each { |host| puts "#{host.fetch("id")} #{host.fetch("address")}" }' > /tmp/deploy-hosts.txt
while read -r host_id host_address; do
  ssh-keyscan -H "$host_address" < /dev/null >> ~/.ssh/known_hosts
  # The reconciler's SSH commands inherit stdin; keep them from consuming the
  # remaining host list and terminating the loop after the first host.
  ruby scripts/reconcile-host.rb "$host_id" "$host_address" "$STACK" < /dev/null
done < /tmp/deploy-hosts.txt
