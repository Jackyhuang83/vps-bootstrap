#!/usr/bin/env bash
# Network tuning v1.10 dev1 regression tests: no real sysctl, tc, or routes altered.
set -euo pipefail
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
NET_TUNE_DIR="$tmp/state"
NET_TUNE_SNAPSHOT="$NET_TUNE_DIR/original.json"
NET_TUNE_SYSCTL_DIR="$tmp/sysctl.d"
NET_TUNE_SYSTEM_SYSCTL_CONF="$tmp/sysctl.conf"
NET_TUNE_CONF="$NET_TUNE_SYSCTL_DIR/99-ss2022-network-tuning.conf"
NET_TUNE_LEGACY_CONF="$NET_TUNE_SYSCTL_DIR/99-ss2022-bbr.conf"
MOCK_KERNEL="$tmp/kernel.json"
mkdir -p "$NET_TUNE_SYSCTL_DIR"

reset_kernel() {
    jq -n \
        '{"net.ipv4.tcp_congestion_control":"cubic",
          "net.ipv4.tcp_available_congestion_control":"reno cubic bbr",
          "net.core.default_qdisc":"fq_codel",
          "net.core.rmem_max":"212992",
          "net.core.wmem_max":"212992",
          "net.ipv4.tcp_rmem":"4096 131072 6291456",
          "net.ipv4.tcp_wmem":"4096 16384 4194304"}' > "$MOCK_KERNEL"
}

# Function overrides in the CI shell only. The test never writes a kernel parameter.
sysctl() {
    local key value next
    case "${1:-}" in
        -n)
            jq -er --arg k "$2" '.[$k] // empty' "$MOCK_KERNEL"
            ;;
        -w)
            key=${2%%=*}
            value=${2#*=}
            [[ -n "$key" && -n "$value" ]] || return 1
            next=$(mktemp "$tmp/kernel.XXXXXXXX")
            jq --arg k "$key" --arg v "$value" '.[$k]=$v' "$MOCK_KERNEL" > "$next"
            mv "$next" "$MOCK_KERNEL"
            ;;
        *)
            echo "unexpected sysctl argument" >&2
            return 1
            ;;
    esac
}

assert_kernel() {
    [[ "$(sysctl -n net.ipv4.tcp_congestion_control)" == "$1" ]]
    [[ "$(sysctl -n net.core.default_qdisc)" == "$2" ]]
}

reset_kernel
network_tuning_snapshot
[[ -s "$NET_TUNE_SNAPSHOT" ]]
[[ "$(stat -c %a "$NET_TUNE_SNAPSHOT")" == 600 ]]
[[ "$(stat -c %a "$NET_TUNE_DIR")" == 700 ]]
[[ "$(jq -r '.baseline.congestion' "$NET_TUNE_SNAPSHOT")" == cubic ]]
[[ "$(jq -r '.baseline.qdisc' "$NET_TUNE_SNAPSHOT")" == fq_codel ]]
[[ "$(jq -r '.baseline.tcp_rmem' "$NET_TUNE_SNAPSHOT")" == '4096 131072 6291456' ]]
original_hash=$(sha256sum "$NET_TUNE_SNAPSHOT" | awk '{print $1}')
network_tuning_snapshot
[[ "$(sha256sum "$NET_TUNE_SNAPSHOT" | awk '{print $1}')" == "$original_hash" ]]
assert_kernel cubic fq_codel

network_tuning_enable_bbr
assert_kernel bbr fq
network_tuning_conf_is_owned
[[ -f "$NET_TUNE_CONF" ]]
network_tuning_restore
assert_kernel cubic fq_codel
[[ ! -e "$NET_TUNE_CONF" ]]
[[ -s "$NET_TUNE_SNAPSHOT" ]]

# Legacy migration: preserve pre-existing v1.9 project-owned BBR upon rollback.
rm -rf "$NET_TUNE_DIR"
printf '%s\n' 'net.core.default_qdisc=fq' \
    'net.ipv4.tcp_congestion_control=bbr' > "$NET_TUNE_LEGACY_CONF"
sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null
sysctl -w net.core.default_qdisc=fq >/dev/null
[[ "$(network_tuning_legacy_status)" == owned ]]
network_tuning_snapshot
[[ "$(jq -r '.legacy_bbr' "$NET_TUNE_SNAPSHOT")" == owned ]]
network_tuning_enable_bbr
[[ ! -e "$NET_TUNE_LEGACY_CONF" ]]
network_tuning_conf_is_owned
network_tuning_restore
[[ "$(network_tuning_legacy_status)" == owned ]]
[[ ! -e "$NET_TUNE_CONF" ]]
assert_kernel bbr fq

# Edited legacy BBR file must not be treated as project-managed.
printf '%s\n' 'net.core.default_qdisc=cake' > "$NET_TUNE_LEGACY_CONF"
if network_tuning_assert_safe; then
    echo "FAIL: modified legacy configuration was accepted" >&2
    exit 1
fi
rm -f "$NET_TUNE_LEGACY_CONF"

# Arbitrary external /etc/sysctl.d config must block mutation.
printf '%s\n' 'net.ipv4.tcp_congestion_control=reno' > "$NET_TUNE_SYSCTL_DIR/90-custom.conf"
if network_tuning_assert_safe; then
    echo "FAIL: external sysctl owner was overwritten" >&2
    exit 1
fi
rm -f "$NET_TUNE_SYSCTL_DIR/90-custom.conf"

# Unknown new config must never be overwritten.
printf '%s\n' '# foreign' > "$NET_TUNE_CONF"
if network_tuning_assert_safe; then
    echo "FAIL: unknown network tuning config was accepted" >&2
    exit 1
fi
rm -f "$NET_TUNE_CONF"

# A new managed config without its original snapshot cannot invent a baseline.
rm -rf "$NET_TUNE_DIR"
printf '%s\n' \
    '# vps-bootstrap network tuning: BBR/fq (managed by ss2022.sh)' \
    'net.core.default_qdisc=fq' \
    'net.ipv4.tcp_congestion_control=bbr' > "$NET_TUNE_CONF"
if network_tuning_snapshot; then
    echo "FAIL: missing original baseline was silently recreated" >&2
    exit 1
fi
[[ ! -f "$NET_TUNE_SNAPSHOT" ]]
rm -f "$NET_TUNE_CONF"

# Corrupted saved baseline is never overwritten.
mkdir -p "$NET_TUNE_DIR"
printf '%s\n' '{"schema":99}' > "$NET_TUNE_SNAPSHOT"
if network_tuning_snapshot; then
    echo "FAIL: corrupted original baseline was overwritten" >&2
    exit 1
fi
grep -Fq '"schema":99' "$NET_TUNE_SNAPSHOT"

echo "Network tuning smoke tests passed."
