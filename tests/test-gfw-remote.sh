#!/usr/bin/env bash
# Globalping integration regression: no internet, no probe, no keys or configs.
set -euo pipefail
cd "$(dirname "$0")/.."
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
STATE_DIR="$tmp/state"
mkdir -p "$STATE_DIR"
payload=$(gfw_diag_payload 11.22.33.44 443 CN 4 TCP)
jq -e '.type=="ping" and .target=="11.22.33.44" and
       .locations[0].country=="CN" and .locations[0].limit==1 and
       .measurementOptions.protocol=="TCP" and
       .measurementOptions.port==443 and .timeout==10 and
       (.measurementOptions | has("ipVersion") | not)' <<<"$payload" >/dev/null
payload=$(gfw_diag_payload '2001:4860::1' 44444 US 6 UDP)
jq -e '.type=="mtr" and .locations[0].country=="US" and
       .measurementOptions.protocol=="UDP" and .measurementOptions.packets==2 and
       .measurementOptions.port==44444 and .timeout==30 and
       (.measurementOptions | has("ipVersion") | not)' <<<"$payload" >/dev/null


# Literal IPv4/IPv6 targets MUST omit hostname-only ipVersion. Hostnames retain it.
payload=$(gfw_diag_payload '2001:db8::1234' 443 CN 6 TCP 4134)
jq -e '.locations[0].asn==4134 and (.measurementOptions | has("ipVersion") | not)' <<<"$payload" >/dev/null
payload=$(gfw_diag_payload 11.22.33.44 5555 US 4 UDP)
jq -e '.measurementOptions.protocol=="UDP" and (.measurementOptions | has("ipVersion") | not)' <<<"$payload" >/dev/null
payload=$(gfw_diag_payload 'example.org' 443 US 6 TCP)
jq -e '.measurementOptions.ipVersion==6' <<<"$payload" >/dev/null
payload=$(gfw_diag_payload 'example.org' 443 US 4 TCP)
jq -e '.measurementOptions.ipVersion==4' <<<"$payload" >/dev/null

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
            case "$MOCK_SCENARIO" in
                request_invalid) printf '{"error":{"type":"validation_error","message":"SECRET_SHOULD_NOT_BE_SHOWN","params":{"measurementOptions":"invalid"}}}\nHTTP_STATUS:400\n' ;;
                post_200) printf '{"id":"abcDEF123456"}\nHTTP_STATUS:200\n' ;;
                redirect_302) printf '<html>redirect</html>\nHTTP_STATUS:302\n' ;;
                invalid_type) printf '{"error":{"type":"CUSTOM_BAD_MSG SECRET_123"}}\nHTTP_STATUS:400\n' ;;
                no_probe) printf '{"error":{"type":"no_probes_found"}}\nHTTP_STATUS:422\n' ;;
                rate_limit) printf '{"error":{"type":"rate_limit"}}\nHTTP_STATUS:429\n' ;;
                api_dns_error) return 6 ;;
                *) printf '{"id":"abcDEF123456"}\nHTTP_STATUS:202\n' ;;
            esac
            ;;
        *'/v1/probes'*)
            case "$MOCK_SCENARIO" in
                api_dns_error) return 6 ;;
                *) printf '[{"location":{"country":"CN","asn":4134}}]\n' ;;
            esac
            ;;
        *'/v1/measurements/abcDEF123456'*)
            case "$MOCK_SCENARIO" in
                delayed)
                    printf 'poll\n' >> "$tmp/delayed_polls"
                    printf '{"status":"in-progress"}\nHTTP_STATUS:200\n' ;;
                delayed_then_success)
                    count=$(cat "$tmp/polls" 2>/dev/null || echo 0)
                    count=$(( count + 1 ))
                    printf '%s\n' "$count" > "$tmp/polls"
                    if (( count < 8 )); then
                        printf '{"status":"in-progress"}\nHTTP_STATUS:200\n'
                    else
                        printf '{"status":"finished","results":[{"probe":{"country":"CN","asn":4134},"result":{"status":"finished","stats":{"rcv":2,"loss":0,"avg":77.5}}}]}\nHTTP_STATUS:200\n'
                    fi
                    ;;
                mismatch) printf '{"status":"finished","results":[{"probe":{"country":"CN","asn":9999},"result":{"status":"finished","stats":{"rcv":2,"loss":0}}}]}\nHTTP_STATUS:200\n' ;;
                *) printf '{"status":"finished","results":[{"probe":{"country":"CN","asn":4134},"result":{"status":"finished","stats":{"rcv":2,"loss":0,"avg":42.6}}}]}\nHTTP_STATUS:200\n' ;;
            esac
            ;;
        *) echo "FAIL: unexpected request" >&2; return 1 ;;
    esac
}
sleep() { :; }
[[ "$(gfw_diag_globalping 11.22.33.44 443 CN 4 TCP)" == PASS ]]
grep -Fq -- 'https://api.globalping.io/v1/measurements' "$tmp/requests"
MOCK_SCENARIO=no_probe
[[ "$(gfw_diag_globalping 11.22.33.44 443 CN 4 TCP)" == UNKNOWN ]]
[[ "$(gfw_diag_globalping_detailed 11.22.33.44 443 CN 4 TCP)" == 'UNKNOWN|NO_ONLINE_PROBE' ]]
MOCK_SCENARIO=rate_limit
[[ "$(gfw_diag_globalping_detailed 11.22.33.44 443 CN 4 TCP)" == 'UNKNOWN|API_RATE_LIMIT_429' ]]

MOCK_SCENARIO=request_invalid
out=$(gfw_diag_globalping_detailed 11.22.33.44 443 CN 4 TCP)
[[ "$out" == 'UNKNOWN|API_HTTP_400_validation_error' ]]
[[ "$out" != *'SECRET_SHOULD_NOT_BE_SHOWN'* ]]
[[ "$out" != *'11.22.33.44'* ]]
MOCK_SCENARIO=post_200
[[ "$(gfw_diag_globalping_detailed 11.22.33.44 443 CN 4 TCP)" == 'UNKNOWN|API_HTTP_200' ]]
MOCK_SCENARIO=redirect_302
[[ "$(gfw_diag_globalping_detailed 11.22.33.44 443 CN 4 TCP)" == 'UNKNOWN|API_HTTP_302' ]]
MOCK_SCENARIO=invalid_type
[[ "$(gfw_diag_globalping_detailed 11.22.33.44 443 CN 4 TCP)" == 'UNKNOWN|API_HTTP_400' ]]
[[ "$(gfw_diag_http_failure_reason 'HTTP_STATUS:400' '{"error":{"type":"validation_error"}}')" == API_HTTP_400_validation_error ]]
[[ "$(gfw_diag_http_failure_reason 'HTTP_STATUS:422' '{"error":{"type":"other_error"}}')" == API_HTTP_422_other_error ]]
[[ "$(gfw_diag_http_failure_reason 'HTTP_STATUS:bad' 'invalid')" == API_HTTP_STATUS_INVALID ]]

MOCK_SCENARIO=api_dns_error
[[ "$(gfw_diag_globalping_detailed 11.22.33.44 443 CN 4 TCP)" == 'UNKNOWN|API_DNS_FAILURE' ]]
MOCK_SCENARIO=delayed
rm -f "$tmp/delayed_polls"
[[ "$(gfw_diag_globalping_detailed 11.22.33.44 443 CN 4 TCP)" == 'UNKNOWN|MEASUREMENT_TIMEOUT' ]]
[[ "$(wc -l < "$tmp/delayed_polls")" -eq 12 ]]
rm -f "$tmp/delayed_polls"
[[ "$(gfw_diag_globalping_detailed 11.22.33.44 443 CN 4 UDP)" == 'UNKNOWN|MEASUREMENT_TIMEOUT' ]]
[[ "$(wc -l < "$tmp/delayed_polls")" -eq 22 ]]
MOCK_SCENARIO=delayed_then_success
rm -f "$tmp/polls"
[[ "$(gfw_diag_globalping_detailed 11.22.33.44 443 CN 4 TCP 4134)" == 'PASS|TCP_CONNECTED_RTT_77.5ms' ]]
[[ "$(cat "$tmp/polls")" -eq 8 ]]

MOCK_SCENARIO=mismatch
[[ "$(gfw_diag_globalping_detailed 11.22.33.44 443 CN 4 TCP 4134)" == 'UNKNOWN|PROBE_RESULT_INCOMPLETE_OR_MISMATCH' ]]
MOCK_SCENARIO=success
[[ "$(gfw_diag_globalping_detailed 11.22.33.44 443 CN 4 TCP 4134)" == 'PASS|TCP_CONNECTED_RTT_42.6ms' ]]


# API probe discovery distinguishes network failure from GFW blocking.
MOCK_SCENARIO=api_dns_error
if out=$(gfw_diag_probe_inventory 2>&1); then
    echo 'FAIL: DNS-error probe inventory reported success'; exit 1
fi
[[ "$out" == *'PROBE_API_DNS_FAILURE'* ]]
MOCK_SCENARIO=success
jq -e '.[0].location.asn==4134' <<<"$(gfw_diag_probe_inventory)" >/dev/null

# Refusing explicit consent must never invoke any external measurement.
rm -f "$tmp/requests"
MOCK_SCENARIO=success
out=$(gfw_diag_remote_scan 4 TCP <<< $'\nNO\n')
[[ "$out" == *"取消；未发送任何目标信息"* ]]
[[ ! -f "$tmp/requests" ]]


# P1: live probe country and ASN must match China Telecom/Unicom/Mobile.
carrier_probes='[
  {"location":{"country":"CN","asn":4134}},
  {"location":{"country":"CN","asn":4837}},
  {"location":{"country":"CN","asn":9808}},
  {"location":{"country":"US","asn":4134}}
]'
[[ "$(gfw_diag_carrier_asn "$carrier_probes" TELECOM)" == 4134 ]]
[[ "$(gfw_diag_carrier_asn "$carrier_probes" UNICOM)" == 4837 ]]
[[ "$(gfw_diag_carrier_asn "$carrier_probes" MOBILE)" == 9808 ]]
if gfw_diag_carrier_asn '[{"location":{"country":"US","asn":9808}}]' MOBILE; then
    echo 'FAIL: US probe misclassified as mainland China Mobile'; exit 1
fi
payload=$(gfw_diag_payload 11.22.33.44 443 CN 4 TCP 4134)
jq -e '.locations[0].country=="CN" and .locations[0].asn==4134 and .measurementOptions.port==443' <<<"$payload" >/dev/null
[[ "$(gfw_diag_parse_measurement "$pass" CN TCP 4134)" == UNKNOWN ]]
[[ "$(gfw_diag_parse_measurement "$pass" CN TCP 12345)" == PASS ]]
gfw_diag_ports() { printf 'VLESS Reality|TCP|443|xray\n'; }
gfw_diag_listener_status() { printf 'BOUND\n'; }
gfw_diag_probe_inventory() { echo inventory-called >> "$tmp/probe-calls"; printf '%s' "$carrier_probes"; }
gfw_diag_globalping_detailed() {
    case "${6:-0}" in
        4134|4837) echo 'PASS|TCP_CONNECTED' ;;
        9808) echo 'FAIL|TCP_CONNECT_FAILED_NOT_PROOF_OF_GFW' ;;
        *) echo 'PASS|TCP_CONNECTED' ;;
    esac
}
rm -f "$tmp/probe-calls"
out=$(gfw_diag_trinet_auto <<< "$(printf '11.22.33.44\nNO\n')")
[[ "$out" == *'取消；未发送任何目标信息'* ]]
[[ ! -f "$tmp/probe-calls" ]]
[[ ! -e "$STATE_DIR/gfw-diagnostics-history.jsonl" ]]
out=$(gfw_diag_trinet_auto <<< "$(printf '11.22.33.44\nYES\n')")
[[ "$out" == *'中国电信'*'PASS'*'AS4134'* ]]
[[ "$out" == *'中国联通'*'PASS'*'AS4837'* ]]
[[ "$out" == *'中国移动'*'FAIL'*'AS9808'* ]]
[[ "$out" == *'美国对照'*'PASS'* ]]
[[ -f "$tmp/probe-calls" ]]
[[ "$(wc -l < "$STATE_DIR/gfw-diagnostics-history.jsonl")" -eq 3 ]]
jq -e 'select(.carrier=="中国电信" and .asn=="4134" and .cn=="PASS" and .us=="PASS" and .evidence=="TCP_CONNECTED")' "$STATE_DIR/gfw-diagnostics-history.jsonl" >/dev/null
[[ "$(stat -c '%a' "$STATE_DIR/gfw-diagnostics-history.jsonl")" == 600 ]]
carrier_probes='[{"location":{"country":"US","asn":4134}}]'
out=$(gfw_diag_trinet_auto <<< "$(printf '11.22.33.44\nYES\n')")
[[ "$out" == *'NO_ONLINE_PROBE'* ]]

echo 'PASS: Globalping protocol payload, CN absent, TCP verdict, UDP path-only, opt-in security, tri-carrier'
