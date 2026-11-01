# The network

How my places, machines and services are named, numbered and reached over Tailscale. The rules themselves are in `tailscale/policy.hujson` (explained in [tailscale-policy.md](tailscale-policy.md)); why it is shaped this way is ADR 0005.

## Names

Four kinds of names, never mixed:

| Kind | What it names | Examples | Named |
|---|---|---|---|
| **Site** | a physical place with its own network | `home` (mine), `family` (a family member's) | a placeholder here, a short word in use (below) |
| **Machine** | a physical box | `tartiflette` (the Proxmox host), the Synology, the UGREEN DXP, my Mac | a host gets a name of my choosing; personal devices keep theirs |
| **Guest** | a container or VM on Proxmox | `docker-host`, `hermes`, `hanok-ci` | what it does |
| **Service** | an app people use | `grafana`, the arr suite | the app |

A site's infrastructure on the tailnet, its gateway and its NAS, is named `<site>-<role>`, so the name says which home it belongs to: `home-gateway`, `family-gateway`, `family-dxp`. `hanok` is the homelab and this repo, not a site: it may one day span both.

**Site names in this repo are placeholders.** `home` and `family` stand for the real names, which I keep out of the repo and may change at any time. Nothing depends on them:

- The policy names tags and addresses, never machine names (its `hosts` are aliases, local to the file).
- A device's real name is its machine name in the Tailscale console (Machines > Edit machine name). A compose file that starts a site device takes it from `SITE` (`hosts/family-dxp/tailscale/compose.yaml`), only read at the first login.
- Served devices build their address from `${TS_CERT_DOMAIN}`: after a rename, restart the container so it serves the new name, and update bookmarks.
- Runbooks say `home-…` and `family-…`: read them as the real site name.

## Sites

| Site | Router | LAN now | LAN target | Gateway on the tailnet |
|---|---|---|---|---|
| `home` | Bouygues Bbox Miami | `192.168.1.0/24` | `192.168.93.0/24` | `ts-gateway`, to be renamed `home-gateway` |
| `family` | ISP box | `192.168.77.0/24` | done | `family-gateway` |

- **One range per site, numbered after its département** (93, 77). French ISP boxes default to `192.168.1.x` and `192.168.0.x`, so those are never used: wherever I am, my sites never collide with the network I'm on. Inside a site: `.1`–`.49` fixed infrastructure, `.50`–`.199` DHCP, `.254` the router.
- **Other people's networks are not mine to number.** A machine of mine on a friend's network joins as a single tagged device and advertises nothing.
- **4via6** is the stopgap for a site that still overlaps: the gateway advertises its `192.168.1.0/24` under a site number, and a device there without Tailscale is reached by name, `http://192-168-1-23-via-77`, or by its IPv6 address (`tailscale debug via 77 192.168.1.23/32`). The family site used it (site 77) until it was renumbered; none does now.

## Devices

Infrastructure is tagged: it belongs to the tailnet, not to me, never expires, and reaches only what a grant gives its tag. My personal devices (Mac, phone, iPad, TV, PC) are logged in as me.

| Device | Site | Runs on | Tags | Role |
|---|---|---|---|---|
| `ts-gateway` | home | an LXC on `tartiflette` | untagged (to be `tag:exit-node`, `tag:subnet-router`) | exit node from home, subnet router for the home LAN |
| `docker-host` | home | an LXC on `tartiflette` | the tags its projects need (ADR 0007) | every Compose stack |
| `grafana` | home | a container on `docker-host` | `tag:grafana` | Grafana's sidecar (ADR 0002) |
| `obsidian` | home | a container on `docker-host` | `tag:obsidian` | the Obsidian vault's CouchDB sidecar (ADR 0006) |
| `hermes` | home | an LXC on `tartiflette` | untagged (to be `tag:agent`) | the Hermes agent |
| `family-dsm` | family | the Synology | untagged (to be `tag:nas`, `tag:exit-node`) | my family's NAS and exit node, shared with them; replaced by the DXP over time |
| `family-gateway` | family | a container on the DXP, kernel networking | `tag:exit-node`, `tag:subnet-router` | exit node, subnet router for the family site's LAN, `192.168.77.0/24` (`hosts/family-dxp/tailscale`) |
| `family-dxp` | family | a container on the DXP, userspace | `tag:nas` | the DXP's web UI on `https://family-dxp.<tailnet>.ts.net`, and SMB |

A project's own devices are listed in its repository, next to its rules (ADR 0007).

The DXP needs two devices because UGOS's own web server holds port 443 on every address of the NAS: a kernel-mode device could not serve 443, a userspace one can.

## Rules of thumb

- **Change a device's settings with `tailscale set`, never `tailscale up`.** `up` resets every flag it is not given, for example turning Tailscale DNS back on.
- **Infrastructure runs with `--accept-dns=false`.** It looks names up through its site's router; a NAS or gateway that sends its lookups to Tailscale's resolver can break the exit node it is (the Synology did).
- **Personal devices accept routes** once every advertised range is unique (both sites renumbered); until then, only for a debugging session.
- **Reach a tailnet device by its short name** (`docker-host`), or `https://<name>.<tailnet>.ts.net` for a served one. Home names like `docker-host.lan` only work at home.
- **Exit nodes**: `ts-gateway` is my home IP when I'm away; the family gateway is my family's home IP, which they use abroad. A shared exit node needs "Allow use as an exit node" on its share.
- **People** are invited into the tailnet by household (ADR 0008): the family (`group:family`) reaches its NAS, its exit node and its services (`tag:family`); my household (`group:home`) reaches its services (`tag:home`) and the family's. Members live in a secret. Runbook: `docs/runbooks/family-members.md`.
