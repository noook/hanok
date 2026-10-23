# Public through Cloudflare and Traefik, private through a Tailscale sidecar per service

**Public** services go through the existing Cloudflare tunnel (a wildcard on `*.nook.sh`) to Traefik, which routes by Docker labels on the shared `proxy` network. No port is open on my router and a new public service needs no DNS or tunnel change.

**Private** services (Grafana, admin UIs) are reached only from my devices on the tailnet. Each gets a Tailscale sidecar container with its own name, so the address says what it is (`https://grafana.<tailnet>.ts.net`) instead of the machine's name plus a port. The sidecar serves HTTPS with a real certificate and proxies to the service over the Docker network. It runs in userspace mode, so it needs no TUN device and no capabilities. Each sidecar has a tag, so the Tailscale policy can let my devices reach that one service and nothing else on docker-host.

**Rejected:** `tailscale serve` on docker-host itself (one name for every service, distinguished by port or path), and a private service behind Cloudflare Access (it would be on the internet, behind a login).
