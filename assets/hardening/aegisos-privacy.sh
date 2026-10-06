#!/bin/bash
# Opt-in system-wide Tor routing for AegisOS.
set -euo pipefail

SERVICE_NAME="aegisos-privacy-routing.service"
TOR_SERVICE="tor@default.service"
NFT_TABLE="aegisos_privacy"
NFT_BIN="${AEGISOS_NFT_BIN:-/usr/sbin/nft}"
SYSTEMCTL_BIN="${AEGISOS_SYSTEMCTL_BIN:-/usr/bin/systemctl}"

usage() {
  cat <<'EOF'
Usage: aegisos-privacy COMMAND

Commands:
  enable   Start Tor, route public IPv4 TCP/DNS through it, and block leaks
  disable  Remove routing rules and stop the opt-in Tor service
  status   Show the routing service and nftables state
  apply    Internal systemd action: install the nftables rules
  remove   Internal systemd action: remove the nftables rules
  render   Internal validation action: print rules with a numeric Tor UID
EOF
}

require_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "This action must be run as root." >&2
    exit 1
  fi
}

table_exists() {
  "$NFT_BIN" list table inet "$NFT_TABLE" >/dev/null 2>&1
}

remove_rules() {
  if table_exists; then
    "$NFT_BIN" delete table inet "$NFT_TABLE"
  fi
}

render_rules() {
  local tor_uid="$1"

  cat <<EOF
table inet $NFT_TABLE {
  chain redirect_output {
    type nat hook output priority dstnat; policy accept;

    meta skuid $tor_uid return
    oifname "lo" return

    meta nfproto ipv4 udp dport 53 redirect to :5353
    meta nfproto ipv4 tcp dport 53 redirect to :5353

    ip daddr {
      0.0.0.0/8,
      10.0.0.0/8,
      100.64.0.0/10,
      127.0.0.0/8,
      169.254.0.0/16,
      172.16.0.0/12,
      192.168.0.0/16,
      224.0.0.0/3
    } return
    ip6 daddr { ::1/128, fc00::/7, fe80::/10, ff00::/8 } return

    meta nfproto ipv4 tcp dport 1-65535 redirect to :9040
  }

  chain leak_guard {
    type filter hook output priority filter; policy accept;

    meta skuid $tor_uid accept
    oifname "lo" accept
    ip daddr {
      0.0.0.0/8,
      10.0.0.0/8,
      100.64.0.0/10,
      127.0.0.0/8,
      169.254.0.0/16,
      172.16.0.0/12,
      192.168.0.0/16,
      224.0.0.0/3
    } accept
    ip6 daddr { ::1/128, fc00::/7, fe80::/10, ff00::/8 } accept

    reject with icmpx type admin-prohibited
  }
}
EOF
}

apply_rules() {
  local tor_uid

  tor_uid="$(id -u debian-tor 2>/dev/null)" || {
    echo "The debian-tor service account is unavailable." >&2
    exit 1
  }

  remove_rules
  render_rules "$tor_uid" | "$NFT_BIN" -f -
}

show_status() {
  local routing_state="inactive"
  local tor_state="inactive"
  local table_state="absent"

  routing_state="$("$SYSTEMCTL_BIN" is-active "$SERVICE_NAME" 2>/dev/null ||
    true)"
  tor_state="$("$SYSTEMCTL_BIN" is-active "$TOR_SERVICE" 2>/dev/null ||
    true)"
  if table_exists; then
    table_state="present"
  fi

  printf 'Privacy routing service: %s\n' "$routing_state"
  printf 'Tor client service: %s\n' "$tor_state"
  printf 'Privacy nftables table: %s\n' "$table_state"

  [ "$routing_state" = "active" ] &&
    [ "$tor_state" = "active" ] &&
    [ "$table_state" = "present" ]
}

case "${1:---help}" in
  enable)
    require_root
    "$SYSTEMCTL_BIN" enable --now "$SERVICE_NAME"
    "$SYSTEMCTL_BIN" start "$TOR_SERVICE"
    echo "Privacy routing enabled."
    echo "Public IPv4 TCP and DNS use Tor; public UDP and IPv6 are blocked."
    echo "Local/private networks remain directly reachable."
    ;;
  disable)
    require_root
    "$SYSTEMCTL_BIN" disable --now "$SERVICE_NAME"
    remove_rules
    if "$SYSTEMCTL_BIN" is-active --quiet "$TOR_SERVICE"; then
      "$SYSTEMCTL_BIN" stop "$TOR_SERVICE"
    fi
    echo "Privacy routing disabled."
    ;;
  status)
    require_root
    show_status
    ;;
  apply)
    require_root
    apply_rules
    ;;
  remove)
    require_root
    remove_rules
    ;;
  render)
    if ! [[ "${2:-65534}" =~ ^[0-9]+$ ]]; then
      echo "render requires a numeric UID." >&2
      exit 2
    fi
    render_rules "${2:-65534}"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
