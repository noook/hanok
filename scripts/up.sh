#!/usr/bin/env bash
# Start (or update) one stack of this repo: scripts/up.sh <stack> [compose args...]
#
# Run as root on docker-host, from the checkout (/opt/hanok). Secrets come from stacks/<stack>/secrets.enc.env,
# decrypted with SOPS into a root-only file under /run that is deleted when the script ends, as Plouf's deploy does.
# A plain stacks/<stack>/.env is used instead when it exists (local tests). Extra args go to `docker compose up`,
# e.g. `scripts/up.sh observability --profile tailnet`. Shared networks are created if missing.
set -euo pipefail

usage() { echo "usage: scripts/up.sh <stack> [--profile <p>] [compose up args...]" >&2; exit 64; }
[ "$#" -ge 1 ] || usage
stack="$1"; shift
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$root/stacks/$stack"
[ -f "$dir/compose.yaml" ] || { echo "error: no stacks/$stack/compose.yaml" >&2; exit 66; }

profiles=()
while [ "$#" -gt 0 ] && [ "$1" = "--profile" ]; do profiles+=(--profile "$2"); shift 2; done

for net in proxy observability; do
  docker network inspect "$net" >/dev/null 2>&1 || { echo "hanok: creating network $net"; docker network create "$net" >/dev/null; }
done

env_file=""
cleanup() {
  if [ -n "$env_file" ] && [ "$env_file" != "$dir/.env" ]; then rm -f "$env_file"; fi
  return 0
}
trap cleanup EXIT
if [ -f "$dir/.env" ]; then
  env_file="$dir/.env"
elif [ -f "$dir/secrets.enc.env" ]; then
  umask 077
  mkdir -p /run/hanok
  env_file="$(mktemp /run/hanok/"$stack".XXXXXX)"
  sops --decrypt --input-type dotenv --output-type dotenv "$dir/secrets.enc.env" >"$env_file"
fi

args=(compose --project-directory "$dir" -f "$dir/compose.yaml")
[ -n "$env_file" ] && args+=(--env-file "$env_file")
docker "${args[@]}" "${profiles[@]}" pull --quiet
docker "${args[@]}" "${profiles[@]}" up --detach --wait --remove-orphans "$@"
docker "${args[@]}" "${profiles[@]}" ps
