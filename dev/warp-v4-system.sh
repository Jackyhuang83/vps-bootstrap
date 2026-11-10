#!/usr/bin/env bash
# DEV ONLY: IPv6-only VPS / WARP SOCKS5 -> system IPv4 TCP.
set -euo pipefail
D=/etc/ss2022/warp-v4-system
C=$D/config.json
U=/etc/systemd/system/ss2022-warp-v4-system.service
S=ss2022-warp-v4-system.service
T=ss2022-warp-v4-rollback.timer
SELF=/usr/local/sbin/ss2022-warp-v4-system
N=vbw4tun
P=40000
SB=/usr/local/bin/sing-box
IP=$(command -v ip || true)
fail(){ echo "STOP: $*" >&2; exit 1; }
owned(){ [[ -f "$D/owned" && -f "$C" && -f "$U" ]] && grep -Fq "ExecStart=$SB run -c $C" "$U"; }
route_owned(){ "$IP" -4 route show default | grep -Eq "^default dev $N([[:space:]]|$)"; }
trace_proxy(){ curl -4fsS --noproxy '' --socks5-hostname "127.0.0.1:$P" --max-time 12 https://1.1.1.1/cdn-cgi/trace | grep -qx 'warp=on'; }
trace_system(){ curl -4fsS --noproxy '*' --max-time 15 https://1.1.1.1/cdn-cgi/trace | grep -qx 'warp=on'; }
v6_ok(){ curl -6fsS --noproxy '*' --max-time 12 https://www.cloudflare.com/cdn-cgi/trace >/dev/null; }
precheck(){
 [[ $EUID -eq 0 && -n "$IP" && -x "$SB" && -c /dev/net/tun ]] || fail "需要 root/ip/sing-box/TUN"
 command -v jq >/dev/null && command -v systemd-run >/dev/null && [[ -d /run/systemd/system ]] || fail "需要 systemd/jq"
 [[ -z "$("$IP" -4 route show default)" ]] || fail "已有 IPv4 默认路由，不覆盖"
 "$IP" -6 route show default | grep -q '^default ' || fail "没有原生 IPv6 路由"
 ! "$IP" link show "$N" >/dev/null 2>&1 || fail "TUN 名称占用"
 [[ ! -e "$D" && ! -e "$U" && ! -e "$SELF" ]] || fail "已有同名文件/组件"
 ! "$IP" -4 route show table all | grep -Fq '172.31.254.0/30' || fail "TUN 私有网段与已有路由冲突"
 [[ -z "$("$IP" -4 route get 1.1.1.1 2>/dev/null || true)" ]] || fail "检测到已有可用 IPv4 策略路由，拒绝接管"
 warp-cli --accept-tos settings 2>/dev/null | grep -qi proxy || fail "WARP 未设置 Local Proxy"
 trace_proxy || fail "WARP SOCKS5 IPv4 验收失败"
 v6_ok || fail "原生 IPv6 HTTPS 失败"
 echo "PRECHECK_PASS: 不修改网络"
}
disable(){
 [[ $EUID -eq 0 ]] || fail "需要 root"
 if ! owned; then [[ ! -e "$U" && ! -e "$D/owned" ]] || fail "ownership 异常"; echo "Not installed"; return; fi
 systemctl stop "$T" >/dev/null 2>&1 || true
 systemctl disable "$S" >/dev/null 2>&1 || true
 systemctl stop "$S" >/dev/null 2>&1 || true
 if route_owned; then "$IP" -4 route del default dev "$N" || fail "route 清理失败"; fi
 ! "$IP" link show "$N" >/dev/null 2>&1 || fail "TUN 仍存在"
 rm -f "$U" "$C" "$D/owned"
 rmdir "$D" || true
 systemctl daemon-reload
 rm -f "$SELF"
 echo "DISABLED: 保留原生 IPv6 和 WARP Local Proxy"
}
wait_warp(){
 local i
 for ((i=0;i<30;i++)); do
  if trace_proxy >/dev/null 2>&1; then return 0; fi
  sleep 2
 done
 fail "WARP SOCKS5 未就绪，拒绝注入系统 IPv4 路由"
}
trial(){
 precheck
 install -m 755 "$0" "$SELF"
 install -d -m 700 "$D"
 jq -n --argjson p "$P" '{log:{level:"warn"},
   inbounds:[{type:"tun",tag:"warp4-in",interface_name:"vbw4tun",address:["172.31.254.1/30"],mtu:1400,auto_route:false,auto_redirect:false,stack:"system"}],
   outbounds:[{type:"socks",tag:"warp4-out",server:"127.0.0.1",server_port:$p,version:"5",network:"tcp"}],
   route:{final:"warp4-out"}}' > "$C"
 chmod 600 "$C"
 if ! "$SB" check -c "$C"; then rm -rf "$D"; rm -f "$SELF"; fail "sing-box check 失败"; fi
 cat > "$U" <<EOF
[Unit]
Description=vps-bootstrap IPv4 TCP WARP via isolated TUN
After=network-online.target warp-svc.service
Wants=network-online.target warp-svc.service
[Service]
Type=exec
ExecStartPre=$SELF wait-warp
ExecStart=$SB run -c $C
ExecStartPost=/bin/sh -c 'n=0; until $IP link show $N >/dev/null 2>&1; do n=\$((n+1)); [ \$n -lt 50 ] || exit 1; sleep .2; done; $IP -4 route add default dev $N'
ExecStopPost=-$IP -4 route del default dev $N
Restart=on-failure
RestartSec=5
TimeoutStartSec=90
NoNewPrivileges=true
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW
[Install]
WantedBy=multi-user.target
EOF
 chmod 644 "$U"; echo v1 > "$D/owned"; chmod 600 "$D/owned"
 systemctl daemon-reload
 if ! systemd-run --quiet --unit=ss2022-warp-v4-rollback --on-active=180s "$SELF" disable; then disable || true; fail "无法设置自动回滚"; fi
 if ! systemctl start "$S" || ! route_owned ||
   ! "$IP" -4 route get 1.1.1.1 | grep -q "dev $N" ||
   ! trace_system || ! v6_ok; then disable || true; fail "双栈验收失败，已请求回滚"; fi
 echo "TRIAL_PASS: 180 秒内运行 '$SELF confirm'；否则自动停止并清理路由"
}
confirm(){
 owned || fail "组件不属于工具箱"
 systemctl is-active --quiet "$S" && route_owned &&
   "$IP" -4 route get 1.1.1.1 | grep -q "dev $N" &&
   trace_system && v6_ok || fail "验收失败，不持久化"
 systemctl enable "$S" >/dev/null
 systemctl stop "$T" >/dev/null 2>&1 || true
 echo "CONFIRMED: IPv4 TCP 系统出口持久化，IPv6 不变"
}
status(){
 "$IP" -4 route show default; "$IP" -6 route show default
 systemctl is-active "$S" 2>/dev/null || true
 systemctl is-active "$T" 2>/dev/null || true
 echo "IPv4 TCP over WARP SOCKS5: supported"
 echo "IPv4 UDP/QUIC: NOT supported; native IPv6 DNS remains unchanged"
}
case "${1:-}" in
 precheck) precheck;; trial) trial;; confirm) confirm;; disable) disable;; status) status;; wait-warp) wait_warp;;
 *) echo "usage: $0 precheck|trial|confirm|status|disable"; exit 2;;
esac
