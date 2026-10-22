# Migrating ouranos.local from Docker Compose to Quadlets

A one-off runbook. Run everything on `ouranos.local` **in a root shell**, from
`/home/dwales/ouranos-infrastructure`:

```sh
git -C /home/dwales/ouranos-infrastructure pull   # as dwales, before becoming root
sudo -i
cd /home/dwales/ouranos-infrastructure
```

Rootless and rootful Podman have separate networks, images and volumes, so
mixing `podman …` and `sudo podman …` doesn't work: everything here must run as
root.

**The Docker volumes are never modified or removed.** Data is copied into new
Podman volumes, and the originals stay as the backup and the rollback path.
Docker itself stays installed: `gitlab-runner` and `mongo` still run on it.

| Docker volume (`/var/snap/docker/common/var-lib-docker/volumes/…`) | Podman volume (`/var/lib/containers/storage/volumes/…`) |
|---|---|
| `ouranos_postgres_data` (~175 GB) | same name |
| `ouranos_rabbitmq_data`, `ouranos_rabbitmq_logs` | same names |
| `ouranos_grafana_data`, `ouranos_valkey_data` | same names |

Loki, Tempo and Mimir data in `stacks/infrastructure/grafana/.data/` is
bind-mounted and is not copied.

```sh
VOLS="ouranos_postgres_data ouranos_rabbitmq_data ouranos_rabbitmq_logs ouranos_grafana_data ouranos_valkey_data"
DOCKER_VOLS=/var/snap/docker/common/var-lib-docker/volumes
PODMAN_VOLS=/var/lib/containers/storage/volumes
```

## 1. Prepare (no downtime)

```sh
QUADLET_UNIT_DIRS=$PWD/quadlets /usr/libexec/podman/quadlet -dryrun -no-kmsg-log >/dev/null && echo units ok
grep -h '^Image=' quadlets/*.container | cut -d= -f2 | sort -u | xargs -n1 podman pull
```

Don't run `deploy.sh` yet. Installed units start at boot, so a reboot before
cutover would start Podman postgres on a half-copied volume.

**Network smoke test (required).** Snap Docker's iptables rules can drop
forwarded traffic before netavark's nftables rules get to accept it. Prove
Podman networking works while Docker is running:

```sh
./smoketest.sh      # container DNS, egress, published port on localhost and the LAN IP
```

All four checks must print `ok`. If any fails, set `"ip-forward-no-drop": true` in
`/var/snap/docker/current/config/daemon.json` and run `snap restart docker`.
Then repeat the test.

**Optional extra safety net:** take a logical dump to another disk or host.
This is slow at this size; do it the night before.

```sh
docker exec ouranos-postgres-1 pg_dump -U psql -Fc pantheon  > /mnt/backup/pantheon.dump
docker exec ouranos-postgres-1 pg_dump -U psql -Fc flagsmith > /mnt/backup/flagsmith.dump
```

## 2. Pre-seed the copy (no downtime)

```sh
for v in $VOLS; do podman volume create --ignore "$v"; done   # what the .volume units do
for v in $VOLS; do rsync -aHAX --numeric-ids --delete "$DOCKER_VOLS/$v/_data/" "$PODMAN_VOLS/$v/_data/"; done
```

The data is still being written, so this copy is inconsistent; that is fine.
It moves most of the 175 GB before the stack goes down. Running it again
shortly before cutover shrinks the final delta.

## 3. Cut over (downtime starts)

```sh
docker exec ouranos-postgres-1 psql -U psql -d postgres -Atc \
  "SELECT datname, pg_database_size(datname) FROM pg_database ORDER BY 1" | tee /root/pg-before.txt
docker compose down                       # NOT -v; postgres gets a clean shutdown
docker ps --format '{{.Names}}'           # only gitlab-runner-1 and mongo remain
docker volume ls -q | grep ouranos_       # volumes still there

for v in $VOLS; do rsync -aHAX --numeric-ids --delete "$DOCKER_VOLS/$v/_data/" "$PODMAN_VOLS/$v/_data/"; done
```

Check that the copy is exact. Any output means a difference: re-run the rsync.

```sh
rsync -aHAXn --delete -i "$DOCKER_VOLS/ouranos_postgres_data/_data/" "$PODMAN_VOLS/ouranos_postgres_data/_data/"
# Definitive but reads all 175 GB twice; worth it if the window allows:
rsync -aHAXn --checksum --delete -i "$DOCKER_VOLS/ouranos_postgres_data/_data/" "$PODMAN_VOLS/ouranos_postgres_data/_data/"
stat -c '%u:%g %n' "$PODMAN_VOLS/ouranos_postgres_data/_data/PG_VERSION"   # 70:70
```

## 4. Start on Podman

```sh
./deploy.sh                               # install units, enable podman.socket and the auto-update timer
systemctl start postgres.service          # returns once pg_isready passes
journalctl -u postgres.service -o cat | grep -E 'was shut down at|not properly|recovery'
```

The log must show `database system was shut down at …` and **no** `not
properly shut down` or `automatic recovery` lines. Then compare the sizes
with `/root/pg-before.txt`. The rsync check in step 3 is the real proof; this
is a sanity check. A few kB of drift once autovacuum runs is normal:

```sh
podman exec postgres psql -U psql -d postgres -Atc \
  "SELECT datname, pg_database_size(datname) FROM pg_database ORDER BY 1" | diff /root/pg-before.txt - && echo match
```

Start the rest of the stack:

```sh
systemctl start db-init.service rabbitmq.service valkey.service flagsmith.service \
  loki.service tempo.service mimir.service alloy.service grafana.service \
  pantheon-gateway.service pantheon-interface.service
systemctl --no-pager status 'ouranos-network' postgres db-init rabbitmq valkey flagsmith loki tempo mimir alloy grafana pantheon-gateway pantheon-interface | grep -E '●|Active:'
```

## 5. Verify

- `podman exec rabbitmq rabbitmqctl list_queues` and `list_users` show the existing queues and users.
- `curl -s localhost:8001/health`, `curl -sI localhost`, `curl -s localhost:3100/ready`.
- Grafana (port 3000) shows the dashboards. Loki, Tempo and Mimir return data from before the cutover. New container logs arrive in Loki through alloy.
- `podman auto-update --dry-run` lists `pantheon-gateway` and `pantheon-interface`.
- `systemctl list-timers podman-auto-update.timer` shows a 5-minute schedule.
- Reboot once. Everything comes back, and `journalctl -u postgres.service -b -1 -o cat | tail` ends in `database system is shut down`, which means Postgres was not killed.

## Rollback

At any point before the Docker volumes are deleted:

```sh
systemctl stop pantheon-gateway pantheon-interface grafana alloy mimir tempo loki flagsmith valkey rabbitmq db-init postgres
rm /etc/containers/systemd/ouranos && systemctl daemon-reload   # so they don't start at next boot
docker compose up -d
```

Docker reattaches the original volumes, which were never changed. Any data
written while running on Podman is not in them.

## Afterwards

After about a week of stable running, delete the compose files and the
`docker compose config` CI step in a follow-up PR. Only after that, and with a
fresh backup, remove the old Docker volumes listed above. Leave the unlabelled
anonymous volumes and `ouranos_forgejo_data` alone until you know what they
hold.
