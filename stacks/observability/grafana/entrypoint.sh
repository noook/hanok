#!/usr/bin/env bash
# Starts grafana/otel-lgtm with the homelab's provisioning, then each project's (docs/conventions.md).
#
# A project mounted at /projects/<name> may hold:
#   dashboards/*.json            loaded into a Grafana folder named after the project, capitalised ("Plouf"),
#                                the same folder its alert rules should name
#   provisioning/alert-rules.yaml (or alert-rules/*.yaml)   alert rules, routed to the homelab's contact point
# Contact points and the notification policy belong to the homelab (one tree per Grafana org), not to projects.
set -euo pipefail

provisioning=/otel-lgtm/grafana/conf/provisioning
mkdir -p "$provisioning/dashboards" "$provisioning/alerting"

if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
  cp /hanok/provisioning/contact-points.yaml.tmpl "$provisioning/alerting/hanok-contact-points.yaml"
  echo "hanok: alerts go to Telegram."
else
  echo "hanok: TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID not set, alerts are shown in Grafana only."
fi

for dir in /projects/*/; do
  [ -d "$dir" ] || continue
  name="$(basename "$dir")"
  if [ -d "$dir/dashboards" ]; then
    cat >"$provisioning/dashboards/project-$name.yaml" <<EOF
apiVersion: 1
providers:
  - name: $name
    type: file
    folder: ${name^}
    allowUiUpdates: false
    updateIntervalSeconds: 30
    options:
      path: ${dir%/}/dashboards
EOF
    echo "hanok: dashboards of $name."
  fi
  for rules in "$dir"/provisioning/alert-rules.yaml "$dir"/alert-rules/*.yaml; do
    [ -f "$rules" ] || continue
    cp "$rules" "$provisioning/alerting/project-$name-$(basename "$rules")"
    echo "hanok: alert rules of $name ($(basename "$rules"))."
  done
done

exec /otel-lgtm/run-all.sh
