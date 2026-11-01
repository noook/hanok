# People are invited into the tailnet, by household, access by tag

My family used their own Tailscale accounts, and I shared them machines one by one (`autogroup:shared`). Each new person meant a share per machine, and each new service a share per person. Their apps now include services they use away from home every day (requesting a film, for one), more family members will join, and someone outside that household (my partner) should use the family's services and mine.

**Decision.**

- **People are invited into my tailnet** with the Member role, once each. The Personal plan allows 6 users.
- **Each person belongs to a household**, a group: `group:family` (the family site) or `group:home` (mine). A member in no group reaches nothing.
- **Services are tagged by household**: `tag:family`, `tag:home`, on 443. A project puts the tag next to its own on the services meant for a household (a sidecar advertises `tag:<project>-<service>,tag:family`), so the project chooses, hanok keeps the rule.
- **What each household reaches:**

  | | its NAS, Synology, exit node | `tag:family` services | `tag:home` services |
  |---|---|---|---|
  | `group:family` | yes | yes | no |
  | `group:home` | no | yes | yes |
  | me (`autogroup:owner`, `autogroup:admin`) | everything | | |

  Files and exit nodes stay with their household; the family's services are open to my household as guests.
- **No email in this public repo.** The policy names groups; their members come from the `TAILNET_GROUPS` secret (JSON), which `combine.py` adds at build time and never prints. It refuses a policy whose groups and secret don't match, and a `groups` section in the file.

**Rejected.**

- **Keep sharing**: the cost grows with people × machines, and Tailscale cannot share a group of machines.
- **Everyone invited gets the family's access (`autogroup:member`)**: no way to tell my partner from my father.
- **Groups in the policy file**: names my family in a public file.
- **Tag people's devices by household**: a tagged device loses its user, and its owner can no longer manage it.
- **Let a project's fragment grant to people**: ADR 0007 keeps fragments from opening themselves to anyone.

**Consequences.**

- Adding a person: invite them, add their email to `TAILNET_GROUPS`, run the workflow (runbook). Moving someone between households is editing the secret.
- My household's future members also get the family's services. A guest of one person only would need a group of its own.
- Their devices appear in my tailnet's console; someone with a tailnet of their own switches accounts in the Tailscale app.
- Every exit node tagged `tag:exit-node` is open to `group:family`. Today that is only the family's gateway; when `ts-gateway` is tagged, give exit nodes a site tag and narrow `via`.
- Every apply needs the secret: without it the workflow stops before applying, and the tailnet keeps the last good policy.
- The `autogroup:shared` grants stay until the migration is done, then go.
