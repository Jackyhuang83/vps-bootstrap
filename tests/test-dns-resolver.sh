#!/usr/bin/env bash
# Regression: DNS settings must never split IPv4 addresses into individual octets.
# Extract and redirect only the DNS function so no real /etc/resolv.conf is modified.
set -euo pipefail
cd "$(dirname "$0")/.."
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh

fixture=$(mktemp -d /tmp/ss2022-dns-regression.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
STATE_DIR="$fixture/state"
printf '%s\n' 'nameserver 127.0.0.1' > "$fixture/resolv.conf"

# Exercise the production function, but confine all resolver file operations to the fixture.
safe_fn=$(declare -f server_tool_dns_apply | sed "s|/etc/resolv.conf|$fixture/resolv.conf|g")
eval "$safe_fn"
server_tool_dns_apply "1.1.1.1 8.8.8.8 2606:4700:4700::1111 2001:4860:4860::8888" > "$fixture/output"

cat > "$fixture/expected" <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 2606:4700:4700::1111
nameserver 2001:4860:4860::8888
options timeout:2 attempts:2
EOF
if ! cmp -s "$fixture/expected" "$fixture/resolv.conf"; then
    echo 'FAIL: IPv4 DNS octets or IPv6 entries were split incorrectly'
    diff -u "$fixture/expected" "$fixture/resolv.conf" || true
    exit 1
fi
[[ -f "$STATE_DIR/resolv.conf.server-tools.bak" ]]
grep -Fxq 'nameserver 127.0.0.1' "$STATE_DIR/resolv.conf.server-tools.bak"
[[ "$IFS" == $' \t\n' ]] || { echo 'FAIL: DNS parser leaked modified IFS'; exit 1; }

cp "$fixture/resolv.conf" "$fixture/snapshot"
if server_tool_dns_apply "300.1.1.1 8.8.8.8" > "$fixture/invalid-output"; then
    echo 'FAIL: invalid IPv4 accepted'; exit 1
fi
cmp -s "$fixture/resolv.conf" "$fixture/snapshot" || {
    echo 'FAIL: invalid DNS changed existing resolver'; exit 1
}
echo 'PASS: DNS parser scope, resolver output, IPv6, backup and invalid IPv4'
