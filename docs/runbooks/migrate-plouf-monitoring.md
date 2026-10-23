# Migrate Plouf's monitoring into the shared stack

Plouf used to run its own `lgtm` container (Grafana, Prometheus, Loki, Tempo, a collector) inside its compose project. This moves it, with everything it collected, into `stacks/observability`, so every project shares one Grafana.

Expected downtime: the time to copy what changed during the first pass and start the stack. Plouf keeps sending metrics the whole time; what it sends during that gap is lost, nothing else.

## Before

1. On docker-host, as root: `git clone git@github.com:noook/hanok.git /opt/hanok` (or `git pull` in it).
2. Secrets: `cp stacks/observability/.env.example /tmp/obs.env`, fill it, then, from the repo root (SOPS looks for `.sops.yaml` there), `sops --encrypt --input-type dotenv --output-type dotenv /tmp/obs.env > stacks/observability/secrets.enc.env && shred -u /tmp/obs.env`. Check the first line of `secrets.enc.env` is encrypted (`GRAFANA_ADMIN_PASSWORD=ENC[...`). Commit and push `secrets.enc.env` from your Mac instead if you prefer (`sops` there too). `GRAFANA_ADMIN_PASSWORD` can be Plouf's: the copied Grafana keeps the password it already has anyway.
3. For `grafana.<tailnet>.ts.net`: add `tag:grafana` to the Tailscale policy file and create an auth key with that tag ([docs/tailscale-policy.md](../tailscale-policy.md), step A and "Auth keys"); put the key in `TS_AUTHKEY_GRAFANA`. Skip this and drop `--tailnet` below to start without the tailnet name (SSH tunnel to `127.0.0.1:3317` as before).
4. Dry run, which changes nothing and runs every check (source volume, free disk space, Plouf's OTLP endpoint):

   ```bash
   cd /opt/hanok && scripts/migrate-plouf-lgtm.sh --dry-run --tailnet
   ```

## Run

```bash
cd /opt/hanok && scripts/migrate-plouf-lgtm.sh --tailnet
```

What it does:

1. **Checks** the source container and volume, the free disk space (data size + 20 % + 1 GB), and that the target volume is new.
2. **First copy, no downtime.** Pulls the images, creates `observability_lgtm-data` and copies Plouf's volume into it with `rsync` while Plouf's `lgtm` keeps running.
3. **Stop and final copy.** Stops Plouf's `lgtm` (stopped, not removed) and runs `rsync` again: only what changed since the first pass is copied, which leaves the databases consistent.
4. **Starts the stack** with `scripts/up.sh observability` and waits for Grafana and Loki to be healthy. If that fails, it stops the new stack and starts Plouf's `lgtm` again (rollback).
5. **Connects Plouf's running `web` and `worker`** to the `observability` network. Their endpoint `http://lgtm:4318` now resolves to the new stack, with no Plouf redeploy.
6. **Checks** that Prometheus still answers for the time before the stop (old data kept) and that new Plouf metrics arrive.

If it stops half way, fix the cause and rerun with `RESUME=1`: `rsync` continues where it stopped.

## After

- Open Grafana at `https://grafana.<tailnet>.ts.net`. Plouf's dashboard is in the *Plouf* folder, its alert rules under *Alerting*. Alerts now go through the homelab's contact point (`hanok-telegram`); the old `plouf-telegram` contact point may still be listed and can be deleted in the UI.
- Deploy the Plouf release that removes `lgtm` from Plouf's compose and adds the `observability` network to `web` and `worker`. Until then, a Plouf redeploy recreates those containers without the network: reconnect them with `docker network connect observability plouf-web-1` and the same for `plouf-worker-1`.
- After a few days without problems: `docker rm plouf-lgtm-1 && docker volume rm plouf_lgtm-data`.

## How it was tested

On a local Docker host, against a simulated Plouf (a compose project with the same `lgtm` image and volume, and two containers sending OTLP to `http://lgtm:4318` every 10 s), 435 MB of data:

- full run: exit 0, monitoring back after 20 s, metrics from before the stop still queryable, new metrics arriving 11 s after the stack started, through the hot-connected network;
- rollback: a failing start stopped the new stack and brought the old `lgtm` back healthy; `RESUME=1` then finished the migration;
- the shared stack: Plouf's real dashboard and five alert rules loaded into one *Plouf* folder; container logs reached Loki labelled by compose project and service; a container labelled `observability.scrape=true` was scraped within a minute.

Not tested: the `tailnet` profile (it needs a real auth key). If `https://grafana.<tailnet>.ts.net` does not answer, read `docker logs observability-tailscale-grafana-1`. The serve config proxies to `http://lgtm:3000` over the Docker network; if a Tailscale version refuses that in userspace mode, set `network_mode: service:lgtm` on the sidecar and proxy to `http://127.0.0.1:3000` instead.
