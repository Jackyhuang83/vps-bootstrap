#!/usr/bin/env bash
# Offline integration checks: all HTTP and scheduler operations are replaced.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh
STATE_DIR="$tmp/state"
GOOGLE_LOCATION_WORKER="$tmp/lib/google-location-worker.sh"
GOOGLE_LOCATION_UNIT_DIR="$tmp/units"
mkdir -p "$STATE_DIR" "$GOOGLE_LOCATION_UNIT_DIR"
export MOCK_HOME="$tmp"
checks=0
check() {
    if ! "$@"; then printf 'FAIL: %s\n' "$*" >&2; exit 1; fi
    checks=$((checks + 1))
}
has() { [[ "$1" == *"$2"* ]]; }
parse() { google_parse_response "$1" "$tmp/body" "${2:-200}" "${3:-https://www.google.com/search}" "${4:-0}"; }
footer() { printf '<html><body><div id="fbar"><span>%s</span><span> - From your internet address</span></div></body></html>\n' "$1" >"$tmp/body"; }
for country in 'China:CN' 'Japan:JP' 'United States:US' 'Macau:MO' 'Macao China:MO' 'Hong Kong China:HK' 'Taiwan:TW'; do
    footer "${country%:*}"
    out=$(parse search)
    check has "$out" "${country##*:}"$'\tGoogle 搜索 IP 定位'
done
footer Japan
check has "$(parse search 429)" $'UNKNOWN\tHTTP 429'
check has "$(parse search 200 https://www.google.com/sorry/index)" $'UNKNOWN\t验证码'
check has "$(parse search 200 https://consent.google.com/)" $'UNKNOWN\t验证码'
check has "$(parse search 200 https://www.google.com/search 28)" $'UNKNOWN\tcurl 28'
check has "$(parse search 200 https://www.google.com.hk/)" 'UNKNOWN'
printf '<div>China</div><footer>Based on your past activity</footer>\n' >"$tmp/body"
check has "$(parse search)" 'UNKNOWN'
printf '<div>China - From your internet address</div>\n' >"$tmp/body"
check has "$(parse search)" 'UNKNOWN'
printf '<footer><script>China</script>Japan - From your internet address</footer>\n' >"$tmp/body"
check has "$(parse search)" $'JP\t'
printf '<footer>China Japan - From your internet address</footer>\n' >"$tmp/body"
check has "$(parse search)" 'UNKNOWN'
printf '<div id="footcnt">Taiwan - From your IP address</div>\n' >"$tmp/body"
check has "$(parse search)" $'TW\t'
printf '<html>Please enable JavaScript to use Google Search</html>\n' >"$tmp/body"
check has "$(parse search)" '依赖 JavaScript'
printf '<script>ytcfg.set({"INNERTUBE_CONTEXT":{"client":{"gl":"HK"}}})</script>\n' >"$tmp/body"
check has "$(parse youtube 200 https://www.youtube.com/premium)" $'HK\tYouTube'
printf '{"GL":"US","countryCode":"CN","contentRegion":"JP"}\n' >"$tmp/body"
check has "$(parse youtube 200 https://www.youtube.com/premium)" 'UNKNOWN'

rpc_fixture() {
    python3 - "$@" <<'PY_RPC'
import json, sys
path, region, source, variant = sys.argv[1:]
row = [region, source, False, None, '//www.google.com/maps/vt/data=IGNORED']
frame = ['wrb.fr', 'K4WWud', json.dumps([row]), None, None, [0]]
frames = [frame]
if variant == 'error': frame[5] = [7]
elif variant == 'false_status': frame[5] = [False]
elif variant == 'wrong_id': frame[1] = 'OtherRPC'
elif variant == 'duplicate': frames.append(frame)
elif variant == 'other_frame': frames.append(['wrb.fr', 'OtherRPC', '[["China"]]'])
elif variant == 'bad_payload': frame[2] = 'not json'
encoded = json.dumps(frames, indent=2 if variant == 'pretty' else None)
open(path, 'w').write(")]}'\n" + str(len(encoded.encode())) + '\n\n' + encoded + '\n')
PY_RPC
}
ip_source=SWML_DESCRIPTION_FROM_YOUR_INTERNET_ADDRESS
for country in 'Taipei, Taiwan:TW' 'China:CN' 'Hong Kong China:HK' 'Macao:MO' 'United States:US' 'JP:JP'; do
    rpc_fixture "$tmp/body" "${country%:*}" "$ip_source" normal
    check has "$(parse location 200 https://gemini.google.com/_)" "${country##*:}"$'\tGoogle 服务 IP 定位'
done
for variant in error false_status wrong_id duplicate bad_payload; do
    rpc_fixture "$tmp/body" Taiwan "$ip_source" "$variant"
    check has "$(parse location 200 https://gemini.google.com/_)" UNKNOWN
done
for variant in pretty other_frame; do
    rpc_fixture "$tmp/body" Taiwan "$ip_source" "$variant"
    check has "$(parse location 200 https://gemini.google.com/_)" $'TW\t'
done
rpc_fixture "$tmp/body" Taiwan SWML_DESCRIPTION_FROM_YOUR_DEVICE normal
check has "$(parse location 200 https://gemini.google.com/_)" UNKNOWN
rpc_fixture "$tmp/body" 'San Jose, CA' "$ip_source" normal
check has "$(parse location 200 https://gemini.google.com/_)" UNKNOWN
rpc_fixture "$tmp/body" Taiwan "$ip_source" normal
check has "$(parse location 200 https://accounts.google.com/_)" UNKNOWN
check has "$(parse location 429 https://gemini.google.com/_)" UNKNOWN
check has "$(parse location 200 https://gemini.google.com/_ 28)" UNKNOWN
printf '<html>China Taiwan</html>\n' >"$tmp/body"
check has "$(parse location 200 https://gemini.google.com/_)" UNKNOWN
printf '{"INNERTUBE_CONTEXT_GL":"US","INNERTUBE_CONTEXT":{"client":{"gl":"CN"}}}\n' >"$tmp/body"
check has "$(parse youtube 200 https://www.youtube.com/premium)" 'UNKNOWN'
check google_location_validate MO 22.1987 113.5439
check google_location_validate JP -0.1 -180
if google_location_validate ZZ 0 0 || google_location_validate US 91 0 || google_location_validate US 0 NaN || google_location_validate US 0 '1;touch /tmp/unsafe'; then
    echo 'FAIL: invalid coordinates accepted'; exit 1
fi
checks=$((checks + 1))

# Mock real curl arguments, not google_fetch, to verify direct transport and
# that the same implementation in the generated worker remains standalone.
curl() {
    local body='' url='' arg prev='' http="${MOCK_HTTP:-200}"
    printf '%s\n' "$*" >>"$MOCK_HOME/requests"
    for arg in "$@"; do
        [[ "$prev" != -o ]] || body="$arg"
        prev="$arg"
        [[ "$arg" != https://* ]] || url="$arg"
    done
    case "$url" in
        *cdn-cgi/trace) printf 'ip=203.0.113.1\nloc=US\n' >"$body" ;;
        *gemini.google.com/*)
            if [[ -z "${MOCK_RPC_REGION:-}" ]]; then
                printf '[]' >"$body"
            else
                rpc_fixture "$body" "$MOCK_RPC_REGION" "${MOCK_RPC_SOURCE:-SWML_DESCRIPTION_FROM_YOUR_INTERNET_ADDRESS}" normal
            fi ;;
        *youtube.com*) printf '{"INNERTUBE_CONTEXT":{"client":{"gl":"%s"}}}' "${MOCK_YT_CC:-US}" >"$body" ;;
        *ipwho.is*) printf '{"success":true,"country_code":"JP","latitude":35.6762,"longitude":139.6503}' >"$body" ;;
        *search*)
            if [[ "${MOCK_UNKNOWN:-0}" == 1 ]]; then
                printf '<div>consent</div>' >"$body"
            else
                printf '<footer>%s - From your internet address</footer>' "${MOCK_SEARCH_COUNTRY:-United States}" >"$body"
            fi ;;
        *) printf '<html>Map</html>' >"$body" ;;
    esac
    printf '%s\t%s' "$http" "$url"
    return "${MOCK_CURL_RC:-0}"
}
export -f curl
out=$(google_probe_family 4)
check has "$out" '未发现送中（US）'
check has "$(MOCK_SEARCH_COUNTRY=China google_probe_family 4)" '中国大陆（送中）'
check has "$(MOCK_SEARCH_COUNTRY='Hong Kong China' MOCK_YT_CC=HK google_probe_family 6)" '未发现送中（HK）'
check has "$(MOCK_SEARCH_COUNTRY=Macau MOCK_YT_CC=MO google_probe_family 4)" '未发现送中（MO）'
check has "$(MOCK_YT_CC=JP google_probe_family 4)" '地区不一致'
check has "$(MOCK_UNKNOWN=1 MOCK_YT_CC=CN google_probe_family 4)" '疑似送中'
check has "$(MOCK_HTTP=429 google_probe_family 6)" '无法判定'
check has "$(MOCK_CURL_RC=6 google_probe_family 6)" '无法判定'
check has "$(MOCK_UNKNOWN=1 MOCK_YT_CC=TW google_probe_family 4)" '部分结果——YouTube 地区为 TW'
check has "$(MOCK_UNKNOWN=1 MOCK_RPC_REGION=Taiwan MOCK_YT_CC=TW google_probe_family 4)" 'Google 服务 IP 地区为 TW（搜索定位未确认）'
check has "$(MOCK_UNKNOWN=1 MOCK_RPC_REGION=China MOCK_YT_CC=CN google_probe_family 6)" '发现送中信号'
check has "$(MOCK_UNKNOWN=1 MOCK_RPC_REGION=China MOCK_YT_CC=TW google_probe_family 4)" '服务地区不一致'
check has "$(MOCK_UNKNOWN=1 MOCK_RPC_REGION=China MOCK_YT_CC=TW google_probe_family 4)" '存在中国大陆 CN 信号'
check has "$(MOCK_UNKNOWN=1 MOCK_RPC_REGION=Taiwan MOCK_YT_CC=JP google_probe_family 4)" '服务地区不一致'
check has "$(MOCK_UNKNOWN=1 MOCK_RPC_REGION=Taiwan MOCK_RPC_SOURCE=ACTIVITY MOCK_YT_CC=TW google_probe_family 4)" '部分结果——YouTube 地区为 TW'
check grep -q -- '--data-urlencode f.req=' "$tmp/requests"
check grep -q -- '-q -6 --noproxy \*' "$tmp/requests"
if grep -E 'google.com/search.*(gl=|uule=)' "$tmp/requests"; then echo 'FAIL: probe region forced'; exit 1; fi
checks=$((checks + 1))
: >"$tmp/requests"
google_probe_family 4 >/dev/null
if grep -q 'batchexecute' "$tmp/requests"; then echo 'FAIL: extra location request despite valid Search footer'; exit 1; fi
checks=$((checks + 1))
: >"$tmp/requests"
out=$(google_location_round 4 MO 22.1987 113.5439)
check has "$out" '完成 2/2'
check has "$out" '不代表 IP 定位已改变'
check grep -q 'gl=mo' "$tmp/requests"
check grep -q 'query=22.1987%2C113.5439' "$tmp/requests"
: >"$tmp/requests"
if MOCK_HTTP=429 google_location_round 4 MO 22.1987 113.5439 >"$tmp/result"; then echo 'FAIL: rejected request accepted'; exit 1; fi
check test "$(wc -l <"$tmp/requests")" -eq 1
check test "$(google_location_suggest 6)" = $'JP\t35.6762\t139.6503'

systemctl() {
    printf '%s\n' "$*" >>"$MOCK_HOME/systemctl"
    [[ "${MOCK_SYSTEMD_FAIL:-0}" != 1 || "$1" != enable ]]
}
crontab() {
    if [[ "$1" == -l ]]; then cat "$MOCK_HOME/crontab"; else cp "$1" "$MOCK_HOME/crontab"; fi
}
rc-service() { [[ "${MOCK_CRON_DOWN:-0}" != 1 ]]; }
PLATFORM_INIT=systemd
google_location_enable macau 4 MO 22.1987 113.5439 >/dev/null
check test -x "$GOOGLE_LOCATION_WORKER"
check bash -n "$GOOGLE_LOCATION_WORKER"
check grep -q 'OnUnitActiveSec=6h' "$GOOGLE_LOCATION_UNIT_DIR/ss2022-google-location.timer"
check grep -q "ReadWritePaths=$STATE_DIR" "$GOOGLE_LOCATION_UNIT_DIR/ss2022-google-location.service"
check test "$(stat -c %a "$STATE_DIR/google-location.json")" = 600
bash "$GOOGLE_LOCATION_WORKER"
check grep -q '完成 2/2' "$STATE_DIR/google-location-last.txt"
google_location_enable restore 6 JP 35.6762 139.6503 >/dev/null
check grep -q '"mode": "restore"' "$STATE_DIR/google-location.json"
if MOCK_HTTP=429 bash "$GOOGLE_LOCATION_WORKER"; then echo 'FAIL: worker failure hidden'; exit 1; fi
check grep -q '异常 1' "$STATE_DIR/google-location-last.txt"
printf '{"owner":"vps-bootstrap-google-v1","mode":"restore","family":"4","cc":"US","lat":"0","lon":"$(touch bad)"}' >"$STATE_DIR/google-location.json"
: >"$tmp/requests"
if bash "$GOOGLE_LOCATION_WORKER"; then echo 'FAIL: malicious configuration accepted'; exit 1; fi
check test ! -s "$tmp/requests"
google_location_stop
check test ! -e "$STATE_DIR/google-location.json"
if MOCK_SYSTEMD_FAIL=1 google_location_enable macau 4 MO 22.1987 113.5439 >/dev/null; then echo 'FAIL: timer failure hidden'; exit 1; fi
check test ! -e "$STATE_DIR/google-location.json"
PLATFORM_INIT=openrc
printf '0 2 * * * echo keep-me\n' >"$tmp/crontab"
google_location_enable macau 0 MO 22.1987 113.5439 >/dev/null
google_location_enable restore 4 US 34.0522 -118.2437 >/dev/null
check test "$(grep -c '# ss2022-google-location$' "$tmp/crontab")" -eq 1
check grep -q 'keep-me' "$tmp/crontab"
google_location_stop
check grep -q 'keep-me' "$tmp/crontab"
if grep -q '# ss2022-google-location$' "$tmp/crontab"; then echo 'FAIL: cron entry retained'; exit 1; fi
checks=$((checks + 1))
if MOCK_CRON_DOWN=1 google_location_enable macau 4 MO 22.1987 113.5439 >/dev/null; then echo 'FAIL: inactive cron accepted'; exit 1; fi
check test ! -e "$STATE_DIR/google-location.json"
google_location_remove
check test ! -e "$GOOGLE_LOCATION_WORKER"
check test ! -e "$GOOGLE_LOCATION_UNIT_DIR/ss2022-google-location.timer"

out=$(
    clear() { :; }
    google_test_management() { echo GOOGLE_MENU_REACHED; }
    server_test_management <<< $'4\n0'
)
check has "$out" GOOGLE_MENU_REACHED
echo "PASS: $checks Google parsing, HTTP, worker, scheduler and menu checks"
