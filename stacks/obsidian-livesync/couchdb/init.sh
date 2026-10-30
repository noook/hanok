#!/bin/sh
# Configure CouchDB for Self-hosted LiveSync, create the vault database and its users. Runs on every start of the
# stack (the `init` service) and is idempotent: running it again changes nothing, or resets the users' passwords to
# the ones in the secrets.
#
# The settings are the ones LiveSync's own provisioning sets (utils/couchdb/provision.ts upstream). Two users, so
# the agents can be cut off without touching my devices:
#
#   DEVICES_USER  my Obsidian apps. Admin of the vault database only: it may write anything in it, design documents
#                 included, but cannot delete the database, create another, or change the server's settings.
#   AGENTS_USER   the headless LiveSync client the agents read and write through. Member: documents only.
#
# Rebuilding the remote from a device ("Overwrite Server Data") deletes and recreates the database, which takes the
# server admin: the runbook says when.
set -eu

url="${COUCHDB_URL:?}"
admin="${COUCHDB_ADMIN_USER:?}:${COUCHDB_ADMIN_PASSWORD:?}"
db="${VAULT_DATABASE:?}"

# Passwords go into JSON as is: keep them to letters and digits (openssl rand -hex 24).
for p in "$COUCHDB_ADMIN_PASSWORD" "${DEVICES_PASSWORD:?}" "${AGENTS_PASSWORD:?}"; do
  case "$p" in *[!A-Za-z0-9]*) echo "init: passwords must be letters and digits only (openssl rand -hex 24)" >&2; exit 1 ;; esac
done

# call <label> <method> <path> [body]: fails the script on any HTTP error, prints the body on failure.
call() {
  label="$1"; method="$2"; path="$3"; body="${4:-}"
  if [ -n "$body" ]; then
    code=$(curl -sS -o /tmp/out -w '%{http_code}' -u "$admin" -X "$method" -H 'Content-Type: application/json' -d "$body" "$url$path")
  else
    code=$(curl -sS -o /tmp/out -w '%{http_code}' -u "$admin" -X "$method" "$url$path")
  fi
  echo "$code" >/tmp/code
  case "$code" in
    2*) echo "init: $label" ;;
    *) return 1 ;;
  esac
}

until curl -fsS -u "$admin" "$url/_up" >/dev/null 2>&1; do sleep 2; done

# A single node: creates _users, _replicator, _global_changes. Answers 400 "already" once done.
if ! call "single node" POST /_cluster_setup \
  "{\"action\":\"enable_single_node\",\"username\":\"${COUCHDB_ADMIN_USER}\",\"password\":\"${COUCHDB_ADMIN_PASSWORD}\",\"bind_address\":\"0.0.0.0\",\"port\":5984,\"singlenode\":true}"; then
  grep -qiE 'already|finished' /tmp/out || { echo "init: cluster setup failed ($(cat /tmp/code)): $(cat /tmp/out)" >&2; exit 1; }
  echo "init: single node (already)"
fi

# key value: the server settings LiveSync needs.
while read -r key value; do
  [ -n "$key" ] || continue
  call "$key" PUT "/_node/_local/_config/$key" "$value" || { echo "init: $key failed ($(cat /tmp/code)): $(cat /tmp/out)" >&2; exit 1; }
done <<'EOF'
chttpd/require_valid_user "true"
chttpd_auth/require_valid_user "true"
httpd/WWW-Authenticate "Basic realm=\"couchdb\""
httpd/enable_cors "true"
chttpd/enable_cors "true"
chttpd/max_http_request_size "4294967296"
couchdb/max_document_size "50000000"
cors/credentials "true"
cors/origins "app://obsidian.md,capacitor://localhost,http://localhost"
cors/methods "GET, PUT, POST, HEAD, DELETE"
cors/headers "accept, authorization, content-type, origin, referer"
EOF

if ! call "database $db" PUT "/$db"; then
  [ "$(cat /tmp/code)" = 412 ] || { echo "init: database $db failed ($(cat /tmp/code)): $(cat /tmp/out)" >&2; exit 1; }
  echo "init: database $db (already)"
fi

# user <name> <password>: create, or update the password of an existing user (needs its current _rev).
user() {
  doc="/_users/org.couchdb.user:$1"
  rev=""
  if call "read user $1" GET "$doc"; then
    rev=$(sed -n 's/.*"_rev":"\([^"]*\)".*/\1/p' /tmp/out)
  elif [ "$(cat /tmp/code)" != 404 ]; then
    echo "init: reading user $1 failed ($(cat /tmp/code)): $(cat /tmp/out)" >&2; exit 1
  fi
  body="{\"name\":\"$1\",\"password\":\"$2\",\"roles\":[],\"type\":\"user\"${rev:+,\"_rev\":\"$rev\"}}"
  call "user $1" PUT "$doc" "$body" || { echo "init: user $1 failed ($(cat /tmp/code)): $(cat /tmp/out)" >&2; exit 1; }
}
user "${DEVICES_USER:?}" "$DEVICES_PASSWORD"
user "${AGENTS_USER:?}" "$AGENTS_PASSWORD"

call "security of $db" PUT "/$db/_security" \
  "{\"admins\":{\"names\":[\"$DEVICES_USER\"],\"roles\":[]},\"members\":{\"names\":[\"$DEVICES_USER\",\"$AGENTS_USER\"],\"roles\":[]}}" \
  || { echo "init: security of $db failed ($(cat /tmp/code)): $(cat /tmp/out)" >&2; exit 1; }

echo "init: done"
