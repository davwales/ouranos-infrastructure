#!/bin/bash
# Install the Ouranos Quadlets as rootful systemd units. Run as root.
# Installs only; starting units is left to the operator (see README).
set -euo pipefail

repo=$(cd "$(dirname "$0")" && pwd)

ln -sfn "$repo/quadlets" /etc/containers/systemd/ouranos
install -D -m 644 "$repo/systemd/podman-auto-update.timer.d/override.conf" \
  /etc/systemd/system/podman-auto-update.timer.d/override.conf

/usr/libexec/podman/quadlet -dryrun -no-kmsg-log >/dev/null
systemctl daemon-reload
systemctl enable --now podman.socket podman-auto-update.timer
