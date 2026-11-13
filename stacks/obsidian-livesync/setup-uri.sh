#!/usr/bin/env bash
# Print a Setup URI for this vault, as text and as a QR code to scan with a phone (ADR 0006).
#
#   stacks/obsidian-livesync/setup-uri.sh [admin|devices]      as root on docker-host, from anywhere in the checkout
#
# Uses LiveSync's own generator (utils/setup/generate_setup_uri.ts): end-to-end encryption and path obfuscation
# on, CouchDB at https://obsidian.<tailnet>.ts.net, database and password from secrets.enc.env. Asks for the E2EE
# passphrase (twice) and, for an existing vault, its ID recovery code. Nothing is written to disk but a temporary
# env file, deleted at the end.
#
#   admin    the first device, which overwrites the server (a rebuild deletes and recreates the database)
#   devices  every other device (normally: "Copy settings as a new Setup URI" from a working device instead)
set -euo pipefail

user="${1:-devices}"
case "$user" in admin) key=COUCHDB_ADMIN_PASSWORD ;; devices) key=DEVICES_PASSWORD ;; *) echo "usage: $0 [admin|devices]" >&2; exit 64 ;; esac
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$dir/secrets.enc.env" ] || dir=/opt/hanok/stacks/obsidian-livesync
[ "$(id -u)" = 0 ] || { echo "run as root (sops needs docker-host's age key)" >&2; exit 1; }

secrets="$(sops --decrypt --input-type dotenv --output-type dotenv "$dir/secrets.enc.env")"
password="$(printf '%s\n' "$secrets" | sed -n "s/^$key=//p")"
database="$(printf '%s\n' "$secrets" | sed -n 's/^VAULT_DATABASE=//p')"
[ -n "$password" ] || { echo "$key not found in secrets.enc.env" >&2; exit 1; }
suffix="$(tailscale status --json | grep -m1 -oE '"MagicDNSSuffix": *"[^"]+"' | cut -d'"' -f4)"
[ -n "$suffix" ] || { echo "could not read the tailnet's name from tailscale status" >&2; exit 1; }

read -rsp "E2EE passphrase: " p1; echo
read -rsp "Again: " p2; echo
[ -n "$p1" ] && [ "$p1" = "$p2" ] || { echo "passphrases empty or different" >&2; exit 1; }
read -rp "ID recovery code (sls-id-v1:…), empty for a vault that has none yet: " idcode
read -rp "Setup URI passphrase, typed on the phone (empty: a random one): " uripass

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
umask 077
{
  echo "LIVESYNC_HOST=https://obsidian.$suffix"
  echo "LIVESYNC_DB=${database:-vault}"
  echo "LIVESYNC_USER=$user"
  echo "LIVESYNC_PASS=$password"
  echo "LIVESYNC_PASSPHRASE=$p1"
  [ -z "$idcode" ] || echo "id_recovery_code=$idcode"
  [ -z "$uripass" ] || echo "uri_passphrase=$uripass"
} > "$tmp/env"

docker run --rm --env-file "$tmp/env" denoland/deno:2.9.8 run --quiet --minimum-dependency-age=0 --allow-env \
  https://raw.githubusercontent.com/vrtmrz/obsidian-livesync/main/utils/setup/generate_setup_uri.ts > "$tmp/out" 2>/dev/null \
  || { echo "the generator failed" >&2; exit 1; }
grep -v '^obsidian://' "$tmp/out"
uri="$(grep -m1 '^obsidian://' "$tmp/out")"
echo
echo "Scan with the phone's camera (it opens Obsidian), or copy the URI below:"
docker run --rm -e URI="$uri" alpine:3.22 sh -c 'apk add -q --no-progress libqrencode-tools >/dev/null && qrencode -t ANSIUTF8 -m 2 "$URI"'
echo "$uri"
echo
echo "Store in Bitwarden: the ID recovery code (\"Obsidian · LiveSync ID recovery code\"). The Setup URI passphrase is"
echo "only for this URI: type it on the phone, don't store it."
