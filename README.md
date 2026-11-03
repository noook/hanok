# hanok

The infrastructure of my homelab, as code. *Hanok* (한옥) is the traditional Korean house: this repo is the house my services live in.

One Proxmox host runs a Debian LXC, `docker-host`, which runs every service as a Docker Compose stack. A second guest, the VM `hanok-ci`, runs GitHub Actions jobs for my private repositories, cut off from the rest of the network. This repo holds the shared pieces those services stand on: reverse proxy, tunnel, monitoring, and the small third-party apps I self-host. My own applications (for example [Plouf](https://plouf.nook.sh)) keep their code, compose file and deploy scripts in their own repositories. They plug into the shared pieces through Docker networks and labels.

## How it fits together

```
Internet ──► Cloudflare ──► cloudflared ──► Traefik ──► public apps (labels: traefik.*)
My devices ──► Tailscale ──► one sidecar per private service (https://<service>.<tailnet>.ts.net)
Every container ──► Alloy ──► Loki / Prometheus ──► Grafana   (labels: observability.*)
Apps speaking OpenTelemetry ──► http://lgtm:4318 ─────────────┘
GitHub Actions jobs ◄── outbound only ── VM hanok-ci (internet yes, LAN and tailnet no)
```

- **Public** (anyone on the internet): through the Cloudflare tunnel and Traefik, routed by `traefik.*` labels on the shared `proxy` network. No port is opened on the router.
- **Private** (only my devices on the tailnet): a Tailscale sidecar per service gives it its own name and a real certificate, e.g. `https://grafana.<tailnet>.ts.net`. Nothing is exposed to the internet.
- **Monitored**: every container's logs are collected; containers that serve metrics say so with labels. See [docs/conventions.md](docs/conventions.md).

## Layout

```
stacks/<stack>/compose.yaml      one Compose project per stack (name: <stack>)
stacks/<stack>/secrets.enc.env   its secrets, encrypted with SOPS + age (safe to commit)
scripts/up.sh <stack>            decrypt the secrets and start or update a stack
scripts/                         one-off migrations, with their runbook in docs/runbooks/
hosts/hanok-ci/                  the CI runner VM: firewall, setup, register a repository
hosts/family-dxp/                a family member's UGREEN NAS: its Tailscale (gateway and web UI)
tailscale/policy.hujson          hanok's part of the tailnet policy; tailscale/combine.py adds the projects' parts (ADR 0007)
docs/adr/                        why things are the way they are
docs/conventions.md              labels, networks, naming, secrets
docs/network.md                  sites, address ranges, names, every device on the tailnet
docs/tailscale-policy.md         who may reach what on the tailnet, explained
renovate.json                    image updates as pull requests
```

| Stack | What | Reached |
|---|---|---|
| `observability` | Grafana, Prometheus, Loki, Tempo, an OpenTelemetry collector (one container for now), Alloy | tailnet: `grafana.<tailnet>.ts.net` |
| `ntfy` | push notifications for my projects and my family's apps | public: `ntfy.nook.sh`, no anonymous access |
| `obsidian-livesync` | CouchDB for my Obsidian vault (Self-hosted LiveSync, end-to-end encrypted), shared with my agents ([ADR 0006](docs/adr/0006-obsidian-vault-on-the-tailnet-encrypted-shared-with-agents.md), [runbook](docs/runbooks/obsidian-livesync.md)) | tailnet: `obsidian.<tailnet>.ts.net` |
| `traefik`, `cloudflared`, `umami` | still in `/opt/stacks` on docker-host, to be imported ([docs/runbooks/import-a-stack.md](docs/runbooks/import-a-stack.md)) | |

## Running a stack

On docker-host, as root, in the checkout (`/opt/hanok`):

```bash
git pull
scripts/up.sh observability --profile tailnet
```

`up.sh` decrypts `secrets.enc.env` into a root-only file under `/run` that is deleted afterwards, creates the shared networks if they are missing, pulls the images and starts the stack.

## Using this repo

It is my homelab, published for reference: the decisions (`docs/adr/`) and conventions are the useful part. It is not a product to install. Names, addresses and secrets are mine, and the scripts assume my hosts. MIT licensed, so take whatever helps.
