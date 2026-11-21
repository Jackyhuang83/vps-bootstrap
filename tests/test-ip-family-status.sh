#!/usr/bin/env bash
# Menu regression: RFC1918 NIC addresses must never masquerade as public ingress.
# No network access, configuration changes, or real VPS operations.
set -euo pipefail
cd "$(dirname "$0")/.."
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh

fixture=$(mktemp -d /tmp/ss2022-ip-family-status.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
RED="" GREEN="" YELLOW="" CYAN="" PLAIN=""
server_tool_ip_family_mode() { echo dual; }
routing_global_ip_family() { echo default; }
server_tool_ip_priority_status() { echo "默认"; }
SCENARIO=nat
ip() {
    case "$*" in
        "-4 -o addr show scope global"|"-o -4 addr show scope global")
            if [[ "$SCENARIO" == nat ]]; then
                printf '%s\n' "2: ens3 inet 172.20.5.9/20 scope global ens3"
            else
                printf '%s\n' "2: eth0 inet 11.22.33.44/24 scope global eth0" \
                    "3: wgcf inet 172.16.0.2/32 scope global wgcf"
            fi
            ;;
        "-6 -o addr show scope global")
            printf '%s\n' "2: eth0 inet6 2001:db8::7/64 scope global eth0"
            ;;
        *) return 2 ;;
    esac
}
curl() {
    printf '%s\n' "$*" >> "$fixture/curl-args"
    printf '104.16.0.9'
}
contains() {
    [[ "$1" == *"$2"* ]] || {
        printf 'FAIL: expected [%s] in output:\n%s\n' "$2" "$1" >&2
        exit 1
    }
}

# Cloud NAT: 172.20.5.9 is a local interface and never a client entry.
out=$(server_tool_ip_family_status)
contains "$out" "IPv4 网卡地址   : 172.20.5.9/20（可能是私网/NAT）"
contains "$out" "IPv4 公网入口候选: 无法自动确认（云 NAT 请以 VPS 控制台为准）"
contains "$out" "IPv4 公网出口   : 104.16.0.9（可能是 WARP/NAT"
contains "$out" "IPv6 网卡地址   : 2001:db8::7/64"
contains "$out" "系统协议族状态"
if [[ "$out" == *"IPv4 公网入口候选: 104.16.0.9"* ]]; then
    echo 'FAIL: WARP egress was mislabeled public ingress'; exit 1
fi
grep -Fq -- '--connect-timeout 2 --max-time 4' "$fixture/curl-args"

# One native public interface: show it as a *candidate*, not the WARP egress.
SCENARIO=native
out=$(server_tool_ip_family_status)
contains "$out" "IPv4 网卡地址   : 11.22.33.44/24"
contains "$out" "IPv4 公网入口候选: 11.22.33.44"
contains "$out" "IPv4 公网出口   : 104.16.0.9"
echo 'PASS: IPv4 NAT/native ingress distinguished from WARP egress in IP-family menu'
