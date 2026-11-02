#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh
# shellcheck disable=SC1091
source ./modules/snell-v6.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
SNELL6_CONF="$tmp/config.conf"
SNELL6_BIN="$tmp/snell-v6"
SNELL6_SERVICE="$tmp/snell-v6.service"
SNELL6_CONF_DIR="$tmp/conf-dir"
SNELL6_MANAGED_MARKER="$tmp/managed"
SNELL_CONF="$tmp/v5.conf"
SINGBOX_CONF="$tmp/sing.json"
XRAY_CONF="$tmp/xray.json"
PLATFORM_INIT=systemd
platform_is_alpine() { return 1; }
port_in_use_by_other_process() { return 1; }
service_is_active() { return 1; }
snell6_ownership
touch "$SNELL6_BIN"
if snell6_ownership >/dev/null 2>&1; then
    echo "FAIL: unmanaged Snell v6 binary overwritten"; exit 1
fi
rm -f "$SNELL6_BIN"

snell6_choose_network <<<"3" >/dev/null
[[ "$SNELL6_SELECTED_NETWORK" == dual ]]
snell6_choose_network <<<"2" >/dev/null
[[ "$SNELL6_SELECTED_NETWORK" == ipv6 ]]
if grep -Eq '(^|[[:space:]])(select_network_mode|setup_keepalive|disable_keepalive_for_ipv4)([[:space:]]|$)' modules/snell-v6.sh; then
    echo "FAIL: Snell v6 module changes global network/keepalive"; exit 1
fi
snell6_candidate "$tmp/dual.conf" dual 64444 0123456789abcdef0123456789abcdef
grep -q '^listen = 0.0.0.0:64444,\[::\]:64444$' "$tmp/dual.conf"
grep -q '^mode = default$' "$tmp/dual.conf"
grep -q '^version = 6$' "$tmp/dual.conf"
grep -q '^ipv6 = true$' "$tmp/dual.conf"
grep -q '^dns-ip-preference = default$' "$tmp/dual.conf"
if grep -Eq '^mode = (unsafe-raw|unshaped)$' "$tmp/dual.conf"; then
    echo "FAIL: unsafe wire mode"; exit 1
fi
snell6_candidate "$tmp/ipv4.conf" ipv4 64444 testkey
grep -q '^listen = 0.0.0.0:64444$' "$tmp/ipv4.conf"
snell6_candidate "$tmp/ipv6.conf" ipv6 64444 testkey
grep -q '^listen = \[::\]:64444$' "$tmp/ipv6.conf"

printf 'listen = 0.0.0.0:6888\n' > "$SNELL_CONF"
if snell6_port_free 6888 >/dev/null 2>&1; then
    echo "FAIL: v5 reserved port accepted"; exit 1
fi
snell6_port_free 6999

# Source-only module must never modify live services by itself.
for fn in deploy_snell_v6 update_snell_v6 delete_snell_v6 view_snell_v6_config; do
    declare -F "$fn" >/dev/null || { echo "FAIL: missing $fn"; exit 1; }
done
echo "PASS: Snell v6 module isolation, listen modes, safety guards"
