# Import a stack from /opt/stacks

The stacks that predate this repo (`traefik`, `cloudflared`, `umami`; `obsidian-livesync` was rebuilt instead, see docs/runbooks/obsidian-livesync.md) still live in `/opt/stacks/<name>/` on docker-host, with their compose file and a plain `.env`. Importing one makes it reviewable and rebuildable without changing how it runs.

On your Mac, in the repo, for a stack `<name>`:

1. Copy its compose file: `scp root@docker-host:/opt/stacks/<name>/compose.y*ml stacks/<name>/compose.yaml`.
2. Add `name: <name>` at the top if it is missing. The project name must stay the same as today's (the old directory name), or Compose creates new, empty volumes. Check with `docker compose ls` on docker-host.
3. Pin every image to the exact version running now: `docker inspect <container> --format '{{.Config.Image}}'`, then the tag or digest.
4. Secrets: list the keys of its `.env` in `stacks/<name>/.env.example` (no values), then `scp root@docker-host:/opt/stacks/<name>/.env /tmp/<name>.env && sops --encrypt --input-type dotenv --output-type dotenv /tmp/<name>.env > stacks/<name>/secrets.enc.env && shred -u /tmp/<name>.env` (run from the repo root, so SOPS finds `.sops.yaml`).
5. Bind mounts with relative paths (`./data`) point into the old directory: make them absolute (`/opt/stacks/<name>/data`) for now, or move the data to a named volume later.
6. Commit, push. On docker-host: `cd /opt/hanok && git pull && scripts/up.sh <name>`. Compose sees the same project and the same volumes, recreates the containers from the new file, and the old directory keeps only its data.
7. Check the service works, then remove the old compose file and `.env` from `/opt/stacks/<name>/`.

Do `cloudflared` and `traefik` last and one at a time: everything public goes through them.
