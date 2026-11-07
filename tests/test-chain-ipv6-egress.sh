#!/usr/bin/env bash
# Regression: Snell inbound family must not silently disable IPv6 chaining.
# SS2022/ShadowTLS (sing-box), VLESS Reality (Xray), HY2 are not Snell:
# their IPv6 second hop depends on destination routing, rules and protocol.
set -euo pipefail
cd "$(dirname "$0")/.."
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh
# shellcheck disable=SC1091
source ./modules/snell-v6.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

MOCK_ROUTE=global
ip() {
    case "$MOCK_ROUTE" in
        global)
            echo "2606:4700:4700::1111 via fe80::1 dev eth0 src 240b:4001:2ab::123 metric 1024"
            ;;
        ula)
            echo "2606:4700:4700::1111 via fe80::1 dev eth0 src fd00::1 metric 1024"
            ;;
        none)
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

[[ "$(snell_ipv6_egress_flag ipv4)" == true ]]
[[ "$(snell_ipv6_egress_flag ipv6)" == true ]]
[[ "$(snell_ipv6_egress_flag dual)" == true ]]

MOCK_ROUTE=none
[[ "$(snell_ipv6_egress_flag ipv4)" == false ]]
[[ "$(snell_ipv6_egress_flag ipv4 true)" == true ]]
[[ "$(snell_ipv6_egress_flag ipv6)" == true ]]
[[ "$(snell_ipv6_egress_flag dual)" == true ]]

MOCK_ROUTE=ula
[[ "$(snell_ipv6_egress_flag ipv4)" == false ]]

MOCK_ROUTE=global
snell6_candidate "$tmp/snell6-v4.conf" ipv4 58889 testpsk
grep -Fxq 'listen = 0.0.0.0:58889' "$tmp/snell6-v4.conf"
grep -Fxq 'ipv6 = true' "$tmp/snell6-v4.conf"

MOCK_ROUTE=none
snell6_candidate "$tmp/snell6-v4only.conf" ipv4 58889 testpsk
grep -Fxq 'ipv6 = false' "$tmp/snell6-v4only.conf"
snell6_candidate "$tmp/snell6-preserved.conf" ipv4 58889 testpsk true
grep -Fxq 'ipv6 = true' "$tmp/snell6-preserved.conf"
snell6_candidate "$tmp/snell6-dual.conf" dual 58889 testpsk
grep -Fxq 'ipv6 = true' "$tmp/snell6-dual.conf"
grep -Fxq 'listen = 0.0.0.0:58889,[::]:58889' "$tmp/snell6-dual.conf"

# Both Snell v5 flows must use the same independent IPv6 egress setting.
[[ $(grep -Fc 'ipv6_flag=$(snell_ipv6_egress_flag' ss2022.sh) -eq 2 ]]
[[ $(grep -Fc 'snell6_candidate "$tmp" "$nnetwork" "$nport" "$npsk" "$current_ipv6"' modules/snell-v6.sh) -eq 1 ]]

# Other cores have no Snell-style ipv6=false switch: never inject one blindly.
grep -Fq '{"type":"direct","tag":"direct"}' ss2022.sh
grep -Fq 'outbounds:[{protocol:"freedom",tag:"direct"}]' ss2022.sh
declare -F chain_ipv6_preflight >/dev/null
[[ $(grep -Fc '5) chain_ipv6_preflight; pause ;;' ss2022.sh) -eq 1 ]]

echo "PASS: Snell v5/v6 IPv4 ingress to IPv6 egress, old config preservation, IPv4-only fallback and all-core read-only audit"
