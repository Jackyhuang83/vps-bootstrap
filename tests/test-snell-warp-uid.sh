#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh

temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT

snell_warp_uid_config_json 40000 > "$temp/route.json"
jq -e '
  (.inbounds|length)==1 and
  .inbounds[0].type=="tun" and
  .inbounds[0].interface_name=="swipv6tun" and
  .inbounds[0].address==["fd7e:5e11:2022::1/64"] and
  .inbounds[0].auto_route==false and
  .inbounds[0].auto_redirect==false and
  (.outbounds|length)==1 and
  .outbounds[0].type=="socks" and
  .outbounds[0].server=="127.0.0.1" and
  .outbounds[0].server_port==40000 and
  .outbounds[0].network=="tcp" and
  .route.final=="warp-v6"
' "$temp/route.json" >/dev/null

SNELL_WARP_UID_SERVICE="$temp/uid.service"
SNELL_WARP_UID_MARKER="$temp/marker"
SNELL_WARP_UID_CONF="$temp/uid.json"
SINGBOX_BIN="/usr/local/bin/sing-box"
cp "$temp/route.json" "$SNELL_WARP_UID_CONF"
echo "[Service]" > "$SNELL_WARP_UID_SERVICE"
echo "ExecStart=$SINGBOX_BIN run -c $SNELL_WARP_UID_CONF" >> "$SNELL_WARP_UID_SERVICE"
! snell_warp_uid_owned
touch "$SNELL_WARP_UID_MARKER"
snell_warp_uid_owned

SNELL_CONF="$temp/snell.conf"
SNELL_WARP_UID_BACKUP="$temp/backup.conf"
SNELL_WARP_UID_ACTIVE_SHA="$temp/active.sha"
printf 'listen=0.0.0.0:12345\npsk=secret-not-printed\nipv6 = true\n' > "$SNELL_CONF"
printf 'listen=0.0.0.0:12345\npsk=secret-not-printed\nipv6 = false\n' > "$SNELL_WARP_UID_BACKUP"
sha256sum "$SNELL_CONF" | awk '{print $1}' > "$SNELL_WARP_UID_ACTIVE_SHA"
service_restart() { :; }
service_is_active() { return 0; }
snell_warp_uid_restore
grep -Fq 'ipv6 = false' "$SNELL_CONF"
[[ ! -e "$SNELL_WARP_UID_BACKUP" && ! -e "$SNELL_WARP_UID_ACTIVE_SHA" ]]

printf 'ipv6 = true\n' > "$SNELL_CONF"
cp "$SNELL_CONF" "$SNELL_WARP_UID_BACKUP"
sha256sum "$SNELL_CONF" | awk '{print $1}' > "$SNELL_WARP_UID_ACTIVE_SHA"
echo '# user changed configuration later' >> "$SNELL_CONF"
if snell_warp_uid_restore >/dev/null 2>&1; then
    echo "FAIL: overwrote user modification"
    exit 1
fi
grep -Fq '# user changed configuration later' "$SNELL_CONF"

# The isolated service must only add 2000::/3 to a private table for Snell UID.
deploy=$(declare -f snell_warp_uid_deploy)
grep -Fq 'table 16381' <<<"$deploy"
grep -Fq 'uidrange $uid-$uid ipproto tcp' <<<"$deploy"
grep -Fq 'to 2000::/3' <<<"$deploy"
grep -Fq 'ip -6 rule show' <<<"$deploy"
grep -Fq 'snell_is_project_managed' <<<"$deploy"
grep -Fq 'warp_proxy_ready' <<<"$deploy"
! grep -Eq 'ip -6 route (add|replace) default|nft add|iptables -' <<<"$deploy"
echo "PASS: Snell UID WARP IPv6 TCP config, exact routing and rollback safeguards"
