#!/usr/bin/env bash
# One-time setup of a fresh hanok-ci VM (Debian 13 cloud image). Run as the admin user, from a copy of this
# directory on the VM:  scp -r hosts/hanok-ci hanok-ci: && ssh hanok-ci 'sudo hanok-ci/setup.sh'
#
# Installs the QEMU guest agent, unattended-upgrades, Docker Engine from Docker's apt repository, the `runner`
# user (in the docker group, no sudo), the job-completed cleanup hook and the weekly prune timer.
# Re-running it is safe: every step checks before it changes anything.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "error: run with sudo" >&2; exit 1; }
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DEBIAN_FRONTEND=noninteractive

apt-get update -q
apt-get full-upgrade -yq
apt-get install -yq qemu-guest-agent unattended-upgrades ca-certificates curl
systemctl enable --now qemu-guest-agent

# Docker's own repository: Debian's docker.io lags behind and has no buildx plugin.
install -m 0755 -d /etc/apt/keyrings
[ -f /etc/apt/keyrings/docker.asc ] || curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $VERSION_CODENAME stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -q
apt-get install -yq docker-ce docker-ce-cli containerd.io docker-buildx-plugin

# Tools GitHub's hosted images ship and workflows call directly: git, jq, and the GitHub CLI (Plouf's Release
# workflow runs `gh release create`). The CLI comes from GitHub's own apt repository.
[ -f /etc/apt/keyrings/githubcli.gpg ] || curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli.gpg] https://cli.github.com/packages stable main" \
  > /etc/apt/sources.list.d/github-cli.list
apt-get update -q
apt-get install -yq git jq gh

# The user the runners run as. Being in the docker group makes it root-equivalent inside this VM; that is why the
# VM, not this user, is the security boundary (ADR 0004).
id runner >/dev/null 2>&1 || useradd --create-home --shell /bin/bash runner
usermod -aG docker runner
install -d -o runner -g runner /opt/actions-runner

install -m 0755 "$here/files/job-completed.sh" /opt/actions-runner/job-completed.sh
install -m 0644 "$here/files/docker-prune.service" "$here/files/docker-prune.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now docker-prune.timer

# IPv6 off in the guest, so programs don't try an IPv6 address first and wait for the firewall's drop to time
# out. The Proxmox firewall is what enforces it (a job is root here and could turn it back on).
cat > /etc/sysctl.d/90-no-ipv6.conf <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
sysctl --quiet --system

echo "Done. Next: sudo $here/add-repo.sh <owner/repo> <count>  (docs/runbooks/ci-runner.md)"
