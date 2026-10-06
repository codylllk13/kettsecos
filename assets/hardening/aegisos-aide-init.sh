#!/bin/bash
# Initialize the AIDE database once on an installed system.
set -euo pipefail

CMDLINE_FILE="${AEGISOS_CMDLINE_FILE:-/proc/cmdline}"
AIDEINIT_BIN="${AEGISOS_AIDEINIT_BIN:-/usr/sbin/aideinit}"
SYSTEMCTL_BIN="${AEGISOS_SYSTEMCTL_BIN:-/usr/bin/systemctl}"

usage() {
  cat <<'EOF'
Usage: aegisos-aide-init

Initializes AIDE once on a persistent installation, then enables its daily
integrity-check timer. Ephemeral casper live sessions are intentionally skipped.
EOF
}

has_cmdline_flag() {
  local expected="$1"

  tr ' ' '\n' < "$CMDLINE_FILE" | grep -Fxq "$expected"
}

database_exists() {
  [ -s /var/lib/aide/aide.db ] || [ -s /var/lib/aide/aide.db.gz ]
}

case "${1:-run}" in
  -h|--help|help)
    usage
    exit 0
    ;;
  run)
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

if has_cmdline_flag "boot=casper" || has_cmdline_flag "boot=live"; then
  echo "Skipping AIDE initialization in the ephemeral live session."
  exit 0
fi

if [ "$EUID" -ne 0 ]; then
  echo "AIDE initialization must run as root." >&2
  exit 1
fi

if ! database_exists; then
  "$AIDEINIT_BIN" --yes --force
fi

"$SYSTEMCTL_BIN" enable --now dailyaidecheck.timer
