#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# The bridge uses a loopback-only TCP listener. It does NOT redirect Snell's
# original IPv6 socket, nor replace the global sing-box routing configuration.
snell_warp_bridge_config_json 16001 2001:b030:a81d:a00::82:adf3 10000 40000 > "$tmp/bridge.json"
jq -e '
  (.inbounds|length)==1 and
  .inbounds[0].type=="direct" and
  .inbounds[0].listen=="127.0.0.1" and
  .inbounds[0].listen_port==16001 and
  .inbounds[0].network=="tcp" and
  .inbounds[0].override_address=="2001:b030:a81d:a00::82:adf3" and
  .inbounds[0].override_port==10000 and
  (.outbounds|length)==1 and
  .outbounds[0].type=="socks" and
  .outbounds[0].server=="127.0.0.1" and
  .outbounds[0].server_port==40000 and
  .route.final=="warp-out"
' "$tmp/bridge.json" >/dev/null

# A pre-existing service without the managed marker must never be replaced.
SNELL_WARP_BRIDGE_SERVICE="$tmp/bridge.service"
SNELL_WARP_BRIDGE_MARKER="$tmp/bridge-owned"
SNELL_WARP_BRIDGE_CONF="$tmp/bridge-config.json"
cp "$tmp/bridge.json" "$SNELL_WARP_BRIDGE_CONF"
printf '[Service]\nExecStart=/usr/local/bin/sing-box run -c %s\n' "$SNELL_WARP_BRIDGE_CONF" > "$SNELL_WARP_BRIDGE_SERVICE"
if snell_warp_bridge_owned; then
    echo "FAIL: unmanaged bridge claimed"
    exit 1
fi
touch "$SNELL_WARP_BRIDGE_MARKER"
if ! snell_warp_bridge_owned; then
    echo "FAIL: owned bridge not recognized"
    exit 1
fi
# Status never mutates the proxy.
service_is_active() { return 1; }
status=$(snell_warp_bridge_show)
grep -Fq '127.0.0.1:16001' <<< "$status"
grep -Fq 'underlying-proxy=<Snell策略名>' <<< "$status"
grep -Fq '仅 TCP' <<< "$status"

# Guard against accidental public binding or global WARP mode changes.
if grep -E 'warp-cli .*mode (warp|tunnel)|ip(6|tables)?tables|nft add|ip -6 route add' ss2022.sh |
   grep -E 'snell_warp_bridge_' >/dev/null; then
    echo "FAIL: unexpected global network mutation"
    exit 1
fi
echo "PASS: isolated Snell/WARP TCP bridge config, loopback bind, ownership, Surge example"
