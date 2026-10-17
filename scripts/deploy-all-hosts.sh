#!/usr/bin/env bash
# Deploy a compose stack to every host where it's assigned.
#
# Usage: deploy-all-hosts.sh STACK
#
# Discoveries deploy hosts from the Ansible inventory, then runs
# deploy-stack.sh for each host that has the stack assigned.
# Used by CI workflows — assumes setup-ssh.sh has already been run.

set -euo pipefail

STACK="$1"

echo "[$STACK] discovering deploy hosts"
ruby scripts/discover-deploy-hosts.rb ansible/inventory.yaml > /tmp/deploy-hosts.json

ruby -rjson -e '
  JSON.parse(File.read("/tmp/deploy-hosts.json")).each { |h|
    puts "#{h["id"]} #{h["address"]}"
  }
' > /tmp/deploy-hosts.txt

FAILED=false

while read -r host_id host_address; do
  ssh-keyscan -H "$host_address" < /dev/null >> ~/.ssh/known_hosts 2>/dev/null || true
  echo "--- $STACK -> $host_id ($host_address) ---"
  if bash scripts/deploy-stack.sh "$STACK" "$host_id" "$host_address"; then
    echo "--- $host_id OK ---"
  else
    echo "--- $host_id FAILED ---"
    FAILED=true
  fi
done < /tmp/deploy-hosts.txt

if [ "$FAILED" = "true" ]; then
  echo "[$STACK] one or more hosts failed"
  exit 1
fi

echo "[$STACK] all hosts done"