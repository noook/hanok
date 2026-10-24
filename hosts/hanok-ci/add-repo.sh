#!/usr/bin/env bash
# Register a private repository on this VM: sudo ./add-repo.sh <owner/repo> <count>
#
# Creates <count> runners named hanok-ci-<repo>-<n> with the label hanok-ci, in /opt/actions-runner/<repo>-<n>,
# each a systemd service running as `runner`, with the cleanup hook set. Use one runner per job a workflow runs
# in parallel (Plouf's CI has two).
#
# The registration token comes from the repository: Settings > Actions > Runners > New self-hosted runner, the
# --token value on that page. It is valid for one hour and for every registration made in that hour. It is read
# at a hidden prompt and never written to disk. NEVER register a public repository (ADR 0004).
set -euo pipefail
# Pinned runner release (https://github.com/actions/runner/releases). Runners update themselves after that,
# so this only matters for new registrations. To bump: take the version and the linux-x64 SHA-256 from the notes.
VERSION=2.338.1
SHA256=08e9ccb3604d2462c24b5e33604dc30810296ca15cc65f23cffd4317eb144c37

usage() { echo "usage: sudo $0 <owner/repo> <count>" >&2; exit 64; }
[ "$#" = 2 ] || usage
slug="$1"; count="$2"
[[ "$slug" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || usage
[[ "$count" =~ ^[1-9]$ ]] || usage
[ "$(id -u)" = 0 ] || { echo "error: run with sudo" >&2; exit 1; }
id runner >/dev/null 2>&1 || { echo "error: no runner user, run setup.sh first" >&2; exit 1; }
repo="${slug#*/}"

# Refuse a public repository: anyone could run code here through a pull request from a fork. Without a token, the API
# answers 200 for a public repository and 404 for a private one; anything else stops here rather than guessing.
visibility=$(curl -sS -o /dev/null -w '%{http_code}' "https://api.github.com/repos/$slug")
case "$visibility" in
  404) ;;
  200) echo "error: $slug is public: never on hanok-ci, use GitHub's runners (ADR 0004)" >&2; exit 1 ;;
  *) echo "error: could not tell whether $slug is public (GitHub answered $visibility); try again" >&2; exit 1 ;;
esac
base=/opt/actions-runner
tarball="$base/actions-runner-linux-x64-$VERSION.tar.gz"

if [ ! -f "$tarball" ]; then
  sudo -u runner curl -fsSL -o "$tarball.part" \
    "https://github.com/actions/runner/releases/download/v$VERSION/actions-runner-linux-x64-$VERSION.tar.gz"
  echo "$SHA256  $tarball.part" | sha256sum -c --quiet
  sudo -u runner mv "$tarball.part" "$tarball"
fi

# Leave it empty when every runner is already registered (it then only adds the cleanup hook).
read -rsp "Registration token for $slug (Enter if already registered): " token; echo

for n in $(seq 1 "$count"); do
  dir="$base/$repo-$n"
  name="hanok-ci-$repo-$n"
  hook="ACTIONS_RUNNER_HOOK_JOB_COMPLETED=$base/job-completed.sh"
  if [ -f "$dir/.runner" ]; then
    # Already registered (by hand, or an earlier run): only make sure the cleanup hook is set.
    if ! grep -qxF "$hook" "$dir/.env" 2>/dev/null; then
      echo "$hook" | sudo -u runner tee -a "$dir/.env" >/dev/null
      (cd "$dir" && ./svc.sh stop && ./svc.sh start) >/dev/null
      echo "$name: already registered, cleanup hook added and runner restarted"
    else
      echo "$name: already registered, nothing to do"
    fi
    continue
  fi
  [ -n "$token" ] || { echo "error: empty token" >&2; exit 1; }
  sudo -u runner mkdir -p "$dir"
  sudo -u runner tar xzf "$tarball" -C "$dir"
  (cd "$dir" && sudo -u runner ./config.sh --unattended --url "https://github.com/$slug" --token "$token" \
    --name "$name" --labels hanok-ci --work _work --replace)
  # The runner reads .env at start: the hook cleans Docker after every job.
  echo "$hook" | sudo -u runner tee -a "$dir/.env" >/dev/null
  (cd "$dir" && ./svc.sh install runner && ./svc.sh start)
  echo "$name: registered and started"
done
echo "Check Settings > Actions > Runners on $slug: every runner should be Idle."
