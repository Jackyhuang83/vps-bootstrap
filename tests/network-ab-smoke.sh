#!/usr/bin/env bash
# Dev8: synthetic A/B evidence. The production evaluator is READ-ONLY.
set -euo pipefail
set -x
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
make_json() {
 jq -nc --argjson stalls "$1" --argjson web "$2" --argjson chat "$3" '
 {schema:1,tier_mbps:30,video_source:"same news stream",
  video_resolution:"1080p",samples:[
   range(1;3) as $round |
   {phase:"baseline",round:$round,duration_s:360,video_stalls:$stalls,
    video_buffer_s:20,video_dropped_frames:0,web_p95_ms:400,
    chat_p95_ms:200,ping_p95_ms:100,loss_pct:0},
   {phase:"trial",round:$round,duration_s:360,video_stalls:0,
    video_buffer_s:0,video_dropped_frames:0,web_p95_ms:$web,
    chat_p95_ms:$chat,ping_p95_ms:90,loss_pct:0}]}' 
}
make_json 2 330 180 > "$tmp/ok.json"
ok=$(network_tuning_ab_assess 30 "$tmp/ok.json")
[[ "$(jq -r .verdict <<< "$ok")" == candidate_for_further_field_validation ]]
[[ "$(jq -r .auto_apply <<< "$ok")" == false ]]
make_json 0 395 180 > "$tmp/neutral.json"
[[ "$(network_tuning_ab_assess 30 "$tmp/neutral.json" | jq -r .verdict)" == keep_baseline ]]
make_json 2 330 500 > "$tmp/chat.json"
[[ "$(network_tuning_ab_assess 30 "$tmp/chat.json" | jq -r .verdict)" == keep_baseline ]]
jq '.samples |= map(if .phase=="trial" then .video_stalls=3 else . end)' \
 "$tmp/ok.json" > "$tmp/stalls.json"
[[ "$(network_tuning_ab_assess 30 "$tmp/stalls.json" | jq -r .verdict)" == keep_baseline ]]
jq 'del(.samples[3])' "$tmp/ok.json" > "$tmp/incomplete.json"
[[ "$(network_tuning_ab_assess 30 "$tmp/incomplete.json" | jq -r .verdict)" == inconclusive ]]
[[ "$(network_tuning_ab_assess 20 "$tmp/ok.json" | jq -r .verdict)" == inconclusive ]]
jq '.samples[1].duration_s=5' "$tmp/ok.json" > "$tmp/short.json"
[[ "$(network_tuning_ab_assess 30 "$tmp/short.json" | jq -r .verdict)" == inconclusive ]]
ln -s "$tmp/ok.json" "$tmp/link.json"
if network_tuning_ab_assess 30 "$tmp/link.json" >/dev/null 2>&1; then
    echo "FAIL accepted symlink evidence" >&2; exit 1
fi
echo 'Dev8 video-first A/B evidence gate smoke passed.'
