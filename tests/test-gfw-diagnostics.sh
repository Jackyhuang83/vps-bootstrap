#!/usr/bin/env bash
# GFW diagnostics must never confuse local listeners with cross-border reachability.
set -euo pipefail
cd "$(dirname "$0")/.."
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
SINGBOX_CONF="$tmp/sing-box.json"
XRAY_CONF="$tmp/xray.json"
SNELL_CONF="$tmp/snell-v5.conf"
SNELL6_CONF="$tmp/snell-v6.conf"
HY2_CONF="$tmp/hy2.json"
HY2_MANAGED_MARKER="$tmp/hy2-managed"
RED="" GREEN="" YELLOW="" CYAN="" PLAIN=""
jq -n --arg ss "$TAG_SS" --arg stls "$TAG_STLS" --arg udp "$TAG_STLS_UDP" \
    '{inbounds:[
       {tag:$ss,type:"shadowsocks",listen_port:41001},
       {tag:$stls,type:"shadowtls",listen_port:41002},
       {tag:$udp,type:"shadowsocks",network:"udp",listen_port:41003}
    ]}' > "$SINGBOX_CONF"
jq -n '{inbounds:[{tag:"vless-reality-in",protocol:"vless",port:41004}]}' > "$XRAY_CONF"
printf 'listen = 0.0.0.0:41005\n' > "$SNELL_CONF"
printf 'listen = [::]:41006\n' > "$SNELL6_CONF"
jq -n '{listen:":41007"}' > "$HY2_CONF"
touch "$HY2_MANAGED_MARKER"

ss() {
    case "$*" in
        "-H -ltn")
            printf '%s\n' \
                "LISTEN 0 128 0.0.0.0:41001 0.0.0.0:*" \
                "LISTEN 0 128 127.0.0.1:41002 0.0.0.0:*" \
                "LISTEN 0 128 [::]:41004 [::]:*" \
                "LISTEN 0 128 0.0.0.0:41005 0.0.0.0:*" \
                "LISTEN 0 128 [::]:41006 [::]:*"
            ;;
        "-H -lun")
            printf '%s\n' \
                "UNCONN 0 0 0.0.0.0:41001 0.0.0.0:*" \
                "UNCONN 0 0 [::]:41007 [::]:*"
            ;;
        *) return 2 ;;
    esac
}
service_is_active() { [[ "$1" != "snell-v5" ]]; }
get_inbound_ipv4() { printf '11.22.33.44'; }

found=$(gfw_diag_ports)
for row in \
    "SS2022|TCP|41001|sing-box" \
    "SS2022|UDP|41001|sing-box" \
    "ShadowTLS v3|TCP|41002|sing-box" \
    "ShadowTLS UDP|UDP|41003|sing-box" \
    "VLESS Reality|TCP|41004|ss2022-xray" \
    "Snell v5|TCP|41005|snell-v5" \
    "Snell v6|TCP|41006|snell-v6" \
    "Hysteria 2|UDP|41007|ss2022-hy2"; do
    grep -Fqx "$row" <<<"$found" || { echo "FAIL: missing $row"; exit 1; }
done
[[ "$(printf '%s\n' "$found" | wc -l)" -eq 8 ]]
[[ "$(gfw_diag_listener_status TCP 41001)" == BOUND ]]
[[ "$(gfw_diag_listener_status TCP 41002)" == LOOPBACK ]]
[[ "$(gfw_diag_listener_status UDP 41003)" == NOT_LISTENING ]]
[[ "$(gfw_diag_listener_status UDP 41007)" == BOUND ]]

out=$(gfw_diag_local)
[[ "$out" == *"公网入口 IPv4 候选: 11.22.33.44"* ]]
[[ "$out" == *"SS2022"* && "$out" == *"VLESS Reality"* && "$out" == *"Hysteria 2"* ]]
[[ "$out" == *"优先排查服务/监听"* && "$out" == *"公网客户端无法直连"* ]]
[[ "$out" == *"UDP 端口有监听 ≠ UDP 双向可达"* ]]
[[ "$out" != *"GFW_BLOCKED"* ]]

rm -f "$SNELL_CONF" "$SNELL6_CONF" "$HY2_CONF" "$HY2_MANAGED_MARKER" "$XRAY_CONF" "$SINGBOX_CONF"
out=$(gfw_diag_local)
[[ "$out" == *"未找到本工具箱管理的已部署协议"* ]]
echo "PASS: TCP/UDP installed protocol discovery, listening, and conservative reporting"
