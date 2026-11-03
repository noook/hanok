# ntfy

Push notifications at `https://ntfy.nook.sh`, for my projects and for apps of mine that other people use. Stack: `stacks/ntfy`.

## Model

- **No anonymous access.** Every reader and writer is a declared user (`NTFY_AUTH_USERS`) with explicit topic permissions (`NTFY_AUTH_ACCESS`).
- **People read, services write.** A person gets a user with a password, read-only on their topics, and logs in from the ntfy app. A service gets a user with write-only access to its topics and publishes with a token (`NTFY_AUTH_TOKENS`).
- **One topic per audience**, prefixed with the project or site, e.g. `<site>-admin` (me) and `<site>-ready` (the family).
- All of it lives in `secrets.enc.env`: the names are private, and changing a permission is a commit, not a click.

## First start

1. Hash a password per person, generate a token per publishing service:

   ```sh
   docker run --rm -it binwiederhier/ntfy:v2.36.0 user hash    # prompts, prints $2a$10$...
   docker run --rm binwiederhier/ntfy:v2.36.0 token generate    # prints tk_...
   ```

2. Write the values (formats in `.env.example`) and encrypt, from the repo root on the Mac:

   ```sh
   sops stacks/ntfy/secrets.enc.env
   ```

3. On docker-host, as root in `/opt/hanok`: `git pull && scripts/up.sh ntfy`. Expect `ntfy ... (healthy)`.

## Checks

```sh
curl -s https://ntfy.nook.sh/v1/health                          # {"healthy":true}
curl -s -o /dev/null -w '%{http_code}\n' -d hi https://ntfy.nook.sh/test    # 403: anonymous publishing refused
curl -s -H "Authorization: Bearer tk_..." -d hi https://ntfy.nook.sh/<topic>  # JSON with an "id": published
```

On a phone: ntfy app, Settings > Manage users > add `https://ntfy.nook.sh` with that person's user, then subscribe to the topic on that server. On iPhone the notification arrives within seconds through the ntfy.sh relay; nothing else to set up.
