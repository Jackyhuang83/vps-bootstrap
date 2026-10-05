#!/usr/bin/env bash
set -euo pipefail

export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh

detect_platform
[[ "$PLATFORM_OS" == "alpine" ]]

arch=$(uname -m)
case "$arch" in
    x86_64|amd64)
        asset_arch="amd64"
        expected="$SNELL_SHA256_AMD64"
        ;;
    aarch64|arm64)
        asset_arch="aarch64"
        expected="$SNELL_SHA256_ARM64"
        ;;
    *)
        echo "Unsupported CI architecture: $arch"
        exit 1
        ;;
esac

tmp=$(mktemp -d)
pid=""
cleanup() {
    if [[ -n "$pid" ]]; then
        kill "$pid" >/dev/null 2>&1 || true
        wait "$pid" 2>/dev/null || true
    fi
    rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

zip="$tmp/snell.zip"
url="https://dl.nssurge.com/snell/snell-server-v${SNELL_VERSION}-linux-${asset_arch}.zip"

curl -fL --connect-timeout 20 --max-time 120 --retry 3 --retry-delay 2 -o "$zip" "$url"
actual=$(sha256sum "$zip" | awk '{print $1}')
[[ "$actual" == "$expected" ]]

unzip -oq "$zip" -d "$tmp"
chmod 755 "$tmp/snell-server"
snell_binary_works "$tmp/snell-server"

printf '%s\n' \
    '[snell-server]' \
    'listen = 127.0.0.1:63333' \
    'psk = ci-runtime-test' \
    'version = 5' \
    'ipv6 = false' \
    'obfs = off' > "$tmp/snell.conf"

"$tmp/snell-server" -c "$tmp/snell.conf" >"$tmp/snell.log" 2>&1 &
pid=$!

ready=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
    if ! kill -0 "$pid" >/dev/null 2>&1; then
        echo "Snell exited before becoming ready:"
        cat "$tmp/snell.log" || true
        exit 1
    fi
    if ss -lnt | grep -Eq '127\.0\.0\.1:63333|0\.0\.0\.0:63333'; then
        ready=1
        break
    fi
    sleep 0.2
done

if [[ $ready -ne 1 ]]; then
    echo "Snell did not listen on 127.0.0.1:63333:"
    cat "$tmp/snell.log" || true
    exit 1
fi

kill "$pid"
wait "$pid" 2>/dev/null || true
pid=""

echo "Official Snell runtime test passed on Alpine 3.21."
