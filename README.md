# ouranos-infrastructure

Compose stacks for Ouranos. Run everything from the repo root with
`docker compose up -d`; `docker-compose.yaml` includes `stacks/pantheon` and
`stacks/infrastructure`. Copy each `sample.env` to `.env` next to it first.

## Updates

- **Pantheon images** (`ghcr.io/davwales/ouranos-pantheon/*:latest`) are
  updated automatically by the `watchtower` service. It polls every 5 minutes
  and only touches containers labeled `com.centurylinklabs.watchtower.enable=true`.
- **Everything else** is pinned to an exact version. Renovate (`renovate.json`)
  opens a PR when a new version is released. Major upgrades of TimescaleDB,
  RabbitMQ and Valkey wait for approval on the dependency dashboard, because
  they need a manual migration.
