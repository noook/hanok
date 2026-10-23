#!/usr/bin/env bash
# Move Plouf's monitoring (its `lgtm` container and the data it collected) into the shared observability stack.
#
#   scripts/migrate-plouf-lgtm.sh [--dry-run] [--tailnet]
#
# Run as root on docker-host, from the hanok checkout, once stacks/observability has its secrets.
# What it does, in order (docs/runbooks/migrate-plouf-monitoring.md explains each step):
#   1. checks: the source container and volume, free disk space, the target volume is new or empty;
#   2. pulls the stack's images and copies the data while Plouf's lgtm still runs (the long part, no downtime);
#   3. stops Plouf's lgtm (not removed), copies again what changed meanwhile (seconds);
#   4. starts the observability stack and waits for Grafana and Loki to be healthy;
#   5. connects Plouf's running web and worker to the `observability` network, so `http://lgtm:4318`
#      reaches the new stack at once, without redeploying Plouf;
#   6. checks the old data is there and new data arrives.
# If step 4 fails, it rolls back: the new stack is stopped and Plouf's lgtm is started again. The old volume is
# only ever read, so it stays as it was until you delete it yourself.
#
# Knobs: SRC_PROJECT (plouf), SRC_VOLUME_KEY (lgtm-data), DST_VOLUME (observability_lgtm-data),
# SYNC_IMAGE (alpine:3.22), WAIT_NEW_DATA_S (180).
set -euo pipefail

SRC_PROJECT="${SRC_PROJECT:-plouf}"
SRC_SERVICE=lgtm
SRC_VOLUME_KEY="${SRC_VOLUME_KEY:-lgtm-data}"
DST_PROJECT=observability
DST_VOLUME="${DST_VOLUME:-observability_lgtm-data}"
SYNC_IMAGE="${SYNC_IMAGE:-alpine:3.22}"
WAIT_NEW_DATA_S="${WAIT_NEW_DATA_S:-180}"

dry_run=""
up_args=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=1 ;;
    --tailnet) up_args+=(--profile tailnet) ;;
    *) echo "usage: $0 [--dry-run] [--tailnet]" >&2; exit 64 ;;
  esac
done

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { log "error: $*"; exit 1; }
run() { if [ -n "$dry_run" ]; then log "(dry run) $*"; else "$@"; fi; }

sync_data() { # $1 = label for the log; rsync keeps it incremental, so the second pass only copies what changed
  log "copying data ($1)"
  run docker run --rm -v "$src_volume":/from:ro -v "$DST_VOLUME":/to "$SYNC_IMAGE" \
    sh -c 'apk add --no-cache --quiet rsync && rsync -a --delete /from/ /to/'
}

prom() { # $1 = PromQL, $2 = unix time (optional): how many series the answer holds
  docker exec "$DST_PROJECT-lgtm-1" curl -fsS -G --data-urlencode "query=$1" ${2:+--data-urlencode "time=$2"} \
    "http://127.0.0.1:9090/api/v1/query" | { grep -o '"metric"' || true; } | wc -l
}

# ---------------------------------------------------------------- 1. checks
[ "$(id -u)" = 0 ] || [ -n "$dry_run" ] || [ -n "${HANOK_ALLOW_NON_ROOT:-}" ] || die "run as root (docker and /run/hanok)"
src_container="$(docker ps -a -q --filter "label=com.docker.compose.project=$SRC_PROJECT" --filter "label=com.docker.compose.service=$SRC_SERVICE" | head -1)"
src_volume="$(docker volume ls -q --filter "label=com.docker.compose.project=$SRC_PROJECT" --filter "label=com.docker.compose.volume=$SRC_VOLUME_KEY" | head -1)"
[ -n "$src_volume" ] || die "no volume '$SRC_VOLUME_KEY' in compose project '$SRC_PROJECT': nothing to migrate (start the stack with scripts/up.sh $DST_PROJECT instead)"
log "source: volume $src_volume, container ${src_container:-<none>}"

if docker volume inspect "$DST_VOLUME" >/dev/null 2>&1; then
  used="$(docker run --rm -v "$DST_VOLUME":/to:ro "$SYNC_IMAGE" sh -c 'ls -A /to | wc -l')"
  if [ "$used" != 0 ] && [ -z "${RESUME:-}" ]; then
    die "$DST_VOLUME already holds data. If a previous run stopped half way, rerun with RESUME=1 (rsync continues it)"
  fi
fi
if docker ps -q --filter "label=com.docker.compose.project=$DST_PROJECT" --filter "label=com.docker.compose.service=lgtm" | grep -q .; then
  die "the observability stack's lgtm is already running: migrate before starting it"
fi

need_kb="$(docker run --rm -v "$src_volume":/from:ro "$SYNC_IMAGE" du -sk /from | cut -f1)"
free_kb="$(df -Pk "$(docker info --format '{{.DockerRootDir}}')" | awk 'NR==2 {print $4}')"
log "data to copy: $((need_kb / 1024)) MB, free: $((free_kb / 1024)) MB"
[ "$free_kb" -gt $((need_kb * 12 / 10 + 1048576)) ] || die "not enough free disk space (need the data size + 20 % + 1 GB)"

endpoint=""
plouf_apps=()
for svc in web worker; do
  c="$(docker ps -q --filter "label=com.docker.compose.project=$SRC_PROJECT" --filter "label=com.docker.compose.service=$svc" | head -1)"
  [ -n "$c" ] || continue
  plouf_apps+=("$c")
  e="$(docker inspect "$c" --format '{{range .Config.Env}}{{println .}}{{end}}' | sed -n 's/^OTEL_EXPORTER_OTLP_ENDPOINT=//p')"
  [ -n "$e" ] && endpoint="$e"
done
case "$endpoint" in
  http://lgtm:4318*) log "Plouf sends to $endpoint: it will reach the new stack once connected to the network" ;;
  "") log "warning: Plouf's web/worker have no OTEL_EXPORTER_OTLP_ENDPOINT: they send nothing today (see Plouf #59)" ;;
  *) log "warning: Plouf sends to '$endpoint', not http://lgtm:4318: set it to that in Plouf's secrets and redeploy" ;;
esac

[ -n "$dry_run" ] && log "dry run: checks passed; the steps below are only printed"

# ---------------------------------------------------------------- 2. pull and first copy (no downtime)
for net in proxy observability; do
  docker network inspect "$net" >/dev/null 2>&1 || run docker network create "$net" >/dev/null
done
run docker pull --quiet "$SYNC_IMAGE" >/dev/null
docker volume inspect "$DST_VOLUME" >/dev/null 2>&1 || run docker volume create \
  --label "com.docker.compose.project=$DST_PROJECT" --label "com.docker.compose.volume=lgtm-data" "$DST_VOLUME" >/dev/null
sync_data "first pass, Plouf's monitoring still running"

# ---------------------------------------------------------------- 3. stop, final copy
stopped_at="$(date +%s)"
if [ -n "$src_container" ]; then
  log "stopping Plouf's lgtm (downtime starts)"
  run docker stop -t 60 "$src_container" >/dev/null
fi
sync_data "final pass"

# ---------------------------------------------------------------- 4. start the stack, roll back on failure
rollback() {
  log "rolling back: stopping the new stack, starting Plouf's lgtm again"
  docker compose --project-directory "$root/stacks/$DST_PROJECT" -f "$root/stacks/$DST_PROJECT/compose.yaml" stop || true
  [ -n "$src_container" ] && docker start "$src_container" >/dev/null
  log "rolled back. The copied data stays in $DST_VOLUME; rerun with RESUME=1 after fixing the cause."
  exit 1
}
log "starting the observability stack"
if [ -n "$dry_run" ]; then
  log "(dry run) $root/scripts/up.sh $DST_PROJECT ${up_args[*]}"
else
  "$root/scripts/up.sh" "$DST_PROJECT" "${up_args[@]}" || rollback
fi
log "monitoring is back after $(( $(date +%s) - stopped_at )) s"

# ---------------------------------------------------------------- 5. connect Plouf's running containers
for c in "${plouf_apps[@]}"; do
  if docker inspect "$c" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' | grep -qw observability; then
    continue
  fi
  log "connecting $(docker inspect "$c" --format '{{.Name}}') to the observability network"
  run docker network connect observability "$c"
done

[ -n "$dry_run" ] && { log "dry run done"; exit 0; }

# ---------------------------------------------------------------- 6. checks
old="$(prom 'count({__name__=~".+"})' "$((stopped_at - 60))")"
if [ "$old" -gt 0 ]; then log "old metrics are there (Prometheus answers for one minute before the stop)"
else log "warning: no metrics from before the stop. If Plouf's lgtm had collected some, look at $DST_VOLUME before deleting $src_volume"; fi

if [ -n "$endpoint" ]; then
  log "waiting up to $WAIT_NEW_DATA_S s for new data from Plouf"
  deadline=$(( $(date +%s) + WAIT_NEW_DATA_S ))
  while :; do
    # timestamp() drops metric names, so several metrics in one vector clash (HTTP 422): ask one gauge the worker
    # reports on every export.
    if [ "$(prom "max(timestamp(worker_queue_backlog)) > $stopped_at" 2>/dev/null)" -gt 0 ]; then
      log "new data from Plouf arrives"; break
    fi
    [ "$(date +%s)" -lt "$deadline" ] || { log "warning: no new Plouf metric yet; check Plouf's worker logs for OTLP export errors"; break; }
    sleep 10
  done
fi

cat <<EOF

Done. Next:
  - Open Grafana: https://grafana.<your tailnet>.ts.net (with --tailnet) or an SSH tunnel to 127.0.0.1:3317.
    The admin password is the one Plouf's Grafana already had (it lives in the copied data).
  - Plouf's own release that drops lgtm from its compose and joins the observability network makes step 5
    permanent. Until then, a Plouf redeploy disconnects web and worker: rerun this script's step 5 by hand:
      docker network connect observability plouf-web-1; docker network connect observability plouf-worker-1
  - Plouf's old container and volume are kept for rollback. After a few days:
      docker rm $( [ -n "$src_container" ] && docker inspect "$src_container" --format '{{.Name}}' | tr -d / ) && docker volume rm $src_volume
EOF
