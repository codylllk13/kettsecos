#!/bin/bash
# Apply the runtime no-swap/no-automount guard for the forensic boot entry.
set -euo pipefail

CMDLINE_FILE="${AEGISOS_CMDLINE_FILE:-/proc/cmdline}"
SYSTEMCTL_BIN="${AEGISOS_SYSTEMCTL_BIN:-/usr/bin/systemctl}"
SWAPOFF_BIN="${AEGISOS_SWAPOFF_BIN:-/usr/sbin/swapoff}"
INSTALL_BIN="${AEGISOS_INSTALL_BIN:-/usr/bin/install}"
LOGGER_BIN="${AEGISOS_LOGGER_BIN:-/usr/bin/logger}"

usage() {
  cat <<'EOF'
Usage: aegisos-forensic-mode [--check]

This helper is run by systemd when the kernel command line contains
aegisos.forensic=1. It disables swap and masks desktop disk automounting for
the current boot. --check reports whether the boot flag is present.
EOF
}

is_forensic_boot() {
  tr ' ' '\n' < "$CMDLINE_FILE" | grep -Fxq "aegisos.forensic=1"
}

case "${1:-apply}" in
  --check|check)
    is_forensic_boot
    ;;
  -h|--help|help)
    usage
    ;;
  apply)
    if ! is_forensic_boot; then
      echo "Forensic boot flag not present; no changes applied."
      exit 0
    fi

    "$SWAPOFF_BIN" --all
    "$SYSTEMCTL_BIN" --runtime --now mask swap.target udisks2.service
    "$INSTALL_BIN" -d -m0755 /run/aegisos
    printf 'enabled\n' > /run/aegisos/forensic-mode
    "$LOGGER_BIN" -t aegisos-forensic \
      "Forensic mode active: swap and UDisks2 automounting disabled" || true
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
