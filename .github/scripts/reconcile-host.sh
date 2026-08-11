#!/usr/bin/env bash
set -uo pipefail

# This script intentionally runs all stacks and reports failures at the end.
HOST_ID=$1
HOST_ADDRESS=$2
STACKS_JSON=$3
REMOTE_USER=${DOCKER_USER:-deploy}
REMOTE="$REMOTE_USER@$HOST_ADDRESS"
BASE=/etc/compose-stacks
RUN_TAG="${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
FAILED=()

ssh_run() { ssh -o BatchMode=yes "$REMOTE" "$1"; }

for stack in $(jq -r '.[]' <<<"$STACKS_JSON"); do
  local_dir="compose-stacks/$stack"
  live="$BASE/$stack"
  assignment="$local_dir/deployments/$HOST_ID.env"
  if [[ -f "$assignment" ]]; then
    merged=$(mktemp)
    stage="$BASE/.staging/$stack-$RUN_TAG"
    cleanup_stage() { ssh_run "rm -rf -- '$stage'" >/dev/null 2>&1 || true; }
    trap cleanup_stage RETURN
    node .github/scripts/merge-dotenv.mjs "$local_dir/deployments/_shared.env" "$assignment" >"$merged" || {
      echo "::error::[$HOST_ID/$stack] dotenv merge failed"; FAILED+=("$HOST_ID/$stack"); rm -f "$merged"; trap - RETURN; continue;
    }
    marker_content=$(printf 'REPOSITORY=%s\nSTACK_NAME=%s\nCOMMIT_SHA=%s\nWORKFLOW_RUN_ID=%s\nWORKFLOW_RUN_NUMBER=%s\nSYNCED_AT=%s\n' \
      "$GITHUB_REPOSITORY" "$stack" "$GITHUB_SHA" "$GITHUB_RUN_ID" "$GITHUB_RUN_NUMBER" "$(date -u +%Y-%m-%dT%H:%M:%SZ)")
    if ! ssh_run "umask 077 && mkdir -p -- '$BASE/.staging' && mkdir -- '$stage'"; then
      echo "::error::[$HOST_ID/$stack] unable to create remote staging directory"; FAILED+=("$HOST_ID/$stack"); rm -f "$merged"; trap - RETURN; continue
    fi
    if ! rsync -r --delete --exclude='.env' --exclude='.env.*' --exclude='.git/' --exclude='deployments/' "$local_dir/" "$REMOTE:$stage/"; then
      echo "::error::[$HOST_ID/$stack] rsync failed"; FAILED+=("$HOST_ID/$stack"); rm -f "$merged"; trap - RETURN; continue
    fi
    if ! ssh_run "umask 077 && printf '%s' '$marker_content' > '$stage/.managed-by-github-actions' && chmod 600 '$stage/.managed-by-github-actions'"; then
      echo "::error::[$HOST_ID/$stack] unable to write deployment marker"; FAILED+=("$HOST_ID/$stack"); rm -f "$merged"; trap - RETURN; continue
    fi
    if ! OP_SERVICE_ACCOUNT_TOKEN="$OP_SERVICE_ACCOUNT_TOKEN" op inject -i "$merged" | ssh "$REMOTE" "umask 077 && cat > '$stage/.env.tmp' && chmod 600 '$stage/.env.tmp' && mv -f -- '$stage/.env.tmp' '$stage/.env'"; then
      echo "::error::[$HOST_ID/$stack] secret injection failed; live stack was not changed"; FAILED+=("$HOST_ID/$stack"); rm -f "$merged"; trap - RETURN; continue
    fi
    if ! ssh_run "cd '$stage' && docker compose --project-name '$stack' --env-file .env config --quiet"; then
      echo "::error::[$HOST_ID/$stack] staged Compose validation failed"; FAILED+=("$HOST_ID/$stack"); rm -f "$merged"; trap - RETURN; continue
    fi
    if ! ssh_run "if [ -e '$live' ]; then test -f '$live/.managed-by-github-actions' && grep -Fxq 'STACK_NAME=$stack' '$live/.managed-by-github-actions'; fi"; then
      echo "::error::[$HOST_ID/$stack] existing live directory is unmarked or has the wrong marker; refusing replacement"; FAILED+=("$HOST_ID/$stack"); rm -f "$merged"; trap - RETURN; continue
    fi
    if ! ssh_run "if [ -e '$live' ]; then rm -rf -- '$live'; fi && mv -- '$stage' '$live'"; then
      echo "::error::[$HOST_ID/$stack] publication failed"; FAILED+=("$HOST_ID/$stack"); rm -f "$merged"; trap - RETURN; continue
    fi
    if ! ssh_run "cd '$live' && if docker compose up --help 2>/dev/null | grep -q -- '--wait'; then docker compose --project-name '$stack' --env-file .env up -d --remove-orphans --pull always --wait --wait-timeout 120; else docker compose --project-name '$stack' --env-file .env up -d --remove-orphans --pull always; fi"; then
      echo "::error::[$HOST_ID/$stack] Compose up failed"; FAILED+=("$HOST_ID/$stack"); rm -f "$merged"; trap - RETURN; continue
    fi
    echo "[$HOST_ID/$stack] deployed"
    rm -f "$merged"; trap - RETURN
  else
    # An SSH failure is a host failure, never an unassignment. Only a marked
    # existing directory is eligible for teardown and automatic removal.
    if ! ssh_run "test -d '$live'"; then
      if ssh -o BatchMode=yes "$REMOTE" true >/dev/null 2>&1; then
        echo "[$HOST_ID/$stack] not assigned and not deployed"
      else
        echo "::error::[$HOST_ID/$stack] host connectivity failed; no cleanup attempted"; FAILED+=("$HOST_ID/$stack")
      fi
      continue
    fi
    if ! ssh_run "test -f '$live/.managed-by-github-actions' && grep -Fxq 'STACK_NAME=$stack' '$live/.managed-by-github-actions'"; then
      echo "::error::[$HOST_ID/$stack] unmarked live directory exists; refusing teardown"; FAILED+=("$HOST_ID/$stack"); continue
    fi
    if ! ssh_run "cd '$live' && docker compose --project-name '$stack' --env-file .env down --remove-orphans"; then
      echo "::error::[$HOST_ID/$stack] teardown failed; retaining remote directory"; FAILED+=("$HOST_ID/$stack"); continue
    fi
    if ! ssh_run "rm -rf -- '$live'"; then
      echo "::error::[$HOST_ID/$stack] teardown succeeded but directory removal failed"; FAILED+=("$HOST_ID/$stack"); continue
    fi
    echo "[$HOST_ID/$stack] removed"
  fi
done

if ((${#FAILED[@]})); then
  printf '::error::Failed stack/host pairs: %s\n' "${FAILED[*]}"
  exit 1
fi
