# Compose stacks in one repository, deployed by hand with a script

I run one Proxmox host with one Docker LXC (`docker-host`). Its stacks used to live only in `/opt/stacks` on that machine: not reviewable, not rebuildable, and invisible to the agents that help me. Shared pieces (monitoring) were starting to live inside one application's repository.

I looked at three ways a self-hoster I follow has run the same kind of homelab, each for a few months:

- Compose files in a repo, with Ansible for the host, Terraform for VMs and DNS, Komodo to deploy, and a Tailscale sidecar per private service.
- NixOS: the whole machine described in Nix, rebuilt by a GitHub runner on every merge.
- Kubernetes with Argo CD: manifests in the repo, the cluster syncs itself.

The last two mean rebuilding the host and learning a new system, for one machine. The first matches what I already run.

**Decision.** One repository, `hanok`, holds a directory per shared stack (`stacks/<name>/compose.yaml`), its secrets encrypted with SOPS + age, and `scripts/up.sh` to start or update one. My own applications keep their stacks in their own repositories and join the shared networks. Images are pinned; Renovate proposes updates. Deploying is `git pull && scripts/up.sh <stack>` as root on docker-host, by hand.

## Consequences

- Rebuilding docker-host means installing Docker, SOPS and the age key, cloning the repo and starting each stack.
- Later, maybe: Terraform for Cloudflare DNS and the Tailscale policy, a pull-based timer like Plouf's to deploy on merge, Ansible for the Proxmox side (LXC config, TUN device).
