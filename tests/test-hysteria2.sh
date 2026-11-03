#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh
# shellcheck disable=SC1091
source ./modules/hysteria2.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
HY2_BIN="$tmp/hysteria"
HY2_CONF_DIR="$tmp/hy2"
HY2_CONF="$HY2_CONF_DIR/config.json"
HY2_SERVICE="$tmp/hy2.service"
HY2_MANAGED_MARKER="$tmp/managed"
mkdir -p "$HY2_CONF_DIR"
PLATFORM_INIT=systemd
platform_is_alpine() { return 1; }
service_is_active() { return 1; }
service_restart() { return 1; }
touch "$HY2_BIN"
if hy2_ownership >/dev/null 2>&1; then
    echo "FAIL: overwrote externally owned HY2 binary"; exit 1
fi
rm -f "$HY2_BIN"
hy2_ownership
touch "$HY2_MANAGED_MARKER"
hy2_ownership

hy2_validate_domain 'hy2.example.com'
hy2_validate_domain 'a-b.example.com'
if hy2_validate_domain '127.0.0.1' || hy2_validate_domain 'example..com' ||
   hy2_validate_domain 'bad domain.com' || hy2_validate_domain '-foo.example.com'; then
    echo "FAIL: unsafe/invalid domain accepted"; exit 1
fi
[[ "$(hy2_listen ipv4 34443)" == '0.0.0.0:34443' ]]
[[ "$(hy2_listen ipv6 34443)" == '[::]:34443' ]]
[[ "$(hy2_listen dual 34443)" == ':34443' ]]
if hy2_listen dual 65536 >/dev/null 2>&1; then
    echo "FAIL: invalid port accepted"; exit 1
fi

hy2_candidate "$tmp/v4.json" ipv4 34443 hy2.example.com "0123456789abcdef0123456789abcdef"
jq -e '.listen=="0.0.0.0:34443" and .auth.type=="password" and
  .acme.type=="http" and .masquerade.type=="proxy" and
  (.tls|not) and (.obfs|not)' "$tmp/v4.json" >/dev/null
hy2_candidate "$tmp/v6.json" ipv6 34443 hy2.example.com "0123456789abcdef0123456789abcdef"
jq -e '.listen=="[::]:34443"' "$tmp/v6.json" >/dev/null
hy2_candidate "$tmp/dual.json" dual 34443 hy2.example.com "0123456789abcdef0123456789abcdef"
jq -e '.listen==":34443"' "$tmp/dual.json" >/dev/null

for fn in deploy_hy2 update_hy2 delete_hy2 view_hy2_config hy2_apply; do
    declare -F "$fn" >/dev/null || { echo "FAIL: missing function $fn"; exit 1; }
done
if grep -Eq '(^|[[:space:]])(select_network_mode|setup_keepalive|disable_keepalive_for_ipv4)([[:space:]]|$)' modules/hysteria2.sh; then
    echo "FAIL: HY2 module changes global network or keepalive"; exit 1
fi
if grep -Eq 'skip-cert-verify=true|insecure[[:space:]]*:[[:space:]]*true' modules/hysteria2.sh; then
    echo "FAIL: unsafe TLS verification"; exit 1
fi
echo "PASS: HY2 ownership, IPv4/IPv6/dual JSON configs, independent service"
