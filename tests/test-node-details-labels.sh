#!/usr/bin/env bash
# P8: bilingual node labels with unchanged client export content.
set -euo pipefail
cd "$(dirname "$0")/.."
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh
# shellcheck disable=SC1091
source ./modules/hysteria2.sh
# shellcheck disable=SC1091
source ./modules/snell-v6.sh
GREEN='' CYAN='' YELLOW='' RED='' PLAIN=''
show_qr() { :; }

assert_has() {
    if [[ "$1" != *"$2"* ]]; then
        printf 'FAIL: missing expected node detail: %s\n' "$2" >&2
        exit 1
    fi
}
assert_base() {
    assert_has "$1" '节点名称 (name):'
    assert_has "$1" "协议 (protocol): $2"
    assert_has "$1" '地址 (address):'
    assert_has "$1" '端口 (port):'
}
vless=$(show_vless_details '198.51.100.7' 12001 \
  'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' 'www.openssl.org' 'FAKE_PUBLIC_KEY' '04154744' 'test-vless')
assert_base "$vless" vless
for label in '用户 ID (id): aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' \
 '流控 (flow): xtls-rprx-vision' '传输层安全 (TLS): reality' \
 '伪装域名 (sni): www.openssl.org' '公钥 (pbk): FAKE_PUBLIC_KEY' \
 'ShortId (sid): 04154744'; do assert_has "$vless" "$label"; done
assert_has "$vless" 'security=reality&sni=www.openssl.org&fp=chrome&pbk=FAKE_PUBLIC_KEY&sid=04154744&type=tcp'
assert_has "$vless" 'username=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee, flow=xtls-rprx-vision, sni=www.openssl.org, reality-public-key=FAKE_PUBLIC_KEY'
assert_has "$vless" 'reality-short-id=04154744'

ssout=$(show_ss_details_single '198.51.100.7' 9000 \
 '2022-blake3-aes-128-gcm' 'FAKE_SS_PASSWORD' 'test-ss')
assert_base "$ssout" ss
assert_has "$ssout" '加密方式 (cipher): 2022-blake3-aes-128-gcm'
assert_has "$ssout" '密码 (password): FAKE_SS_PASSWORD'
assert_has "$ssout" 'UDP 转发 (udp): 开启'
assert_has "$ssout" 'encrypt-method=2022-blake3-aes-128-gcm, password="FAKE_SS_PASSWORD", udp-relay=true'

stls=$(show_shadowtls_details_single '198.51.100.7' 8443 \
 '2022-blake3-aes-128-gcm' 'FAKE_SS_PASSWORD' 'FAKE_STLS_PASSWORD' \
 'www.openssl.org' true 9001 test-stls)
for label in '节点名称 (name): test-stls' \
 '协议 (protocol): SS2022 + ShadowTLS v3' '地址 (address): 198.51.100.7' \
 'TCP 端口 (port): 8443' 'SS2022 加密方式 (cipher): 2022-blake3-aes-128-gcm' \
 'SS2022 密码 (password): FAKE_SS_PASSWORD' \
 'ShadowTLS 密码 (shadow-tls-password): FAKE_STLS_PASSWORD' \
 '伪装域名 (sni): www.openssl.org' \
 'UDP 转发 (udp): 开启，UDP 端口 (udp-port): 9001'; do assert_has "$stls" "$label"; done
assert_has "$stls" 'shadow-tls-password="FAKE_STLS_PASSWORD", shadow-tls-version=3, shadow-tls-sni=www.openssl.org'

snell5=$(show_snell_details '198.51.100.7' 8800 FAKE_PSK test-snell5)
assert_base "$snell5" snell
assert_has "$snell5" '预共享密钥 (psk): FAKE_PSK'
assert_has "$snell5" '版本 (version): 5'
assert_has "$snell5" 'UDP 转发 (udp): Snell v5 原生支持'
assert_has "$snell5" 'test-snell5 = snell, 198.51.100.7, 8800, psk="FAKE_PSK", version=5, reuse=true, tfo=true'

snell6=$(snell6_details '198.51.100.7' 8801 FAKE_PSK6 test-snell6)
assert_base "$snell6" snell
assert_has "$snell6" '预共享密钥 (psk): FAKE_PSK6'
assert_has "$snell6" '模式 (mode): default'
assert_has "$snell6" 'test-snell6 = snell, 198.51.100.7, 8801, psk="FAKE_PSK6", version=6, mode=default'

hy2=$(hy2_details hy2.example.com 7443 hy2.example.com FAKE_HY2_PASSWORD test-hy2)
assert_base "$hy2" hysteria2
assert_has "$hy2" '传输协议 (network): QUIC / UDP'
assert_has "$hy2" 'TLS 证书域名 (sni): hy2.example.com'
assert_has "$hy2" '认证密码 (password): FAKE_HY2_PASSWORD'
assert_has "$hy2" 'test-hy2 = hysteria2, hy2.example.com, 7443, password=FAKE_HY2_PASSWORD, sni=hy2.example.com'
assert_has "$hy2" 'hysteria2://FAKE_HY2_PASSWORD@hy2.example.com:7443?sni=hy2.example.com#test-hy2'

[[ "$(sha256sum modules/snell-v6.sh | cut -d' ' -f1)" == "$SNELL6_MODULE_SHA256" ]]
[[ "$(sha256sum modules/hysteria2.sh | cut -d' ' -f1)" == "$HY2_MODULE_SHA256" ]]
echo 'PASS: P8 bilingual labels, unchanged client config lines, module SHA256 pins'
