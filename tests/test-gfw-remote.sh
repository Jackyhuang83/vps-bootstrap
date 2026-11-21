#!/usr/bin/env bash
# Globalping integration regression: no internet, no probe, no keys or configs.
set -euo pipefail
cd "$(dirname "$0")/.."
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
payload=$(gfw_diag_payload 11.22.33.44 443 CN 4 TCP)
jq -e '.type=="ping" and .target=="11.22.33.44" and
       .locations[0].country=="CN" and .locations[0].limit==1 and
       .measurementOptions.protocol=="TCP" and
       .measurementOptions.port==443 and .measurementOptions.ipVersion==4' <<<"$payload" >/dev/null
payload=$(gfw_diag_payload '2001:4860::1' 44444 US 6 UDP)
jq -e '.type=="traceroute" and .locations[0].country=="US" and
       .measurementOptions.protocol=="UDP" and
       .measurementOptions.port==44444 and .measurementOptions.ipVersion==6' <<<"$payload" >/dev/null

pass='{"status":"finished","results":[{"probe":{"country":"CN","asn":12345},"result":{"status":"finished","stats":{"rcv":2,"loss":0}}}]}'
fail='{"status":"finished","results":[{"probe":{"country":"CN","asn":12345},"result":{"status":"finished","stats":{"rcv":0,"loss":100}}}]}'
offline='{"status":"finished","results":[{"probe":{"country":"CN"},"result":{"status":"offline"}}]}'
no_cn='{"status":"finished","results":[{"probe":{"country":"US"},"result":{"status":"finished","stats":{"rcv":2,"loss":0}}}]}'
[[ "$(gfw_diag_parse_measurement "$pass" CN TCP)" == PASS ]]
[[ "$(gfw_diag_parse_measurement "$fail" CN TCP)" == FAIL ]]
[[ "$(gfw_diag_parse_measurement "$offline" CN TCP)" == UNKNOWN ]]
[[ "$(gfw_diag_parse_measurement "$no_cn" CN TCP)" == UNKNOWN ]]
[[ "$(gfw_diag_parse_measurement "$pass" CN UDP)" == PATH_ONLY ]]
[[ "$(gfw_diag_parse_measurement "$fail" CN UDP)" == PATH_ONLY ]]
[[ "$(gfw_diag_parse_measurement "$offline" CN UDP)" == UNKNOWN ]]
[[ "$(gfw_diag_parse_measurement '{}' CN TCP)" == UNKNOWN ]]
[[ "$(gfw_diag_tcp_verdict BOUND FAIL PASS)" == CN_PATH_SUSPECT_NOT_PROVEN_GFW ]]
[[ "$(gfw_diag_tcp_verdict BOUND FAIL UNKNOWN)" == INSUFFICIENT_EVIDENCE ]]
[[ "$(gfw_diag_tcp_verdict BOUND FAIL FAIL)" == BOTH_FAIL_CHECK_FIREWALL_NAT ]]
[[ "$(gfw_diag_tcp_verdict NOT_LISTENING FAIL PASS)" == LOCAL_ISSUE ]]
[[ "$(gfw_diag_tcp_verdict BOUND PASS FAIL)" == TCP_REACHABLE_FROM_CN ]]

get_inbound_ipv4() { printf '11.22.33.44'; }
[[ "$(gfw_diag_remote_target 4 <<<"")" == 11.22.33.44 ]]
if gfw_diag_remote_target 4 <<<'10.1.2.3' >/dev/null 2>"$tmp/err"; then
    echo "FAIL: private target accepted"; exit 1
fi

# Simulate API result after POST, no socket or external API request.
MOCK_SCENARIO=success
curl() {
    case "$*" in
        *'-X POST'*)
            printf '%s\n' "$*" >> "$tmp/requests"
            if [[ "$MOCK_SCENARIO" == no_probe ]]; then echo '{"error":{"type":"no_probes_found"}}'
            else echo '{"id":"abcDEF123456"}'; fi
            ;;
        *'/v1/measurements/abcDEF123456'*)
            echo '{"status":"finished","results":[{"probe":{"country":"CN"},"result":{"status":"finished","stats":{"rcv":2,"loss":0}}}]}'
            ;;
        *) echo "FAIL: unexpected request" >&2; return 1 ;;
    esac
}
sleep() { :; }
[[ "$(gfw_diag_globalping 11.22.33.44 443 CN 4 TCP)" == PASS ]]
grep -Fq -- 'https://api.globalping.io/v1/measurements' "$tmp/requests"
MOCK_SCENARIO=no_probe
[[ "$(gfw_diag_globalping 11.22.33.44 443 CN 4 TCP)" == UNKNOWN ]]

# Refusing explicit consent must never invoke any external measurement.
rm -f "$tmp/requests"
MOCK_SCENARIO=success
out=$(gfw_diag_remote_scan 4 TCP <<< $'\nNO\n')
[[ "$out" == *"取消；未发送任何目标信息"* ]]
[[ ! -f "$tmp/requests" ]]

echo 'PASS: Globalping protocol payload, CN absent, TCP verdict, UDP path-only, opt-in security'
