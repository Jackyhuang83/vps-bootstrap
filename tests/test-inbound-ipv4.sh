#!/usr/bin/env bash
# Reproduce WARP/SNAT address divergence without network access or service changes.
set -euo pipefail
cd "$(dirname "$0")/.."
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh

RED="" GREEN="" YELLOW="" CYAN="" PLAIN=""
TEST_SCENARIO=direct
ip() {
    [[ "$*" == "-o -4 addr show scope global" ]] || return 2
    case "$TEST_SCENARIO" in
        direct|warp)
            cat <<'ADDR'
2: eth0    inet 11.22.33.44/24 brd 11.22.33.255 scope global eth0
3: wgcf    inet 172.16.0.2/32 scope global wgcf
4: docker0 inet 172.17.0.1/16 scope global docker0
5: tun0    inet 9.9.9.9/32 scope global tun0
ADDR
            ;;
        nat)
            printf '%s\n' '2: ens3 inet 10.10.0.5/24 scope global ens3'
            ;;
        multi)
            printf '%s\n' '2: eth0 inet 11.22.33.44/24 scope global eth0' \
                '3: eth1 inet 13.14.15.16/24 scope global eth1'
            ;;
    esac
}
# Simulate WARP public egress differing from the reachable native VPS entry.
get_public_ipv4() { printf '104.16.0.9'; }
curl() { printf 'loc=US\n'; }

assert_eq() {
    if [[ "$1" != "$2" ]]; then
        printf 'FAIL: %s expected <%s> got <%s>\n' "$3" "$2" "$1" >&2
        exit 1
    fi
}
for bad in 10.0.0.1 172.16.7.8 192.168.1.1 100.64.1.1 \
           127.0.0.1 169.254.1.1 198.18.0.1 203.0.113.4 224.0.0.1; do
    if ipv4_is_public_unicast "$bad"; then echo "FAIL: nonpublic $bad accepted"; exit 1; fi
done
ipv4_is_public_unicast 11.22.33.44
ipv4_is_public_unicast 172.32.5.6

TEST_SCENARIO=warp
assert_eq "$(get_inbound_ipv4)" "11.22.33.44" "WARP entry address"
NETWORK_MODE=ipv4
SERVER_HOST=""
SERVER_HOST_V4=""
ask_server_host <<<"" >/dev/null
assert_eq "$SERVER_HOST" "11.22.33.44" "node default must be native IPv4"
assert_eq "$SERVER_HOST_V4" "11.22.33.44" "saved node IPv4 candidate"
[[ "$SERVER_HOST" != "$(get_public_ipv4)" ]]
warn=$(warn_ingress_ipv4_mismatch "104.16.0.9")
[[ "$warn" == *"请核对"* && "$warn" == *"11.22.33.44"* ]] || {
    echo "FAIL: stored WARP egress not warned"; exit 1
}
out=$(server_test_exit_info ipv4)
[[ "$out" == *"出口 IP"* && "$out" == *"104.16.0.9"* ]] || {
    echo "FAIL: outbound IP semantics changed"; exit 1
}

TEST_SCENARIO=nat
if get_inbound_ipv4 >/dev/null; then echo "FAIL: NAT entry guessed from egress"; exit 1; fi
SERVER_HOST=""
ask_server_host <<<'12.13.14.15' >/dev/null
assert_eq "$SERVER_HOST" "12.13.14.15" "manual cloud NAT entry"

TEST_SCENARIO=nat
NETWORK_MODE=dual
get_public_ipv6() { printf '2001:db8::12'; }
SERVER_HOST=""
SERVER_HOST_V4=""
ask_server_host <<<'12.13.14.15' >/dev/null
assert_eq "$SERVER_HOST_V4" "12.13.14.15" "manual NAT entry saved for dual-stack export"
assert_eq "$SERVER_HOST_V6" "2001:db8::12" "dual-stack IPv6 field preserved"

TEST_SCENARIO=multi
if get_inbound_ipv4 >/dev/null; then echo "FAIL: arbitrary address chosen on multi-IP VPS"; exit 1; fi
SERVER_HOST=""
ask_server_host <<<'12.13.14.15' >/dev/null
assert_eq "$SERVER_HOST" "12.13.14.15" "manual multi-address entry"

TEST_SCENARIO=none
if get_inbound_ipv4 >/dev/null; then echo "FAIL: empty interface detected"; exit 1; fi

echo "PASS: public ingress, WARP egress, cloud NAT, multi-IP and saved host warnings"
