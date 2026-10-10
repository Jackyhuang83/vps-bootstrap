#!/usr/bin/env bash
# v1.10 dev2 throughput-probe tests: NEVER open sockets or modify kernel routing.
set -euo pipefail
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
NET_TUNE_PROBE_SYSFS="$tmp/sys"
mkdir -p "$NET_TUNE_PROBE_SYSFS/eth0/statistics"
echo 1000 > "$NET_TUNE_PROBE_SYSFS/eth0/statistics/tx_bytes"

# All external network actions are mocked and isolated in this shell.
ip() {
    case "$1" in
        -4)
            [[ "$2" == route && "$3" == get ]] || return 1
            echo "$4 via 203.0.113.1 dev eth0 src 203.0.113.2"
            ;;
        -6)
            [[ "$2" == route && "$3" == get ]] || return 1
            echo "$4 via 2001:db8::1 dev eth0 src 2001:db8::2"
            ;;
        *) return 1 ;;
    esac
}
getent() {
    case "$1" in
        ahostsv4)
            echo '203.0.113.15 STREAM test.example'
            ;;
        ahostsv6)
            echo '2001:db8::15 STREAM test.example'
            ;;
        *) return 1 ;;
    esac
}
# If any code inadvertently mutates the kernel, fail loudly.
tc() { echo "tc unexpectedly invoked" >&2; return 88; }
sysctl() { echo "sysctl unexpectedly invoked" >&2; return 88; }
iperf3() {
    if [[ "${FAKE_PROBE_HANG:-0}" == 1 ]]; then
        while :; do :; done
    elif [[ "${FAKE_PROBE_BAD_JSON:-0}" == 1 ]]; then
        printf '{"error":"server busy"}\n'
    else
        cat <<'JSON'
{"start":{"test_start":{"protocol":"TCP"}},"end":{"sum_sent":{"bits_per_second":10000000,"bytes":3750000,"retransmits":0},"sum_received":{"bits_per_second":9800000,"bytes":3675000}}}
JSON
    fi
}

expect_denied() {
    if "$@" >/dev/null 2>&1; then
        echo "FAIL: unexpected success: $*" >&2
        exit 1
    fi
}
result=$(network_tuning_probe_check 4 test.example 10 3 16)
[[ "$result" == "203.0.113.15|eth0|3750000" ]]
result=$(network_tuning_probe_check 6 test.example 10 3 16)
[[ "$result" == "2001:db8::15|eth0|3750000" ]]
result=$(network_tuning_probe_check 6 2001:db8::15 10 3 16)
[[ "$result" == "2001:db8::15|eth0|3750000" ]]
expect_denied network_tuning_probe_check 4 test.example 101 3 16
expect_denied network_tuning_probe_check 4 test.example 10 21 16
expect_denied network_tuning_probe_check 4 test.example 10 3 1
expect_denied network_tuning_probe_check 4 test.example "010" 3 16
expect_denied network_tuning_probe_check 4 test.example "10;echo bad" 3 16
expect_denied network_tuning_probe_check 6 203.0.113.15 10 3 16
expect_denied network_tuning_probe_check 4 2001:db8::15 10 3 16
expect_denied network_tuning_probe_resolve 6 ::ffff:203.0.113.15
expect_denied network_tuning_probe_resolve 4 "-foo"

# Reject WARP, Docker, loopback, and unsafe interfaces, regardless of family.
for iface in wgcf tun0 docker0 veth123 lo br-abcd tailscale0; do
    expect_denied network_tuning_probe_iface_guard "$iface" "route dev $iface"
done
network_tuning_probe_iface_guard eth0 "203.0.113.15 via 203.0.113.1 dev eth0"

# Normal flow reads fake iperf3 JSON and succeeds under the interface budget.
out=$(printf 'RUN\n' | network_tuning_probe_run 4 test.example 5201 10 3 16)
grep -Fq '10Mbps' <<< "$out"
grep -Fq '9.8Mbps' <<< "$out"
grep -Fq '安全测速完成' <<< "$out"
[[ "$(cat "$NET_TUNE_PROBE_SYSFS/eth0/statistics/tx_bytes")" == 1000 ]]

# Explicit confirmation is mandatory; random "y" is not enough.
out=$(printf 'y\n' | network_tuning_probe_run 4 test.example 5201 10 3 16)
grep -Fq '已取消' <<< "$out"

FAKE_PROBE_BAD_JSON=1
export FAKE_PROBE_BAD_JSON
if printf 'RUN\n' | network_tuning_probe_run 4 test.example 5201 10 3 16 >/dev/null 2>&1; then
    echo "FAIL: accepted iperf3 JSON error" >&2
    exit 1
fi
unset FAKE_PROBE_BAD_JSON

# In-run budget enforcement: mock NIC counter leaps above limit while
# a fake iperf3 loop is active, and independent watchdog must end test.
FAKE_PROBE_HANG=1
export FAKE_PROBE_HANG
(
    sleep 0.5
    printf '50000000\n' > "$NET_TUNE_PROBE_SYSFS/eth0/statistics/tx_bytes"
) &
counter_writer=$!
if printf 'RUN\n' | network_tuning_probe_run 4 test.example 5201 10 3 16 >/dev/null 2>&1; then
    echo "FAIL: watchdog allowed an over-budget test" >&2
    exit 1
fi
wait "$counter_writer"
unset FAKE_PROBE_HANG

# No function in the new feature may accidentally invoke mutation commands.
for fn in network_tuning_probe_check network_tuning_probe_run network_tuning_probe_watchdog; do
    body=$(declare -f "$fn")
    if grep -Eq 'tc qdisc (add|replace|del)|sysctl -w|ip route (replace|del)' <<< "$body"; then
        echo "FAIL: mutating command found in $fn" >&2
        exit 1
    fi
done

# Line VPS presets are intentionally discrete: no auto tuning >= 1Gbps.
for tier in 10 20 30 100 200 300 500; do
    spec=$(network_tuning_profile "$tier")
    read -r package first coarse fine duration <<< "$spec"
    [[ "$package" == "$tier" ]]
    [[ "$first" -lt "$tier" && "$coarse" -gt "$fine" && "$fine" -gt 0 ]]
    [[ "$duration" -ge 3 && "$duration" -le 20 ]]
    ceiling=$(network_tuning_profile_upper_kbps "$tier")
    [[ "$ceiling" -ge $((tier * 1000)) && "$ceiling" -le 500000 ]]
    preview=$(network_tuning_profile_print "$tier")
    [[ "$preview" == *"策略预览"* ]]
done
for rejected in 0 1 9 15 25 50 90 150 250 400 501 999 1000 10000 '-1' '10;id'; do
    expect_denied network_tuning_profile "$rejected"
    expect_denied network_tuning_profile_upper_kbps "$rejected"
done
[[ "$NET_TUNE_SUPPORTED_MAX_MBPS" == 500 ]]
[[ "$(network_tuning_profile_upper_kbps 500)" == 500000 ]]
[[ "$(network_tuning_profile_upper_kbps 30)" == 36000 ]]
[[ "$(network_tuning_profile_upper_kbps 300)" == 360000 ]]

echo "Network tuning dev2 throughput smoke passed."
