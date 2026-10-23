# ouranos-infrastructure

Ouranos runs as rootful Podman [Quadlets](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html):
each file in `quadlets/` becomes a systemd service, and `ouranos.target` groups
them so the whole stack starts at boot and can be started, stopped or restarted
together. Needs Podman 5.0 or later.

## New server

```sh
git clone https://github.com/davwales/ouranos-infrastructure.git
cd ouranos-infrastructure
sudo scripts/ouranos-bootstrap   # first run creates .env from sample.env and stops
$EDITOR .env                     # real credentials and API keys
sudo scripts/ouranos-bootstrap   # installs Podman if needed, installs units, starts the stack
```

Then put the commands on your `PATH`, e.g. in `~/.bashrc`:

```sh
export PATH="$HOME/ouranos-infrastructure/scripts:$PATH"
```

## Commands

Commands that need root re-run themselves with `sudo`. Service names are the
file names in `quadlets/` (`postgres`, `pantheon-gateway`, …); leaving them out
means the whole stack.

| Command | What it does |
|---|---|
| `ouranos-status` | State, uptime and restart count of every service |
| `ouranos-health [-q]` | Checks units, container health checks, HTTP endpoints and Postgres/Valkey/RabbitMQ; exits 1 on any failure (`-q`: only print problems) |
| `ouranos-logs [service] [journalctl args]` | Logs for one service or all of them, e.g. `ouranos-logs postgres -f` |
| `ouranos-start [service…]` | Start the stack or the named services |
| `ouranos-stop [service…]` | Stop them (Postgres gets up to 120 s to shut down cleanly) |
| `ouranos-restart [service…]` | Restart them; services that depend on them restart too |
| `ouranos-update [--restart]` | `git pull`, reinstall the units, and list (or restart) the services whose units changed |
| `ouranos-backup [dir]` | `pg_dump` every database to `/var/backups/ouranos/<timestamp>` |
| `ouranos-install` | Render the units for this checkout into `/etc/containers/systemd/ouranos` (run by `ouranos-update` and `ouranos-bootstrap`) |
| `ouranos-bootstrap` | Set up a fresh server (see above) |
| `ouranos-smoketest` | Check container networking, egress and published ports from the LAN |
| `ouranos-validate` | Check the units with Podman 5.7's Quadlet in a container (CI runs this) |

## Layout

- `quadlets/`: one `.container` per service, plus the `ouranos` network and
  the named volumes. Paths are written as `@REPO@`; `ouranos-install` fills in
  where this checkout lives.
- `.env` (from `sample.env`): the one secrets file. Units expand its values
  with `${VAR}`; `ouranos-install` refuses to run if any are missing.
- `config/`: one folder per service with the config files its container
  mounts read-only (Alloy, Grafana datasources, Loki, Tempo, Mimir, the Postgres
  init script). See [docs/observability.md](docs/observability.md) for the
  telemetry stack.
- State lives in named Podman volumes, one `*_data.volume` per service
  (`podman volume ls`).
- `systemd/`: `ouranos.target` and the 5-minute `podman-auto-update` timer.

## Updates

- **Pantheon images** (`ghcr.io/davwales/ouranos-pantheon/*:latest`) carry
  `AutoUpdate=registry`. `podman-auto-update.timer` checks every 5 minutes and
  rolls back if the new container fails to start.
- **Everything else** is pinned to an exact version. Renovate (`renovate.json`)
  opens a PR when a new version is released. Major upgrades of TimescaleDB,
  RabbitMQ and Valkey wait for approval on the dependency dashboard, because
  they need a manual migration. After merging, run `ouranos-update --restart`.

## Running next to Docker

Docker sets the kernel's `FORWARD` policy to `DROP`, which silently breaks
Podman container networking and makes published ports unreachable from other
machines. On a host that also runs Docker, set `"ip-forward-no-drop": true`
in Docker's `daemon.json` (snap: `/var/snap/docker/current/config/daemon.json`),
restart Docker, and run `sudo iptables -P FORWARD ACCEPT` once.
`ouranos-bootstrap` refuses to continue while the policy is `DROP`, and
`ouranos-smoketest` checks the result.

## Restoring a backup

TimescaleDB databases must be restored into an empty database with:

```sql
SELECT timescaledb_pre_restore();
-- pg_restore -d <db> <db>.dump
SELECT timescaledb_post_restore();
```
