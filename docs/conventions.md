# Conventions

## Exposure

| Who should reach it | How | What the stack does |
|---|---|---|
| Anyone (a public site) | Cloudflare tunnel, then Traefik | joins the external `proxy` network; labels `traefik.enable=true`, `traefik.docker.network=proxy`, a router with `entrypoints=web` and a literal-backtick `Host()` rule. TLS ends at Cloudflare, so no `tls` label. The tunnel already sends `*.nook.sh` to Traefik: no DNS or tunnel change per service. |
| Only my devices | a Tailscale sidecar | a `tailscale/tailscale` container with `TS_HOSTNAME=<service>`, a tag, and a serve config (`stacks/<stack>/tailscale/<service>.json`) proxying to the service. Userspace mode (`TS_USERSPACE=true`): no `/dev/net/tun`, no capabilities. Funnel always off. |
| Nobody from outside | nothing | no `ports:` entry, or `127.0.0.1:<port>` only, for an SSH tunnel. |

A service is never published on the host's LAN address.

## Monitoring a project

A project joins the external `observability` network and uses some of these:

| Want | Do |
|---|---|
| Its container logs in Loki | nothing: every container is collected, labelled `compose_project`, `compose_service`, `container` |
| Keep a container's logs out (it prints secrets, or it is noisy) | label `observability.logs: "false"` |
| Prometheus metrics it serves | labels `observability.scrape: "true"`, `observability.port: "<port>"`, optionally `observability.path: "/metrics"`; the container must be on the `observability` network |
| OpenTelemetry (metrics, traces, logs) | `OTEL_EXPORTER_OTLP_ENDPOINT=http://lgtm:4318` |
| Dashboards and alert rules | keep them in the project's repo, in a folder with `dashboards/*.json` and `provisioning/alert-rules.yaml` (or `alert-rules/*.yaml`), and add one read-only mount of that folder at `/projects/<name>` to `stacks/observability/compose.yaml`. Dashboards land in a Grafana folder named after the project, capitalised; alert rules should name the same folder. |
| Jump between a trace and its logs | write JSON log lines with a `trace_id` field and send them over OTLP: Loki shows a "Trace" link on the line, and Tempo's "Logs for this span" finds the lines of the same `service.name` (`grafana/provisioning/trace-log-links.yaml`) |
| Alerts delivered | nothing: the homelab owns the contact point (Telegram) and the notification policy; alerts are grouped by folder |

Datasource uids in dashboards and rules: `prometheus`, `loki`, `tempo`.

## A project's tailnet rules

A project that needs machines of its own on the tailnet brings `.hanok/tailnet.hujson` in its repository: `tagOwners`, `grants` and `tests`, only for the tags named after it (`tag:<repository>-*`), and installs the `hanok-tailnet` GitHub App on its repository. hanok's workflow adds it at the next hourly run. The rules a fragment must follow, and what it cannot do: `docs/tailscale-policy.md`, ADR 0007.

## Naming

- A stack, its directory and its Compose project are named after the project, not the technology: `obsidian-livesync`, not `couchdb`.
- Every compose file starts with `name: <stack>`, so the project name (and its volume names) does not depend on the directory.
- Images are pinned to an exact version. Renovate opens a pull request for each update.

## Secrets

- `stacks/<stack>/secrets.enc.env`, encrypted with SOPS for the age keys in `.sops.yaml` (my Mac and docker-host). Edit with `sops stacks/<stack>/secrets.enc.env`.
- Every key a stack reads is listed, without values, in `stacks/<stack>/.env.example`.
- Plain `.env` files are for local tests only and are gitignored.
- The repo is meant to become public: no plain secret, no personal email, no tailnet name in committed files (they come from secrets or `${TS_CERT_DOMAIN}`).

## Using the CI runner

Private repositories can run their GitHub Actions jobs on `hanok-ci`, a VM on the homelab (ADR 0004), instead of paying for hosted minutes. Never a public repository.

1. Register the repository on the VM: `docs/runbooks/ci-runner.md`, "Register a repository".
2. In every job: `runs-on: ${{ vars.CI_RUNNER || 'ubuntu-latest' }}`. Set the repository variable `CI_RUNNER` to `hanok-ci` to use the VM; unset it to fall back to GitHub's runners.
3. Service containers publish on the VM itself, shared with every other job. Never a fixed host port (`5432:5432`): use `- 5432` and read the port Docker picked from `${{ job.services.<service>.ports['5432'] }}`, in a step (that context is not available in a job's `env`).
4. Nothing on the VM reaches the LAN or the tailnet. A job that needs a homelab service cannot run there.
5. The VM is not GitHub's hosted image: it only has Docker, git, curl, jq and `gh`. A step that calls another tool directly needs a setup action (`actions/setup-node`…) or a line in `hosts/hanok-ci/setup.sh`. The first Release on the VM failed this way (`gh: command not found`).

