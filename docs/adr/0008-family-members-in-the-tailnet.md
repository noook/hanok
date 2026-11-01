# Family members are invited into the tailnet, access by tag

My family used their own Tailscale accounts, and I shared them machines one by one (`autogroup:shared`). Each new person meant a share per machine, and each new service a share per person. Their apps now include services they use away from home every day (requesting a film, for one), and more family members will join.

**Decision.**

- **Family members are invited into my tailnet** with the Member role, once each. The Personal plan allows 6 users.
- **Access is by tag, never by machine or person.** The owner and admins (`autogroup:owner`, `autogroup:admin`: me) reach everything, as before. Members (`autogroup:member`, the family) reach `tag:nas`, the Synology while it lasts, anything tagged `tag:family` on 443, and the internet through a tagged exit node (`via: tag:exit-node`). Nothing else: no LAN route, no server, no other project.
- **`tag:family` is a role:** "the family may open this". A project puts it next to its own tag on the services meant for them (a sidecar advertises `tag:<project>-<service>,tag:family`). hanok keeps the one rule, the project chooses which services it applies to, and no email or name enters this public repo: the policy names only autogroups and tags.

**Rejected.**

- **Keep sharing**: the cost grows with people × machines, and Tailscale cannot share a group of machines.
- **A group of family emails**: names my family in a public file.
- **Let a project's fragment grant to members**: ADR 0007 keeps fragments from opening themselves to anyone; a role tag owned by hanok keeps that rule.

**Consequences.**

- Their devices appear in my tailnet's console; someone with a tailnet of their own switches accounts in the Tailscale app.
- Every exit node tagged `tag:exit-node` is open to them. Today that is only the family's gateway; when `ts-gateway` is tagged, give exit nodes a site tag and narrow `via`.
- Tests about the family need one of their devices (`hosts` entry, its tailnet IP): added once the first one joins (runbook).
- The `autogroup:shared` grants stay until the migration is done, then go.
