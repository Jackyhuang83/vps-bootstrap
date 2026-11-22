#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh

report=$'New, TLSv1.3, Cipher is TLS_AES_128_GCM_SHA256\nServer Temp Key: X25519, 253 bits\nALPN protocol: h2\nVerify return code: 0 (ok)'
reality_sni_tls_ok "$report" || { echo 'FAIL: valid full OpenSSL handshake rejected'; exit 1; }
if reality_sni_tls_ok "${report/ALPN protocol: h2/No ALPN negotiated}"; then
    echo 'FAIL: missing HTTP/2 accepted'; exit 1
fi
if reality_sni_tls_ok "${report/TLSv1.3/TLSv1.2}"; then
    echo 'FAIL: TLS 1.2 accepted'; exit 1
fi
if reality_sni_tls_ok "${report/Server Temp Key: X25519/Server Temp Key: P-256}"; then
    echo 'FAIL: unsuitable curve accepted'; exit 1
fi
if reality_sni_tls_ok "${report/Verify return code: 0 (ok)/Verify return code: 62 (hostname mismatch)}"; then
    echo 'FAIL: invalid certificate accepted'; exit 1
fi
brief=$'Protocol version: TLSv1.3\nTemp Key: X25519\nALPN protocol: h2\nVerification: OK'
reality_sni_tls_ok "$brief" || { echo 'FAIL: supported alternate OpenSSL output rejected'; exit 1; }

# No real network requests; deterministic local ranking tests.
reality_sni_probe() {
    case "$1" in
        addons.mozilla.org) REALITY_SNI_PROBE_MS=50;;
        www.python.org) REALITY_SNI_PROBE_MS=12;;
        www.arm.com) REALITY_SNI_PROBE_MS=26;;
        *) return 1;;
    esac
}
select_reality_sni "" <<<"1" >/dev/null
[[ "$REALITY_SELECTED_SNI" == "www.python.org" ]] || {
    echo "FAIL: fastest valid SNI not selected first"; exit 1
}
select_reality_sni "" <<<"3" >/dev/null
[[ "$REALITY_SELECTED_SNI" == "addons.mozilla.org" ]] || {
    echo "FAIL: third ranked SNI index mismatch"; exit 1
}
select_reality_sni "existing.example.org" <<<"1" >/dev/null
[[ "$REALITY_SELECTED_SNI" == "existing.example.org" ]] || {
    echo 'FAIL: current SNI option changed'; exit 1
}
select_reality_sni "" <<<"0" >/dev/null && {
    echo 'FAIL: cancellation accepted'; exit 1
}
# No valid TLS targets must not be called verified.
reality_sni_probe() { return 1; }
fallback=$(select_reality_sni "" <<<"0" || true)
[[ "$fallback" == *"未验证"* ]] || {
    echo 'FAIL: no compliant targets not labeled unverified'; exit 1
}

# P8: bilingual labels in the VLESS Reality node detail view only.
# No service writes, network access or QR rendering in this fixture.
CYAN="" GREEN="" PLAIN="" YELLOW=""
show_qr() { :; }
fixture_uuid='12345678-1234-1234-1234-1234567890ab'
fixture_key='fixture-public-key-not-a-secret'
details=$(show_vless_details '203.0.113.9' 12001 "$fixture_uuid" \
    'www.openssl.org' "$fixture_key" '04154744' 'VLESS-demo')
expected_fields=$(cat <<'EXPECTED'
  协议（protocol）: vless
  地址（address）: 203.0.113.9
  端口（port）: 12001
  用户ID（id）: 12345678-1234-1234-1234-1234567890ab
  流控（flow）: xtls-rprx-vision
  传输层安全（TLS）: reality
  伪装域名（sni）: www.openssl.org
  公钥（pbk）: fixture-public-key-not-a-secret
  ShortId（sid）: 04154744
EXPECTED
)
[[ "$details" == *"$expected_fields"* ]] || {
    echo 'FAIL: VLESS bilingual field order/values or colon delimiter mismatch'; exit 1
}
[[ "$details" == *'节点名称: VLESS-demo'* ]] || {
    echo 'FAIL: existing node name label changed'; exit 1
}
[[ "$details" == *'vless://12345678-1234-1234-1234-1234567890ab@203.0.113.9:12001?'* ]] || {
    echo 'FAIL: VLESS URI export changed'; exit 1
}
[[ "$details" == *'VLESS-demo = vless, 203.0.113.9, 12001, username=12345678-1234-1234-1234-1234567890ab, flow=xtls-rprx-vision, sni=www.openssl.org, reality-public-key=fixture-public-key-not-a-secret, reality-short-id=04154744'* ]] || {
    echo 'FAIL: Surge line changed'; exit 1
}

echo 'PASS: Reality SNI output parser, bounded ranking, preservation and fallback'
