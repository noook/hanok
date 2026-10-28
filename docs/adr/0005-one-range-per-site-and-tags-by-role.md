# One address range per site, tags by role, the policy in this repo

Every network I connect from was `192.168.1.0/24`: my home, my family's, friends' and work. A subnet route for one of them collided with the network I was on, and two routers advertising `192.168.1.0/24` from two homes looked to Tailscale like one network, so traffic for my family's LAN went to mine. The policy lived only in the admin console, my family's NAS and my home gateway were logged in as me (so they reached all my devices), and a Synology with Tailscale DNS on could not resolve names, which broke the internet for anyone using it as an exit node.

**Decision.**

- **One `/24` per site, numbered after its département**: `192.168.93.0/24` at home (`home`), `192.168.77.0/24` at my family's (`family`). Never `192.168.0.x` or `192.168.1.x`, the ISP defaults. I renumber only my sites; friends and work keep theirs, so their networks never overlap mine.
- **4via6 for a site until it is renumbered**: its gateway advertises the old range under the site's number (77), which never collides with anything.
- **Tailscale on the device first; subnet routes only for what cannot run it** (a router's page, a NAS before it has Tailscale).
- **Tags by role, never machines or IPs in rules**: `tag:exit-node`, `tag:subnet-router`, `tag:nas`, `tag:server`, `tag:agent`, plus one tag per service (`tag:grafana`) and Plouf's two. Moving to a new machine is tagging it. Personal devices stay logged in as me; anything else is tagged.
- **Infrastructure does not use Tailscale DNS** (`--accept-dns=false`).
- **My family keeps its own tailnet**; I share them their NAS and exit node, nothing else.
- **The policy file is `tailscale/policy.hujson`**, applied by Tailscale's GitOps Action on push to `main`, tested on pull requests. The Action authenticates with a Tailscale OAuth client limited to the `policy_file` scope, and runs on GitHub's hosted runners: this repository is public, and a public repository never runs on `hanok-ci` (ADR 0004). A project's own rules live in its repository and are added at apply time (ADR 0007).

**Rejected.**

- **4via6 everywhere, no renumbering**: works, but every address becomes `192-168-1-23-via-77`.
- **A second tailnet** for my family's site: names are unique per tailnet anyway, and it would split the policy and need sharing across it.
- **One Proxmox cluster across both homes**: corosync wants a few milliseconds of latency and a third vote; two standalone hosts, each a site, back each other up over the tailnet instead.
- **Terraform for the tailnet**: state and a provider for one file.

**Consequences.**

- Renumbering a site is an evening: router, DHCP reservations, static addresses in Proxmox (`docs/runbooks/tailnet-migration.md`).
- The admin console's policy editor is read-only in practice: an edit there is overwritten by the next push.
- The DXP runs two Tailscale devices (`family-gateway`, `family-dxp`): UGOS holds port 443 on every address of the NAS, so the device that serves its UI must run in userspace mode, and the one that routes in kernel mode.
