# The Tailscale policy file

## What it is

The tailnet's rulebook: one file, kept by Tailscale, that says which machine may open a connection to which other machine. Saving it applies it to every device within seconds.

Three words:

- **Tag**: an identity for a machine that is not a person, like `tag:grafana`. A tagged machine belongs to the tailnet, not to a user: no key expiry, and it keeps working if you change your login.
- **Tag owners** (`tagOwners`): who may give a tag to a machine. A tag must be listed here before an auth key can carry it. `[]` means "the tailnet's admins", that is, me.
- **Grants** (`grants`): the "allow" rules. Anything no grant allows is blocked. There is no "deny" rule: you restrict by allowing less.

The file can also hold **tests** (`tests`): "this machine must / must not reach that one". If a change breaks a test, Tailscale refuses it, so a typo cannot lock me out or open a hole.

## How it is built here

Never edited in the admin console: the next run of the workflow overwrites it.

```
tailscale/policy.hujson            hanok's part: my devices, the family's share, hanok's service tags
<project>/.hanok/tailnet.hujson    a project's part, in its own repository (ADR 0007)
        │
        ▼  tailscale/combine.py: checks each fragment, adds it, generates isolation tests
build/policy.hujson                never committed
        │
        ▼  .github/workflows/tailscale-policy.yml: tests on a pull request; applies on main, hourly, or by hand
the tailnet
```

The rules in hanok's part:

1. My devices (`autogroup:owner`, `autogroup:admin`) reach everything, and the internet through any exit node.
2. People are invited as members and belong to a household, `group:family` or `group:home` (members from the `TAILNET_GROUPS` secret, never in this repo). Both households reach the family's NAS (its own accounts decide who opens what) and the services tagged `tag:family`; the exit node is the family's; only mine reaches `tag:home` (ADR 0008).
3. Tagged machines get nothing unless a grant names them: a service sidecar (`tag:grafana`, `tag:obsidian`) answers, it never opens connections.

## A service of hanok

Its tag goes in `tagOwners` of `tailscale/policy.hujson`, with a test that one of my devices reaches it (`macnook-pro` in `tests`). Nothing else: rule 1 already lets my devices in.

## A project's own rules

A project that needs machines of its own on the tailnet (a worker, proxies on other networks) keeps its rules next to its code, in `.hanok/tailnet.hujson`:

```jsonc
{
  "tagOwners": { "tag:myapp-worker": [], "tag:myapp-proxy": [] },
  "grants": [
    { "src": ["tag:myapp-worker"], "dst": ["tag:myapp-proxy"], "ip": ["tcp:8888"] },
  ],
  "tests": [
    { "src": "tag:myapp-worker", "accept": ["tag:myapp-proxy:8888"], "deny": ["tag:myapp-proxy:22"] },
  ],
}
```

`combine.py` refuses anything else:

- only `tagOwners`, `grants` and `tests`;
- only the project's own tags, `tag:<repository>-*`, owned by `[]`, and declared by nobody else;
- every `src`, `dst` and `accept` inside those tags: a project cannot give itself access to my devices, to hanok's services or to another project, nor open itself to anyone;
- and for each of its tags, a generated test that it reaches none of the other tags.

The project joins by installing the `hanok-tailnet` GitHub App on its repository (Settings > Applications > hanok-tailnet > Configure, add the repository). Its rules apply at the next hourly run, or at once with **Run workflow** on the Actions tab. If anything a project brings is refused, nothing is applied: the tailnet keeps the last good policy. Nor is anything applied when a tag the tailnet has today would disappear (a project whose App installation or file went missing); removing a project on purpose is a manual run with **allow tag removal** ticked.

## Auth keys

**Settings > Keys > Generate auth key**: Reusable off, Ephemeral off, Pre-approved on, Tags: the one tag the machine needs. The key is only used for the first login; the machine stays in the tailnet after the key expires.

## Checking

- **Machines** page: the new machine shows its tag instead of my email.
- **Access controls > Preview rules**: pick a machine and see what it can reach.
- From the phone, with Tailscale on: open `https://grafana.<tailnet>.ts.net`.

## Households: the `TAILNET_GROUPS` secret

Who is in `group:family` and `group:home` is not in this repo (it would publish emails). It lives in **one GitHub repository secret of hanok, `TAILNET_GROUPS`**, read by `tailscale/combine.py` on every run of the policy workflow and never printed (the log says `combine: N groups, M members`).

| | |
|---|---|
| Where | hanok > Settings > Secrets and variables > Actions > `TAILNET_GROUPS` |
| Format | one JSON object, every group the policy uses, even empty: `{"group:family": ["dad@example.com"], "group:home": ["partner@example.com"]}` |
| The readable copy | Bitwarden, secure note **"hanok TAILNET_GROUPS"**: GitHub never shows a secret again, so this note is the source of truth |
| Change it | edit the note, then from the Mac: `pbpaste \| gh secret set TAILNET_GROUPS --repo noook/hanok` (with the JSON copied), then Actions > Tailscale policy > Run workflow |
| Check | the run is green and says the expected count; Access controls > Preview rules > pick the person: their household's machines are listed |
| If it is missing or wrong | the run stops before applying (`TAILNET_GROUPS is not set`, `... has [...], the policy uses [...]`, `not valid JSON`); the tailnet keeps the last good policy |

The emails are the identities people sign in to Tailscale with (Apple, Google...). Me: not listed, the owner reaches everything. A new household is a new group in `tailscale/policy.hujson` plus its key in the secret, in the same change. Adding a person, step by step: `docs/runbooks/family-members.md`.

