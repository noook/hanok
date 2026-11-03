# Pocket ID (id.nook.sh)

The one login of the homelab: passkeys (Face ID, fingerprint, a password manager), no password. Apps sign users in through OpenID Connect. Stack: `stacks/pocket-id`.

## Why it is public

Phones, Cloudflare Access and the apps' own servers must reach it without Tailscale. It is safe to expose because there is no password to guess, signups are off, and only the admin creates users.

## Deploy (docker-host, as root, from /opt/hanok)

1. On the Mac: `openssl rand -base64 32`, then `sops stacks/pocket-id/secrets.enc.env` and add `POCKET_ID_ENCRYPTION_KEY=<that value>`. Back the value up in the password manager: losing it loses the signing keys.
2. `scripts/up.sh pocket-id`.
3. Cloudflare: nothing to add. `*.nook.sh` already goes to Traefik. Check `https://id.nook.sh` loads.
4. No IP restriction on the admin pages, on purpose: I want to reach them from anywhere, and the admin passkey is the gate (no password, signups off). If Security Events ever shows bots on `/settings/admin`, add a Managed Challenge custom rule on that path (free plan).
5. Create the admin account right away (next section): `/setup` is open to anyone until the first account exists.

## First admin

Open `https://id.nook.sh/setup`, create the admin account, add a passkey. Add a second passkey on another device (laptop or password manager) straight away.

## People: how you know it is her

Pocket ID only knows who holds an enrolled device. The link to a person is the handover:

1. Administration > Users > Add user (username, her email, her name).
2. Open her user and create a **Login Code** with a short lifetime. Do it with her, in the room.
3. She opens the link on her own phone, signs in once, taps **Add Passkey**, confirms with Face ID. Then a second passkey (iCloud Keychain syncs across her Apple devices; add the laptop or a password manager too).
4. Never send the code by chat.

Lost device: another passkey still works; otherwise create a new Login Code. If the admin's passkeys are all lost: `docker compose -p pocket-id exec pocket-id /app/pocket-id one-time-access-token <username>` prints a link valid for 1 hour.

## Group and clients

1. User groups > add `foyer`, with both people.
2. For every app (OIDC client), open its **Access** tab and tick only `foyer`. A client made in the interface starts with no group, so nobody can sign in until this is done.
3. Donetick: see `richvry/` in the household stack runbook (callbacks `https://richvry-taches.nook.sh/auth/oauth2` and `donetick://auth/oauth2`).

## Open points (not verified)

- Whether a Login Code is single-use.
- The health check command (`/app/pocket-id healthcheck`) comes from Pocket ID's docs; if `up.sh` waits forever, check `docker logs`.
