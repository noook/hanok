# Tailnet migration

From "everything logged in as me, every site on `192.168.1.0/24`" to the layout in [docs/network.md](../network.md) (ADR 0005). One step at a time; each is checked before the next, and each has a way back.

## 0. The DXP on the tailnet: done

`hosts/family-dxp/tailscale` deployed from UGOS: `family-gateway` (exit node, 4via6 site 77) and `family-dxp` (UGOS on 443, SMB).

## 0b. Site names: in the console

The repo writes `home` and `family`; the machines carry the real site names (docs/network.md, "Names"). Machines > Edit machine name: the DXP's two devices, then the Synology (step 4). Restart the DXP's `dxp` container so it serves its new name, tell the family their NAS's new address, and check it opens from their side.

## 1. The policy in the repo, no change in behaviour

1. In the admin console, **Settings > Trust credentials**: an OAuth client with the `policy_file` scope (write).
2. In the repository's **Settings > Secrets and variables > Actions**: secrets `TS_OAUTH_ID` (the client ID) and `TS_OAUTH_SECRET` (its secret). The workflow runs on GitHub's hosted runners: this repository is public, and a public repository never uses `hanok-ci` (ADR 0004).
3. Push a branch with `tailscale/policy.hujson` and open a pull request: the check runs the tests against the tailnet. Merge: the Action applies the file. The console's policy then matches the repo.
4. In the console's Access controls, turn on the warning that the policy is managed externally, if offered.

**Check:** Access controls shows the file from the repo; every device still reaches what it did. **Back:** paste the previous policy in the console.

## 2. Additive policy changes

Declare `tag:server`, `tag:agent`, `tag:hypervisor`. Auto-approve exit nodes for `tag:exit-node` and routes for `tag:subnet-router` (`192.168.93.0/24`, `192.168.77.0/24`, `fd7a:115c:a1e0:b1a:0:4d:c0a8:100/120`). The family rule targets `tag:nas` plus `tcp:443`, and gains `autogroup:shared` to `autogroup:internet` (their exit node). Tests for each.

In the console, share `family-dxp` and `family-gateway` with my family, the second with **Allow use as an exit node**.

**Check:** from the family's side, on mobile data: the internet through their exit node, and their NAS through `https://family-dxp.<tailnet>.ts.net`. **Back:** revert the pull request.

## 3. My Mac

`tailscale set --advertise-routes=` (it advertised `10/8`, `172.16/12`, `192.168/16`, `127.0.0.1`, never approved).

## 4. The Synology

1. SSH with my key: DSM ignores `authorized_keys` when the home folder is too open. `chmod 755 ~ && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys`, with User home enabled in DSM.
2. `sudo tailscale set --accept-dns=false --advertise-routes=` (no Tailscale DNS; its plain `192.168.1.0/24` collided with `ts-gateway`'s and was never used, and `family-gateway` routes the family site now).
3. From the Mac: use it as exit node and check that names resolve (`curl https://example.com`), then `tailscale set --exit-node=`.
4. `sudo tailscale serve --bg --https=443 https+insecure://localhost:5001`, if the Synology's Tailscale runs in userspace mode (it does on DSM 7); keep 8443 until the family's bookmarks move.

**Back:** `sudo tailscale set --accept-dns=true`.

## 5. Tag and rename the infrastructure, one device at a time

| Device | New name | Tags |
|---|---|---|
| `ts-gateway` | `home-gateway` | `tag:exit-node`, `tag:subnet-router` |
| the Synology | `family-dsm` | `tag:nas`, `tag:exit-node`; check that the family's share survived |
| `docker-host` | | adds `tag:server`, keeps its projects' tags |
| `hermes` | | `tag:agent` |
| `tartiflette` | joins the tailnet | `tag:hypervisor` |
| the TV | `home-tv` | none, a personal device |

Tags and names are changed in the admin console (Machines > Edit ACL tags / Edit machine name). Each infrastructure device also runs `tailscale set --accept-dns=false`. **Back:** log the device in as me again.

## 6. Tighten the policy

Members reach everything; `tag:agent` reaches `tag:server:22` and `tag:grafana:443`; shared users reach `tag:nas` and the internet through their exit node; every other tag reaches nothing. Tests for each. The Proxmox firewall on `hermes` drops outbound traffic to the LAN except the router, as for `hanok-ci`. **Back:** revert the pull request.

## 7. Renumber home to `192.168.93.0/24` (an evening at home)

The Bbox's LAN and DHCP range; DHCP reservations; static addresses on `tartiflette`, its LXCs and `hanok-ci` (and its firewall file); `home-gateway` advertises `192.168.93.0/24`. **Back:** the Bbox back to `192.168.1.0/24`.

## 8. Renumber the family site to `192.168.77.0/24` (remotely, someone at home there)

1. Reserve the future addresses in the box (Synology `.10`, DXP `.11`); switch the Synology from a fixed address to DHCP.
2. Schedule a reboot of the Synology 10 minutes later; change the box's LAN to `192.168.77.0/24`.
3. Both NAS come back on their reserved addresses; `family-gateway` (DHCP) reconnects by itself.
4. `family-gateway` advertises `192.168.77.0/24` instead of the 4via6 route (`TS_ROUTES`).

**Back:** the box back to `192.168.1.0/24`; someone there power-cycles a NAS if it doesn't come back.

## 9. Close the other doors

After a few days without problems: QuickConnect off on the Synology, UGREENlink off on the DXP.

## 10. Finish the DXP

1. Done: `hosts/family-dxp/sysctl.d/99-tailscale.conf` is installed as `/etc/sysctl.d/99-tailscale.conf`, and the gateway no longer runs `privileged`. After a UGOS update, check `sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding` still says 1.
2. Deploy over SSH with `docker compose` from then on (`neil` needs `sudo` or the `docker` group).
