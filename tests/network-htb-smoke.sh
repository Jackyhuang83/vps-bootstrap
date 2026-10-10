#!/usr/bin/env bash
# Dev7: qdisc restoration contract, worker success/conflict, no real tc writes.
set -euo pipefail
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
NET_TUNE_PROBE_SYSFS="$tmp/sys"
mkdir -p "$NET_TUNE_PROBE_SYSFS/eth0/statistics"
echo 100 > "$NET_TUNE_PROBE_SYSFS/eth0/statistics/tx_bytes"
echo 8 > "$NET_TUNE_PROBE_SYSFS/eth0/ifindex"
TC_MODE=fq
tc() {
    case "$1" in
        qdisc)
            case "$TC_MODE" in
                fq) echo 'qdisc fq_codel 0: root refcnt 2 limit 10240p flows 1024 quantum 1514 target 5ms interval 100ms ecn' ;;
                custom) echo 'qdisc fq_codel 0: root unknown_custom 9' ;;
                fq_root) echo 'qdisc fq 0: root' ;;
                mq) echo 'qdisc mq 0: root' ;;
                htb) echo 'qdisc htb 1: root' ;;
                multi) printf 'qdisc fq_codel 0: root\nqdisc clsact ffff: parent ffff:fff1\n' ;;
                class|filter) echo 'qdisc fq_codel 0: root' ;;
            esac ;;
        class) [[ "$TC_MODE" != class ]] || echo 'class htb 1:1 root rate 10Mbit' ;;
        filter) [[ "$TC_MODE" != filter ]] || echo 'filter parent 1: protocol ip pref 1' ;;
        *) return 1 ;;
    esac
}
baseline=$(network_tuning_htb_baseline eth0)
[[ "$(jq -r .restore_kind <<< "$baseline")" == fq_codel ]]
[[ "$(jq -r '.restore_args|join(" ")' <<< "$baseline")" == 'limit 10240 flows 1024 quantum 1514 target 5ms interval 100ms ecn' ]]
for mode in custom fq_root mq htb multi class filter; do
    TC_MODE="$mode"
    if network_tuning_htb_baseline eth0 >/dev/null 2>&1; then
        echo "FAIL: accepted unsafe root $mode" >&2; exit 1
    fi
done
TC_MODE=fq
for iface in '../eth0' 'tun0' 'wg0'; do
    if network_tuning_htb_baseline "$iface" >/dev/null 2>&1; then
        echo "FAIL: accepted unsafe iface $iface" >&2; exit 1
    fi
done

# Extract the hermetic rollback script without running host-shaping code.
awk '/^    cat > .*RESTORE_HTB_EOF/ {inside=1;next} inside && /^RESTORE_HTB_EOF$/ {exit} inside {print}' \
    ss2022.sh > "$tmp/restore.sh"
[[ $(wc -l < "$tmp/restore.sh") -gt 35 ]]
chmod 700 "$tmp/restore.sh"
mkdir -p "$tmp/worker"
trial="$tmp/worker/htb-test"
mkdir -m 700 "$trial"
ifindex=$(cat /sys/class/net/lo/ifindex)
jq -nc --arg idx "$ifindex" \
    '{schema:1,mode:"htb_ephemeral_trial",iface:"lo",ifindex:$idx,
      restore_kind:"fq_codel",restore_args:["limit","10240","flows","1024","ecn"]}' \
    > "$trial/snapshot.json"
printf '%s\n' "$trial" > "$tmp/worker/.htb-active"
fakebin="$tmp/bin"
mkdir -p "$fakebin"
cat > "$fakebin/tc" <<'FAKE_TC_EOF'
#!/usr/bin/env bash
case "$1" in
    qdisc)
        if [[ "$2" == show ]]; then cat "$FAKE_TC_STATE"
        elif [[ "$2" == replace ]]; then
            [[ "$6" == fq_codel ]] || exit 1
            printf '%s\n' "$*" > "$FAKE_TC_ARGS"
            echo 'qdisc fq_codel 8001: root refcnt 2' > "$FAKE_TC_STATE"
        else exit 1; fi ;;
    class) echo 'class htb 1:10 root leaf 10: prio 0 rate 22Mbit ceil 22Mbit' ;;
    filter) : ;;
    *) exit 1 ;;
esac
FAKE_TC_EOF
chmod 700 "$fakebin/tc"
export FAKE_TC_STATE="$tmp/tc.state" FAKE_TC_ARGS="$tmp/tc.args"
echo 'qdisc htb 1: root refcnt 2' > "$FAKE_TC_STATE"
PATH="$fakebin:$PATH" bash "$tmp/restore.sh" "$trial"
[[ "$(cat "$trial/result")" == rolled_back_live ]]
[[ ! -e "$tmp/worker/.htb-active" ]]
grep -Fq 'limit 10240' "$FAKE_TC_ARGS"

# External qdisc modification must not be overwritten.
echo 'qdisc mq 0: root refcnt 2' > "$FAKE_TC_STATE"
printf '%s\n' "$trial" > "$tmp/worker/.htb-active"
rm -f "$trial/result" "$FAKE_TC_ARGS"
if PATH="$fakebin:$PATH" bash "$tmp/restore.sh" "$trial" >/dev/null 2>&1; then
    echo 'FAIL: external root modification was accepted' >&2; exit 1
fi
[[ "$(cat "$trial/result")" == external_root_conflict ]]
[[ -f "$tmp/worker/.htb-active" ]]
[[ ! -e "$FAKE_TC_ARGS" ]]
echo 'Network tuning dev7 HTB preflight and rollback worker smoke passed.'
