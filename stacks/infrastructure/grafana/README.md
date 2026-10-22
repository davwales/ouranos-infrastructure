The contents of this stack were influenced heavily by https://github.com/grafana/loki/tree/main/examples/getting-started.

## Components

| Service                | Purpose                                                                                                                                                                                                                                                           | Ports (host)      |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------- |
| loki                   | Log store (single binary, local filesystem storage under `./.data/loki`, 14d retention)                                                                                                                                                                           | 3100              |
| alloy                  | Collector: scrapes container logs to Loki through Podman's Docker-compatible socket; receives OTLP traces/metrics (gRPC 4317 / HTTP 4318) and forwards traces to Tempo and metrics to Mimir                                                                                                          | 12345, 4317, 4318 |
| tempo                  | Trace store (single binary, local filesystem storage under `./.data/tempo`, 14d block retention)                                                                                                                                                                  | 3200              |
| mimir                  | Metric store (single process, local filesystem storage under `./.data/mimir`, multi-tenancy disabled, 14d retention)                                                                                                                                              | 9009              |
| grafana                | Visualization; datasources provisioned from `provisioning/datasources/ds.yaml` (mounted read-only at startup): Loki (with a `TraceId` derived field linking into Tempo), Tempo (with traces-to-logs correlation back to Loki), and Mimir (`/prometheus` endpoint) | 3000              |

## Telemetry flow

Upstream apps push OTLP to `alloy:4317` on the `ouranos` Podman network.
Publishing 4317/4318 to the host also lets machines outside that network
push to `http://<host>:4317`.

Notes:

- All three telemetry stores keep data for 14 days. Loki retention runs in its
  built-in compactor (`limits_config.retention_period: 14d` +
  `compactor.retention_enabled`), Mimir deletes old blocks on compaction
  (`limits.compactor_blocks_retention_period: 14d`). Tempo is left on its
  14-day default.
- `tempo` runs as root (`User=root`) because the image defaults to uid 10001, which
  cannot write to the root-owned bind-mounted `./.data/tempo` directory.
- Grafana state (dashboards, users, alerting) lives in the `grafana_data` named
  volume at `/var/lib/grafana` and survives container recreation and image
  updates. It is removed only by `podman volume rm ouranos_grafana_data`, same
  as the other named volumes. Pin the image tag deliberately when upgrading Grafana; the
  SQLite database migrates automatically on startup.
- Mimir ingests metrics via its native OTLP endpoint (`/otlp/v1/metrics`);
  the Loki tenant header (`tenant1`) is vestigial from the upstream example -
  Loki itself runs with `auth_enabled: false`.
- `loki` also runs as root for the same reason with `./.data/loki`.
  It replaced the earlier simple-scalable setup (read/write/backend behind an
  nginx gateway, storing to MinIO); hosts upgraded from that setup can delete
  `./.data/minio`. The `loki-gateway` network alias on `loki` is kept until
  ouranos-pantheon's Serilog sink is repointed to `loki:3100`.
- The Tempo datasource expects log lines to carry Serilog's `TraceId` property
  (hex trace id); the Loki derived-field regex links matching lines to Tempo.
