#!/usr/bin/env bash
# Xray restart guard regression: no network, root writes or real service calls.
set -euo pipefail
cd "$(dirname "$0")/.."
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
XRAY_BIN="$fixture/xray"
XRAY_CONF="$fixture/config.json"
cat > "$XRAY_BIN" <<'SH'
#!/bin/bash
if [[ "${1:-}" == run && "${2:-}" == -test ]]; then
    exit "${FAKE_XRAY_TEST:-0}"
fi
exit 1
SH
chmod 755 "$XRAY_BIN"
UNIT=yes
RESTART_OK=yes
ACTIVE=yes
service_exists() { [[ "$1" == "$XRAY_SERVICE_NAME" && "$UNIT" == yes ]]; }
service_restart() { echo "RESTART_CALLED"; [[ "$RESTART_OK" == yes ]]; }
service_is_active() { [[ "$ACTIVE" == yes ]]; }
write_xray_service() { echo "UNIT_CREATED"; UNIT=yes; }
xray_restart_diagnostics() { echo "DIAGNOSTICS_SHOWN"; }
sleep() { :; }

assert_failure() {
    local output="$1" expected="$2"
    [[ "$output" == *"$expected"* ]] || { printf 'FAIL: missing %s in %s\n' "$expected" "$output"; exit 1; }
}

# Installed engine alone is not a deployed VLESS node.
out=$(restart_xray_safe </dev/null 2>&1) && { echo "FAIL: absent config"; exit 1; }
assert_failure "$out" "尚无本工具箱的 VLESS 配置"
[[ "$out" != *RESTART_CALLED* ]]

printf '%s\n' '{"inbounds":[{"protocol":"vless","tag":"vless-reality-in"}]}' > "$XRAY_CONF"
export FAKE_XRAY_TEST=1
out=$(restart_xray_safe </dev/null 2>&1) && { echo "FAIL: invalid core precheck"; exit 1; }
assert_failure "$out" "配置预检失败"
[[ "$out" != *RESTART_CALLED* ]]
export FAKE_XRAY_TEST=0

# Missing service: no implicit registration without confirmation.
UNIT=no
out=$(restart_xray_safe </dev/null 2>&1) && { echo "FAIL: missing service"; exit 1; }
assert_failure "$out" "服务未注册"
[[ "$out" != *UNIT_CREATED* ]]

# Explicit approval recreates only the mock dedicated service.
out=$(printf 'y\n' | restart_xray_safe 2>&1)
assert_failure "$out" "UNIT_CREATED"
assert_failure "$out" "处于运行状态"

# A system service may report a successful restart and then exit immediately.
UNIT=yes; ACTIVE=no
out=$(restart_xray_safe </dev/null 2>&1) && { echo "FAIL: expected inactive state"; exit 1; }
assert_failure "$out" "未保持运行"
assert_failure "$out" "DIAGNOSTICS_SHOWN"

ACTIVE=yes; RESTART_OK=no
out=$(restart_xray_safe </dev/null 2>&1) && { echo "FAIL: expected service restart error"; exit 1; }
assert_failure "$out" "重启命令失败"

RESTART_OK=yes
out=$(restart_xray_safe </dev/null 2>&1)
assert_failure "$out" "处于运行状态"

echo "PASS: Xray restart guards and state verification"
