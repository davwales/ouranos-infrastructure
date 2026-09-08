The contents of this stack were influenced heavily by https://github.com/grafana/loki/tree/main/examples/getting-started.

## Components

| Service | Purpose | Ports (host) |
|---------|---------|--------------|
| read / write / backend | Loki simple-scalable mode (S3 storage via MinIO) | 3101, 3102 |
| loki-gateway | Nginx routing pushes to the writer and queries to the reader | 3100 |
| alloy | Collector: scrapes Docker container logs to Loki; receives OTLP traces/metrics (gRPC 4317 / HTTP 4318) and forwards traces to Tempo and metrics to Mimir | 12345, 4317, 4318 |
| tempo | Trace store (single binary, local filesystem storage under `./.data/tempo`, default 14d block retention) | 3200 |
| mimir | Metric store (single process, local filesystem storage under `./.data/mimir`, multi-tenancy disabled) | 9009 |
| grafana | Visualization; datasources provisioned from `provisioning/datasources/ds.yaml` (mounted read-only at startup): Loki (with a `TraceId` derived field linking into Tempo), Tempo (with traces-to-logs correlation back to Loki), and Mimir (`/prometheus` endpoint) | 3000 |
| minio | S3-compatible object storage for Loki | 9000 |

## Telemetry flow

Upstream apps push OTLP to `alloy:4317` on the shared compose network.
Publishing 4317/4318 to the host also lets machines outside the compose network
push to `http://<host>:4317`.

Notes:

- `tempo` runs as `user: root` because the image defaults to uid 10001, which
  cannot write to the root-owned bind-mounted `./.data/tempo` directory.
- Grafana state (dashboards, users, alerting) lives in the `grafana_data` named
  volume at `/var/lib/grafana` and survives container recreation and image
  updates. It is removed only by `docker compose down -v`, same as the other
  named volumes. Pin the image tag deliberately when upgrading Grafana; the
  SQLite database migrates automatically on startup.
- Mimir ingests metrics via its native OTLP endpoint (`/otlp/v1/metrics`);
  the Loki tenant header (`tenant1`) is vestigial from the upstream example -
  Loki itself runs with `auth_enabled: false`.
- The Tempo datasource expects log lines to carry Serilog's `TraceId` property
  (hex trace id); the Loki derived-field regex links matching lines to Tempo.