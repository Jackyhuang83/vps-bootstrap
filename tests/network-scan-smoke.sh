#!/usr/bin/env bash
# v1.10-dev5: full collector regression. No real network traffic.
set -euo pipefail
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
NET_TUNE_DIR="$tmp/private"
NET_TUNE_PROBE_SYSFS="$tmp/net"
mkdir -p "$NET_TUNE_DIR" "$NET_TUNE_PROBE_SYSFS/eth0/statistics"
chmod 700 "$NET_TUNE_DIR"
printf '1000\n' > "$NET_TUNE_PROBE_SYSFS/eth0/statistics/tx_bytes"
ip() {
    [[ "$1" == -4 || "$1" == -6 ]] || return 1
    echo "$4 via 203.0.113.1 dev eth0 src 203.0.113.2"
}
getent() { echo '203.0.113.15 STREAM test.example'; }
tc() {
    case "$1" in
        qdisc) echo "qdisc fq_codel 0: root refcnt 2" ;;
        class|filter) : ;;
        *) return 1 ;;
    esac
}
ping() { echo "ERROR: unexpected ping" >&2; return 1; }
iperf3() { echo "ERROR: unexpected iperf3" >&2; return 1; }
sysctl() { echo "ERROR: unexpected sysctl" >&2; return 1; }
sleep() { :; }
network_tuning_qoe_ping() {
    local n="$3" rtt=20 j
    if [[ "$n" == "$NET_TUNE_QOE_LOADED_COUNT" ]]; then
        rtt=40
        [[ "$rate" != 30 ]] || rtt=240
    fi
    for ((j=1;j<=n;j++)); do
        printf '64 bytes from 203.0.113.15: icmp_seq=%s ttl=55 time=%s.00 ms\n' "$j" "$rtt"
    done
}
network_tuning_probe_run() {
    local rate="$4" path="$7" received
    [[ "$rate" =~ ^(12|24|30)$ ]] || return 1
    [[ "${FAKE_SCAN_FAILURE:-}" != "$rate" ]] || return 1
    received=$(awk -v r="$rate" 'BEGIN {if(r==30) print "24.3"; else print r*0.985}')
    jq -nc --argjson sent "$rate" --argjson got "$received" \
        '{sender_mbps:$sent,received_mbps:$got,retransmits:(if $sent==30 then 12 else 1 end)}' > "$path"
}
expect_denied() { if "$@" >/dev/null 2>&1; then echo "FAIL accepted: $*" >&2; exit 1; fi; }
for tier in 10 20 30 100 200 300 500; do
    plan=$(network_tuning_scan_plan "$tier")
    [[ "$(jq -r '.rate_mbps|length' <<< "$plan")" == 3 ]]
    [[ "$(jq -r '.auto_apply' <<< "$plan")" == false ]]
    [[ "$(jq -r '.rate_mbps[2]' <<< "$plan")" == "$tier" ]]
    [[ "$(jq -r '.aggregate_budget_mib<=.aggregate_cap_mib' <<< "$plan")" == true ]]
    [[ "$(jq -r '.budget_mib|max' <<< "$plan")" -le 768 ]]
done
[[ "$(jq -r '.rate_mbps|join(",")' <<< "$(network_tuning_scan_plan 30)")" == "12,24,30" ]]
expect_denied network_tuning_scan_plan 1000
expect_denied network_tuning_scan_plan 501
expect_denied network_tuning_scan_plan '30;id'
cancel=$(printf 'n\n' | network_tuning_scan_run 30 4 test.example 5201)
grep -Fq '已取消' <<< "$cancel"
[[ "$(find "$NET_TUNE_DIR" -name 'scan-*.json' | wc -l)" -eq 0 ]]
out=$(printf 'RUN\n' | network_tuning_scan_run 30 4 test.example 5201)
grep -Fq '只读判定：candidate_for_validation' <<< "$out"
[[ "$(find "$NET_TUNE_DIR" -name 'scan-*.json' | wc -l)" -eq 1 ]]
report=$(find "$NET_TUNE_DIR" -name 'scan-*.json' | head -n1)
[[ "$(stat -c %a "$report")" == 600 ]]
[[ "$(jq -r '.samples|length' "$report")" == 6 ]]
[[ "$(jq -r '.samples[5].loaded_p95_ms' "$report")" == 240 ]]
[[ "$(network_tuning_candidate_assess 30 "$report" | jq -r .candidate_kbps)" == 22800 ]]
FAKE_SCAN_FAILURE=24
export FAKE_SCAN_FAILURE
if printf 'RUN\n' | network_tuning_scan_run 30 4 test.example 5201 >/dev/null 2>&1; then
    echo "FAIL: accepted missing sample" >&2; exit 1
fi
[[ "$(find "$NET_TUNE_DIR" -name 'scan-*.json' | wc -l)" -eq 1 ]]
for fn in network_tuning_scan_plan network_tuning_scan_run network_tuning_scan_menu; do
    if declare -f "$fn" | grep -Eq 'tc qdisc (add|replace|del)|sysctl -w|ip route (replace|del)'; then
        echo "FAIL: prohibited mutation in $fn" >&2; exit 1
    fi
done
echo "Network tuning dev5 scan smoke passed."
