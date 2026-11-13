# One shared monitoring stack, all-in-one first

Plouf had its own Grafana stack inside its compose project; the crypto bots (dotori) had another Grafana. More projects will come. One Grafana should show all of them.

**Decision.** `stacks/observability`:

- **Storage and screens:** Grafana's all-in-one `otel-lgtm` image (an OpenTelemetry collector, Prometheus, Loki, Tempo and Grafana in one container). It is what Plouf already ran, so moving Plouf's collected data is moving a volume, with a minute of downtime (`scripts/migrate-plouf-lgtm.sh`). Grafana presents this image as meant for development and demos; for one person's homelab that is acceptable for now. Splitting it into one container per program (each with its own retention and upgrades) is planned for November 2026, once the move is done.
- **Discovery, like Traefik:** Grafana Alloy reads the Docker API through a read-only socket proxy. It collects every container's logs and scrapes containers labelled `observability.scrape=true` (`docs/conventions.md`). Applications that speak OpenTelemetry send to `http://lgtm:4318` on the shared `observability` network.
- **Dashboards and alert rules stay in each project's repository**, mounted read-only into Grafana, one folder per project. Grafana has no Docker-label discovery for dashboards, and files keep them in git.
- **One contact point and one notification policy** (Telegram), owned by this repo: Grafana has one policy tree per organisation, so projects cannot each bring their own.
- Grafana is reached on the tailnet as `grafana.<tailnet>.ts.net` (ADR 0002).

**Amendment (13 Nov 2026): Loki keeps 30 days.** The image's Loki keeps logs forever. `LOKI_EXTRA_ARGS` in `stacks/observability/compose.yaml` turns on the compactor's retention for every stream (`720h`), so container logs and Plouf's browser telemetry (privacy notice: 30 days) both expire after 30 days. Check: `docker exec observability-lgtm-1 curl -s localhost:3100/config | grep -E 'retention_(period|enabled)'` shows `30d` and `true`. Prometheus (15 days) and Tempo are unchanged.
