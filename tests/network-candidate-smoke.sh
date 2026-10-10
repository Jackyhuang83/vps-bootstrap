#!/usr/bin/env bash
# v1.10.0-dev4 offline estimator and qdisc audit. No real network commands.
set -euo pipefail
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
MOCK_TC_MODE="fq"
tc() {
    case "$1" in
        qdisc)
            case "$MOCK_TC_MODE" in
                fq) echo "qdisc fq_codel 0: root refcnt 2 limit 10240p" ;;
                mq) echo "qdisc mq 0: root" ;;
                clsact) echo "qdisc clsact ffff: parent ffff:fff1" ;;
                htb) echo "qdisc htb 1: root refcnt 2 r2q 10" ;;
                *) return 1 ;;
            esac ;;
        class) [[ "$MOCK_TC_MODE" != classes ]] || echo "class htb 1:1 root rate 20Mbit" ;;
        filter) [[ "$MOCK_TC_MODE" != filters ]] || echo "filter parent 1: protocol ip pref 10 u32" ;;
        *) return 1 ;;
    esac
}
sysctl() { echo "Unexpected sysctl call" >&2; return 99; }
make_fixture() {
    local mode="$1" out="$2"
    jq -n --arg mode "$mode" '
      {schema:1,tier_mbps:(if $mode=="wrong_tier" then 100 else 30 end),
       samples:[
         [12,24,30][] as $rate |
         [1,2][] as $round |
         {rate_mbps:$rate,
          round:(if $mode=="bad_round" and $rate==30 and $round==2 then 3 else $round end),
          sender_mbps:(if $rate==12 then 11.9 elif $rate==24 then 23.8 else 29.8 end),
          received_mbps:
            (if $rate==12 then 11.8
             elif $rate==24 then (if $mode=="bad_peer" then 13 else 23.6 end)
             elif $mode=="no_knee" then 29.6
             elif $mode=="unstable" and $round==2 then 13
             else 24.3 end),
          idle_p95_ms:20,
          loaded_p95_ms:
            (if $rate!=30 then 40
             elif $mode=="no_knee" then 40
             elif $mode=="single_spike" and $round==2 then 40
             else 240 end),
          retransmits:(if $rate==30 then 12 else 1 end)}
       ]}
    ' > "$out"
}
get_status() {
    network_tuning_candidate_assess 30 "$1" | jq -r '.status'
}
make_fixture knee "$tmp/knee.json"
result=$(network_tuning_candidate_assess 30 "$tmp/knee.json")
[[ "$(jq -r .status <<< "$result")" == candidate_for_validation ]]
[[ "$(jq -r .candidate_kbps <<< "$result")" == 22800 ]]
[[ "$(jq -r .auto_apply <<< "$result")" == false ]]
[[ "$(jq -r .reason <<< "$result")" == independent_peer_and_a_b_qoe_testing_required ]]
for mode in no_knee single_spike bad_peer unstable bad_round wrong_tier; do
    make_fixture "$mode" "$tmp/$mode.json"
done
[[ "$(get_status "$tmp/no_knee.json")" == no_confirmed_knee ]]
[[ "$(get_status "$tmp/single_spike.json")" == no_confirmed_knee ]]
[[ "$(get_status "$tmp/bad_peer.json")" == no_confirmed_knee ]]
[[ "$(get_status "$tmp/unstable.json")" == inconclusive ]]
[[ "$(get_status "$tmp/bad_round.json")" == inconclusive ]]
[[ "$(get_status "$tmp/wrong_tier.json")" == inconclusive ]]
[[ "$(network_tuning_candidate_assess 1000 "$tmp/knee.json" 2>/dev/null || true)" == "" ]]
[[ "$(network_tuning_candidate_assess 30 "$tmp/missing.json" 2>/dev/null || true)" == "" ]]
ln -s "$tmp/knee.json" "$tmp/evil.json"
[[ "$(network_tuning_candidate_assess 30 "$tmp/evil.json" 2>/dev/null || true)" == "" ]]
printf '{bad json\n' > "$tmp/invalid.json"
[[ "$(network_tuning_candidate_assess 30 "$tmp/invalid.json" 2>/dev/null || true)" == "" ]]

# Root qdisc reading does not grant authorization to mutate.
MOCK_TC_MODE=fq
[[ "$(network_tuning_qdisc_audit eth0)" == inspect_only* ]]
for mode in mq clsact htb classes filters; do
    MOCK_TC_MODE="$mode"
    audit=$(network_tuning_qdisc_audit eth0 || true)
    [[ "$audit" == blocked\|* ]] || {
        echo "FAIL: unexpected qdisc permission for $mode: $audit" >&2
        exit 1
    }
done
if network_tuning_qdisc_audit '/bad/name' >/dev/null 2>&1; then
    echo "FAIL: accepted invalid device" >&2; exit 1
fi
for fn in network_tuning_candidate_assess network_tuning_qdisc_audit network_tuning_candidate_menu; do
    if declare -f "$fn" | grep -Eq 'tc (qdisc|class|filter) (add|del|replace)|sysctl -w|ip route (replace|del)'; then
        echo "FAIL: dev4 mutation in $fn" >&2; exit 1
    fi
done
echo "Network tuning dev4 candidate and qdisc smoke passed."
