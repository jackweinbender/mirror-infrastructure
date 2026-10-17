#!/usr/bin/env bash
# Deploy a single compose stack to one host.
#
# Replaces reconcile-host.rb, reconcile-platform.rb, and deploy-compose-stack.sh
# with a simpler pattern: rsync in-place + per-service rollout with health checks.
#
# Usage: deploy-stack.sh STACK HOST_ID HOST_ADDRESS
#
# Environment:
#   DEPLOY_TIMEOUT    max seconds to wait for new containers to become healthy (default 120)
#   DEPLOY_NO_HC_WAIT seconds to wait for services without healthchecks (default 10)

set -euo pipefail

STACK="$1"
HOST_ID="$2"
HOST_ADDRESS="$3"

REMOTE="deploy@$HOST_ADDRESS"
LIVE="/etc/compose-stacks/$STACK"
WAIT_TIMEOUT="${DEPLOY_TIMEOUT:-120}"
NO_HC_WAIT="${DEPLOY_NO_HC_WAIT:-10}"

# --- Self-managed stacks ------------------------------------------------
# crow-ci hosts its own pipeline runner; reconciling it would down the runner.
case "$STACK" in
  crow-ci)
    echo "[$HOST_ID/$STACK] self-managed; skipped"
    exit 0
    ;;
esac

# --- Determine assignment ------------------------------------------------
ASSIGNMENT="compose-stacks/$STACK/deployments/$HOST_ID/.env.template"

if [ ! -f "$ASSIGNMENT" ]; then
  # Not assigned to this host. Tear down if it exists, otherwise no-op.
  if ssh "$REMOTE" "test -d $LIVE" 2>/dev/null; then
    echo "[$HOST_ID/$STACK] not assigned but deployed; removing"
    ssh "$REMOTE" "cd $LIVE && docker compose --project-name $STACK --env-file .env down --remove-orphans 2>/dev/null; rm -rf $LIVE"
  else
    echo "[$HOST_ID/$STACK] not assigned"
  fi
  exit 0
fi

# --- File delivery -------------------------------------------------------
echo "[$HOST_ID/$STACK] delivering files"
ssh "$REMOTE" "mkdir -p $LIVE"
rsync -r --delete --exclude=.env --exclude=deployments/ "compose-stacks/$STACK/" "$REMOTE:$LIVE/"

# --- Secrets -------------------------------------------------------------
# Merge shared + per-host env templates, resolve 1Password references,
# pipe into remote .env without touching CI runner disk.
ruby scripts/merge-dotenv.rb \
  "compose-stacks/$STACK/.env.template" \
  "$ASSIGNMENT" \
  | op inject \
  | ssh "$REMOTE" "umask 077 && cat > $LIVE/.env && chmod 600 $LIVE/.env"

# Optional host-specific Compose override (e.g. port bindings per host)
if [ -f "compose-stacks/$STACK/deployments/$HOST_ID/docker-compose.yaml" ]; then
  echo "[$HOST_ID/$STACK] applying host override"
  scp "compose-stacks/$STACK/deployments/$HOST_ID/docker-compose.yaml" "$REMOTE:$LIVE/docker-compose.override.yaml"
fi

# --- Rollout -------------------------------------------------------------
echo "[$HOST_ID/$STACK] deploying"

# Pass timeout values to the remote script via env vars to keep quoting simple
# on the remote side. The heredoc is single-quoted to prevent local expansion
# of $ references meant for the remote bash.
ssh "$REMOTE" \
    "LIVE=$LIVE STACK=$STACK WAIT_TIMEOUT=$WAIT_TIMEOUT NO_HC_WAIT=$NO_HC_WAIT" \
    bash -s <<-'ROLLOUT'
  set -euo pipefail
  cd "$LIVE"

  COMPOSE="docker compose --project-name $STACK --env-file .env"

  echo "  pulling images"
  $COMPOSE pull 2>&1 | sed 's/^/    /'

  # Services in dependency order (compose topological sort)
  SERVICES=$($COMPOSE config --services 2>/dev/null)
  if [ -z "$SERVICES" ]; then
    echo "  no services defined"; exit 1
  fi

  ALL_OK=true

  for SERVICE in $SERVICES; do
    # Current scale
    SCALE=$($COMPOSE ps --quiet "$SERVICE" 2>/dev/null | wc -l | tr -d ' ')
    OLD_IDS=""

    if [ "$SCALE" -eq 0 ]; then
      # First deploy — just start
      echo "  $SERVICE: starting (first deploy)"
      $COMPOSE up --detach --no-recreate "$SERVICE"
      continue
    fi

    # Remember old containers before scaling up
    OLD_IDS=$($COMPOSE ps --quiet "$SERVICE" 2>/dev/null | tr '\n' ' ')

    echo "  $SERVICE: scaling from $SCALE to $((SCALE * 2))"
    $COMPOSE up --detach --scale "$SERVICE=$((SCALE * 2))" --no-recreate "$SERVICE"

    # Identify new containers (those not in OLD_IDS)
    ALL_IDS=$($COMPOSE ps --quiet "$SERVICE" 2>/dev/null | tr '\n' ' ')
    FRESH_IDS=""
    for CID in $ALL_IDS; do
      case " $OLD_IDS " in
        *" $CID "*) ;;
        *) FRESH_IDS="$FRESH_IDS $CID" ;;
      esac
    done
    FRESH_IDS=$(echo "$FRESH_IDS" | xargs)

    if [ -z "$FRESH_IDS" ]; then
      echo "  $SERVICE: no new containers started"
      ALL_OK=false
      continue
    fi

    # Check if any new container has a healthcheck defined
    HAS_HC=false
    FIRST=$(echo "$FRESH_IDS" | cut -d' ' -f1)
    if docker inspect --format='{{json .State.Health}}' "$FIRST" 2>/dev/null | grep -q '"Status"'; then
      HAS_HC=true
    fi

    if [ "$HAS_HC" = "true" ]; then
      echo "  $SERVICE: waiting for new containers to become healthy (timeout: ${WAIT_TIMEOUT}s)"
      HEALTHY=false
      for _ in $(seq 1 "$WAIT_TIMEOUT"); do
        HEALTHY=true
        for CID in $FRESH_IDS; do
          STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$CID" 2>/dev/null)
          if [ "$STATUS" != "healthy" ]; then
            if [ "$STATUS" = "unhealthy" ]; then
              echo "  $SERVICE: container $CID is unhealthy"
              HEALTHY=false
              break 2
            fi
            HEALTHY=false
          fi
        done
        if [ "$HEALTHY" = "true" ]; then
          break
        fi
        sleep 1
      done
    else
      echo "  $SERVICE: no healthcheck defined; waiting ${NO_HC_WAIT}s"
      sleep "$NO_HC_WAIT"
      HEALTHY=true
    fi

    if [ "$HEALTHY" != "true" ]; then
      echo "  $SERVICE: FAILED — new containers did not become healthy; rolling back"
      docker stop $FRESH_IDS 2>/dev/null || true
      docker rm $FRESH_IDS 2>/dev/null || true
      ALL_OK=false
      continue
    fi

    echo "  $SERVICE: healthy; stopping old containers"
    # shellcheck disable=SC2086
    docker stop $OLD_IDS 2>/dev/null || true
    # shellcheck disable=SC2086
    docker rm $OLD_IDS 2>/dev/null || true
    echo "  $SERVICE: rolled"
  done

  if [ "$ALL_OK" != "true" ]; then
    echo "DEPLOY FAILED: one or more services did not deploy successfully"
    exit 1
  fi

  docker image prune --force 2>/dev/null || true
  echo "[$STACK] deployed"
ROLLOUT

echo "[$HOST_ID/$STACK] done"