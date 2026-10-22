# ouranos-infrastructure

Ouranos runs as rootful Podman [Quadlets](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html):
systemd units generated from the files in `quadlets/`. The units expect this
repo at `/home/dwales/ouranos-infrastructure`, with each `sample.env` copied to
`.env` next to it.

```sh
sudo ./deploy.sh                  # symlink quadlets/ into /etc/containers/systemd and reload
sudo systemctl start pantheon-gateway.service pantheon-interface.service grafana.service alloy.service valkey.service
systemctl status postgres.service # each service is <name>.service; logs via journalctl -u <name>
```

Units start at boot. Services reach each other by container name on the
`ouranos` network. Postgres reports started only once `pg_isready` passes, so
dependents wait for it.

Moving an existing Docker Compose install over is a one-off; follow
[docs/quadlet-migration.md](docs/quadlet-migration.md). The compose files stay
until that is done, as the rollback path.

## Updates

- **Pantheon images** (`ghcr.io/davwales/ouranos-pantheon/*:latest`) carry
  `AutoUpdate=registry`. `podman-auto-update.timer` checks every 5 minutes
  (drop-in in `systemd/`) and rolls back if the new container fails to start.
- **Everything else** is pinned to an exact version. Renovate (`renovate.json`)
  opens a PR when a new version is released. Major upgrades of TimescaleDB,
  RabbitMQ and Valkey wait for approval on the dependency dashboard, because
  they need a manual migration.
