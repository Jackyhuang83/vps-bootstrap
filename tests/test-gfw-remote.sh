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
jq -e '.type=="mtr" and .locations[0].country=="US" and
       .measurementOptions.protocol=="UDP" and .measurementOptions.packets==2 and
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
gfw_diag_globalping() {
    case "${6:-0}" in 4134|4837) echo PASS ;; 9808) echo FAIL ;; *) echo PASS ;; esac
}
rm -f "$tmp/probe-calls"
out=$(gfw_diag_trinet_auto <<< "$(printf '11.22.33.44\nNO\n')")
[[ "$out" == *'取消；未发送任何目标信息'* ]]
[[ ! -f "$tmp/probe-calls" ]]
out=$(gfw_diag_trinet_auto <<< "$(printf '11.22.33.44\nYES\n')")
[[ "$out" == *'中国电信'*'PASS'*'AS4134'* ]]
[[ "$out" == *'中国联通'*'PASS'*'AS4837'* ]]
[[ "$out" == *'中国移动'*'FAIL'*'AS9808'* ]]
[[ "$out" == *'美国对照'*'PASS'* ]]
[[ -f "$tmp/probe-calls" ]]
carrier_probes='[{"location":{"country":"US","asn":4134}}]'
out=$(gfw_diag_trinet_auto <<< "$(printf '11.22.33.44\nYES\n')")
[[ "$out" == *'NO_ONLINE_PROBE'* ]]

echo 'PASS: Globalping protocol payload, CN absent, TCP verdict, UDP path-only, opt-in security, tri-carrier'
