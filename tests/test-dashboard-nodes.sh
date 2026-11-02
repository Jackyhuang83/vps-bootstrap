#!/usr/bin/env bash
# Only render dashboard with fixture data; no real services or network changes.
set -euo pipefail
cd "$(dirname "$0")/.."
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

SINGBOX_CONF="$tmp/sing-box.json"
XRAY_CONF="$tmp/xray.json"
SNELL_CONF="$tmp/snell.conf"
SINGBOX_BIN="$tmp/sing-box"
XRAY_BIN="$tmp/xray"
SNELL_BIN="$tmp/snell"
REALM_BIN="$tmp/realm"
FORWARDING_FILE="$tmp/forwarding.json"
RED="" GREEN="" YELLOW="" CYAN="" PLAIN=""
ACTIVE_SB=0 ACTIVE_XR=0 ACTIVE_SN=0 ACTIVE_REALM=0

clear() { :; }
get_sys_info() { echo fixture; }
get_singbox_version() { if [[ -x "$SINGBOX_BIN" ]]; then echo "Sing-box test"; else echo "Sing-box 未安装"; fi; }
get_xray_version() { if [[ -x "$XRAY_BIN" ]]; then echo "Xray 26.3.27"; else echo "Xray 未安装"; fi; }
get_snell_version() { if [[ -x "$SNELL_BIN" ]]; then echo "Snell v5.0.1"; else echo "Snell 未安装"; fi; }
get_time_sync_status() { echo "时间正常"; }
platform_label() { echo "test-platform"; }
proxy_shortcut_is_project_managed() { return 1; }
service_exists() { return 0; }
service_is_active() {
    case "$1" in
        sing-box) [[ "$ACTIVE_SB" == 1 ]] ;;
        "$XRAY_SERVICE_NAME") [[ "$ACTIVE_XR" == 1 ]] ;;
        snell-v5) [[ "$ACTIVE_SN" == 1 ]] ;;
        "$REALM_SERVICE_NAME") [[ "$ACTIVE_REALM" == 1 ]] ;;
        *) return 1 ;;
    esac
}
check_contains() {
    if [[ "$1" != *"$2"* ]]; then
        printf 'FAIL: expected [%s] in dashboard:\n%s\n' "$2" "$1" >&2
        exit 1
    fi
}
render() {
    # Existing installed_count++ expressions start from zero and must not cause
    # fixture tests to stop under errexit.
    local rendered
    rendered=$(show_dashboard) || { echo "FAIL: dashboard call" >&2; return 1; }
    printf '%s\n' "$rendered"
}

# Neither installed binary nor configured node.
out=$(render)
check_contains "$out" "SS2022 未部署；ShadowTLS v3 未部署"
check_contains "$out" "VLESS Reality 未部署"
check_contains "$out" "Snell v5 未部署"
check_contains "$out" "活跃协议: 未配置"

# Installed binary without a node is NOT the same as a stopped service.
touch "$SINGBOX_BIN" "$XRAY_BIN" "$SNELL_BIN"
chmod 755 "$SINGBOX_BIN" "$XRAY_BIN" "$SNELL_BIN"
out=$(render)
check_contains "$out" "sing-box: Sing-box test / ○ 仅安装核心"
check_contains "$out" "Xray核心: Xray 26.3.27 / ○ 仅安装核心"
check_contains "$out" "Snell核心: Snell v5.0.1 / ○ 仅安装核心"

# User's reported case: SS2022 is configured, Xray is engine-only, Snell absent.
rm -f "$SNELL_BIN"
jq -n --arg ss "$TAG_SS" '{inbounds:[{tag:$ss,listen_port:585}]}' > "$SINGBOX_CONF"
ACTIVE_SB=1
out=$(render)
check_contains "$out" "节点: SS2022 已部署 (端口 585)；ShadowTLS v3 未部署"
check_contains "$out" "节点: VLESS Reality 未部署"
check_contains "$out" "节点: Snell v5 未部署"
check_contains "$out" "活跃协议: 已部署 (1个)"

# All configured cores, including optional ShadowTLS UDP, show own ports.
jq -n --arg ss "$TAG_SS" --arg stls "$TAG_STLS" --arg udp "$TAG_STLS_UDP"     '{inbounds:[{tag:$ss,listen_port:585},{tag:$stls,listen_port:8443},{tag:$udp,listen_port:8444}]}' > "$SINGBOX_CONF"
jq -n '{inbounds:[{tag:"vless-reality-in",protocol:"vless",port:9443}]}' > "$XRAY_CONF"
printf 'listen = [::]:7555\n' > "$SNELL_CONF"
touch "$SNELL_BIN"
chmod 755 "$SNELL_BIN"
ACTIVE_XR=1 ACTIVE_SN=1
out=$(render)
check_contains "$out" "节点: SS2022 已部署 (端口 585)；ShadowTLS v3 已部署 (TCP 8443) / UDP 8444"
check_contains "$out" "节点: VLESS Reality 已部署 (端口 9443)"
check_contains "$out" "节点: Snell v5 已部署 (端口 7555)"
check_contains "$out" "活跃协议: 已部署 (4个)"

# Legacy sing-box VLESS must not be attributed to the Xray core.
rm -f "$XRAY_CONF"
jq -n --arg old "$TAG_VLESS" '{inbounds:[{tag:$old,listen_port:7443}]}' > "$SINGBOX_CONF"
out=$(render)
check_contains "$out" "节点: VLESS Reality 未部署（旧 sing-box 仍有 VLESS，待迁移）"
# Realm output exposes build feature tags which must not appear on the homepage.
cat > "$REALM_BIN" <<'REALM_MOCK'
#!/bin/sh
echo 'Realm 2.9.6 [brutal][batched-udp][proxy][balance][transport][multi-thread]'
REALM_MOCK
chmod 755 "$REALM_BIN"
printf '%s\n' '{"rules":[{"listen":"0.0.0.0:9999","remote":"127.0.0.1:9999"}]}' > "$FORWARDING_FILE"
ACTIVE_REALM=1
out=$(render)
check_contains "$out" "Realm转发: Realm 2.9.6 / ● 运行中 / 规则 1 条"
if [[ "$out" == *"[brutal]"* || "$out" == *"[balance]"* || "$out" == *"[multi-thread]"* ]]; then
    echo "FAIL: Realm feature flags leaked into dashboard" >&2
    exit 1
fi

# Version probe failure remains safe and does not leak flags or break the menu.
printf '#!/bin/sh\nexit 1\n' > "$REALM_BIN"
chmod 755 "$REALM_BIN"
out=$(render)
check_contains "$out" "Realm转发: Realm 已安装（版本未知） / ● 运行中 / 规则 1 条"

echo "PASS: per-core protocol deployment and concise Realm dashboard states"
