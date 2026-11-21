#!/usr/bin/env bash
# Isolated regressions: no network, services, firewall or VPS state changes.
set -euo pipefail
cd "$(dirname "$0")/.."
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
SINGBOX_CONF="$tmp/singbox.json"
XRAY_CONF="$tmp/xray.json"
SNELL_CONF="$tmp/snell-v5.conf"
SNELL6_CONF="$tmp/snell-v6.conf"
HY2_CONF="$tmp/hy2.json"
HY2_MANAGED_MARKER="$tmp/hy2-managed"
cat >"$SINGBOX_CONF" <<'JSON'
{"inbounds":[
  {"tag":"ss-in","type":"shadowsocks","listen_port":443},
  {"tag":"ss-shadowtls-in","type":"shadowtls","listen_port":8443},
  {"tag":"ss-shadowtls-udp","type":"shadowsocks","listen_port":8444}]}
JSON
cat >"$XRAY_CONF" <<'JSON'
{"inbounds":[{"tag":"vless-reality-in","protocol":"vless","port":9443}]}
JSON
printf 'listen = 0.0.0.0:5555\npsk=SECRETSHOULDNOTSHOW\n' >"$SNELL_CONF"
printf 'listen = [::]:6555\n' >"$SNELL6_CONF"
printf '{"listen":":7443","auth":{"password":"SECRETSHOULDNOTSHOW"}}\n' >"$HY2_CONF"
touch "$HY2_MANAGED_MARKER"
service_is_active() { [[ "$1" != "$HY2_SERVICE_NAME" ]]; }
ss() {
    case "$*" in
        "-H -lnt")
            printf 'LISTEN 0 128 0.0.0.0:443 0.0.0.0:*\n'
            printf 'LISTEN 0 128 127.0.0.1:8443 0.0.0.0:*\n'
            printf 'LISTEN 0 128 [::]:9443 [::]:*\n'
            printf 'LISTEN 0 128 0.0.0.0:5555 0.0.0.0:*\n'
            printf 'LISTEN 0 128 [::]:6555 [::]:*\n'
            ;;
        "-H -lnu")
            printf 'UNCONN 0 0 0.0.0.0:443 0.0.0.0:*\n'
            printf 'UNCONN 0 0 [::]:7443 [::]:*\n'
            ;;
        *) return 2 ;;
    esac
}
for good in 1 443 65535; do gfw_diag_valid_port "$good"; done
for bad in 0 65536 1a "" -1 "443:1"; do
    if gfw_diag_valid_port "$bad"; then echo "FAIL: invalid port $bad"; exit 1; fi
done
ports=$(gfw_diag_configured_ports)
for row in $'SS2022\ttcp\t443\tsing-box' $'SS2022\tudp\t443\tsing-box' \
           $'ShadowTLS\ttcp\t8443\tsing-box' $'ShadowTLS\tudp\t8444\tsing-box' \
           $'VLESS Reality\ttcp\t9443\tss2022-xray' \
           $'Snell v5\ttcp\t5555\tsnell-v5' $'Snell v6\ttcp\t6555\tsnell-v6' \
           $'Hysteria 2\tudp\t7443\tss2022-hy2'; do
    grep -Fqx "$row" <<<"$ports" || { echo "FAIL: missing $row"; exit 1; }
done
[[ "$(gfw_diag_socket_status tcp 443)" == LISTEN_NON_LOOPBACK ]]
[[ "$(gfw_diag_socket_status tcp 8443)" == LOOPBACK_ONLY ]]
[[ "$(gfw_diag_socket_status udp 8444)" == NOT_LISTENING ]]
[[ "$(gfw_diag_socket_status udp 7443)" == LISTEN_NON_LOOPBACK ]]
out=$(gfw_diag_local_report)
[[ "$out" == *'本机故障候选'* && "$out" == *'INACTIVE_OR_UNKNOWN'* ]]
[[ "$out" == *'监听正常≠大陆可达'* && "$out" == *'UDP 必须'* ]]
[[ "$out" != *'SECRETSHOULDNOTSHOW'* ]]
# Existing server test menu must be nested and main menu must remain unchanged.
src=$(cat ss2022.sh)
[[ "$src" == *'6) gfw_diagnostics_menu ;;'* ]]
[[ "$src" == *'8) server_test_management ;;'* ]]
echo "PASS: GFW local-only protocol/transport inventory, socket status and menu nesting"
