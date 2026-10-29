# shellcheck shell=bash
# Shared helpers for the ouranos-* commands. Sourced, not run.

REPO=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
# shellcheck disable=SC2034  # used by the commands that source this file
QUADLET_DEST=/etc/containers/systemd/ouranos
# shellcheck disable=SC2034
MARKER=.managed-by-ouranos-infrastructure

die() { echo "error: $*" >&2; exit 1; }

# Re-run the calling command under sudo unless already root: as_root "$@"
as_root() {
  [ "$(id -u)" -eq 0 ] || exec sudo "$(readlink -f "$0")" "$@"
}

quadlet_bin() {
  local q
  for q in /usr/libexec/podman/quadlet /usr/lib/podman/quadlet; do
    [ -x "$q" ] && { echo "$q"; return; }
  done
  die "quadlet not found; is podman installed?"
}

# Copy quadlets/ into $1 with @REPO@ replaced by $2 (default: this checkout).
render() {
  local out=$1 repo=${2:-$REPO} f
  mkdir -p "$out"
  for f in "$REPO"/quadlets/*; do
    sed "s#@REPO@#$repo#g" "$f" > "$out/$(basename "$f")"
  done
  ! grep -l '@REPO@' "$out"/* 2>/dev/null || die "unrendered @REPO@ left in $out"
}

# Variables the units expand with ${VAR}.
required_vars() {
  grep -ohE '\$\{[A-Z_]+\}' "$REPO"/quadlets/* | sed 's/[^A-Z_]//g' | sort -u
}

# Fail unless every required variable is set and non-empty in env file $1.
check_env() {
  local file=$1 missing
  [ -f "$file" ] || die "$file not found; copy sample.env to .env and fill it in"
  # shellcheck source=/dev/null
  missing=$(set -a; . "$file"; set +a
    for v in $(required_vars); do [ -n "${!v:-}" ] || echo "$v"; done)
  [ -z "$missing" ] || die "$file is missing: ${missing//$'\n'/ }"
}

# Every image the units run.
images() {
  grep -h '^Image=' "$REPO"/quadlets/*.container | cut -d= -f2 | sort -u
}

# Service names, one per .container file (postgres, pantheon-gateway, ...).
services() {
  local f
  for f in "$REPO"/quadlets/*.container; do basename "$f" .container; done
}

# Map service names to unit names, rejecting unknown ones. No arguments means
# the whole stack (ouranos.target).
units() {
  local s
  [ $# -gt 0 ] || { echo ouranos.target; return; }
  for s in "$@"; do
    s=${s%.service}
    services | grep -x "$s" >/dev/null || die "unknown service '$s' (one of: $(services | paste -sd' '))"
    echo "$s.service"
  done
}
