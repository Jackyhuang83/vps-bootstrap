#!/usr/bin/env bash
# Offline history and China tri-network handoff regression: no external probes.
set -euo pipefail
cd "$(dirname "$0")/.."
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
STATE_DIR="$tmp/state"
mkdir -p "$STATE_DIR"
file="$STATE_DIR/gfw-diagnostics-history.jsonl"
payload=$(gfw_diag_payload 11.22.33.44 8443 CN 4 UDP)
jq -e '.type=="mtr" and .measurementOptions.protocol=="UDP" and
       .measurementOptions.port==8443 and .measurementOptions.packets==2' <<<"$payload" >/dev/null
gfw_diag_history_append 11.22.33.44 4 TCP 443 BOUND FAIL PASS CN_PATH_SUSPECT_NOT_PROVEN_GFW
[[ -f "$file" ]]
[[ "$(stat -c '%a' "$file")" == 600 ]]
jq -e '.source=="globalping" and .target=="11.22.33.44" and
       .family=="4" and .port=="443" and
       .verdict=="CN_PATH_SUSPECT_NOT_PROVEN_GFW"' "$file" >/dev/null
for i in $(seq 1 55); do
    gfw_diag_history_append 11.22.33.44 4 UDP "$i" BOUND UNKNOWN PATH_ONLY UDP_PATH_ONLY
done
[[ "$(wc -l <"$file")" -eq 50 ]]
out=$(gfw_diag_history_show)
[[ "$out" == *'UDP_PATH_ONLY'* ]]
[[ "$out" == *'最近 20 条外部探测记录'* ]]
[[ "$out" != *'password'* && "$out" != *'UUID'* ]]
mv "$file" "$tmp/historical-backup"
printf 'DO_NOT_OVERWRITE\n' >"$tmp/other-file"
ln -s "$tmp/other-file" "$file"
if gfw_diag_history_append 11.22.33.44 4 TCP 443 BOUND PASS PASS TCP_REACHABLE_FROM_CN 2>/dev/null; then
    echo 'FAIL: history symlink accepted'; exit 1
fi
grep -Fqx 'DO_NOT_OVERWRITE' "$tmp/other-file"
rm -f "$file"
mv "$tmp/historical-backup" "$file"
gfw_diag_history_clear <<<"NO" >/dev/null
[[ -f "$file" ]]
gfw_diag_history_clear <<<"DELETE" >/dev/null
[[ ! -e "$file" ]]
get_inbound_ipv4() { printf '11.22.33.44'; }
gfw_diag_ports() {
    printf '%s\n' 'VLESS Reality|TCP|443|ss2022-xray' \
        'SS2022|TCP|443|sing-box' 'Hysteria 2|UDP|5000|ss2022-hy2' \
        'ShadowTLS v3|TCP|8443|sing-box'
}
output=$(gfw_diag_trinet_links <<<"")
[[ "$output" == *'https://www.itdog.cn/tcping/11.22.33.44:443'* ]]
[[ "$output" == *'https://www.itdog.cn/tcping/11.22.33.44:8443'* ]]
[[ "$output" != *':5000'* ]]
[[ "$(grep -oF 'https://www.itdog.cn/tcping/11.22.33.44:443' <<<"$output" | wc -l)" -eq 1 ]]
[[ "$output" == *'电信'* && "$output" == *'联通'* && "$output" == *'移动'* ]]
echo 'PASS: official UDP MTR target port; JSONL retention and private mode; symlink protection; tri-net links'
