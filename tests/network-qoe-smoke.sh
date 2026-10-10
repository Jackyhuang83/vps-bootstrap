#!/usr/bin/env bash
# v1.10-dev3 deterministic QoE regression (no real ICMP or TCP traffic).
set -euo pipefail
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
NET_TUNE_PROBE_SYSFS="$tmp/net"
mkdir -p "$NET_TUNE_PROBE_SYSFS/eth0/statistics"
printf '1000\n' > "$NET_TUNE_PROBE_SYSFS/eth0/statistics/tx_bytes"
ip() {
    [[ "$1" == -4 || "$1" == -6 ]] || return 1
    echo "$4 via 203.0.113.1 dev eth0 src 203.0.113.2"
}
getent() { echo '203.0.113.15 STREAM test.example'; }
tc() { echo "Unexpected tc call" >&2; return 1; }
sysctl() { echo "Unexpected sysctl call" >&2; return 1; }
ping() {
    local count="${4:-0}" rtt=20 i=1
    [[ "$count" == 6 || "$count" == 12 ]] || return 1
    [[ "$count" == 12 ]] && rtt=160
    for ((i=1;i<=count;i++)); do
        printf '64 bytes from 203.0.113.15: icmp_seq=%d ttl=55 time=%.2f ms\n' "$i" "$rtt"
    done
}
iperf3() {
    cat <<'JSON'
{"start":{"test_start":{"protocol":"TCP"}},"end":{"sum_sent":{"bits_per_second":10000000,"bytes":10000000,"retransmits":1},"sum_received":{"bits_per_second":9800000,"bytes":9800000}}}
JSON
}
mk_round() {
    local filename="$1" count="$2" ms="$3" i
    : > "$filename"
    for ((i=0;i<count;i++)); do printf '%s\n' "$ms" >> "$filename"; done
}
printf '%s\n' '{"sender_mbps":10,"received_mbps":9.8,"retransmits":1}' > "$tmp/probe.json"
mk_round "$tmp/idle" 6 20
mk_round "$tmp/loaded" 12 165
qoe=$(network_tuning_qoe_evaluate "$tmp/idle" "$tmp/loaded" "$tmp/probe.json")
[[ "$(jq -r '.verdict' <<< "$qoe")" == "possible_queueing" ]]
[[ "$(jq -r '.idle_p95_ms' <<< "$qoe")" == 20 ]]
[[ "$(jq -r '.loaded_p95_ms' <<< "$qoe")" == 165 ]]
printf '%s\n' "$qoe" > "$tmp/round1.json"
printf '%s\n' "$qoe" > "$tmp/round2.json"
both=$(network_tuning_qoe_combine "$tmp/round1.json" "$tmp/round2.json")
[[ "$(jq -r .status <<< "$both")" == repeatable_queueing_signal ]]

mk_round "$tmp/loaded" 12 30
normal=$(network_tuning_qoe_evaluate "$tmp/idle" "$tmp/loaded" "$tmp/probe.json")
[[ "$(jq -r .verdict <<< "$normal")" == no_clear_issue_at_sampled_rate ]]
printf '%s\n' "$normal" > "$tmp/round2.json"
both=$(network_tuning_qoe_combine "$tmp/round1.json" "$tmp/round2.json")
[[ "$(jq -r .status <<< "$both")" == inconclusive ]]
[[ "$(jq -r .reason <<< "$both")" == inconsistent_rounds ]]
printf '%s\n' "$normal" > "$tmp/round1.json"
both=$(network_tuning_qoe_combine "$tmp/round1.json" "$tmp/round2.json")
[[ "$(jq -r .status <<< "$both")" == no_clear_issue_at_sampled_rate ]]

mk_round "$tmp/loaded" 9 30
loss=$(network_tuning_qoe_evaluate "$tmp/idle" "$tmp/loaded" "$tmp/probe.json")
[[ "$(jq -r .verdict <<< "$loss")" == possible_loss ]]
[[ "$(jq -r .loss_percent <<< "$loss")" == 25 ]]
mk_round "$tmp/loaded" 8 30
insufficient=$(network_tuning_qoe_evaluate "$tmp/idle" "$tmp/loaded" "$tmp/probe.json")
[[ "$(jq -r .verdict <<< "$insufficient")" == inconclusive ]]
printf '%s\n' '{"sender_mbps":10,"received_mbps":2}' > "$tmp/probe.json"
mk_round "$tmp/loaded" 12 170
peer_bad=$(network_tuning_qoe_evaluate "$tmp/idle" "$tmp/loaded" "$tmp/probe.json")
[[ "$(jq -r .verdict <<< "$peer_bad")" == inconclusive ]]

# Mock-only end-to-end: 2 measured rounds, validated JSON, same iface/budget guard.
out=$(printf 'RUN\n' | network_tuning_qoe_run 30 4 test.example 5201)
grep -Fq 'repeatable_queueing_signal' <<< "$out"
grep -Fq '第 1 轮' <<< "$out"
grep -Fq '第 2 轮' <<< "$out"
[[ "$(cat "$NET_TUNE_PROBE_SYSFS/eth0/statistics/tx_bytes")" == 1000 ]]
out=$(printf 'y\n' | network_tuning_qoe_run 30 4 test.example 5201)
grep -Fq '已取消' <<< "$out"
if printf 'RUN\n' | network_tuning_qoe_run 1000 4 test.example 5201 >/dev/null 2>&1; then
    echo "FAIL: >=1G profile allowed" >&2; exit 1
fi
# Do not add network modification commands to QoE evaluator or orchestration.
for fn in network_tuning_qoe_evaluate network_tuning_qoe_run network_tuning_qoe_combine; do
    if declare -f "$fn" | grep -Eq 'tc qdisc (add|replace|del)|sysctl -w|ip route (replace|del)'; then
        echo "FAIL: network mutation found in $fn" >&2; exit 1
    fi
done
echo "Network tuning dev3 QoE smoke passed."
