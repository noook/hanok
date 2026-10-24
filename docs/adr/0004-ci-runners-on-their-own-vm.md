# CI runners on their own VM

My private repositories use GitHub Actions, and the free plan gives 2,000 minutes a month. Plouf used them up in October 2026. The Proxmox host has spare memory and idle hours, and self-hosted runners cost no Actions minutes. This is the first piece of hanok outside docker-host.

**Decision.**

- **A VM, `hanok-ci`, not an LXC.** Every job can use the Docker socket, which makes it root in its guest, so the guest is the security boundary. An LXC shares the Proxmox host's kernel: a container escape from a CI job would land on the machine that runs everything. A VM has its own kernel. Docker runs there without `nesting`/`keyctl`, and QEMU emulation for arm64 image builds registers in the VM's kernel, not the host's. The cost is a fixed RAM reservation (8 GB, no ballooning), which the host can spare.
- **Isolated from everything I run.** The Proxmox firewall on the VM's NIC lets it reach the internet and nothing private except the box for DNS: no LAN, no tailnet, and no IPv6 at all, because the box gives the LAN a public IPv6 prefix that the private-range rules would not cover (`hosts/hanok-ci/firewall.fw.example`). SSH comes in only from my Mac and from the Tailscale subnet router. Nothing from production goes on it: no Tailscale, no hanok checkout, no SOPS age key.
- **Lower CPU weight.** The host has four cores shared with docker-host. The VM has `cpuunits` 50 against the default 100, so production wins when both are busy.
- **One registration per repository.** A personal GitHub account has no account-level runners: a runner belongs to a repository, an organisation or an enterprise. Moving the repositories into an organisation would allow one shared runner, but it would rename `ghcr.io/noook/...` images that running hosts pull. So each private repository is registered on the same VM, as many times as it runs jobs in parallel. Every runner has the label `hanok-ci`.
- **Private repositories only.** A pull request from a fork of a public repository could run its code on the VM. Public repositories have free hosted minutes anyway.
- **Persistent runners, not ephemeral.** An ephemeral runner registers again after every job, which needs a credential that can create registration tokens (a PAT or GitHub App with Administration write) stored on the VM, where a hostile job could steal it. A persistent runner is registered once with a one-hour token from the GitHub page and keeps only its own runner credential. Between jobs, a hook removes what Docker left behind and a weekly timer prunes images and build cache. If the VM ever looks dirty, it is recreated (`docs/runbooks/ci-runner.md`).
- **A project opts in with a repository variable**, `runs-on: ${{ vars.CI_RUNNER || 'ubuntu-latest' }}`, so it can fall back to hosted runners by unsetting it (`docs/conventions.md`).

**Consequences.**

- CI is slower than on GitHub's runners and shares CPU with production. On a busy weekend, a project unsets its variable.
- Service containers publish on the VM itself, so two jobs at once must not ask for the same host port (`docs/conventions.md`).
- GitHub announced a per-minute platform charge on self-hosted runners in private repositories for March 2026, then postponed it. Check the billing page again if it comes back. Artifact, cache and GHCR storage still count against the free plan either way.
- Runners update themselves. Debian updates through `unattended-upgrades`.
