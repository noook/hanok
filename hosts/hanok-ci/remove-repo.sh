#!/usr/bin/env bash
# Unregister every runner of a repository from this VM: sudo ./remove-repo.sh <owner/repo>
# The removal token: Settings > Actions > Runners > the runner > Remove, the --token value on that page
# (valid for one hour, for all runners of the repo). Read at a hidden prompt.
set -euo pipefail
[ "$#" = 1 ] && [[ "$1" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "usage: sudo $0 <owner/repo>" >&2; exit 64; }
[ "$(id -u)" = 0 ] || { echo "error: run with sudo" >&2; exit 1; }
repo="${1#*/}"
read -rsp "Removal token for $1: " token; echo
shopt -s nullglob
for dir in /opt/actions-runner/"$repo"-[0-9]*; do
  (cd "$dir" && ./svc.sh stop && ./svc.sh uninstall && sudo -u runner ./config.sh remove --token "$token")
  rm -rf "$dir"
  echo "$(basename "$dir"): removed"
done
