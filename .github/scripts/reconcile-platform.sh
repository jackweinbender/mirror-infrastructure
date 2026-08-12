#!/usr/bin/env bash
set -uo pipefail

HOST_ID=$1
HOST_ADDRESS=$2

REMOTE_USER=${DOCKER_USER:-deploy}
REMOTE="$REMOTE_USER@$HOST_ADDRESS"
LOCAL_DIR=${LOCAL_DIR:-compose-stacks/docker-host}
BASE=/etc/compose-stacks
LIVE="$BASE/docker-host"
RUN_TAG="${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
STAGE="$BASE/.staging/docker-host-$RUN_TAG"

ssh_run() {
  ssh -o BatchMode=yes "$REMOTE" "$1"
}

cleanup() {
  ssh_run "rm -rf -- '$STAGE'" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if ! ssh_run "umask 077 && mkdir -p -- '$BASE/.staging' && mkdir -- '$STAGE'"; then
  echo "::error::[$HOST_ID/docker-host] unable to create remote staging directory"
  exit 1
fi

if ! ssh_run "docker network inspect proxy >/dev/null 2>&1 || docker network create --driver bridge --attachable proxy >/dev/null"; then
  echo "::error::[$HOST_ID/docker-host] unable to prepare external proxy network"
  exit 1
fi


if ! rsync -r --delete --exclude-from="$LOCAL_DIR/.rsyncexclude" \
  --exclude='.env' --exclude='.env.*' --exclude='.git/' \
  "$LOCAL_DIR/" "$REMOTE:$STAGE/"; then
  echo "::error::[$HOST_ID/docker-host] rsync to staging failed"
  exit 1
fi

if ! ssh_run "cd -- '$STAGE' && if [ -f 'docker-compose.$HOST_ID.yaml' ]; then cp -- 'docker-compose.$HOST_ID.yaml' docker-compose.override.yaml && chmod 600 docker-compose.override.yaml; fi"; then
  echo "::error::[$HOST_ID/docker-host] unable to prepare host Compose override"
  exit 1
fi

marker_content=$(printf 'REPOSITORY=%s\nSTACK_NAME=docker-host\nCOMMIT_SHA=%s\nWORKFLOW_RUN_ID=%s\nWORKFLOW_RUN_NUMBER=%s\nSYNCED_AT=%s\n' \
  "$GITHUB_REPOSITORY" "$GITHUB_SHA" "$GITHUB_RUN_ID" "$GITHUB_RUN_NUMBER" \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)")
if ! printf '%s' "$marker_content" | ssh "$REMOTE" "umask 077 && cat > '$STAGE/.managed-by-github-actions' && chmod 600 '$STAGE/.managed-by-github-actions'"; then
  echo "::error::[$HOST_ID/docker-host] unable to write deployment marker"
  exit 1
fi

if ! OP_SERVICE_ACCOUNT_TOKEN="$OP_SERVICE_ACCOUNT_TOKEN" op inject -i "$LOCAL_DIR/.env.template" | \
  ssh "$REMOTE" "umask 077 && cat > '$STAGE/.env.tmp' && chmod 600 '$STAGE/.env.tmp' && mv -f -- '$STAGE/.env.tmp' '$STAGE/.env'"; then
  echo "::error::[$HOST_ID/docker-host] secret injection failed; live platform was not changed"
  exit 1
fi

if ! ssh_run "cd -- '$STAGE' && docker compose --project-name docker-host --env-file .env config --quiet"; then
  echo "::error::[$HOST_ID/docker-host] staged Compose validation failed"
  exit 1
fi

if ! ssh_run "if [ -e '$LIVE' ]; then test -f '$LIVE/.managed-by-github-actions' && grep -Fxq 'STACK_NAME=docker-host' '$LIVE/.managed-by-github-actions'; fi"; then
  echo "::error::[$HOST_ID/docker-host] existing platform directory is unmarked or has the wrong marker; refusing replacement"
  exit 1
fi

if ! ssh_run "if [ -e '$LIVE' ]; then rm -rf -- '$LIVE'; fi && mv -- '$STAGE' '$LIVE'"; then
  echo "::error::[$HOST_ID/docker-host] platform publication failed"
  exit 1
fi

if ! ssh_run "cd -- '$LIVE' && if docker compose up --help 2>/dev/null | grep -q -- '--wait'; then docker compose --project-name docker-host --env-file .env up -d --remove-orphans --pull always --wait --wait-timeout 120; else docker compose --project-name docker-host --env-file .env up -d --remove-orphans --pull always; fi"; then
  echo "::error::[$HOST_ID/docker-host] Compose up failed"
  exit 1
fi

echo "[$HOST_ID/docker-host] deployed"
