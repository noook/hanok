# My Obsidian vault, synced on the tailnet, end-to-end encrypted, shared with agents

My notes live in an Obsidian vault on my Mac and phone, synced by the Self-hosted LiveSync plugin through a CouchDB on docker-host. I want my agents to read and write it too: document the homelab as I build it, pick up ideas I drop in an inbox, and take quick notes for me from a machine that does not run Obsidian (my work laptop reaches the homelab's agent over SSH).

The first setup, from before this repo, reached CouchDB at `https://docker-host.<tailnet>.ts.net:6984` with a Tailscale certificate copied in by hand (it expires on 19 Nov 2026), published that port on the LAN, used the CouchDB admin on every device, and stored the vault unencrypted.

**Decision.**

- **CouchDB behind a Tailscale sidecar**, `https://obsidian.<tailnet>.ts.net`, like Grafana (ADR 0002). No host port; the certificate renews itself.
- **End-to-end encryption and path obfuscation on.** CouchDB only stores encrypted chunks and hashed document IDs, so the volume and its backups reveal nothing. The passphrase never reaches the server or this repo.
- **Three CouchDB accounts.** The server admin, for maintenance and the rare rebuild. `devices`, admin of the vault database only, for my Obsidian apps. `agents`, a member, for the agents' client. Cutting the agents off is changing one password.
- **Settings as code.** A one-shot `init` service applies LiveSync's server settings, the database, the users and the database's security on every start, so the config volume holds nothing the repo does not.
- **Agents go through LiveSync's official headless client**, `livesync-cli daemon`, on the `hermes` guest: it keeps a folder of plain markdown in sync both ways, with the plugin's own code for chunking, encryption and conflicts. Agents edit files there like a person would; a git history of that folder makes every agent edit reviewable and revertible. Set up after the cutover.

**Rejected.**

- **MCP servers that write LiveSync's CouchDB format themselves.** Several exist; each reimplements chunking and encryption, and one bug there corrupts the vault on every device.
- **No encryption, since it is tailnet only.** Cheap to turn on now (one rebuild of a few megabytes), costly later; and backups of the volume would be plain text.
- **A second vault for private notes.** Nothing in it needs hiding from the agents today; a `.livesync/ignore` on the agents' client can still leave a folder out later.
- **Through Cloudflare** (public, behind a login): the vault has no reason to be on the internet.

**Consequences.**

- "Overwrite Server Data" (a rebuild) deletes and recreates the database, which needs the server admin, and resets the database's security. After a rebuild, `scripts/up.sh obsidian-livesync --profile tailnet` puts the two users back. The runbook says when to use which account.
- A new device needs the passphrase, through a Setup URI from a working device.
- One more tagged device (`obsidian`) against the Personal plan's 50.
