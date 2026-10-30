# Obsidian LiveSync: cutover, devices, rebuilds

The stack is `stacks/obsidian-livesync` (ADR 0006). This runbook moves the vault from the old CouchDB (`/opt/stacks/obsidian-livesync`, `https://docker-host.<tailnet>.ts.net:6984`, unencrypted) to the new one (`https://obsidian.<tailnet>.ts.net`, end-to-end encrypted). The Mac's vault is the source of truth: everything else is rebuilt from it.

Do it before **19 Nov 2026**: the old setup's certificate expires that day and sync stops.

## Before

1. Tailscale: the pull request adding `tag:obsidian` to `tailscale/policy.hujson` is merged (the Action applies it). Then **Settings > Keys > Generate auth key**: Reusable off, Ephemeral off, Pre-approved on, tag `tag:obsidian`.
2. Secrets, on the Mac, from the repo root:
   ```bash
   { echo COUCHDB_ADMIN_USER=admin; echo "COUCHDB_ADMIN_PASSWORD=$(openssl rand -hex 24)"
     echo DEVICES_USER=devices;     echo "DEVICES_PASSWORD=$(openssl rand -hex 24)"
     echo AGENTS_USER=agents;       echo "AGENTS_PASSWORD=$(openssl rand -hex 24)"
     echo VAULT_DATABASE=vault;     echo "TS_AUTHKEY_OBSIDIAN=<the key>"; } > /tmp/obsidian-livesync.env
   sops --encrypt --input-type dotenv --output-type dotenv /tmp/obsidian-livesync.env > stacks/obsidian-livesync/secrets.enc.env
   shred -u /tmp/obsidian-livesync.env
   ```
   Put the admin and devices passwords in the password manager too (`sops -d` shows them again).
3. Choose the vault's encryption passphrase and store it in the password manager. It goes nowhere else for now.
4. Sync every device one last time on the old server (open Obsidian on the phone and let it finish), then check the Mac has everything.
5. Back up the Mac's vault: `ditto -c -k --keepParent ~/obsidian-vault/Neil ~/Neil-$(date +%F).zip`.

## Cutover

1. On docker-host: `cd /opt/hanok && git pull && scripts/up.sh obsidian-livesync --profile tailnet`. The project keeps its name, so Compose replaces the old `couchdb-livesync` container (port 6984 closes). The old volumes `obsidian-livesync_couchdb_data` and `_couchdb_config` are not touched: they are the backup.
2. Check from the Mac:
   ```bash
   curl -s -o /dev/null -w '%{http_code}\n' https://obsidian.<tailnet>.ts.net/          # 401
   curl -s -u devices:<password> https://obsidian.<tailnet>.ts.net/vault | head -c 80   # {"db_name":"vault",...
   ```
3. On the Mac, point LiveSync at the new server, as the **first device** ([upstream: Configure CouchDB manually on the first device](https://github.com/vrtmrz/obsidian-livesync/blob/main/docs/quick_setup.md#configure-couchdb-manually-on-the-first-device)):
   - URL `https://obsidian.<tailnet>.ts.net`, database `vault`, user **`admin`** (overwriting the server deletes and recreates the database, which only the server admin may do).
   - End-to-End Encryption on, with the passphrase. Obfuscate Properties on.
   - Overwrite the server with this device's files (`I Understand, Overwrite Server`, or **Overwrite Server Data with This Device's Files** if you change the remote in the existing settings instead of onboarding).
4. On docker-host, again `scripts/up.sh obsidian-livesync --profile tailnet`: the overwrite reset the database's security, and `init` puts `devices` and `agents` back.
5. On the Mac, change the remote's user to **`devices`** and its password. Create a test note and let it upload.
6. Check the server only holds ciphertext: `docker exec obsidian-livesync-couchdb-1 sh -c 'curl -s -u "$COUCHDB_USER:$COUCHDB_PASSWORD" "http://127.0.0.1:5984/vault/_all_docs?limit=5"'`. IDs look like `f:3a9c…` and `h:+…`, never a note's path.
7. The phone: on the Mac, command palette > `Self-hosted LiveSync: Copy settings as a new Setup URI`, with a new Setup URI passphrase. On the phone, reset LiveSync and add it as **another device** with that URI ([upstream: Add another device](https://github.com/vrtmrz/obsidian-livesync/blob/main/docs/quick_setup.md#add-another-device)). Send the URI and its passphrase through different channels.
8. Edit a note on the phone, see it on the Mac, and the other way round.

## Device settings

| | Mac | Phone |
|---|---|---|
| Sync mode | LiveSync (continuous) | Periodic, plus on start and on save (battery) |
| Customisation Sync (plugins, themes, settings) | on, once ordinary sync works | on |
| Hidden File Sync | off: never both on the same files | off |

The agents' headless client keeps `usePluginSync: false`: plugins and settings are none of its business.

## Later

- After a week without surprises: `docker volume rm obsidian-livesync_couchdb_data obsidian-livesync_couchdb_config` (the old, unencrypted copy), and remove `/opt/stacks/obsidian-livesync`.
- Never run `docker compose down -v` on this stack: `couchdb-data` is the vault.

## Rebuilds and passwords

- **Overwrite Server Data** from a device (a damaged remote, a settings change for the whole vault): switch that device to `admin`, overwrite, `scripts/up.sh obsidian-livesync --profile tailnet`, back to `devices`. The other devices then reset and fetch.
- **After a rebuild, other clients see a locked remote.** That is LiveSync protecting the data: accept it on each device. The headless client: `livesync-cli <db> unlock-remote` only if it was in sync before, else start it again from an empty folder.
- **Change a password:** `sops stacks/obsidian-livesync/secrets.enc.env`, then `scripts/up.sh obsidian-livesync --profile tailnet` (`init` sets it on every start), then the client's settings. Cutting the agents off is changing `AGENTS_PASSWORD` alone.
