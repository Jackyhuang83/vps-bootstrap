#!/usr/bin/env bash
# Dev8: REAL kernel HTB integration on an unrouted disposable veth only.
set -euo pipefail
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh
if (( EUID != 0 )); then echo "SKIP: root required"; exit 0; fi
for cmd in ip tc jq flock nohup setsid; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "SKIP: missing $cmd"; exit 0
    fi
done
name="nt8a$RANDOM"; peer="nt8b$RANDOM"
while ip link show "$name" >/dev/null 2>&1 ||
      ip link show "$peer" >/dev/null 2>&1; do
    name="nt8a$RANDOM"; peer="nt8b$RANDOM"
done
if ! ip link add "$name" type veth peer name "$peer" 2>/dev/null; then
    echo "SKIP: CAP_NET_ADMIN unavailable; no live qdisc touched"
    exit 0
fi
work=$(mktemp -d)
cleanup() {
    ip link del "$name" >/dev/null 2>&1 || true
    rm -rf -- "$work"
}
trap cleanup EXIT
# No addresses/routes are configured, production network is untouched.
ip link set "$name" up
ip link set "$peer" up
reset_root() {
    tc qdisc replace dev "$name" root fq_codel \
      limit 10240 flows 1024 quantum 1514 target 5ms interval 100ms ecn
}
reset_root
baseline=$(network_tuning_htb_baseline "$name")
[[ "$(jq -r .restore_kind <<< "$baseline")" == fq_codel ]]
[[ "$(jq -r .ifindex <<< "$baseline")" == "$(cat "/sys/class/net/$name/ifindex")" ]]
awk '/^    cat > .*RESTORE_HTB_EOF/ {inside=1;next}
     inside && /^RESTORE_HTB_EOF$/ {exit}
     inside {print}' ss2022.sh > "$work/restore.sh"
bash -n "$work/restore.sh"
[[ -s "$work/restore.sh" ]]
make_trial() {
    local tr="$work/htb-$1"
    mkdir -m 700 "$tr"
    cp "$work/restore.sh" "$tr/restore.sh"
    chmod 700 "$tr/restore.sh"
    printf '%s\n' "$baseline" > "$tr/snapshot.json"
    printf '%s\n' "$tr" > "$work/.htb-active"
    echo "$tr"
}
install_htb() {
    tc qdisc replace dev "$name" root handle 1: htb default 10
    tc class add dev "$name" parent 1: classid 1:10 htb \
        rate 20mbit ceil 20mbit burst 32k cburst 32k
    tc qdisc add dev "$name" parent 1:10 handle 10: fq_codel
    tc qdisc show dev "$name" | grep -q '^qdisc htb 1: root'
}
verify_restored() {
    tc qdisc show dev "$name" | grep -Eq '^qdisc fq_codel [^ ]+ root'
    [[ -z "$(tc class show dev "$name")" ]]
    [[ -z "$(tc filter show dev "$name")" ]]
}
trial=$(make_trial direct)
install_htb
bash "$trial/restore.sh" "$trial"
[[ "$(cat "$trial/result")" == rolled_back_live ]]
[[ ! -e "$work/.htb-active" ]]
verify_restored
echo "PASS: real kernel HTB -> fq_codel rollback on disposable veth"

trial=$(make_trial conflict)
install_htb
tc qdisc replace dev "$name" root fq
if bash "$trial/restore.sh" "$trial" >/dev/null 2>&1; then
    echo "FAIL: overwrote an external qdisc" >&2; exit 1
fi
[[ "$(cat "$trial/result")" == external_root_conflict ]]
[[ -f "$work/.htb-active" ]]
tc qdisc show dev "$name" | grep -Eq '^qdisc fq [^ ]+ root'
echo "PASS: external qdisc remains untouched"
rm -f "$work/.htb-active"
reset_root

trial=$(make_trial sigkill)
# Independent guardian (not systemd timer), executing the real worker.
nohup setsid bash -c '
    sleep 3
    exec /usr/bin/bash "$1" "$2"
' _ "$trial/restore.sh" "$trial" </dev/null > "$work/guardian.log" 2>&1 &
guardian=$!
(
    install_htb
    kill -KILL "$BASHPID"
) > "$work/launcher.log" 2>&1 &
launcher=$!
wait "$launcher" 2>/dev/null || true
for ((i=0;i<120;i++)); do
    [[ -s "$trial/result" ]] && break
    sleep 0.1
done
if [[ "$(cat "$trial/result" 2>/dev/null)" != rolled_back_live ]]; then
    echo "FAIL: detached guardian did not restore after launcher SIGKILL" >&2
    cat "$work/guardian.log" >&2 || true
    kill "$guardian" 2>/dev/null || true
    exit 1
fi
verify_restored
[[ ! -e "$work/.htb-active" ]]
echo "PASS: real kernel rollback after launcher SIGKILL"
