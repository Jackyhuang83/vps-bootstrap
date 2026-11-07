#!/usr/bin/env bash
# Regression: an IPv4 proxy entry on a dual-stack VPS must still reach IPv6 destinations.
set -euo pipefail
cd "$(dirname "$0")/.."
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh
# shellcheck disable=SC1091
source ./modules/snell-v6.sh
# shellcheck disable=SC1091
source ./modules/hysteria2.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

ip() {
    [[ "$*" == "-6 route get 2606:4700:4700::1111" ]] || return 2
    [[ "${IP_ROUTE:-}" == FAIL ]] && return 2
    printf '%s\n' "${IP_ROUTE:-}"
}

expect_ipv6() {
    local title="$1" expected="$2" ingress="$3" old="$4" actual
    actual=$(snell_ipv6_egress_flag "$ingress" "$old")
    [[ "$actual" == "$expected" ]] || {
        echo "FAIL: $title expected=$expected actual=$actual"
        exit 1
    }
}

# 1. Snell v5/v6 share the same route-aware IPv6 egress policy.
IP_ROUTE='2606:4700:4700::1111 via fe80::1 dev eth0 src 240b:4001:2ab::1'
expect_ipv6 "IPv4 listen with dual-stack IPv6 egress" true ipv4 false
expect_ipv6 "IPv6 listen" true ipv6 false
IP_ROUTE=FAIL
expect_ipv6 "IPv4-only host stays IPv4" false ipv4 false
expect_ipv6 "keep previously enabled IPv6 when route temporarily down" true ipv4 true
expect_ipv6 "IPv6 listening remains enabled" true ipv6 false
IP_ROUTE='2606:4700:4700::1111 dev eth0 src fe80::1234'
expect_ipv6 "reject link-local source" false ipv4 false
IP_ROUTE='2606:4700:4700::1111 dev eth0 src fd00::a'
expect_ipv6 "reject ULA source" false ipv4 false
IP_ROUTE='unreachable 2606:4700:4700::1111 dev lo src 240b:4001::1'
expect_ipv6 "reject unreachable route" false ipv4 false
IP_ROUTE='2606:4700:4700::1111 via fe80::1 dev eth0 src 240b:4001::1'

snell6_candidate "$tmp/sn-v6-v4.conf" ipv4 58889 dummy
grep -Fqx 'listen = 0.0.0.0:58889' "$tmp/sn-v6-v4.conf"
grep -Fqx 'ipv6 = true' "$tmp/sn-v6-v4.conf"
snell6_candidate "$tmp/sn-v6-v6.conf" ipv6 58889 dummy
grep -Fqx 'ipv6 = true' "$tmp/sn-v6-v6.conf"

IP_ROUTE=FAIL
snell6_candidate "$tmp/sn-v6-ipv4-only.conf" ipv4 58889 dummy
grep -Fqx 'ipv6 = false' "$tmp/sn-v6-ipv4-only.conf"
snell6_candidate "$tmp/sn-v6-persist.conf" ipv4 58889 dummy true
grep -Fqx 'ipv6 = true' "$tmp/sn-v6-persist.conf"
IP_ROUTE='2606:4700:4700::1111 via fe80::1 dev eth0 src 240b:4001::1'

# 2. SS2022 / ShadowTLS: sing-box direct is dual-stack by default, independent of inbound listen.
SINGBOX_CONF="$tmp/singbox.json"
SINGBOX_BIN=/bin/true
STATE_DIR="$tmp/state"
ROUTING_FILE="$STATE_DIR/routing.json"
mkdir -p "$STATE_DIR"
cat > "$SINGBOX_CONF" <<'JSON'
{"log":{"level":"warn"},"dns":{"servers":[]},"inbounds":[
{"type":"shadowsocks","tag":"ss-in","listen":"0.0.0.0","listen_port":58889,
 "method":"2022-blake3-aes-128-gcm","password":"unit-test"}
],"outbounds":[{"type":"direct","tag":"direct"}],"route":{"final":"direct"}}
JSON
build_singbox_routing_candidate "$tmp/singbox-result.json"
jq -e '
  any(.inbounds[]; .tag=="ss-in" and .listen=="0.0.0.0") and
  any(.outbounds[]; .tag=="direct" and .type=="direct" and
    ((.inet4_bind_address // "") == "") and ((.bind_interface // "") == "")) and
  .route.final == "direct"
' "$tmp/singbox-result.json" >/dev/null

# 3. VLESS / Xray: default freedom does not force IPv4 and handles IPv6 literals.
xray_direct_outbound route-direct default |
    jq -e '.protocol=="freedom" and .settings.domainStrategy=="AsIs" and
           (.sendThrough // "") == ""' >/dev/null
xray_direct_outbound route-direct-v6 ipv6 |
    jq -e '.protocol=="freedom" and .settings.domainStrategy=="UseIPv6"' >/dev/null

# 4. HY2: default direct mode is auto (dual-stack per official documentation).
HY2_CONF_DIR="$tmp/hy2"
hy2_candidate "$tmp/hy2.json" ipv4 34443 hy2.example.com '0123456789abcdef0123456789abcdef'
jq -e '.listen=="0.0.0.0:34443" and
       ((.outbounds // []) | length)==0' "$tmp/hy2.json" >/dev/null

# 5. Read-only audit must warn for broken Snell and must not mutate any config.
SNELL_CONF="$tmp/snell-v5.conf"
SNELL6_CONF="$tmp/snell-v6.conf"
cp "$tmp/sn-v6-v4.conf" "$SNELL6_CONF"
printf '[snell-server]\nlisten = 0.0.0.0:58889\nipv6 = false\n' > "$SNELL_CONF"
XRAY_CONF="$tmp/unused-xray.json"
HY2_CONF="$tmp/hy2.json"
audit=$(test_proxy_ipv6_egress <<<"")
grep -Fq 'WARN: Snell v5 ipv6=false' <<<"$audit"
grep -Fq 'PASS: Snell v6 IPv6 出站已启用' <<<"$audit"
grep -Fq 'PASS: sing-box direct 出站存在' <<<"$audit"
grep -Fq 'PASS: HY2 未发现强制 IPv4' <<<"$audit"

echo "PASS: Snell v5/v6 ingress-egress separation; SS2022/ShadowTLS, Xray, HY2 dual-stack defaults; read-only audit"
