# Family members in the tailnet

Moving the family from shared machines to invited members (ADR 0008), then adding the next ones. Every step is in the Tailscale admin console or the Tailscale app; nothing to deploy.

## 0. Before

This change is merged and applied (Actions > tailscale-policy, last run green). The old `autogroup:shared` grants are still there, so nothing breaks for anyone while you go.

## 1. Tag the services meant for them

Admin console > Machines > the machine > ⋯ > Edit ACL tags > add `tag:family`, keeping its own tag. For family-media: `<site>-jellyfin` and `<site>-seerr` (not `<site>-admin`). A project's compose file advertises the same pair, so a re-registered sidecar gets it back.

Check: Access controls > Preview rules > pick that machine: "autogroup:member, tcp:443" is listed.

## 2. Invite a person

1. Settings > Users > Invite users > their email, role **Member**. They get an email.
2. On their phone: install Tailscale, open the invite link, sign in with the identity the invite was sent to. If they already use Tailscale with their own account, they add this one and switch (the app keeps both).
3. iPhone: Tailscale app > Settings > VPN On Demand on, so it stays connected. One VPN at a time on iOS: another VPN app turns Tailscale off.
4. Check on their phone, Tailscale on: open `https://<site>-seerr.<tailnet>.ts.net`. A page that never loads means step 1 or the policy run; a certificate warning means they typed the short name instead of the full one.

## 3. Add a test for the family (first person only)

In `tailscale/policy.hujson`: add their phone under `hosts` (`"family-phone": "100.x.y.z"`, from the Machines page), and a test:

```jsonc
{"src": "family-phone", "accept": ["tag:nas:443", "tag:family:443"], "deny": ["macnook-pro:22", "tag:grafana:443", "tag:obsidian:443"]},
```

Pull request; the workflow tests it against the live tailnet.

## 4. Remove the old shares

Once everyone is invited: Machines > `family-dsm`, `family-dxp`, `family-gateway` > ⋯ > Share > remove each person. Then a pull request deleting group 3 (`autogroup:shared`) in `tailscale/policy.hujson`, and the `autogroup:shared` sentence in `docs/tailscale-policy.md`.

## Using their exit node

Members may use a node tagged `tag:exit-node`: in the app, Exit node > `family-gateway`. Today it is the only tagged one.
