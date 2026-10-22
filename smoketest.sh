#!/bin/bash
# Check that rootful Podman networking works alongside Docker before cutover.
# Run as root: sudo ./smoketest.sh
set -uo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "run as root (sudo ./smoketest.sh); rootless Podman has a separate network stack" >&2
  exit 1
fi

image=docker.io/library/busybox:1.37
port=18080
failed=0

check() {
  local name=$1; shift
  if "$@" >/dev/null 2>&1; then echo "ok    $name"; else echo "FAIL  $name"; failed=1; fi
}

cleanup() {
  podman rm -f smoke >/dev/null 2>&1
  podman network rm smoketest >/dev/null 2>&1
}
trap cleanup EXIT
cleanup

podman network create smoketest >/dev/null
podman run -d --name smoke --network smoketest -p "$port:8080" "$image" \
  sh -c 'mkdir /www && echo ok > /www/ok && httpd -f -p 8080 -h /www' >/dev/null
sleep 2

check "container DNS (smoke:8080)" podman run --rm --network smoketest "$image" wget -qO- http://smoke:8080/ok
check "egress to the internet"     podman run --rm --network smoketest "$image" wget -q -O /dev/null http://example.com
check "published port (localhost)" sh -c "curl -sf http://localhost:$port/ok | grep -qx ok"
check "published port (LAN IP)"    sh -c "curl -sf http://$(hostname -I | awk '{print $1}'):$port/ok | grep -qx ok"

exit $failed
