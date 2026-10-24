# hanok-ci

The VM that runs GitHub Actions jobs for my private repositories (ADR 0004). Its label is `hanok-ci`; a project opts in with `runs-on: ${{ vars.CI_RUNNER || 'ubuntu-latest' }}` (`docs/conventions.md`, "Using the CI runner").

| File | What |
|---|---|
| `firewall.fw.example` | The Proxmox firewall of the VM, as `/etc/pve/firewall/<vmid>.fw`. Fill in the three addresses. |
| `setup.sh` | Run once on a fresh VM: guest agent, automatic updates, Docker, the `runner` user, the cleanup hook and the weekly prune. Safe to re-run. |
| `add-repo.sh <owner/repo> <count>` | Registers a repository `<count>` times as systemd services. Asks for the registration token at a prompt. |
| `remove-repo.sh <owner/repo>` | Unregisters it. Asks for a removal token. |
| `files/` | What `setup.sh` installs: the job-completed hook, the prune service and its timer. |

How to create, register, rebuild and troubleshoot: [docs/runbooks/ci-runner.md](../../docs/runbooks/ci-runner.md).
