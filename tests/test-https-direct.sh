#!/usr/bin/env bash
# Offline HTTPS IPv4/IPv6 DNS NODATA regression. No real network probes.
set -euo pipefail
cd "$(dirname "$0")/.."
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
MOCK_DNS=normal
MOCK_CURL=normal

dig() {
    local arguments="$*"
    case "$MOCK_DNS" in
        timeout) return 9 ;;
        servfail) printf ';; ->>HEADER<<- opcode: QUERY, status: SERVFAIL, id: 100\n'; return 0 ;;
        nxdomain) printf ';; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN, id: 100\n'; return 0 ;;
    esac
    printf ';; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 100\n'
    case "$arguments" in
        *'www.baidu.com AAAA')
            printf 'www.baidu.com. 1193 IN CNAME www.a.shifen.com.\n'
            printf 'www.a.shifen.com. 23 IN CNAME www.wshifen.com.\n' ;;
        *'www.baidu.com A') printf 'www.baidu.com. 60 IN A 103.235.47.188\n' ;;
        *'www.google.com AAAA') printf 'www.google.com. 60 IN AAAA 2001:4860:4827:7700::\n' ;;
        *'www.google.com A') printf 'www.google.com. 60 IN A 142.251.151.119\n' ;;
        *) echo "UNEXPECTED DNS QUERY: $arguments" >&2; return 1 ;;
    esac
}
curl() {
    printf '%s\n' "$*" >> "$tmp/curl_calls"
    case "$MOCK_CURL" in
        timeout) printf 'HTTP=000 TCP=0.0s TLS=0.0s TOTAL=12.0s REMOTE='; return 28 ;;
        connect) printf 'HTTP=000 TCP=0.0s TLS=0.0s TOTAL=0.1s REMOTE='; return 7 ;;
        tls) printf 'HTTP=000 TCP=0.1s TLS=0.0s TOTAL=0.1s REMOTE='; return 60 ;;
        denied) printf 'HTTP=403 TCP=0.01s TLS=0.04s TOTAL=0.06s REMOTE=142.1.2.3'; return 0 ;;
        *) printf 'HTTP=204 TCP=0.004s TLS=0.025s TOTAL=0.031s REMOTE=142.1.2.3'; return 0 ;;
    esac
}

[[ "$(https_direct_dns_result www.baidu.com AAAA)" == 'SKIP|NO_AAAA_RECORD' ]]
[[ "$(https_direct_dns_result www.baidu.com A)" == 'PASS|RECORD_PRESENT' ]]
[[ "$(https_direct_dns_result www.google.com AAAA)" == 'PASS|RECORD_PRESENT' ]]
out=$(https_direct_one Baidu www.baidu.com 6)
[[ "$out" == *'DNS=NOERROR AAAA=NONE'* ]]
[[ "$out" == *'RESULT=SKIP (NO_AAAA_RECORD)'* ]]
[[ ! -f "$tmp/curl_calls" ]]

out=$(https_direct_run)
[[ "$out" == *'[Baidu / IPv4]'* ]]
[[ "$out" == *'[Google / IPv6]'* ]]
[[ "$out" == *'RESULT=SKIP (NO_AAAA_RECORD)'* ]]
[[ "$(grep -c 'RESULT=PASS' <<<"$out")" == 3 ]]
[[ "$(wc -l < "$tmp/curl_calls")" == 3 ]]
grep -F -- '--noproxy *' "$tmp/curl_calls" >/dev/null
grep -F -- '-6' "$tmp/curl_calls" >/dev/null

MOCK_DNS=servfail
out=$(https_direct_one Baidu www.baidu.com 6)
[[ "$out" == *'DNS=DNS_SERVFAIL'* ]]
[[ "$out" == *'RESULT=FAIL (DNS_FAILURE)'* ]]
MOCK_DNS=nxdomain
out=$(https_direct_one Google www.google.com 6)
[[ "$out" == *'DNS_NXDOMAIN'* ]]
[[ "$out" == *'RESULT=FAIL (DNS_FAILURE)'* ]]
MOCK_DNS=timeout
out=$(https_direct_one Google www.google.com 6)
[[ "$out" == *'DNS_QUERY_FAILED'* ]]
[[ "$out" == *'RESULT=FAIL (DNS_FAILURE)'* ]]

MOCK_DNS=normal
MOCK_CURL=timeout
out=$(https_direct_one Google www.google.com 6)
[[ "$out" == *'RESULT=FAIL (TIMEOUT)'* ]]
MOCK_CURL=connect
out=$(https_direct_one Google www.google.com 6)
[[ "$out" == *'RESULT=FAIL (TCP_CONNECT_FAILED)'* ]]
MOCK_CURL=tls
out=$(https_direct_one Google www.google.com 6)
[[ "$out" == *'RESULT=FAIL (TLS_FAILURE)'* ]]
MOCK_CURL=denied
out=$(https_direct_one Google www.google.com 6)
[[ "$out" == *'RESULT=WARN (HTTP_403'* ]]

sed -n '/^server_test_management() {/,/^}/p' ss2022.sh |
    grep -Fq '7) https_direct_run; pause ;;'
echo 'PASS: DNS NODATA AAAA skip, real DNS failures, curl outcome mapping, menu and opt-out proxies'
