# People in the tailnet

Inviting people into the tailnet by household (ADR 0008), and moving the family off the old shares. Steps in the Tailscale admin console, the Tailscale app, and one GitHub secret.

## The secret

`TAILNET_GROUPS` (repository secret of hanok) lists who is in which household, one JSON object:

```json
{"group:family": ["dad@example.com"], "group:home": ["partner@example.com"]}
```

Every group the policy uses must be there, even empty (`[]`). Set or update it from the Mac:

```sh
gh secret set TAILNET_GROUPS --repo noook/hanok < groups.json   # then delete groups.json
```

Then Actions > tailscale-policy > Run workflow (or wait for the hourly run). The log only says `N groups, M members`.

Before merging the change that introduced groups: set the secret first, or the pull request's test and every apply stop at `TAILNET_GROUPS is not set` (nothing breaks; the tailnet keeps its policy).

## 1. Tag the services

Admin console > Machines > the machine > ⋯ > Edit ACL tags > add the household tag, keeping its own tag. family-media: `tag:family` on `<site>-jellyfin` and `<site>-seerr` (not `<site>-admin`). A project's compose file advertises the same pair, so a re-registered sidecar gets it back.

## 2. Add a person

1. Add their email to the right household in `TAILNET_GROUPS` (above) and run the workflow.
2. Settings > Users > Invite users > that email, role **Member**.
3. On their phone: install Tailscale, open the invite link, sign in with that identity. Someone who already uses Tailscale with their own account adds this one and switches (the app keeps both).
4. iPhone: Tailscale app > Settings > VPN On Demand on. One VPN at a time on iOS: another VPN app turns Tailscale off.
5. Check on their phone, Tailscale on: `https://<site>-seerr.<tailnet>.ts.net` opens. Never loads: the tag (step 1), their group, or the last workflow run. Certificate warning: they typed the short name.

Group tests (`group:family`, `group:home` in `tests`) run on every pull request against the live tailnet.

## 3. Remove the old shares

Once the family is invited: Machines > `family-dsm`, `family-dxp`, `family-gateway` > ⋯ > Share > remove each person. Then a pull request deleting group 4 (`autogroup:shared`) in `tailscale/policy.hujson`, and the `autogroup:shared` sentence in `docs/tailscale-policy.md`.

## Exit nodes

`group:family` may use a node tagged `tag:exit-node`: in the app, Exit node > `family-gateway`. Today it is the only tagged one.
