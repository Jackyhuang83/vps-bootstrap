#!/usr/bin/env bash
# No network or packages are touched: apk/apt-get are mocked.
set -euo pipefail
cd "$(dirname "$0")/.."
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh

workdir="$(mktemp -d /tmp/ss2022-apk-regression.XXXXXX)"
trap 'rm -rf "$workdir"' EXIT
calls="$workdir/calls"
scenario=""
PLATFORM_PKG=apk

sleep() { :; }
apk() {
    [[ "$1" == update ]] || { echo "unexpected apk command: $*" >&2; return 2; }
    printf x >> "$calls"
    local number
    number="$(wc -c < "$calls")"
    case "$scenario" in
        apk2_ok) echo 'OK: 27586 distinct packages available'; return 0 ;;
        apk3_ok) echo '0 unavailable, 0 stale; 27586 distinct packages available'; return 0 ;;
        stale_nonzero)
            echo 'v3.23.5-211-g638208adad0 [https://dl-cdn.alpinelinux.org/alpine/v3.23/community]'
            echo '0 unavailable, 2 stale; 27586 distinct packages available'
            return 1 ;;
        stale_zero) echo '0 unavailable, 2 stale; 27586 distinct packages available'; return 0 ;;
        unavailable_zero) echo '2 unavailable, 0 stale; 27586 distinct packages available'; return 0 ;;
        warning_zero) echo 'WARNING: updating https://example.invalid: TLS handshake failed'; return 0 ;;
        transient)
            if (( number == 1 )); then
                echo 'WARNING: updating https://example.invalid: temporary error'
                return 1
            fi
            echo '0 unavailable, 0 stale; 27586 distinct packages available'
            return 0 ;;
        *) echo "unexpected scenario: $scenario" >&2; return 2 ;;
    esac
}
check_case() {
    local name="$1" expected_status="$2" expected_attempts="$3" result=0 output count
    scenario="$name"
    : > "$calls"
    output="$(pkg_update 2>&1)" || result=$?
    count="$(wc -c < "$calls")"
    [[ "$result" == "$expected_status" ]] || {
        echo "FAIL: $name expected exit $expected_status, got $result" >&2; exit 1;
    }
    [[ "$count" == "$expected_attempts" ]] || {
        echo "FAIL: $name expected $expected_attempts update(s), got $count" >&2; exit 1;
    }
    if (( expected_status != 0 )); then
        [[ "$output" == *"已停止安装依赖"* ]] || {
            echo "FAIL: $name lacked actionable diagnosis" >&2; exit 1;
        }
    fi
}
check_case apk2_ok 0 1
check_case apk3_ok 0 1
check_case transient 0 2
check_case stale_nonzero 1 2
check_case stale_zero 1 2
check_case unavailable_zero 1 2
check_case warning_zero 1 2

pkg_install() { touch "$workdir/installed"; }
scenario=stale_nonzero
: > "$calls"
if install_dependencies >"$workdir/install.log" 2>&1; then
    echo "FAIL: install_dependencies accepted stale indexes" >&2; exit 1
fi
[[ ! -e "$workdir/installed" ]] || {
    echo "FAIL: attempted package installation with stale indexes" >&2; exit 1;
}

PLATFORM_PKG=apt
apt-get() { [[ "$1" == update && "$2" == -y ]]; }
pkg_update || { echo "FAIL: Debian/Ubuntu update path regressed" >&2; exit 1; }
echo 'PASS: apk-tools 2/3 success, stale/unavailable fail-closed, retry, apt path'
