#!/usr/bin/env bash
# Dev6 independent watchdog: simulated file transactions, no real network.
set -euo pipefail
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
NET_TUNE_DIR="$tmp/state"
NET_TUNE_ROLLBACK_TRIALS_DIR="$NET_TUNE_DIR/rollback-rehearsals"
tc() { echo "FORBIDDEN tc" >&2; return 80; }
ip() { echo "FORBIDDEN ip" >&2; return 80; }
sysctl() { echo "FORBIDDEN sysctl" >&2; return 80; }
reject() { if "$@" >/dev/null 2>&1; then echo "FAIL: $*" >&2; exit 1; fi; }
reject network_tuning_rollback_rehearsal 0 RUN
reject network_tuning_rollback_rehearsal 31 RUN
reject network_tuning_rollback_rehearsal '3;id' RUN
cancel=$(printf 'NO\n' | network_tuning_rollback_rehearsal 3 "")
grep -Fq '已取消' <<< "$cancel"
[[ ! -e "$NET_TUNE_DIR" ]]
mkdir -p "$NET_TUNE_DIR"
chmod 777 "$NET_TUNE_DIR"
reject network_tuning_rollback_rehearsal 3 RUN
chmod 700 "$NET_TUNE_DIR"
ln -s "$tmp/elsewhere" "$NET_TUNE_ROLLBACK_TRIALS_DIR"
reject network_tuning_rollback_rehearsal 3 RUN
rm "$NET_TUNE_ROLLBACK_TRIALS_DIR"
out=$(network_tuning_rollback_rehearsal 3 RUN)
grep -Fq '不修改真实网络' <<< "$out"
trial=$(sed -n 's/^演练事务：//p' <<< "$out")
[[ -f "$trial/ready" && -f "$trial/canary.active" ]]
[[ "$(stat -c %a "$trial")" == 700 ]]
for ((i=0;i<70;i++)); do
    [[ -f "$trial/result" ]] && break
    sleep 0.1
done
[[ "$(cat "$trial/result")" == rolled_back_simulated ]]
[[ ! -e "$trial/canary.active" ]]
grep -Fq rolled_back_simulated <<< "$(network_tuning_rollback_rehearsal_status)"
# Kill the Bash that starts a new transaction. A detached worker must survive.
export TEST_DEV6_DIR="$NET_TUNE_DIR"
bash -c '
set -euo pipefail
export SS2022_LIB_ONLY=1
source ./ss2022.sh
NET_TUNE_DIR="$TEST_DEV6_DIR"
NET_TUNE_ROLLBACK_TRIALS_DIR="$NET_TUNE_DIR/rollback-rehearsals"
network_tuning_rollback_rehearsal 3 RUN
kill -KILL "$BASHPID"
' > "$tmp/crash.log" 2>&1 &
child=$!
wait "$child" 2>/dev/null || true
crashed=$(sed -n 's/^演练事务：//p' "$tmp/crash.log" | tail -n1)
[[ -d "$crashed" && -f "$crashed/ready" ]] || exit 1
for ((i=0;i<70;i++)); do
    [[ -f "$crashed/result" ]] && break
    sleep 0.1
done
[[ "$(cat "$crashed/result")" == rolled_back_simulated ]]
[[ ! -e "$crashed/canary.active" ]]
echo "Network tuning dev6 detached watchdog smoke passed."
