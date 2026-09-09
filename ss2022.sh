#!/bin/bash
# ==============================================================================
# 项目名称: VPS Bootstrap & SS2022 多协议代理管理脚本
# 快捷命令: ss2022 / proxy
# 当前版本: v1.7.0-dev6
#
# v1.7.0-dev6:
#   - 修复 VLESS Reality 服务端 inbound 错误写入 network 字段的问题
#   - sing-box 1.13.20 的 VLESS inbound 不支持 network 字段；仅 VLESS outbound 支持该字段
#   - 修复后可正常按项更新 Reality SNI，失败时仍保持原配置不变
#
# v1.7.0-dev5:
#   - 修复“更新”仍然进入整套部署问答的问题
#   - 四种协议的更新统一改为“当前配置 + 按项修改”菜单
#   - 修改单一参数时不再要求重填网络/端口/SNI/地址等无关参数
#   - VLESS 可单独修改 Reality SNI，默认保留 UUID / Reality Key / Short ID
#
# v1.7.0-dev4:
#   - 四种代理模式统一改为二级管理菜单：部署 / 更新 / 删除
#   - 部署：仅用于新建节点；检测到已存在时拒绝覆盖
#   - 更新：保留现有密钥/UUID/PSK，仅修改端口、网络、SNI、UDP、服务器地址等配置
#   - 删除：在对应协议菜单内直接删除，不再要求进入服务运维菜单
#   - VLESS Reality 更新不会重新生成 UUID / Reality Key / Short ID
#
# v1.7.0-dev3:
#   - 节点输出统一增加：通用/分享信息、Surge、Loon、FlClash(Mihomo)、Shadowrocket、二维码
#   - VLESS Reality 默认握手目标改为 swdist.apple.com，可快捷选择 www.icloud.com 或自定义
#   - 对客户端不支持的协议明确标注，不生成伪配置
#
# v1.7.0-dev2:
#   - 修复 VLESS Reality 默认握手目标：由 www.microsoft.com 改为 www.cloudflare.com
#   - VLESS Reality 显式限定 TCP，并提示 Surge 不支持 VLESS
#
# v1.7.0-dev1:
#   - 保留 v1.6.1 SS2022 / IPv4 / IPv6 / 时间同步 / SHA256 / 非 root / 回滚机制
#   - 新增 SS2022 + ShadowTLS v3（sing-box chained inbound）
#   - 新增 VLESS Reality（sing-box）
#   - 新增 Snell v5.0.1（Surge 官方 snell-server，独立 systemd）
#   - ShadowTLS UDP Relay 可选，启用时使用独立 SS2022 UDP 端口
#   - sing-box 多协议入口可共存，按 tag 增删，不再互相覆盖
#
# 注意:
#   这是开发版。建议先在测试 VPS 验证，再替换公开分发的 v1.6.1。
# ==============================================================================

SCRIPT_VERSION="v1.7.0-dev6"
AUTHOR="DevOps"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# ----------------------------- sing-box ---------------------------------------
SINGBOX_BIN="/usr/local/bin/sing-box"
SINGBOX_CONF="/etc/sing-box/config.json"
SINGBOX_SERVICE="/etc/systemd/system/sing-box.service"
SINGBOX_USER="sing-box"
SINGBOX_GROUP="sing-box"
SINGBOX_USER_MARKER="/etc/ss2022-singbox-user-managed"
SINGBOX_VERSION="1.13.20"

# ----------------------------- Snell v5 ---------------------------------------
SNELL_VERSION="5.0.1"
SNELL_BIN="/usr/local/bin/snell-server-v5"
SNELL_CONF="/etc/snell/snell-v5.conf"
SNELL_SERVICE="/etc/systemd/system/snell-v5.service"
SNELL_USER="snell"
SNELL_GROUP="snell"
SNELL_USER_MARKER="/etc/ss2022-snell-user-managed"

# Snell 官方 v5.0.1 固定资产 SHA256（参考成熟模板并固定到官方 dl.nssurge.com 资产）
SNELL_SHA256_AMD64="9bea1c2b9e35b73b31634856c04d18c393072b9e5dcde6a32781d8b8f908c539"
SNELL_SHA256_ARM64="2f178bf5ac468ce1a130454efa40a0603fbbe4e47ecc4880a989f4abc7f824cf"

# ----------------------------- 网络环境 ----------------------------------------
BACKUP_DNS="/root/resolv.conf.orig"
DNS_MARKER="/etc/ss2022-ipv6-dns-managed"
FORCE_IPV6_CONF="/etc/apt/apt.conf.d/99force-ipv6"
STATE_DIR="/etc/ss2022"
STATE_FILE="${STATE_DIR}/state.json"

# ----------------------------- sing-box tag -----------------------------------
TAG_SS="ss-in"
TAG_STLS="ss-shadowtls-in"
TAG_STLS_BACKEND="ss-shadowtls-backend"
TAG_STLS_UDP="ss-shadowtls-udp"
TAG_VLESS="vless-reality-in"

# ----------------------------- 全局临时参数 -------------------------------------
PORT=""
METHOD=""
KEY_BYTES=""
SS_KEY=""
SERVER_HOST=""
NETWORK_MODE=""
LISTEN_ADDR=""

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[错误] 必须使用 root 权限运行此脚本！${PLAIN}"
        exit 1
    fi
}

pause() {
    read -rp "按回车继续..."
}

get_sys_info() {
    local os="" ver="" kernel=""
    if [[ -f /etc/os-release ]]; then
        os=$(grep -E '^(ID)=' /etc/os-release | cut -d= -f2 | tr -d '"')
        ver=$(grep -E '^(VERSION_ID)=' /etc/os-release | cut -d= -f2 | tr -d '"')
        os="${os} ${ver}"
    else
        os=$(uname -s)
    fi
    kernel=$(uname -r)
    echo "${os} | ${kernel}"
}

get_singbox_version() {
    if [[ -x "$SINGBOX_BIN" ]]; then
        local sb_v
        sb_v=$("$SINGBOX_BIN" version 2>/dev/null | head -n 1 | awk '{print $3}')
        echo "Sing-box ${sb_v:-已安装}"
    else
        echo "Sing-box 未安装"
    fi
}

get_snell_version() {
    if [[ -x "$SNELL_BIN" ]]; then
        echo "Snell v${SNELL_VERSION}"
    else
        echo "Snell 未安装"
    fi
}

time_sync_is_healthy() {
    local ntp_sync=""
    if command -v timedatectl &>/dev/null; then
        ntp_sync=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)
        [[ "$ntp_sync" == "yes" ]] && return 0
    fi

    if command -v chronyc &>/dev/null; then
        if chronyc tracking 2>/dev/null | grep -Eq '^Leap status[[:space:]]*:[[:space:]]*Normal$'; then
            return 0
        fi
    fi
    return 1
}

get_time_sync_status() {
    if time_sync_is_healthy; then
        echo -e "${GREEN}● 已同步${PLAIN}"
    elif command -v chronyc &>/dev/null || command -v timedatectl &>/dev/null; then
        echo -e "${YELLOW}○ 未同步${PLAIN}"
    else
        echo -e "${YELLOW}○ 未检测${PLAIN}"
    fi
}

json_has_inbound_tag() {
    local tag="$1"
    [[ -f "$SINGBOX_CONF" ]] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    jq -e --arg t "$tag" '.inbounds[]? | select(.tag == $t)' "$SINGBOX_CONF" >/dev/null 2>&1
}

get_inbound_port() {
    local tag="$1"
    [[ -f "$SINGBOX_CONF" ]] || return 1
    jq -r --arg t "$tag" '.inbounds[]? | select(.tag == $t) | .listen_port // empty' "$SINGBOX_CONF" 2>/dev/null | head -n 1
}

show_dashboard() {
    clear
    local sys_info singbox_info snell_info time_sync_status
    local sb_status="${YELLOW}○ 未安装${PLAIN}"
    local snell_status="${YELLOW}○ 未安装${PLAIN}"
    local keepalive_status="${YELLOW}○ 未配置${PLAIN}"
    local proto_list="" installed_count=0
    local p=""

    sys_info=$(get_sys_info)
    singbox_info=$(get_singbox_version)
    snell_info=$(get_snell_version)
    time_sync_status=$(get_time_sync_status)

    if systemctl is-active --quiet sing-box 2>/dev/null; then
        sb_status="${GREEN}● 运行中${PLAIN}"
    elif [[ -f "$SINGBOX_CONF" || -x "$SINGBOX_BIN" ]]; then
        sb_status="${RED}○ 已停止${PLAIN}"
    fi

    if systemctl is-active --quiet snell-v5 2>/dev/null; then
        snell_status="${GREEN}● 运行中${PLAIN}"
    elif [[ -f "$SNELL_CONF" || -x "$SNELL_BIN" ]]; then
        snell_status="${RED}○ 已停止${PLAIN}"
    fi

    if systemctl is-active --quiet ipv6-keepalive.timer 2>/dev/null; then
        keepalive_status="${GREEN}● 已激活 (5min轮询)${PLAIN}"
    fi

    if json_has_inbound_tag "$TAG_SS"; then
        p=$(get_inbound_port "$TAG_SS")
        ((installed_count++))
        proto_list+="\n    • SS2022 - 端口: ${CYAN}${p:-内部}${PLAIN}"
    fi

    if json_has_inbound_tag "$TAG_STLS"; then
        p=$(get_inbound_port "$TAG_STLS")
        ((installed_count++))
        proto_list+="\n    • SS2022 + ShadowTLS v3 - TCP端口: ${CYAN}${p}${PLAIN}"
        if json_has_inbound_tag "$TAG_STLS_UDP"; then
            p=$(get_inbound_port "$TAG_STLS_UDP")
            proto_list+=" / UDP: ${CYAN}${p}${PLAIN}"
        fi
    fi

    if json_has_inbound_tag "$TAG_VLESS"; then
        p=$(get_inbound_port "$TAG_VLESS")
        ((installed_count++))
        proto_list+="\n    • VLESS Reality - 端口: ${CYAN}${p}${PLAIN}"
    fi

    if [[ -f "$SNELL_CONF" ]]; then
        p=$(awk -F'[: ]+' '/^[[:space:]]*listen[[:space:]]*=/{gsub(/\[/,"",$0); gsub(/\]/,"",$0); print $NF; exit}' "$SNELL_CONF" 2>/dev/null)
        ((installed_count++))
        proto_list+="\n    • Snell v5 - 端口: ${CYAN}${p:-未知}${PLAIN}"
    fi

    echo -e "${CYAN}═════════════════════════════════════════════════════════════════${PLAIN}"
    echo -e "      SS2022 多协议代理管理脚本 ${SCRIPT_VERSION}"
    echo -e "      快捷命令: ${GREEN}ss2022${PLAIN} 或 ${GREEN}proxy${PLAIN}"
    echo -e "${CYAN}═════════════════════════════════════════════════════════════════${PLAIN}"
    echo -e "  系统信息: ${sys_info}"
    echo -e "  sing-box: ${singbox_info} / ${sb_status}"
    echo -e "  Snell核心: ${snell_info} / ${snell_status}"
    echo -e "  时间同步: ${time_sync_status}"
    echo -e "  IPv6链路保活: ${keepalive_status}"
    if [[ $installed_count -gt 0 ]]; then
        echo -e "  活跃协议: ${GREEN}已部署 (${installed_count}个)${PLAIN}${proto_list}"
    else
        echo -e "  活跃协议: ${YELLOW}未配置${PLAIN}"
    fi
    echo -e "${CYAN}═════════════════════════════════════════════════════════════════${PLAIN}"
}

restore_ipv4_apt_and_dns_if_needed() {
    rm -f "$FORCE_IPV6_CONF"

    local should_restore=0
    if [[ -f "$DNS_MARKER" ]]; then
        should_restore=1
    elif [[ -f "$BACKUP_DNS" && -f /etc/resolv.conf && ! -L /etc/resolv.conf ]] \
         && grep -q '2001:4860:4860::8888' /etc/resolv.conf \
         && grep -q '2606:4700:4700::1111' /etc/resolv.conf; then
        should_restore=1
    fi

    if [[ $should_restore -eq 1 && -f "$BACKUP_DNS" && ! -L /etc/resolv.conf ]]; then
        if cp -f "$BACKUP_DNS" /etc/resolv.conf; then
            rm -f "$DNS_MARKER"
            echo -e "${GREEN}✔ 已恢复 IPv4/双栈环境原 DNS 配置。${PLAIN}"
        else
            echo -e "${YELLOW}[警告] DNS 自动恢复失败，请手动检查 /etc/resolv.conf。${PLAIN}"
        fi
    fi
}

ensure_time_sync() {
    local attempt=0

    echo -e "${YELLOW}>> 检查系统时间同步状态...${PLAIN}"
    if time_sync_is_healthy; then
        echo -e "${GREEN}✔ 系统时间已同步。当前 UTC: $(date -u '+%Y-%m-%d %H:%M:%S UTC')${PLAIN}"
        return 0
    fi

    echo -e "${YELLOW}[提示] 系统时钟尚未同步，准备使用 chrony 自动校时。${PLAIN}"
    if ! command -v chronyc &>/dev/null; then
        if ! apt-get install -y chrony; then
            echo -e "${RED}[错误] chrony 安装失败。SS2022 / Reality 对时间偏差敏感，停止部署。${PLAIN}"
            return 1
        fi
    fi

    if ! systemctl enable --now chrony >/dev/null 2>&1; then
        echo -e "${RED}[错误] chrony 服务启动失败。${PLAIN}"
        return 1
    fi

    systemctl restart chrony >/dev/null 2>&1 || true
    chronyc -a burst 4/4 >/dev/null 2>&1 || true
    sleep 2
    chronyc -a makestep >/dev/null 2>&1 || true

    for attempt in {1..15}; do
        if time_sync_is_healthy; then
            echo -e "${GREEN}✔ 系统时间同步完成。当前 UTC: $(date -u '+%Y-%m-%d %H:%M:%S UTC')${PLAIN}"
            return 0
        fi
        sleep 2
    done

    echo -e "${RED}[错误] 30 秒内未确认系统时间同步。停止部署。${PLAIN}"
    chronyc tracking 2>/dev/null || true
    return 1
}

install_dependencies() {
    echo -e "${YELLOW}>> 更新 APT 索引...${PLAIN}"
    if ! apt-get update -y; then
        echo -e "${RED}[错误] apt-get update 失败，请检查网络或软件源。${PLAIN}"
        return 1
    fi

    echo -e "${YELLOW}>> 安装运行依赖...${PLAIN}"
    if ! apt-get install -y curl jq openssl coreutils qrencode ca-certificates iproute2 tar unzip; then
        echo -e "${RED}[错误] 依赖安装失败。${PLAIN}"
        return 1
    fi
    return 0
}

prepare_ipv4_env() {
    local require_time_sync="${1:-yes}"
    echo -e "${YELLOW}>> 初始化 IPv4 / 双栈部署环境...${PLAIN}"
    restore_ipv4_apt_and_dns_if_needed
    install_dependencies || return 1
    if [[ "$require_time_sync" == "yes" ]]; then
        ensure_time_sync || return 1
    fi
    return 0
}

dns_ipv6_resolution_works() {
    local host=""
    for host in deb.debian.org github.com cloudflare.com; do
        if getent ahostsv6 "$host" 2>/dev/null | grep -q ':'; then
            return 0
        fi
    done
    return 1
}

prepare_ipv6_env() {
    local require_time_sync="${1:-yes}"
    echo -e "${YELLOW}>> 初始化 IPv6-only 部署环境...${PLAIN}"

    if ! ip -6 addr show scope global 2>/dev/null | grep -q 'inet6 '; then
        echo -e "${RED}[错误] 未检测到全局 IPv6 地址，无法使用 IPv6-only 模式。${PLAIN}"
        return 1
    fi

    sed -i '/github/d' /etc/hosts 2>/dev/null || true
    sed -i '/ghproxy/d' /etc/hosts 2>/dev/null || true
    sed -i '/danwin/d' /etc/hosts 2>/dev/null || true

    if dns_ipv6_resolution_works; then
        echo -e "${GREEN}✔ 当前 DNS 可正常解析 IPv6 地址，不修改 /etc/resolv.conf。${PLAIN}"
    else
        echo -e "${YELLOW}[提示] 当前 DNS 无法完成 IPv6 解析，准备使用公共 IPv6 DNS 兜底。${PLAIN}"

        if [[ -f /etc/resolv.conf && ! -L /etc/resolv.conf ]]; then
            if [[ ! -f "$BACKUP_DNS" ]]; then
                cp -a /etc/resolv.conf "$BACKUP_DNS" || {
                    echo -e "${RED}[错误] 无法备份 /etc/resolv.conf。${PLAIN}"
                    return 1
                }
            fi

            cat > /etc/resolv.conf <<'DNS'
nameserver 2001:4860:4860::8888
nameserver 2606:4700:4700::1111
options timeout:2 attempts:2
DNS
            touch "$DNS_MARKER"

            if ! dns_ipv6_resolution_works; then
                echo -e "${RED}[错误] 切换公共 IPv6 DNS 后仍无法解析，正在恢复原 DNS。${PLAIN}"
                [[ -f "$BACKUP_DNS" ]] && cp -f "$BACKUP_DNS" /etc/resolv.conf 2>/dev/null || true
                rm -f "$DNS_MARKER"
                return 1
            fi
        else
            echo -e "${RED}[错误] DNS 解析失败，且 /etc/resolv.conf 由系统服务管理。${PLAIN}"
            echo -e "${YELLOW}为避免破坏 systemd-resolved/NetworkManager，本脚本不会强制覆盖符号链接。${PLAIN}"
            return 1
        fi
    fi

    mkdir -p /etc/apt/apt.conf.d/
    printf '%s\n' 'Acquire::ForceIPv6 "true";' > "$FORCE_IPV6_CONF" || return 1

    if [[ -f /etc/apt/mirrors/debian.list ]]; then
        printf '%s\n' 'https://deb.debian.org/debian' > /etc/apt/mirrors/debian.list || return 1
    fi
    if [[ -f /etc/apt/mirrors/debian-security.list ]]; then
        printf '%s\n' 'https://deb.debian.org/debian-security' > /etc/apt/mirrors/debian-security.list || return 1
    fi

    install_dependencies || return 1
    if [[ "$require_time_sync" == "yes" ]]; then
        ensure_time_sync || return 1
    fi
    return 0
}

setup_keepalive() {
    echo -e "${YELLOW}>> 部署 IPv6 HTTPS 链路保活定时器...${PLAIN}"

    cat > /etc/systemd/system/ipv6-keepalive.service <<'KSERVICE'
[Unit]
Description=IPv6 HTTPS Keepalive Probe
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/curl -6fsSI --max-time 5 https://www.cloudflare.com
StandardOutput=null
StandardError=null
KSERVICE

    cat > /etc/systemd/system/ipv6-keepalive.timer <<'KTIMER'
[Unit]
Description=Run IPv6 Keepalive Every 5 Minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
Unit=ipv6-keepalive.service

[Install]
WantedBy=timers.target
KTIMER

    systemctl daemon-reload || return 1
    systemctl enable --now ipv6-keepalive.timer >/dev/null 2>&1 || return 1
    echo -e "${GREEN}✔ IPv6 Keepalive 定时器已激活。${PLAIN}"
    return 0
}

disable_keepalive_for_ipv4() {
    # 双栈 VPS 上若已有 IPv6 节点在使用 Keepalive，不因新增 IPv4 节点而关闭。
    if ip -6 addr show scope global 2>/dev/null | grep -q 'inet6 '; then
        return 0
    fi

    if systemctl is-enabled --quiet ipv6-keepalive.timer 2>/dev/null || \
       systemctl is-active --quiet ipv6-keepalive.timer 2>/dev/null; then
        systemctl disable --now ipv6-keepalive.timer >/dev/null 2>&1 || \
            echo -e "${YELLOW}[警告] IPv6 Keepalive 定时器未能自动停用。${PLAIN}"
    fi
}

select_network_mode() {
    local require_time_sync="${1:-yes}"
    while true; do
        echo ""
        echo "请选择 VPS 入站网络模式："
        echo "  1) IPv4 / 双栈（监听 0.0.0.0）"
        echo "  2) IPv6-only（监听 ::，启用 IPv6 Keepalive）"
        echo "  0) 取消"
        read -rp "请选择 [0-2]: " n

        case "$n" in
            1)
                NETWORK_MODE="ipv4"
                LISTEN_ADDR="0.0.0.0"
                prepare_ipv4_env "$require_time_sync" || return 1
                disable_keepalive_for_ipv4
                return 0
                ;;
            2)
                NETWORK_MODE="ipv6"
                LISTEN_ADDR="::"
                prepare_ipv6_env "$require_time_sync" || return 1
                setup_keepalive || return 1
                return 0
                ;;
            0)
                return 1
                ;;
            *)
                echo -e "${RED}输入无效。${PLAIN}"
                ;;
        esac
    done
}

ensure_state_file() {
    mkdir -p "$STATE_DIR" || return 1
    chmod 700 "$STATE_DIR"
    if [[ ! -f "$STATE_FILE" ]]; then
        printf '%s\n' '{}' > "$STATE_FILE" || return 1
    fi
    chmod 600 "$STATE_FILE"
    jq -e 'type == "object"' "$STATE_FILE" >/dev/null 2>&1 || printf '%s\n' '{}' > "$STATE_FILE"
    return 0
}

save_mode_state() {
    local mode="$1" object_json="$2" tmp=""
    ensure_state_file || return 1
    tmp=$(mktemp "${STATE_DIR}/state.json.tmp.XXXXXX") || return 1
    chmod 600 "$tmp"
    if ! jq --arg mode "$mode" --argjson obj "$object_json" '.[$mode] = $obj' "$STATE_FILE" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    mv -f "$tmp" "$STATE_FILE"
    chmod 600 "$STATE_FILE"
}

remove_mode_state() {
    local mode="$1" tmp=""
    [[ -f "$STATE_FILE" ]] || return 0
    tmp=$(mktemp "${STATE_DIR}/state.json.tmp.XXXXXX") || return 1
    chmod 600 "$tmp"
    if ! jq --arg mode "$mode" 'del(.[$mode])' "$STATE_FILE" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    mv -f "$tmp" "$STATE_FILE"
    chmod 600 "$STATE_FILE"
}

get_mode_state_field() {
    local mode="$1" field="$2"
    [[ -f "$STATE_FILE" ]] || return 1
    jq -r --arg mode "$mode" --arg field "$field" '.[$mode][$field] // empty' "$STATE_FILE" 2>/dev/null
}

ensure_singbox_user() {
    local nologin_shell=""

    if id -u "$SINGBOX_USER" >/dev/null 2>&1; then
        if ! getent group "$SINGBOX_GROUP" >/dev/null 2>&1; then
            groupadd --system "$SINGBOX_GROUP" || return 1
        fi
        if ! id -nG "$SINGBOX_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$SINGBOX_GROUP"; then
            usermod -a -G "$SINGBOX_GROUP" "$SINGBOX_USER" || return 1
        fi
        return 0
    fi

    nologin_shell=$(command -v nologin 2>/dev/null || true)
    nologin_shell=${nologin_shell:-/usr/sbin/nologin}
    useradd --system --user-group --no-create-home --home-dir /nonexistent --shell "$nologin_shell" "$SINGBOX_USER" || return 1
    touch "$SINGBOX_USER_MARKER"
    chmod 600 "$SINGBOX_USER_MARKER"
    return 0
}

write_singbox_service() {
    ensure_singbox_user || return 1

    cat > "$SINGBOX_SERVICE" <<'SERVICE'
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=sing-box
Group=sing-box
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=10s
LimitNOFILE=1048576
UMask=0077
NoNewPrivileges=true
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX AF_NETLINK

[Install]
WantedBy=multi-user.target
SERVICE

    systemctl daemon-reload || return 1
    systemctl enable sing-box >/dev/null 2>&1 || return 1
    return 0
}

install_singbox_core() {
    local arch s_arch="" expected_sha256="" tar_file="" target_url="" curl_family=""
    local success=0 download_url="" actual_sha256=""

    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)
            s_arch="amd64"
            expected_sha256="646bc01bf128c32a12eb50d8690e387bba7504da7b1d65c704bd53916e38595a"
            ;;
        aarch64|arm64)
            s_arch="arm64"
            expected_sha256="7f8187b1d1d30258cd4fa70892eaa232649f8f28b294078eeac719579e14cf42"
            ;;
        *)
            echo -e "${RED}[错误] 暂不支持 CPU 架构: ${arch}${PLAIN}"
            return 1
            ;;
    esac

    [[ "$NETWORK_MODE" == "ipv6" ]] && curl_family="-6" || curl_family="-4"

    if [[ -x "$SINGBOX_BIN" ]]; then
        local current=""
        current=$("$SINGBOX_BIN" version 2>/dev/null | head -n 1 | awk '{print $3}')
        echo -e "${YELLOW}>> 已检测到 sing-box ${current:-未知版本}；按 v1.6.1 安全策略重新下载固定版本 ${SINGBOX_VERSION} 并校验 SHA256 后覆盖。${PLAIN}"
    else
        echo -e "${YELLOW}>> 下载 sing-box ${SINGBOX_VERSION} 并进行 SHA256 校验...${PLAIN}"
    fi

    tar_file="sing-box-${SINGBOX_VERSION}-linux-${s_arch}.tar.gz"
    target_url="https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/${tar_file}"

    local download_sources=(
        "$target_url"
        "https://ghproxy.net/${target_url}"
        "https://gh-proxy.com/${target_url}"
        "https://ghps.cc/${target_url}"
        "https://github.boki.moe/${target_url}"
    )

    cd /tmp || return 1
    rm -rf /tmp/sb-temp "/tmp/${tar_file}"

    for download_url in "${download_sources[@]}"; do
        echo -e "   尝试下载: ${CYAN}${download_url}${PLAIN}"
        rm -f "/tmp/${tar_file}"

        if ! curl -fL "$curl_family" --retry 2 --retry-delay 1 --connect-timeout 8 --max-time 90 \
            "$download_url" -o "/tmp/${tar_file}"; then
            echo -e "${YELLOW}   下载失败，尝试下一个源。${PLAIN}"
            continue
        fi

        actual_sha256=$(sha256sum "/tmp/${tar_file}" | awk '{print $1}')
        if [[ "$actual_sha256" != "$expected_sha256" ]]; then
            echo -e "${RED}   SHA256 校验失败，拒绝安装该文件！${PLAIN}"
            echo -e "${YELLOW}   期望: ${expected_sha256}${PLAIN}"
            echo -e "${YELLOW}   实际: ${actual_sha256}${PLAIN}"
            rm -f "/tmp/${tar_file}"
            continue
        fi

        if ! tar -tzf "/tmp/${tar_file}" >/dev/null 2>&1; then
            echo -e "${RED}   压缩包结构校验失败。${PLAIN}"
            rm -f "/tmp/${tar_file}"
            continue
        fi

        success=1
        break
    done

    if [[ $success -ne 1 ]]; then
        echo -e "${RED}[错误] 所有下载源均失败或未通过 SHA256 校验。${PLAIN}"
        return 1
    fi

    mkdir -p /tmp/sb-temp
    tar -xzf "/tmp/${tar_file}" -C /tmp/sb-temp --strip-components=1 || return 1

    if [[ ! -f /tmp/sb-temp/sing-box ]]; then
        echo -e "${RED}[错误] 压缩包中未找到 sing-box 二进制。${PLAIN}"
        rm -rf /tmp/sb-temp "/tmp/${tar_file}"
        return 1
    fi

    install -m 755 /tmp/sb-temp/sing-box "$SINGBOX_BIN" || return 1
    rm -rf /tmp/sb-temp "/tmp/${tar_file}"

    "$SINGBOX_BIN" version >/dev/null 2>&1 || {
        echo -e "${RED}[错误] sing-box 安装后无法执行。${PLAIN}"
        return 1
    }

    write_singbox_service || return 1
    echo -e "${GREEN}✔ sing-box ${SINGBOX_VERSION} 核心与 systemd 服务已就绪。${PLAIN}"
    return 0
}

ensure_base_singbox_config() {
    ensure_singbox_user || return 1
    mkdir -p /etc/sing-box || return 1
    chown root:"$SINGBOX_GROUP" /etc/sing-box
    chmod 750 /etc/sing-box

    if [[ -f "$SINGBOX_CONF" ]]; then
        return 0
    fi

    cat > "$SINGBOX_CONF" <<'CONFIG'
{
  "log": {
    "level": "warn"
  },
  "inbounds": [],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "final": "direct"
  }
}
CONFIG
    chown root:"$SINGBOX_GROUP" "$SINGBOX_CONF"
    chmod 640 "$SINGBOX_CONF"
    "$SINGBOX_BIN" check -c "$SINGBOX_CONF" >/dev/null 2>&1 || return 1
    return 0
}

apply_singbox_candidate() {
    local candidate="$1"
    local conf_dir="/etc/sing-box"
    local backup="" had_old=0 inbound_count=0

    if [[ ! -f "$candidate" ]]; then
        echo -e "${RED}[错误] 候选配置不存在。${PLAIN}"
        return 1
    fi

    echo -e "${YELLOW}>> 校验新 sing-box 配置...${PLAIN}"
    if ! "$SINGBOX_BIN" check -c "$candidate"; then
        echo -e "${RED}[错误] 新配置未通过 sing-box check，原配置保持不变。${PLAIN}"
        rm -f "$candidate"
        return 1
    fi

    if [[ -f "$SINGBOX_CONF" ]]; then
        had_old=1
        backup=$(mktemp "${conf_dir}/config.json.rollback.XXXXXX") || {
            rm -f "$candidate"
            return 1
        }
        cp -a "$SINGBOX_CONF" "$backup" || {
            rm -f "$candidate" "$backup"
            return 1
        }
        chown root:"$SINGBOX_GROUP" "$backup"
        chmod 640 "$backup"
    fi

    mv -f "$candidate" "$SINGBOX_CONF" || {
        rm -f "$candidate" "$backup"
        return 1
    }
    chown root:"$SINGBOX_GROUP" "$SINGBOX_CONF"
    chmod 640 "$SINGBOX_CONF"

    inbound_count=$(jq '.inbounds | length' "$SINGBOX_CONF" 2>/dev/null || echo 0)

    if [[ "$inbound_count" -eq 0 ]]; then
        systemctl stop sing-box >/dev/null 2>&1 || true
        rm -f "$backup"
        echo -e "${GREEN}✔ sing-box 配置已更新，当前无活动入口，服务已停止。${PLAIN}"
        return 0
    fi

    if ! systemctl restart sing-box; then
        echo -e "${RED}[错误] sing-box 使用新配置启动失败，正在自动回滚...${PLAIN}"
        if [[ $had_old -eq 1 && -f "$backup" ]]; then
            mv -f "$backup" "$SINGBOX_CONF"
            chown root:"$SINGBOX_GROUP" "$SINGBOX_CONF"
            chmod 640 "$SINGBOX_CONF"
            if systemctl restart sing-box; then
                echo -e "${YELLOW}✔ 已恢复原配置并重新启动服务。${PLAIN}"
            else
                echo -e "${RED}[严重] 原配置已恢复，但 sing-box 仍无法启动。${PLAIN}"
            fi
        else
            rm -f "$SINGBOX_CONF"
            systemctl stop sing-box >/dev/null 2>&1 || true
        fi
        return 1
    fi

    rm -f "$backup"
    echo -e "${GREEN}✔ 新配置校验通过并已安全切换。${PLAIN}"
    return 0
}

update_singbox_inbounds() {
    local remove_tags_json="$1"
    local add_inbounds_json="$2"
    local tmp=""

    ensure_base_singbox_config || return 1

    tmp=$(mktemp "/etc/sing-box/config.json.tmp.XXXXXX") || return 1
    chmod 600 "$tmp"

    if ! jq \
        --argjson remove_tags "$remove_tags_json" \
        --argjson add_items "$add_inbounds_json" \
        '
        .log = (.log // {"level":"warn"}) |
        .inbounds = (
          ((.inbounds // []) | map(select((.tag // "") as $t | ($remove_tags | index($t) | not))))
          + $add_items
        ) |
        .outbounds = (
          if ((.outbounds // []) | map(.tag // "") | index("direct")) == null
          then ((.outbounds // []) + [{"type":"direct","tag":"direct"}])
          else .outbounds
          end
        ) |
        .route = (.route // {}) |
        .route.final = (.route.final // "direct")
        ' "$SINGBOX_CONF" > "$tmp"; then
        rm -f "$tmp"
        echo -e "${RED}[错误] sing-box 配置合并失败。${PLAIN}"
        return 1
    fi

    apply_singbox_candidate "$tmp"
}

singbox_config_port_conflict() {
    local port="$1"
    local excluded_tags_json="${2:-[]}"

    [[ -f "$SINGBOX_CONF" ]] || return 1
    jq -e \
        --argjson p "$port" \
        --argjson excluded "$excluded_tags_json" '
        .inbounds[]?
        | select((.listen_port // 0) == $p)
        | select((.tag // "") as $t | ($excluded | index($t) | not))
        ' "$SINGBOX_CONF" >/dev/null 2>&1
}

port_in_use_by_other_process() {
    local port="$1"
    local allowed_pid="${2:-}"
    local lines conflicts

    lines=$(ss -H -lntup 2>/dev/null | awk -v p="$port" '
        {
          addr=$5
          n=split(addr,a,":")
          if (a[n] == p) print
        }')
    [[ -z "$lines" ]] && return 1

    if [[ "$allowed_pid" =~ ^[0-9]+$ && "$allowed_pid" -gt 0 ]]; then
        conflicts=$(printf '%s\n' "$lines" | grep -v "pid=${allowed_pid}," || true)
        [[ -z "$conflicts" ]] && return 1
    fi

    printf '%s\n' "$lines"
    return 0
}

port_is_available_for_singbox_mode() {
    local port="$1"
    local excluded_tags_json="${2:-[]}"
    local sb_pid=""

    if singbox_config_port_conflict "$port" "$excluded_tags_json"; then
        echo -e "${RED}[错误] 端口 ${port} 已被其他 sing-box 协议入口配置占用。${PLAIN}"
        return 1
    fi

    sb_pid=$(systemctl show -p MainPID --value sing-box 2>/dev/null || true)
    if port_in_use_by_other_process "$port" "$sb_pid" >/tmp/ss2022-port-conflict.$$ 2>/dev/null; then
        echo -e "${RED}[错误] 端口 ${port} 已被其他进程占用：${PLAIN}"
        cat /tmp/ss2022-port-conflict.$$ 2>/dev/null || true
        rm -f /tmp/ss2022-port-conflict.$$
        return 1
    fi
    rm -f /tmp/ss2022-port-conflict.$$ 2>/dev/null || true
    return 0
}

validate_port_number() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && [[ "$port" -ge 1 ]] && [[ "$port" -le 65535 ]]
}

ask_singbox_port() {
    local prompt="$1" default="$2" excluded_tags_json="$3"
    local input=""

    while true; do
        read -rp "${prompt} [默认: ${default}]: " input
        input=${input:-$default}

        if ! validate_port_number "$input"; then
            echo -e "${RED}输入无效，请输入 1-65535。${PLAIN}"
            continue
        fi

        if ! port_is_available_for_singbox_mode "$input" "$excluded_tags_json"; then
            continue
        fi

        PORT="$input"
        return 0
    done
}

validate_ss2022_key() {
    local key="$1"
    local expected_bytes="$2"
    local tmp="" decoded_bytes=""

    [[ -n "$key" ]] || return 1
    [[ "$key" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] || return 1

    tmp=$(mktemp) || return 1
    if ! printf '%s' "$key" | base64 --decode > "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        return 1
    fi

    decoded_bytes=$(wc -c < "$tmp" | tr -d ' ')
    rm -f "$tmp"
    [[ "$decoded_bytes" -eq "$expected_bytes" ]]
}

get_ss_cipher_and_key() {
    local cipher_choice auto_key=""

    echo ""
    echo "请选择 SS2022 加密算法："
    echo "  1) 2022-blake3-aes-128-gcm（推荐，高吞吐低开销）"
    echo "  2) 2022-blake3-aes-256-gcm（32 字节密钥）"
    read -rp "请选择 [默认: 1]: " cipher_choice
    cipher_choice=${cipher_choice:-1}

    if [[ "$cipher_choice" == "2" ]]; then
        METHOD="2022-blake3-aes-256-gcm"
        KEY_BYTES=32
    else
        METHOD="2022-blake3-aes-128-gcm"
        KEY_BYTES=16
    fi

    read -rp "是否自动生成合规随机密钥？[Y/n]: " auto_key
    auto_key=${auto_key:-Y}

    if [[ "$auto_key" =~ ^[Yy]$ ]]; then
        SS_KEY=$(openssl rand -base64 "$KEY_BYTES") || return 1
        echo -e "已生成密钥: ${GREEN}${SS_KEY}${PLAIN}"
    else
        while true; do
            read -rp "请输入自定义 ${KEY_BYTES} 字节 Base64 密钥: " SS_KEY
            if validate_ss2022_key "$SS_KEY" "$KEY_BYTES"; then
                echo -e "${GREEN}✔ 自定义密钥格式及长度校验通过。${PLAIN}"
                break
            fi
            echo -e "${RED}[错误] 密钥必须是有效标准 Base64，且解码后正好为 ${KEY_BYTES} 字节。${PLAIN}"
        done
    fi
    return 0
}

get_public_ipv4() {
    local ip=""
    ip=$(curl -4fsS --connect-timeout 5 --max-time 10 https://api.ipify.org 2>/dev/null) || true
    [[ -z "$ip" ]] && ip=$(curl -4fsS --connect-timeout 5 --max-time 10 https://ip.sb 2>/dev/null) || true

    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        printf '%s' "$ip"
        return 0
    fi
    return 1
}

get_global_ipv6() {
    local ip6=""
    ip6=$(ip -6 addr show scope global 2>/dev/null | grep -v 'temporary' | grep 'inet6 ' | awk '{print $2}' | cut -d/ -f1 | head -n 1)
    [[ -n "$ip6" ]] || return 1
    printf '%s' "$ip6"
}

ask_server_host() {
    local detected="" input=""

    if [[ "$NETWORK_MODE" == "ipv6" ]]; then
        detected=$(get_global_ipv6 2>/dev/null || true)
    else
        detected=$(get_public_ipv4 2>/dev/null || true)
    fi

    if [[ -n "$detected" ]]; then
        read -rp "服务器地址/域名 [回车默认使用: ${detected}]: " input
        SERVER_HOST=${input:-$detected}
    else
        while [[ -z "$input" ]]; do
            read -rp "自动获取公网地址失败，请输入服务器地址/域名: " input
        done
        SERVER_HOST="$input"
    fi
}

urlencode() {
    local value="$1"
    jq -nr --arg v "$value" '$v|@uri'
}

format_host_for_uri() {
    local host="$1"
    if [[ "$host" == *:* && "$host" != \[*\] ]]; then
        printf '[%s]' "$host"
    else
        printf '%s' "$host"
    fi
}

show_qr() {
    local payload="$1"
    if command -v qrencode &>/dev/null; then
        echo -e "${YELLOW}【二维码】${PLAIN}"
        qrencode -t ANSIUTF8 "$payload" 2>/dev/null || true
    fi
}

show_ss_details() {
    local host="$1" port="$2" method="$3" pass="$4"
    local tag="Proxy-SS2022"
    local url_host method_enc pass_enc tag_enc ss_url

    url_host=$(format_host_for_uri "$host")
    method_enc=$(urlencode "$method")
    pass_enc=$(urlencode "$pass")
    tag_enc=$(urlencode "$tag")
    ss_url="ss://${method_enc}:${pass_enc}@${url_host}:${port}#${tag_enc}"

    echo ""
    echo -e "${CYAN}════════════════════ SS2022 节点配置 ════════════════════${PLAIN}"
    echo -e "  地址: ${CYAN}${host}${PLAIN}"
    echo -e "  端口: ${CYAN}${port}${PLAIN}"
    echo -e "  加密: ${CYAN}${method}${PLAIN}"
    echo -e "  密钥: ${CYAN}${pass}${PLAIN}"
    echo -e "  UDP : ${GREEN}开启${PLAIN}"
    echo ""
    echo -e "${YELLOW}【通用 URI / SIP002】${PLAIN}"
    echo -e "${GREEN}${ss_url}${PLAIN}"
    echo ""
    echo -e "${YELLOW}【Surge】${PLAIN}"
    echo -e "${GREEN}${tag} = ss, ${host}, ${port}, encrypt-method=${method}, password=\"${pass}\", udp-relay=true${PLAIN}"
    echo ""
    echo -e "${YELLOW}【Loon】${PLAIN}"
    echo -e "${GREEN}${tag} = Shadowsocks,${host},${port},${method},\"${pass}\",fast-open=false,udp=true${PLAIN}"
    echo ""
    echo -e "${YELLOW}【FlClash / Mihomo】${PLAIN}"
    cat <<YAML
- name: "${tag}"
  type: ss
  server: "${host}"
  port: ${port}
  cipher: ${method}
  password: "${pass}"
  udp: true
YAML
    echo ""
    echo -e "${YELLOW}【Shadowrocket】${PLAIN}"
    echo -e "${GREEN}${tag} = ss,${host},${port},password=${pass},method=${method},udp=1${PLAIN}"
    echo -e "${YELLOW}[提示] Shadowrocket 也可直接复制/扫描上面的通用 SS URI 导入。${PLAIN}"
    echo ""
    show_qr "$ss_url"
    echo -e "${CYAN}═════════════════════════════════════════════════════════${PLAIN}"
}

show_shadowtls_details() {
    local host="$1" port="$2" method="$3" ss_pass="$4" stls_pass="$5" sni="$6" udp_enabled="$7" udp_port="$8"
    local tag="Proxy-SS2022-ShadowTLS"
    local surge_udp="udp-relay=false" loon_udp="udp=false" mihomo_udp="false"
    local qr_payload

    if [[ "$udp_enabled" == "true" ]]; then
        surge_udp="udp-relay=true, udp-port=${udp_port}"
        loon_udp="udp-port=${udp_port},udp=true"
        # Mihomo 的 SS+ShadowTLS 客户端配置没有独立 udp-port 字段；不要错误指向 ShadowTLS TCP 端口。
        mihomo_udp="false"
    fi

    echo ""
    echo -e "${CYAN}════════════════ SS2022 + ShadowTLS v3 配置 ════════════════${PLAIN}"
    echo -e "  地址: ${CYAN}${host}${PLAIN}"
    echo -e "  TCP端口: ${CYAN}${port}${PLAIN}"
    echo -e "  SS2022加密: ${CYAN}${method}${PLAIN}"
    echo -e "  SS2022密钥: ${CYAN}${ss_pass}${PLAIN}"
    echo -e "  ShadowTLS密码: ${CYAN}${stls_pass}${PLAIN}"
    echo -e "  ShadowTLS SNI: ${CYAN}${sni}${PLAIN}"
    if [[ "$udp_enabled" == "true" ]]; then
        echo -e "  UDP Relay: ${GREEN}开启，UDP端口 ${udp_port}${PLAIN}"
    else
        echo -e "  UDP Relay: ${YELLOW}关闭${PLAIN}"
    fi
    echo ""
    echo -e "${YELLOW}【通用参数】${PLAIN}"
    cat <<EOF
协议: SS2022 + ShadowTLS v3
服务器: ${host}
TCP端口: ${port}
加密: ${method}
SS2022密钥: ${ss_pass}
ShadowTLS密码: ${stls_pass}
ShadowTLS SNI: ${sni}
EOF
    if [[ "$udp_enabled" == "true" ]]; then
        echo "UDP端口: ${udp_port}"
    else
        echo "UDP: 关闭"
    fi
    echo ""
    echo -e "${YELLOW}【Surge】${PLAIN}"
    echo -e "${GREEN}${tag} = ss, ${host}, ${port}, encrypt-method=${method}, password=\"${ss_pass}\", ${surge_udp}, shadow-tls-password=\"${stls_pass}\", shadow-tls-version=3, shadow-tls-sni=${sni}${PLAIN}"
    echo ""
    echo -e "${YELLOW}【Loon】${PLAIN}"
    echo -e "${GREEN}${tag} = Shadowsocks,${host},${port},${method},\"${ss_pass}\",shadow-tls-password=\"${stls_pass}\",shadow-tls-sni=${sni},shadow-tls-version=3,${loon_udp},fast-open=false${PLAIN}"
    echo ""
    echo -e "${YELLOW}【FlClash / Mihomo】${PLAIN}"
    cat <<YAML
- name: "${tag}"
  type: ss
  server: "${host}"
  port: ${port}
  cipher: ${method}
  password: "${ss_pass}"
  udp: ${mihomo_udp}
  plugin: shadow-tls
  plugin-opts:
    host: "${sni}"
    password: "${stls_pass}"
    version: 3
YAML
    if [[ "$udp_enabled" == "true" ]]; then
        echo -e "${YELLOW}[提示] FlClash/Mihomo 的 ShadowTLS SS 节点没有 Surge/Loon 的独立 udp-port 参数，因此这里安全地保持 udp:false；TCP ShadowTLS 不受影响。${PLAIN}"
    fi
    echo ""
    echo -e "${YELLOW}【Shadowrocket】${PLAIN}"
    echo "类型: Shadowsocks"
    echo "地址: ${host}"
    echo "端口: ${port}"
    echo "加密方法: ${method}"
    echo "密码: ${ss_pass}"
    echo "ShadowTLS: v3"
    echo "ShadowTLS 密码: ${stls_pass}"
    echo "SNI: ${sni}"
    if [[ "$udp_enabled" == "true" ]]; then
        echo "UDP: 开启；独立 UDP 端口: ${udp_port}（若当前 Shadowrocket 版本无独立 UDP 端口字段，则仅使用 TCP）"
    else
        echo "UDP: 关闭"
    fi
    echo ""
    qr_payload=$(jq -cn --arg type "ss2022-shadowtls" --arg server "$host" --argjson port "$port" --arg cipher "$method" --arg password "$ss_pass" --arg stls_password "$stls_pass" --arg sni "$sni" --arg udp "$udp_enabled" --arg udp_port "$udp_port" '{type:$type,server:$server,port:$port,cipher:$cipher,password:$password,shadow_tls:{version:3,password:$stls_password,sni:$sni},udp:($udp=="true"),udp_port:(if $udp_port=="" then null else ($udp_port|tonumber) end)}')
    show_qr "$qr_payload"
    echo -e "${YELLOW}[二维码说明] SS2022+ShadowTLS 尚无统一跨客户端 URI；二维码保存完整参数，客户端仍应使用上面的对应格式。${PLAIN}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${PLAIN}"
}

show_vless_details() {
    local host="$1" port="$2" uuid="$3" sni="$4" public_key="$5" short_id="$6"
    local url_host tag="Proxy-VLESS-Reality"
    local tag_enc vless_uri

    url_host=$(format_host_for_uri "$host")
    tag_enc=$(urlencode "$tag")
    vless_uri="vless://${uuid}@${url_host}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$(urlencode "$sni")&fp=chrome&pbk=$(urlencode "$public_key")&sid=${short_id}&type=tcp#${tag_enc}"

    echo ""
    echo -e "${CYAN}════════════════════ VLESS Reality 配置 ════════════════════${PLAIN}"
    echo -e "  地址: ${CYAN}${host}${PLAIN}"
    echo -e "  端口: ${CYAN}${port}${PLAIN}"
    echo -e "  UUID: ${CYAN}${uuid}${PLAIN}"
    echo -e "  Flow: ${CYAN}xtls-rprx-vision${PLAIN}"
    echo -e "  SNI : ${CYAN}${sni}${PLAIN}"
    echo -e "  Public Key: ${CYAN}${public_key}${PLAIN}"
    echo -e "  Short ID: ${CYAN}${short_id}${PLAIN}"
    echo ""
    echo -e "${YELLOW}【通用 VLESS URI】${PLAIN}"
    echo -e "${GREEN}${vless_uri}${PLAIN}"
    echo ""
    echo -e "${YELLOW}【Surge】${PLAIN}"
    echo -e "${YELLOW}不支持 VLESS Reality，不生成伪配置。${PLAIN}"
    echo ""
    echo -e "${YELLOW}【Loon】${PLAIN}"
    echo -e "${GREEN}${tag} = VLESS,${host},${port},\"${uuid}\",transport=tcp,flow=xtls-rprx-vision,public-key=\"${public_key}\",short-id=${short_id},over-tls=true,sni=${sni},udp=true${PLAIN}"
    echo ""
    echo -e "${YELLOW}【FlClash / Mihomo】${PLAIN}"
    cat <<YAML
- name: "${tag}"
  type: vless
  server: "${host}"
  port: ${port}
  uuid: "${uuid}"
  network: tcp
  tls: true
  udp: true
  flow: xtls-rprx-vision
  servername: "${sni}"
  reality-opts:
    public-key: "${public_key}"
    short-id: "${short_id}"
  client-fingerprint: chrome
YAML
    echo ""
    echo -e "${YELLOW}【Shadowrocket】${PLAIN}"
    echo -e "${GREEN}推荐直接复制/扫描上面的通用 VLESS URI 导入。${PLAIN}"
    echo "类型: VLESS / Reality"
    echo "地址: ${host}:${port}"
    echo "UUID: ${uuid}"
    echo "Flow: xtls-rprx-vision"
    echo "SNI: ${sni}"
    echo "Public Key: ${public_key}"
    echo "Short ID: ${short_id}"
    echo "Fingerprint: chrome"
    echo ""
    show_qr "$vless_uri"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${PLAIN}"
}

show_snell_details() {
    local host="$1" port="$2" psk="$3"
    local tag="Proxy-Snell-v5"
    local surge_line qr_payload
    surge_line="${tag} = snell, ${host}, ${port}, psk=\"${psk}\", version=5, reuse=true, tfo=true"

    echo ""
    echo -e "${CYAN}════════════════════ Snell v5 配置 ════════════════════${PLAIN}"
    echo -e "  地址: ${CYAN}${host}${PLAIN}"
    echo -e "  端口: ${CYAN}${port}${PLAIN}"
    echo -e "  PSK : ${CYAN}${psk}${PLAIN}"
    echo -e "  版本: ${CYAN}5${PLAIN}"
    echo -e "  UDP : ${GREEN}Snell v5 原生支持${PLAIN}"
    echo ""
    echo -e "${YELLOW}【通用参数】${PLAIN}"
    echo "协议: Snell v5"
    echo "服务器: ${host}"
    echo "端口: ${port}"
    echo "PSK: ${psk}"
    echo "version: 5"
    echo ""
    echo -e "${YELLOW}【Surge】${PLAIN}"
    echo -e "${GREEN}${surge_line}${PLAIN}"
    echo ""
    echo -e "${YELLOW}【Loon】${PLAIN}"
    echo -e "${YELLOW}Loon 官方当前协议列表不包含 Snell，不生成伪配置。${PLAIN}"
    echo ""
    echo -e "${YELLOW}【FlClash / Mihomo】${PLAIN}"
    cat <<YAML
- name: "${tag}"
  type: snell
  server: "${host}"
  port: ${port}
  psk: "${psk}"
  version: 5
  reuse: true
  udp: true
YAML
    echo -e "${YELLOW}[提示] Mihomo 提供 Snell 兼容实现；Snell 官方定位仍主要面向 Surge。${PLAIN}"
    echo ""
    echo -e "${YELLOW}【Shadowrocket】${PLAIN}"
    echo "类型: Snell"
    echo "地址: ${host}"
    echo "端口: ${port}"
    echo "PSK/密码: ${psk}"
    echo "版本: 5"
    echo "UDP: 开启"
    echo ""
    qr_payload=$(jq -cn --arg type "snell" --arg server "$host" --argjson port "$port" --arg psk "$psk" '{type:$type,server:$server,port:$port,psk:$psk,version:5,udp:true}')
    show_qr "$qr_payload"
    echo -e "${YELLOW}[二维码说明] Snell 没有统一的跨客户端分享 URI；二维码保存完整参数。${PLAIN}"
    echo -e "${CYAN}═════════════════════════════════════════════════════════${PLAIN}"
}


select_network_mode_for_update() {
    local current_network="$1"
    local require_time_sync="${2:-yes}"
    local default_choice="1" n=""

    [[ "$current_network" == "ipv6" ]] && default_choice="2"

    while true; do
        echo ""
        echo "请选择 VPS 入站网络模式："
        echo "  1) IPv4 / 双栈（监听 0.0.0.0）"
        echo "  2) IPv6-only（监听 ::，启用 IPv6 Keepalive）"
        echo "  0) 取消"
        read -rp "请选择 [0-2，默认: ${default_choice}]: " n
        n=${n:-$default_choice}

        case "$n" in
            1)
                NETWORK_MODE="ipv4"
                LISTEN_ADDR="0.0.0.0"
                prepare_ipv4_env "$require_time_sync" || return 1
                disable_keepalive_for_ipv4
                return 0
                ;;
            2)
                NETWORK_MODE="ipv6"
                LISTEN_ADDR="::"
                prepare_ipv6_env "$require_time_sync" || return 1
                setup_keepalive || return 1
                return 0
                ;;
            0) return 1 ;;
            *) echo -e "${RED}输入无效。${PLAIN}" ;;
        esac
    done
}

ask_server_host_with_default() {
    local current_host="$1" input=""
    if [[ -n "$current_host" ]]; then
        read -rp "服务器地址/域名 [默认保持: ${current_host}]: " input
        SERVER_HOST=${input:-$current_host}
    else
        ask_server_host
    fi
}

infer_network_from_listen() {
    local listen="$1"
    [[ "$listen" == "::" ]] && printf 'ipv6' || printf 'ipv4'
}

protocol_exists_snell() {
    [[ -f "$SNELL_CONF" ]]
}

update_ss2022() {
    local excluded_tags='["ss-in"]'
    local choice="" current_port current_method current_key current_listen current_host current_network
    local new_port new_method new_key new_listen new_network inbound add_json

    if ! json_has_inbound_tag "$TAG_SS"; then
        echo -e "${YELLOW}未部署 SS2022，请先选择“部署”。${PLAIN}"
        pause
        return
    fi

    while true; do
        current_port=$(jq -r --arg t "$TAG_SS" '.inbounds[] | select(.tag==$t) | .listen_port' "$SINGBOX_CONF")
        current_method=$(jq -r --arg t "$TAG_SS" '.inbounds[] | select(.tag==$t) | .method' "$SINGBOX_CONF")
        current_key=$(jq -r --arg t "$TAG_SS" '.inbounds[] | select(.tag==$t) | .password' "$SINGBOX_CONF")
        current_listen=$(jq -r --arg t "$TAG_SS" '.inbounds[] | select(.tag==$t) | .listen' "$SINGBOX_CONF")
        current_host=$(get_mode_state_field "ss" "host" 2>/dev/null || true)
        current_network=$(get_mode_state_field "ss" "network" 2>/dev/null || true)
        [[ -n "$current_network" ]] || current_network=$(infer_network_from_listen "$current_listen")

        clear
        echo -e "${CYAN}════════════════════ SS2022 更新 ════════════════════${PLAIN}"
        echo -e "当前网络模式 : ${GREEN}${current_network}${PLAIN}"
        echo -e "当前监听端口 : ${GREEN}${current_port}${PLAIN}"
        echo -e "当前服务器地址: ${GREEN}${current_host:-未保存}${PLAIN}"
        echo -e "当前加密算法 : ${GREEN}${current_method}${PLAIN}"
        echo ""
        echo "  1. 修改网络模式"
        echo "  2. 修改监听端口"
        echo "  3. 修改服务器地址/域名"
        echo "  4. 重新生成加密算法/密钥"
        echo "  5. 查看当前节点配置"
        echo "  0. 返回"
        read -rp "请选择 [0-5]: " choice

        new_port="$current_port"; new_method="$current_method"; new_key="$current_key"
        new_listen="$current_listen"; new_network="$current_network"

        case "$choice" in
            1)
                select_network_mode_for_update "$current_network" || continue
                new_listen="$LISTEN_ADDR"; new_network="$NETWORK_MODE"
                ;;
            2)
                ask_singbox_port "请输入 SS2022 监听端口" "$current_port" "$excluded_tags" || continue
                new_port="$PORT"
                ;;
            3)
                ask_server_host_with_default "$current_host"
                if save_mode_state "ss" "$(jq -n --arg host "$SERVER_HOST" --arg network "$current_network" '{host:$host,network:$network}')"; then
                    echo -e "${GREEN}✔ 服务器地址已更新，不影响 SS2022 密钥与监听配置。${PLAIN}"
                fi
                pause
                continue
                ;;
            4)
                echo -e "${YELLOW}[警告] 重新生成密钥后，所有客户端都必须同步更新。${PLAIN}"
                read -rp "确认继续？[y/N]: " choice
                [[ "$choice" =~ ^[Yy]$ ]] || continue
                get_ss_cipher_and_key || { pause; continue; }
                new_method="$METHOD"; new_key="$SS_KEY"
                ;;
            5)
                view_ss2022_config
                pause
                continue
                ;;
            0) return ;;
            *) continue ;;
        esac

        inbound=$(jq -n --arg listen "$new_listen" --argjson port "$new_port" --arg method "$new_method" --arg password "$new_key" \
            '{type:"shadowsocks",tag:"ss-in",listen:$listen,listen_port:$port,method:$method,password:$password}')
        add_json=$(jq -n --argjson a "$inbound" '[$a]')
        if update_singbox_inbounds "$excluded_tags" "$add_json"; then
            save_mode_state "ss" "$(jq -n --arg host "$current_host" --arg network "$new_network" '{host:$host,network:$network}')" || true
            echo -e "${GREEN}✔ SS2022 更新成功。${PLAIN}"
        else
            journalctl -u sing-box -n 30 --no-pager 2>/dev/null || true
        fi
        pause
    done
}

update_shadowtls() {
    local excluded_tags='["ss-shadowtls-in","ss-shadowtls-backend","ss-shadowtls-udp"]'
    local choice="" subchoice="" current_port current_method current_ss_key current_stls_pass current_sni current_listen
    local current_host current_network current_udp_enabled current_udp_port
    local new_port new_method new_ss_key new_stls_pass new_sni new_listen new_network new_udp_enabled new_udp_port
    local outer backend udp_inbound add_json default_udp

    if ! json_has_inbound_tag "$TAG_STLS"; then
        echo -e "${YELLOW}未部署 SS2022 + ShadowTLS v3，请先选择“部署”。${PLAIN}"
        pause
        return
    fi

    while true; do
        current_port=$(get_inbound_port "$TAG_STLS")
        current_stls_pass=$(jq -r --arg t "$TAG_STLS" '.inbounds[] | select(.tag==$t) | .users[0].password' "$SINGBOX_CONF")
        current_sni=$(jq -r --arg t "$TAG_STLS" '.inbounds[] | select(.tag==$t) | .handshake.server' "$SINGBOX_CONF")
        current_listen=$(jq -r --arg t "$TAG_STLS" '.inbounds[] | select(.tag==$t) | .listen' "$SINGBOX_CONF")
        current_method=$(jq -r --arg t "$TAG_STLS_BACKEND" '.inbounds[] | select(.tag==$t) | .method' "$SINGBOX_CONF")
        current_ss_key=$(jq -r --arg t "$TAG_STLS_BACKEND" '.inbounds[] | select(.tag==$t) | .password' "$SINGBOX_CONF")
        current_host=$(get_mode_state_field "shadowtls" "host" 2>/dev/null || true)
        current_network=$(get_mode_state_field "shadowtls" "network" 2>/dev/null || true)
        [[ -n "$current_network" ]] || current_network=$(infer_network_from_listen "$current_listen")
        current_udp_enabled="false"; current_udp_port=""
        if json_has_inbound_tag "$TAG_STLS_UDP"; then
            current_udp_enabled="true"
            current_udp_port=$(get_inbound_port "$TAG_STLS_UDP")
        fi

        clear
        echo -e "${CYAN}════════════ SS2022 + ShadowTLS v3 更新 ════════════${PLAIN}"
        echo -e "当前网络模式 : ${GREEN}${current_network}${PLAIN}"
        echo -e "当前 TCP 端口: ${GREEN}${current_port}${PLAIN}"
        echo -e "当前 SNI     : ${GREEN}${current_sni}${PLAIN}"
        echo -e "当前 UDP Relay: ${GREEN}$([[ "$current_udp_enabled" == "true" ]] && echo "开启 (${current_udp_port})" || echo "关闭")${PLAIN}"
        echo -e "当前服务器地址: ${GREEN}${current_host:-未保存}${PLAIN}"
        echo ""
        echo "  1. 修改网络模式"
        echo "  2. 修改 ShadowTLS TCP 端口"
        echo "  3. 修改 ShadowTLS SNI"
        echo "  4. 修改服务器地址/域名"
        echo "  5. 修改 UDP Relay"
        echo "  6. 重新生成内部 SS2022 密钥"
        echo "  7. 重新生成 ShadowTLS 密码"
        echo "  8. 查看当前节点配置"
        echo "  0. 返回"
        read -rp "请选择 [0-8]: " choice

        new_port="$current_port"; new_method="$current_method"; new_ss_key="$current_ss_key"
        new_stls_pass="$current_stls_pass"; new_sni="$current_sni"; new_listen="$current_listen"
        new_network="$current_network"; new_udp_enabled="$current_udp_enabled"; new_udp_port="$current_udp_port"

        case "$choice" in
            1)
                select_network_mode_for_update "$current_network" || continue
                new_listen="$LISTEN_ADDR"; new_network="$NETWORK_MODE"
                ;;
            2)
                ask_singbox_port "请输入 ShadowTLS 对外 TCP 端口" "$current_port" "$excluded_tags" || continue
                new_port="$PORT"
                ;;
            3)
                read -rp "ShadowTLS 握手/SNI [默认保持: ${current_sni}]: " new_sni
                new_sni=${new_sni:-$current_sni}
                ;;
            4)
                ask_server_host_with_default "$current_host"
                if save_mode_state "shadowtls" "$(jq -n --arg host "$SERVER_HOST" --arg network "$current_network" '{host:$host,network:$network}')"; then
                    echo -e "${GREEN}✔ 服务器地址已更新，不影响节点密钥和端口。${PLAIN}"
                fi
                pause
                continue
                ;;
            5)
                echo "当前 UDP Relay: $([[ "$current_udp_enabled" == "true" ]] && echo "开启 (${current_udp_port})" || echo "关闭")"
                echo "  1. 开启 / 修改 UDP Relay 端口"
                echo "  2. 关闭 UDP Relay"
                echo "  0. 取消"
                read -rp "请选择 [0-2]: " subchoice
                case "$subchoice" in
                    1)
                        new_udp_enabled="true"
                        default_udp=${current_udp_port:-$(( (current_port + 10000) % 65535 ))}
                        [[ "$default_udp" -lt 1024 ]] && default_udp=58589
                        while true; do
                            read -rp "请输入独立 UDP 端口 [默认: ${default_udp}]: " new_udp_port
                            new_udp_port=${new_udp_port:-$default_udp}
                            validate_port_number "$new_udp_port" || { echo -e "${RED}端口无效。${PLAIN}"; continue; }
                            port_is_available_for_singbox_mode "$new_udp_port" "$excluded_tags" && break
                        done
                        ;;
                    2) new_udp_enabled="false"; new_udp_port="" ;;
                    *) continue ;;
                esac
                ;;
            6)
                echo -e "${YELLOW}[警告] 更换 SS2022 密钥后，客户端必须同步更新。${PLAIN}"
                read -rp "确认继续？[y/N]: " subchoice
                [[ "$subchoice" =~ ^[Yy]$ ]] || continue
                get_ss_cipher_and_key || { pause; continue; }
                new_method="$METHOD"; new_ss_key="$SS_KEY"
                ;;
            7)
                echo -e "${YELLOW}[警告] 更换 ShadowTLS 密码后，客户端必须同步更新。${PLAIN}"
                read -rp "确认继续？[y/N]: " subchoice
                [[ "$subchoice" =~ ^[Yy]$ ]] || continue
                new_stls_pass=$(openssl rand -base64 24 | tr -d '\n') || { echo -e "${RED}[错误] 密码生成失败。${PLAIN}"; pause; continue; }
                ;;
            8)
                view_shadowtls_config
                pause
                continue
                ;;
            0) return ;;
            *) continue ;;
        esac

        outer=$(jq -n --arg listen "$new_listen" --argjson port "$new_port" --arg password "$new_stls_pass" --arg sni "$new_sni" \
            '{type:"shadowtls",tag:"ss-shadowtls-in",listen:$listen,listen_port:$port,version:3,users:[{name:"default",password:$password}],handshake:{server:$sni,server_port:443},strict_mode:true,detour:"ss-shadowtls-backend"}')
        backend=$(jq -n --arg method "$new_method" --arg password "$new_ss_key" \
            '{type:"shadowsocks",tag:"ss-shadowtls-backend",listen:"127.0.0.1",network:"tcp",method:$method,password:$password}')
        if [[ "$new_udp_enabled" == "true" ]]; then
            udp_inbound=$(jq -n --arg listen "$new_listen" --argjson port "$new_udp_port" --arg method "$new_method" --arg password "$new_ss_key" \
                '{type:"shadowsocks",tag:"ss-shadowtls-udp",listen:$listen,listen_port:$port,network:"udp",method:$method,password:$password}')
            add_json=$(jq -n --argjson a "$outer" --argjson b "$backend" --argjson c "$udp_inbound" '[$a,$b,$c]')
        else
            add_json=$(jq -n --argjson a "$outer" --argjson b "$backend" '[$a,$b]')
        fi

        if update_singbox_inbounds "$excluded_tags" "$add_json"; then
            save_mode_state "shadowtls" "$(jq -n --arg host "$current_host" --arg network "$new_network" '{host:$host,network:$network}')" || true
            echo -e "${GREEN}✔ SS2022 + ShadowTLS v3 更新成功。${PLAIN}"
        else
            journalctl -u sing-box -n 30 --no-pager 2>/dev/null || true
        fi
        pause
    done
}

update_vless_reality() {
    local excluded_tags='["vless-reality-in"]'
    local choice="" confirm="" current_port uuid current_sni private short_id current_listen current_host current_network public
    local new_port new_uuid new_sni new_private new_short_id new_listen new_network new_public inbound add_json
    local REALITY_PRIVATE_KEY="" REALITY_PUBLIC_KEY=""

    if ! json_has_inbound_tag "$TAG_VLESS"; then
        echo -e "${YELLOW}未部署 VLESS Reality，请先选择“部署”。${PLAIN}"
        pause
        return
    fi

    while true; do
        current_port=$(get_inbound_port "$TAG_VLESS")
        uuid=$(jq -r --arg t "$TAG_VLESS" '.inbounds[] | select(.tag==$t) | .users[0].uuid' "$SINGBOX_CONF")
        current_sni=$(jq -r --arg t "$TAG_VLESS" '.inbounds[] | select(.tag==$t) | .tls.reality.handshake.server' "$SINGBOX_CONF")
        private=$(jq -r --arg t "$TAG_VLESS" '.inbounds[] | select(.tag==$t) | .tls.reality.private_key' "$SINGBOX_CONF")
        short_id=$(jq -r --arg t "$TAG_VLESS" '.inbounds[] | select(.tag==$t) | .tls.reality.short_id[0]' "$SINGBOX_CONF")
        current_listen=$(jq -r --arg t "$TAG_VLESS" '.inbounds[] | select(.tag==$t) | .listen' "$SINGBOX_CONF")
        current_host=$(get_mode_state_field "vless" "host" 2>/dev/null || true)
        current_network=$(get_mode_state_field "vless" "network" 2>/dev/null || true)
        public=$(get_mode_state_field "vless" "public_key" 2>/dev/null || true)
        [[ -n "$current_network" ]] || current_network=$(infer_network_from_listen "$current_listen")

        clear
        echo -e "${CYAN}════════════════ VLESS Reality 更新 ════════════════${PLAIN}"
        echo -e "当前网络模式 : ${GREEN}${current_network}${PLAIN}"
        echo -e "当前监听端口 : ${GREEN}${current_port}${PLAIN}"
        echo -e "当前 Reality SNI: ${GREEN}${current_sni}${PLAIN}"
        echo -e "当前服务器地址: ${GREEN}${current_host:-未保存}${PLAIN}"
        echo -e "当前 UUID     : ${GREEN}${uuid}${PLAIN}"
        echo ""
        echo "  1. 修改网络模式"
        echo "  2. 修改监听端口"
        echo "  3. 修改 Reality SNI / 握手目标"
        echo "  4. 修改服务器地址/域名"
        echo "  5. 重新生成 UUID / Reality Key / Short ID"
        echo "  6. 查看当前节点配置"
        echo "  0. 返回"
        read -rp "请选择 [0-6]: " choice

        new_port="$current_port"; new_uuid="$uuid"; new_sni="$current_sni"; new_private="$private"
        new_short_id="$short_id"; new_listen="$current_listen"; new_network="$current_network"; new_public="$public"

        case "$choice" in
            1)
                select_network_mode_for_update "$current_network" || continue
                new_listen="$LISTEN_ADDR"; new_network="$NETWORK_MODE"
                ;;
            2)
                ask_singbox_port "请输入 VLESS Reality 监听端口" "$current_port" "$excluded_tags" || continue
                new_port="$PORT"
                ;;
            3)
                echo "当前 Reality SNI: ${current_sni}"
                echo "  1. 保持当前 SNI"
                echo "  2. swdist.apple.com（推荐）"
                echo "  3. www.icloud.com"
                echo "  4. 自定义域名"
                read -rp "请选择 [1-4，默认 1]: " choice
                case "${choice:-1}" in
                    1) new_sni="$current_sni" ;;
                    2) new_sni="swdist.apple.com" ;;
                    3) new_sni="www.icloud.com" ;;
                    4)
                        new_sni=""
                        while [[ -z "$new_sni" ]]; do read -rp "请输入 Reality 握手/SNI 域名: " new_sni; done
                        ;;
                    *) continue ;;
                esac
                ;;
            4)
                ask_server_host_with_default "$current_host"
                if save_mode_state "vless" "$(jq -n --arg host "$SERVER_HOST" --arg network "$current_network" --arg public_key "$public" '{host:$host,network:$network,public_key:$public_key}')"; then
                    echo -e "${GREEN}✔ 服务器地址已更新，不影响 UUID / Reality Key / Short ID。${PLAIN}"
                fi
                pause
                continue
                ;;
            5)
                echo -e "${YELLOW}[警告] 此操作会生成全新的 VLESS 节点身份，所有客户端参数都必须重新导入。${PLAIN}"
                read -rp "确认重新生成？[y/N]: " confirm
                [[ "$confirm" =~ ^[Yy]$ ]] || continue
                if ! generate_reality_keypair; then
                    echo -e "${RED}[错误] Reality 密钥对生成失败。${PLAIN}"; pause; continue
                fi
                new_private="$REALITY_PRIVATE_KEY"; new_public="$REALITY_PUBLIC_KEY"
                new_uuid=$("$SINGBOX_BIN" generate uuid 2>/dev/null || true)
                [[ -n "$new_uuid" ]] || new_uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || true)
                new_short_id=$(openssl rand -hex 8) || { echo -e "${RED}[错误] Short ID 生成失败。${PLAIN}"; pause; continue; }
                [[ -n "$new_uuid" ]] || { echo -e "${RED}[错误] UUID 生成失败。${PLAIN}"; pause; continue; }
                ;;
            6)
                view_vless_config
                pause
                continue
                ;;
            0) return ;;
            *) continue ;;
        esac

        inbound=$(jq -n --arg listen "$new_listen" --argjson port "$new_port" --arg uuid "$new_uuid" --arg sni "$new_sni" --arg private_key "$new_private" --arg short_id "$new_short_id" \
            '{type:"vless",tag:"vless-reality-in",listen:$listen,listen_port:$port,users:[{name:"default",uuid:$uuid,flow:"xtls-rprx-vision"}],tls:{enabled:true,reality:{enabled:true,handshake:{server:$sni,server_port:443},private_key:$private_key,short_id:[$short_id],max_time_difference:"1m"}}}')
        add_json=$(jq -n --argjson a "$inbound" '[$a]')

        if update_singbox_inbounds "$excluded_tags" "$add_json"; then
            save_mode_state "vless" "$(jq -n --arg host "$current_host" --arg network "$new_network" --arg public_key "$new_public" '{host:$host,network:$network,public_key:$public_key}')" || true
            echo -e "${GREEN}✔ VLESS Reality 更新成功。${PLAIN}"
            if [[ "$choice" != "5" ]]; then
                echo -e "${YELLOW}[保持] UUID / Reality Key / Short ID 未改变。${PLAIN}"
            fi
        else
            journalctl -u sing-box -n 30 --no-pager 2>/dev/null || true
        fi
        pause
    done
}

update_snell_v5() {
    local choice="" confirm="" current_port current_psk current_listen current_host current_network
    local new_port new_psk new_network listen_value ipv6_flag tmp

    if ! protocol_exists_snell; then
        echo -e "${YELLOW}未部署 Snell v5，请先选择“部署”。${PLAIN}"
        pause
        return
    fi
    if [[ ! -x "$SNELL_BIN" ]]; then
        echo -e "${RED}[错误] Snell v5 配置存在，但二进制缺失。请删除后重新部署。${PLAIN}"
        pause
        return
    fi

    while true; do
        current_port=$(snell_port_from_config)
        current_psk=$(awk -F'=' '/^[[:space:]]*psk[[:space:]]*=/{sub(/^[[:space:]]*/,"",$2); sub(/[[:space:]]*$/,"",$2); print $2; exit}' "$SNELL_CONF")
        current_listen=$(awk -F'=' '/^[[:space:]]*listen[[:space:]]*=/{print $2; exit}' "$SNELL_CONF")
        current_host=$(get_mode_state_field "snell" "host" 2>/dev/null || true)
        current_network=$(get_mode_state_field "snell" "network" 2>/dev/null || true)
        if [[ -z "$current_network" ]]; then
            [[ "$current_listen" == *"["* ]] && current_network="ipv6" || current_network="ipv4"
        fi

        clear
        echo -e "${CYAN}══════════════════ Snell v5 更新 ══════════════════${PLAIN}"
        echo -e "当前网络模式 : ${GREEN}${current_network}${PLAIN}"
        echo -e "当前监听端口 : ${GREEN}${current_port}${PLAIN}"
        echo -e "当前服务器地址: ${GREEN}${current_host:-未保存}${PLAIN}"
        echo ""
        echo "  1. 修改网络模式"
        echo "  2. 修改监听端口"
        echo "  3. 修改服务器地址/域名"
        echo "  4. 重新生成 PSK"
        echo "  5. 查看当前节点配置"
        echo "  0. 返回"
        read -rp "请选择 [0-5]: " choice

        new_port="$current_port"; new_psk="$current_psk"; new_network="$current_network"

        case "$choice" in
            1)
                select_network_mode_for_update "$current_network" "no" || continue
                new_network="$NETWORK_MODE"
                ;;
            2)
                while true; do
                    read -rp "请输入 Snell v5 监听端口 [默认: ${current_port}]: " new_port
                    new_port=${new_port:-$current_port}
                    validate_port_number "$new_port" || { echo -e "${RED}端口无效。${PLAIN}"; continue; }
                    port_is_available_for_snell "$new_port" && break
                done
                ;;
            3)
                ask_server_host_with_default "$current_host"
                if save_mode_state "snell" "$(jq -n --arg host "$SERVER_HOST" --arg network "$current_network" '{host:$host,network:$network}')"; then
                    echo -e "${GREEN}✔ 服务器地址已更新，不影响 Snell PSK 与端口。${PLAIN}"
                fi
                pause
                continue
                ;;
            4)
                echo -e "${YELLOW}[警告] 更换 PSK 后，所有客户端必须同步更新。${PLAIN}"
                read -rp "确认继续？[y/N]: " confirm
                [[ "$confirm" =~ ^[Yy]$ ]] || continue
                new_psk=$(openssl rand -base64 24 | tr -d '\n') || { echo -e "${RED}[错误] PSK 生成失败。${PLAIN}"; pause; continue; }
                ;;
            5)
                view_snell_config
                pause
                continue
                ;;
            0) return ;;
            *) continue ;;
        esac

        if [[ "$new_network" == "ipv6" ]]; then
            listen_value="[::]:${new_port}"; ipv6_flag="true"
        else
            listen_value="0.0.0.0:${new_port}"; ipv6_flag="false"
        fi

        ensure_snell_user || { pause; continue; }
        write_snell_service || { pause; continue; }
        tmp=$(mktemp "/etc/snell-v5.conf.tmp.XXXXXX") || continue
        chmod 600 "$tmp"
        cat > "$tmp" <<CONFIG
[snell-server]
listen = ${listen_value}
psk = ${new_psk}
version = 5
ipv6 = ${ipv6_flag}
obfs = off
CONFIG

        if apply_snell_config "$tmp"; then
            save_mode_state "snell" "$(jq -n --arg host "$current_host" --arg network "$new_network" '{host:$host,network:$network}')" || true
            echo -e "${GREEN}✔ Snell v5 更新成功。${PLAIN}"
        else
            journalctl -u snell-v5 -n 30 --no-pager 2>/dev/null || true
        fi
        pause
    done
}

delete_ss2022() {
    if ! json_has_inbound_tag "$TAG_SS"; then echo -e "${YELLOW}未部署 SS2022。${PLAIN}"; pause; return; fi
    local yes=""; read -rp "确认删除 SS2022？[y/N]: " yes
    if [[ "$yes" =~ ^[Yy]$ ]] && remove_singbox_mode ss; then echo -e "${GREEN}✔ SS2022 已删除。${PLAIN}"; fi
    pause
}

delete_shadowtls() {
    if ! json_has_inbound_tag "$TAG_STLS"; then echo -e "${YELLOW}未部署 SS2022 + ShadowTLS v3。${PLAIN}"; pause; return; fi
    local yes=""; read -rp "确认删除 SS2022 + ShadowTLS v3？[y/N]: " yes
    if [[ "$yes" =~ ^[Yy]$ ]] && remove_singbox_mode stls; then echo -e "${GREEN}✔ SS2022 + ShadowTLS v3 已删除。${PLAIN}"; fi
    pause
}

delete_vless_reality() {
    if ! json_has_inbound_tag "$TAG_VLESS"; then echo -e "${YELLOW}未部署 VLESS Reality。${PLAIN}"; pause; return; fi
    local yes=""; read -rp "确认删除 VLESS Reality？[y/N]: " yes
    if [[ "$yes" =~ ^[Yy]$ ]] && remove_singbox_mode vless; then echo -e "${GREEN}✔ VLESS Reality 已删除。${PLAIN}"; fi
    pause
}

delete_snell_v5() {
    if ! protocol_exists_snell; then echo -e "${YELLOW}未部署 Snell v5。${PLAIN}"; pause; return; fi
    local yes=""; read -rp "确认删除 Snell v5 配置与服务？[y/N]: " yes
    if [[ "$yes" =~ ^[Yy]$ ]]; then
        systemctl disable --now snell-v5 >/dev/null 2>&1 || true
        rm -f "$SNELL_CONF" "$SNELL_SERVICE"
        remove_mode_state "snell" || true
        systemctl daemon-reload || true
        echo -e "${GREEN}✔ Snell v5 节点已删除，官方二进制保留。${PLAIN}"
    fi
    pause
}

protocol_action_menu() {
    local title="$1" deploy_fn="$2" update_fn="$3" delete_fn="$4"
    while true; do
        clear
        echo -e "${CYAN}════════════════════ ${title} ════════════════════${PLAIN}"
        echo "  1. 部署"
        echo "  2. 更新"
        echo "  3. 删除"
        echo "  0. 返回"
        echo -e "${CYAN}═══════════════════════════════════════════════════════${PLAIN}"
        read -rp "请选择 [0-3]: " c
        case "$c" in
            1) "$deploy_fn" ;;
            2) "$update_fn" ;;
            3) "$delete_fn" ;;
            0) return ;;
            *) echo -e "${RED}输入无效。${PLAIN}"; sleep 1 ;;
        esac
    done
}

deploy_ss2022() {
    local excluded_tags='["ss-in"]'
    local inbound add_json

    if json_has_inbound_tag "$TAG_SS"; then
        echo -e "${YELLOW}SS2022 已存在。请返回并选择“更新”或“删除”。${PLAIN}"
        pause
        return
    fi

    select_network_mode || return
    install_singbox_core || { pause; return; }

    ask_singbox_port "请输入 SS2022 监听端口" "58588" "$excluded_tags" || return
    get_ss_cipher_and_key || { pause; return; }
    ask_server_host

    inbound=$(jq -n \
        --arg listen "$LISTEN_ADDR" \
        --argjson port "$PORT" \
        --arg method "$METHOD" \
        --arg password "$SS_KEY" \
        '{
          type:"shadowsocks",
          tag:"ss-in",
          listen:$listen,
          listen_port:$port,
          method:$method,
          password:$password
        }')
    add_json=$(jq -n --argjson a "$inbound" '[$a]')

    if update_singbox_inbounds "$excluded_tags" "$add_json"; then
        echo -e "${GREEN}✔ SS2022 部署成功。${PLAIN}"
        save_mode_state "ss" "$(jq -n --arg host "$SERVER_HOST" --arg network "$NETWORK_MODE" '{host:$host,network:$network}')" || true
        show_ss_details "$SERVER_HOST" "$PORT" "$METHOD" "$SS_KEY"
    else
        journalctl -u sing-box -n 30 --no-pager 2>/dev/null || true
    fi
    pause
}

deploy_shadowtls() {
    local excluded_tags='["ss-shadowtls-in","ss-shadowtls-backend","ss-shadowtls-udp"]'
    local tcp_port stls_pass sni udp_choice udp_enabled="false" udp_port=""

    if json_has_inbound_tag "$TAG_STLS"; then
        echo -e "${YELLOW}SS2022 + ShadowTLS v3 已存在。请返回并选择“更新”或“删除”。${PLAIN}"
        pause
        return
    fi
    local outer backend udp_inbound add_json=""
    local default_udp=""

    select_network_mode || return
    install_singbox_core || { pause; return; }

    ask_singbox_port "请输入 ShadowTLS 对外 TCP 端口（推荐 443）" "443" "$excluded_tags" || return
    tcp_port="$PORT"

    get_ss_cipher_and_key || { pause; return; }

    stls_pass=$(openssl rand -base64 24 | tr -d '\n') || {
        echo -e "${RED}[错误] ShadowTLS 密码生成失败。${PLAIN}"
        pause
        return
    }

    read -rp "请输入 ShadowTLS 握手/SNI 域名 [默认: www.microsoft.com]: " sni
    sni=${sni:-www.microsoft.com}

    echo ""
    read -rp "是否启用独立 SS2022 UDP Relay？[y/N]: " udp_choice
    if [[ "$udp_choice" =~ ^[Yy]$ ]]; then
        udp_enabled="true"
        default_udp=$(( (tcp_port + 10000) % 65535 ))
        [[ "$default_udp" -lt 1024 ]] && default_udp=58589
        while true; do
            read -rp "请输入独立 UDP 端口 [默认: ${default_udp}]: " udp_port
            udp_port=${udp_port:-$default_udp}
            if ! validate_port_number "$udp_port"; then
                echo -e "${RED}端口无效。${PLAIN}"
                continue
            fi
            # 对 UDP 端口同样检查 sing-box 配置；OS 层只要不是其他进程占用即可。
            if singbox_config_port_conflict "$udp_port" "$excluded_tags"; then
                echo -e "${RED}[错误] UDP 端口 ${udp_port} 已被其他 sing-box 入口配置占用。${PLAIN}"
                continue
            fi
            local sb_pid
            sb_pid=$(systemctl show -p MainPID --value sing-box 2>/dev/null || true)
            if port_in_use_by_other_process "$udp_port" "$sb_pid" >/tmp/ss2022-udp-conflict.$$ 2>/dev/null; then
                echo -e "${RED}[错误] 端口 ${udp_port} 已被其他进程占用。${PLAIN}"
                cat /tmp/ss2022-udp-conflict.$$ 2>/dev/null || true
                rm -f /tmp/ss2022-udp-conflict.$$
                continue
            fi
            rm -f /tmp/ss2022-udp-conflict.$$ 2>/dev/null || true
            break
        done
    fi

    ask_server_host

    outer=$(jq -n \
        --arg listen "$LISTEN_ADDR" \
        --argjson port "$tcp_port" \
        --arg password "$stls_pass" \
        --arg sni "$sni" \
        '{
          type:"shadowtls",
          tag:"ss-shadowtls-in",
          listen:$listen,
          listen_port:$port,
          version:3,
          users:[{name:"default",password:$password}],
          handshake:{server:$sni,server_port:443},
          strict_mode:true,
          detour:"ss-shadowtls-backend"
        }')

    backend=$(jq -n \
        --arg method "$METHOD" \
        --arg password "$SS_KEY" \
        '{
          type:"shadowsocks",
          tag:"ss-shadowtls-backend",
          listen:"127.0.0.1",
          network:"tcp",
          method:$method,
          password:$password
        }')

    if [[ "$udp_enabled" == "true" ]]; then
        udp_inbound=$(jq -n \
            --arg listen "$LISTEN_ADDR" \
            --argjson port "$udp_port" \
            --arg method "$METHOD" \
            --arg password "$SS_KEY" \
            '{
              type:"shadowsocks",
              tag:"ss-shadowtls-udp",
              listen:$listen,
              listen_port:$port,
              network:"udp",
              method:$method,
              password:$password
            }')
        add_json=$(jq -n --argjson a "$outer" --argjson b "$backend" --argjson c "$udp_inbound" '[$a,$b,$c]')
    else
        add_json=$(jq -n --argjson a "$outer" --argjson b "$backend" '[$a,$b]')
    fi

    if update_singbox_inbounds "$excluded_tags" "$add_json"; then
        echo -e "${GREEN}✔ SS2022 + ShadowTLS v3 部署成功。${PLAIN}"
        save_mode_state "shadowtls" "$(jq -n --arg host "$SERVER_HOST" --arg network "$NETWORK_MODE" '{host:$host,network:$network}')" || true
        show_shadowtls_details "$SERVER_HOST" "$tcp_port" "$METHOD" "$SS_KEY" "$stls_pass" "$sni" "$udp_enabled" "$udp_port"
    else
        journalctl -u sing-box -n 30 --no-pager 2>/dev/null || true
    fi
    pause
}

generate_reality_keypair() {
    local keys private public

    keys=$("$SINGBOX_BIN" generate reality-keypair 2>/dev/null) || return 1
    private=$(printf '%s\n' "$keys" | awk -F': *' '/PrivateKey/ {print $2; exit}')
    public=$(printf '%s\n' "$keys" | awk -F': *' '/PublicKey/ {print $2; exit}')

    [[ -n "$private" && -n "$public" ]] || return 1
    REALITY_PRIVATE_KEY="$private"
    REALITY_PUBLIC_KEY="$public"
    return 0
}

deploy_vless_reality() {
    local excluded_tags='["vless-reality-in"]'
    local vless_port uuid sni short_id inbound add_json reality_sni_choice

    if json_has_inbound_tag "$TAG_VLESS"; then
        echo -e "${YELLOW}VLESS Reality 已存在。请返回并选择“更新”或“删除”。${PLAIN}"
        pause
        return
    fi
    local REALITY_PRIVATE_KEY="" REALITY_PUBLIC_KEY=""

    select_network_mode || return
    install_singbox_core || { pause; return; }

    ask_singbox_port "请输入 VLESS Reality 监听端口" "443" "$excluded_tags" || return
    vless_port="$PORT"

    if ! generate_reality_keypair; then
        echo -e "${RED}[错误] Reality 密钥对生成失败。${PLAIN}"
        pause
        return
    fi

    uuid=$("$SINGBOX_BIN" generate uuid 2>/dev/null || true)
    [[ -n "$uuid" ]] || uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || true)
    if [[ -z "$uuid" ]]; then
        echo -e "${RED}[错误] UUID 生成失败。${PLAIN}"
        pause
        return
    fi

    short_id=$(openssl rand -hex 8) || {
        echo -e "${RED}[错误] Short ID 生成失败。${PLAIN}"
        pause
        return
    }

    echo -e "${YELLOW}[提示] Reality 握手目标应选择从本机可正常访问的 TLS 1.3 站点。${PLAIN}"
    echo -e "${YELLOW}[提示] 当前 sing-box 已知 www.microsoft.com 可能触发 Reality 握手兼容问题。${PLAIN}"
    echo "请选择 Reality 握手/SNI："
    echo "  1. swdist.apple.com（默认，Apple CDN；当前已知可用）"
    echo "  2. www.icloud.com（Apple iCloud）"
    echo "  3. 自定义域名"
    read -rp "请选择 [1-3，默认 1]: " reality_sni_choice
    case "${reality_sni_choice:-1}" in
        1) sni="swdist.apple.com" ;;
        2) sni="www.icloud.com" ;;
        3)
            while [[ -z "$sni" ]]; do
                read -rp "请输入 Reality 握手/SNI 域名: " sni
            done
            ;;
        *)
            echo -e "${YELLOW}[提示] 输入无效，使用默认 swdist.apple.com。${PLAIN}"
            sni="swdist.apple.com"
            ;;
    esac

    ask_server_host

    inbound=$(jq -n \
        --arg listen "$LISTEN_ADDR" \
        --argjson port "$vless_port" \
        --arg uuid "$uuid" \
        --arg sni "$sni" \
        --arg private_key "$REALITY_PRIVATE_KEY" \
        --arg short_id "$short_id" \
        '{
          type:"vless",
          tag:"vless-reality-in",
          listen:$listen,
          listen_port:$port,
          users:[{
            name:"default",
            uuid:$uuid,
            flow:"xtls-rprx-vision"
          }],
          tls:{
            enabled:true,
            reality:{
              enabled:true,
              handshake:{server:$sni,server_port:443},
              private_key:$private_key,
              short_id:[$short_id],
              max_time_difference:"1m"
            }
          }
        }')
    add_json=$(jq -n --argjson a "$inbound" '[$a]')

    if update_singbox_inbounds "$excluded_tags" "$add_json"; then
        echo -e "${GREEN}✔ VLESS Reality 部署成功。${PLAIN}"
        save_mode_state "vless" "$(jq -n --arg host "$SERVER_HOST" --arg network "$NETWORK_MODE" --arg public_key "$REALITY_PUBLIC_KEY" '{host:$host,network:$network,public_key:$public_key}')" || true
        show_vless_details "$SERVER_HOST" "$vless_port" "$uuid" "$sni" "$REALITY_PUBLIC_KEY" "$short_id"
    else
        journalctl -u sing-box -n 30 --no-pager 2>/dev/null || true
    fi
    pause
}

ensure_snell_user() {
    local nologin_shell=""

    if id -u "$SNELL_USER" >/dev/null 2>&1; then
        return 0
    fi

    nologin_shell=$(command -v nologin 2>/dev/null || true)
    nologin_shell=${nologin_shell:-/usr/sbin/nologin}
    useradd --system --user-group --no-create-home --home-dir /nonexistent --shell "$nologin_shell" "$SNELL_USER" || return 1
    touch "$SNELL_USER_MARKER"
    chmod 600 "$SNELL_USER_MARKER"
    return 0
}

snell_port_from_config() {
    [[ -f "$SNELL_CONF" ]] || return 1
    awk -F'[: ]+' '/^[[:space:]]*listen[[:space:]]*=/{gsub(/\[/,"",$0); gsub(/\]/,"",$0); print $NF; exit}' "$SNELL_CONF" 2>/dev/null
}

port_is_available_for_snell() {
    local port="$1"
    local current_port="" snell_pid=""

    current_port=$(snell_port_from_config 2>/dev/null || true)
    snell_pid=$(systemctl show -p MainPID --value snell-v5 2>/dev/null || true)

    # 允许重新使用当前 Snell 自身端口。
    if [[ "$current_port" == "$port" && "$snell_pid" =~ ^[0-9]+$ && "$snell_pid" -gt 0 ]]; then
        if port_in_use_by_other_process "$port" "$snell_pid" >/tmp/ss2022-snell-conflict.$$ 2>/dev/null; then
            echo -e "${RED}[错误] 端口 ${port} 还被其他进程占用。${PLAIN}"
            cat /tmp/ss2022-snell-conflict.$$ 2>/dev/null || true
            rm -f /tmp/ss2022-snell-conflict.$$
            return 1
        fi
        rm -f /tmp/ss2022-snell-conflict.$$ 2>/dev/null || true
        return 0
    fi

    if [[ -f "$SINGBOX_CONF" ]] && jq -e --argjson p "$port" '.inbounds[]? | select((.listen_port // 0) == $p)' "$SINGBOX_CONF" >/dev/null 2>&1; then
        echo -e "${RED}[错误] 端口 ${port} 已被 sing-box 协议入口配置占用。${PLAIN}"
        return 1
    fi

    if port_in_use_by_other_process "$port" "" >/tmp/ss2022-snell-conflict.$$ 2>/dev/null; then
        echo -e "${RED}[错误] 端口 ${port} 已被占用：${PLAIN}"
        cat /tmp/ss2022-snell-conflict.$$ 2>/dev/null || true
        rm -f /tmp/ss2022-snell-conflict.$$
        return 1
    fi
    rm -f /tmp/ss2022-snell-conflict.$$ 2>/dev/null || true
    return 0
}

snell_binary_works() {
    local binary="$1" output=""
    [[ -x "$binary" ]] || return 1

    "$binary" --v >/dev/null 2>&1 && return 0
    "$binary" --version >/dev/null 2>&1 && return 0
    "$binary" -v >/dev/null 2>&1 && return 0

    if command -v ldd >/dev/null 2>&1; then
        output=$(ldd "$binary" 2>&1 || true)
        echo "$output" | grep -qiE 'not found|No such file|Error loading' && return 1
        [[ -n "$output" ]] && return 0
    fi
    return 1
}

install_snell_v5_core() {
    local arch sarch expected_sha url tmp zip actual curl_family

    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)
            sarch="amd64"
            expected_sha="$SNELL_SHA256_AMD64"
            ;;
        aarch64|arm64)
            sarch="aarch64"
            expected_sha="$SNELL_SHA256_ARM64"
            ;;
        *)
            echo -e "${RED}[错误] Snell v5 当前脚本仅支持 amd64 / aarch64。${PLAIN}"
            return 1
            ;;
    esac

    [[ "$NETWORK_MODE" == "ipv6" ]] && curl_family="-6" || curl_family="-4"

    if [[ -x "$SNELL_BIN" ]]; then
        echo -e "${GREEN}✔ 已检测到 Snell v5 二进制，将重新核验固定版本包后覆盖安装。${PLAIN}"
    fi

    tmp=$(mktemp -d) || return 1
    zip="$tmp/snell.zip"
    url="https://dl.nssurge.com/snell/snell-server-v${SNELL_VERSION}-linux-${sarch}.zip"

    echo -e "${YELLOW}>> 从 Surge 官方下载 Snell v${SNELL_VERSION}...${PLAIN}"
    if ! curl -fL "$curl_family" --connect-timeout 20 --max-time 120 --retry 3 --retry-delay 2 \
        -o "$zip" "$url"; then
        rm -rf "$tmp"
        echo -e "${RED}[错误] Snell v5 下载失败：${url}${PLAIN}"
        return 1
    fi

    actual=$(sha256sum "$zip" | awk '{print $1}')
    if [[ "$actual" != "$expected_sha" ]]; then
        echo -e "${RED}[错误] Snell v5 SHA256 校验失败，拒绝安装。${PLAIN}"
        echo -e "${YELLOW}期望: ${expected_sha}${PLAIN}"
        echo -e "${YELLOW}实际: ${actual}${PLAIN}"
        rm -rf "$tmp"
        return 1
    fi

    if ! unzip -tq "$zip" >/dev/null 2>&1; then
        echo -e "${RED}[错误] Snell 下载文件不是有效 ZIP。${PLAIN}"
        rm -rf "$tmp"
        return 1
    fi

    # 防止压缩包路径穿越。
    if unzip -Z1 "$zip" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
        echo -e "${RED}[错误] Snell ZIP 包含不安全路径，拒绝解压。${PLAIN}"
        rm -rf "$tmp"
        return 1
    fi

    unzip -oq "$zip" -d "$tmp" || {
        rm -rf "$tmp"
        return 1
    }

    if [[ ! -f "$tmp/snell-server" ]]; then
        echo -e "${RED}[错误] Snell ZIP 内未找到 snell-server。${PLAIN}"
        rm -rf "$tmp"
        return 1
    fi

    install -m 755 "$tmp/snell-server" "$SNELL_BIN" || {
        rm -rf "$tmp"
        return 1
    }
    rm -rf "$tmp"

    if ! snell_binary_works "$SNELL_BIN"; then
        echo -e "${RED}[错误] Snell v5 二进制安装后无法正常加载/执行。${PLAIN}"
        return 1
    fi

    echo -e "${GREEN}✔ Snell v${SNELL_VERSION} 官方二进制安装并校验完成。${PLAIN}"
    return 0
}

write_snell_service() {
    ensure_snell_user || return 1

    cat > "$SNELL_SERVICE" <<'SERVICE'
[Unit]
Description=Snell Server v5
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=snell
Group=snell
ExecStart=/usr/local/bin/snell-server-v5 -c /etc/snell/snell-v5.conf
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576
UMask=0077
NoNewPrivileges=true
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

[Install]
WantedBy=multi-user.target
SERVICE

    systemctl daemon-reload || return 1
    systemctl enable snell-v5 >/dev/null 2>&1 || return 1
    return 0
}

apply_snell_config() {
    local candidate="$1"
    local backup="" had_old=0

    mkdir -p /etc/snell || return 1
    chown root:"$SNELL_GROUP" /etc/snell
    chmod 750 /etc/snell

    if [[ -f "$SNELL_CONF" ]]; then
        had_old=1
        backup=$(mktemp "/etc/snell/snell-v5.conf.rollback.XXXXXX") || return 1
        cp -a "$SNELL_CONF" "$backup" || {
            rm -f "$backup"
            return 1
        }
    fi

    mv -f "$candidate" "$SNELL_CONF" || {
        rm -f "$candidate" "$backup"
        return 1
    }
    chown root:"$SNELL_GROUP" "$SNELL_CONF"
    chmod 640 "$SNELL_CONF"

    if ! systemctl restart snell-v5; then
        echo -e "${RED}[错误] Snell v5 启动失败，正在回滚配置...${PLAIN}"
        if [[ $had_old -eq 1 && -f "$backup" ]]; then
            mv -f "$backup" "$SNELL_CONF"
            chown root:"$SNELL_GROUP" "$SNELL_CONF"
            chmod 640 "$SNELL_CONF"
            systemctl restart snell-v5 >/dev/null 2>&1 || true
        else
            rm -f "$SNELL_CONF"
            systemctl stop snell-v5 >/dev/null 2>&1 || true
        fi
        return 1
    fi

    rm -f "$backup"
    return 0
}

deploy_snell_v5() {
    local snell_port psk listen_value ipv6_flag tmp

    if protocol_exists_snell; then
        echo -e "${YELLOW}Snell v5 已存在。请返回并选择“更新”或“删除”。${PLAIN}"
        pause
        return
    fi

    select_network_mode "no" || return
    install_snell_v5_core || { pause; return; }
    ensure_snell_user || { pause; return; }
    write_snell_service || { pause; return; }

    while true; do
        read -rp "请输入 Snell v5 监听端口 [默认: 63333]: " snell_port
        snell_port=${snell_port:-63333}
        if ! validate_port_number "$snell_port"; then
            echo -e "${RED}端口无效。${PLAIN}"
            continue
        fi
        port_is_available_for_snell "$snell_port" && break
    done

    psk=$(openssl rand -base64 24 | tr -d '\n') || {
        echo -e "${RED}[错误] Snell PSK 生成失败。${PLAIN}"
        pause
        return
    }

    if [[ "$NETWORK_MODE" == "ipv6" ]]; then
        listen_value="[::]:${snell_port}"
        ipv6_flag="true"
    else
        listen_value="0.0.0.0:${snell_port}"
        ipv6_flag="false"
    fi

    ask_server_host

    tmp=$(mktemp "/etc/snell-v5.conf.tmp.XXXXXX") || return
    chmod 600 "$tmp"
    cat > "$tmp" <<CONFIG
[snell-server]
listen = ${listen_value}
psk = ${psk}
version = 5
ipv6 = ${ipv6_flag}
obfs = off
CONFIG

    if apply_snell_config "$tmp"; then
        echo -e "${GREEN}✔ Snell v5 部署成功。${PLAIN}"
        save_mode_state "snell" "$(jq -n --arg host "$SERVER_HOST" --arg network "$NETWORK_MODE" '{host:$host,network:$network}')" || true
        show_snell_details "$SERVER_HOST" "$snell_port" "$psk"
    else
        journalctl -u snell-v5 -n 30 --no-pager 2>/dev/null || true
    fi
    pause
}

view_ss2022_config() {
    local host port method pass listen ip_type
    json_has_inbound_tag "$TAG_SS" || {
        echo -e "${YELLOW}未部署 SS2022。${PLAIN}"
        return
    }

    port=$(jq -r --arg t "$TAG_SS" '.inbounds[] | select(.tag==$t) | .listen_port' "$SINGBOX_CONF")
    method=$(jq -r --arg t "$TAG_SS" '.inbounds[] | select(.tag==$t) | .method' "$SINGBOX_CONF")
    pass=$(jq -r --arg t "$TAG_SS" '.inbounds[] | select(.tag==$t) | .password' "$SINGBOX_CONF")
    listen=$(jq -r --arg t "$TAG_SS" '.inbounds[] | select(.tag==$t) | .listen' "$SINGBOX_CONF")

    host=$(get_mode_state_field "ss" "host" 2>/dev/null || true)
    if [[ -z "$host" ]]; then
        if [[ "$listen" == "::" ]]; then
            host=$(get_global_ipv6 2>/dev/null || echo "请填写IPv6地址")
        else
            host=$(get_public_ipv4 2>/dev/null || echo "请填写服务器地址")
        fi
    fi
    show_ss_details "$host" "$port" "$method" "$pass"
}

view_shadowtls_config() {
    local host port method ss_pass stls_pass sni listen udp_enabled="false" udp_port=""

    json_has_inbound_tag "$TAG_STLS" || {
        echo -e "${YELLOW}未部署 SS2022 + ShadowTLS。${PLAIN}"
        return
    }

    port=$(jq -r --arg t "$TAG_STLS" '.inbounds[] | select(.tag==$t) | .listen_port' "$SINGBOX_CONF")
    stls_pass=$(jq -r --arg t "$TAG_STLS" '.inbounds[] | select(.tag==$t) | .users[0].password' "$SINGBOX_CONF")
    sni=$(jq -r --arg t "$TAG_STLS" '.inbounds[] | select(.tag==$t) | .handshake.server' "$SINGBOX_CONF")
    listen=$(jq -r --arg t "$TAG_STLS" '.inbounds[] | select(.tag==$t) | .listen' "$SINGBOX_CONF")
    method=$(jq -r --arg t "$TAG_STLS_BACKEND" '.inbounds[] | select(.tag==$t) | .method' "$SINGBOX_CONF")
    ss_pass=$(jq -r --arg t "$TAG_STLS_BACKEND" '.inbounds[] | select(.tag==$t) | .password' "$SINGBOX_CONF")

    if json_has_inbound_tag "$TAG_STLS_UDP"; then
        udp_enabled="true"
        udp_port=$(get_inbound_port "$TAG_STLS_UDP")
    fi

    host=$(get_mode_state_field "shadowtls" "host" 2>/dev/null || true)
    if [[ -z "$host" ]]; then
        if [[ "$listen" == "::" ]]; then
            host=$(get_global_ipv6 2>/dev/null || echo "请填写IPv6地址")
        else
            host=$(get_public_ipv4 2>/dev/null || echo "请填写服务器地址")
        fi
    fi
    show_shadowtls_details "$host" "$port" "$method" "$ss_pass" "$stls_pass" "$sni" "$udp_enabled" "$udp_port"
}

view_vless_config() {
    local host port uuid sni private public short_id listen keys

    json_has_inbound_tag "$TAG_VLESS" || {
        echo -e "${YELLOW}未部署 VLESS Reality。${PLAIN}"
        return
    }

    port=$(jq -r --arg t "$TAG_VLESS" '.inbounds[] | select(.tag==$t) | .listen_port' "$SINGBOX_CONF")
    uuid=$(jq -r --arg t "$TAG_VLESS" '.inbounds[] | select(.tag==$t) | .users[0].uuid' "$SINGBOX_CONF")
    sni=$(jq -r --arg t "$TAG_VLESS" '.inbounds[] | select(.tag==$t) | .tls.reality.handshake.server' "$SINGBOX_CONF")
    private=$(jq -r --arg t "$TAG_VLESS" '.inbounds[] | select(.tag==$t) | .tls.reality.private_key' "$SINGBOX_CONF")
    short_id=$(jq -r --arg t "$TAG_VLESS" '.inbounds[] | select(.tag==$t) | .tls.reality.short_id[0]' "$SINGBOX_CONF")
    listen=$(jq -r --arg t "$TAG_VLESS" '.inbounds[] | select(.tag==$t) | .listen' "$SINGBOX_CONF")

    host=$(get_mode_state_field "vless" "host" 2>/dev/null || true)
    public=$(get_mode_state_field "vless" "public_key" 2>/dev/null || true)
    if [[ -z "$host" ]]; then
        if [[ "$listen" == "::" ]]; then
            host=$(get_global_ipv6 2>/dev/null || echo "请填写IPv6地址")
        else
            host=$(get_public_ipv4 2>/dev/null || echo "请填写服务器地址")
        fi
    fi

    if [[ -n "$public" ]]; then
        show_vless_details "$host" "$port" "$uuid" "$sni" "$public" "$short_id"
    else
        echo ""
        echo -e "${CYAN}════════════════════ VLESS Reality 服务端配置 ════════════════════${PLAIN}"
        echo -e "  地址: ${CYAN}${host}${PLAIN}"
        echo -e "  端口: ${CYAN}${port}${PLAIN}"
        echo -e "  UUID: ${CYAN}${uuid}${PLAIN}"
        echo -e "  SNI : ${CYAN}${sni}${PLAIN}"
        echo -e "  Private Key: ${CYAN}${private}${PLAIN}"
        echo -e "  Short ID: ${CYAN}${short_id}${PLAIN}"
        echo -e "${YELLOW}[提示] 这是从旧配置升级而来的节点，state.json 中没有 Public Key；重新部署一次 VLESS Reality 后即可完整保存/查看客户端参数。${PLAIN}"
        echo -e "${CYAN}════════════════════════════════════════════════════════════${PLAIN}"
    fi
}

view_snell_config() {
    local host port psk listen

    [[ -f "$SNELL_CONF" ]] || {
        echo -e "${YELLOW}未部署 Snell v5。${PLAIN}"
        return
    }

    port=$(snell_port_from_config)
    psk=$(awk -F'=' '/^[[:space:]]*psk[[:space:]]*=/{sub(/^[[:space:]]*/,"",$2); sub(/[[:space:]]*$/,"",$2); print $2; exit}' "$SNELL_CONF")
    listen=$(awk -F'=' '/^[[:space:]]*listen[[:space:]]*=/{print $2; exit}' "$SNELL_CONF")

    host=$(get_mode_state_field "snell" "host" 2>/dev/null || true)
    if [[ -z "$host" ]]; then
        if [[ "$listen" == *"["* ]]; then
            host=$(get_global_ipv6 2>/dev/null || echo "请填写IPv6地址")
        else
            host=$(get_public_ipv4 2>/dev/null || echo "请填写服务器地址")
        fi
    fi
    show_snell_details "$host" "$port" "$psk"
}

view_config_menu() {
    while true; do
        clear
        echo -e "${CYAN}════════════════════ 查看节点配置 ════════════════════${PLAIN}"
        echo "  1. SS2022"
        echo "  2. SS2022 + ShadowTLS v3"
        echo "  3. VLESS Reality"
        echo "  4. Snell v5"
        echo "  0. 返回"
        echo -e "${CYAN}═══════════════════════════════════════════════════════${PLAIN}"
        read -rp "请选择 [0-4]: " c
        case "$c" in
            1) view_ss2022_config; pause ;;
            2) view_shadowtls_config; pause ;;
            3) view_vless_config; pause ;;
            4) view_snell_config; pause ;;
            0) return ;;
            *) echo -e "${RED}输入无效。${PLAIN}"; sleep 1 ;;
        esac
    done
}

remove_singbox_mode() {
    local mode="$1"
    local tags='[]'
    case "$mode" in
        ss) tags='["ss-in"]' ;;
        stls) tags='["ss-shadowtls-in","ss-shadowtls-backend","ss-shadowtls-udp"]' ;;
        vless) tags='["vless-reality-in"]' ;;
        *) return 1 ;;
    esac
    if update_singbox_inbounds "$tags" '[]'; then
        case "$mode" in
            ss) remove_mode_state "ss" || true ;;
            stls) remove_mode_state "shadowtls" || true ;;
            vless) remove_mode_state "vless" || true ;;
        esac
        return 0
    fi
    return 1
}

remove_protocol_menu() {
    while true; do
        clear
        echo -e "${CYAN}════════════════════ 删除单个协议 ════════════════════${PLAIN}"
        echo "  1. 删除 SS2022"
        echo "  2. 删除 SS2022 + ShadowTLS v3"
        echo "  3. 删除 VLESS Reality"
        echo "  4. 删除 Snell v5 配置/服务（保留二进制）"
        echo "  0. 返回"
        read -rp "请选择 [0-4]: " c
        case "$c" in
            1)
                read -rp "确认删除 SS2022？[y/N]: " yes
                [[ "$yes" =~ ^[Yy]$ ]] && remove_singbox_mode ss
                pause
                ;;
            2)
                read -rp "确认删除 SS2022 + ShadowTLS？[y/N]: " yes
                [[ "$yes" =~ ^[Yy]$ ]] && remove_singbox_mode stls
                pause
                ;;
            3)
                read -rp "确认删除 VLESS Reality？[y/N]: " yes
                [[ "$yes" =~ ^[Yy]$ ]] && remove_singbox_mode vless
                pause
                ;;
            4)
                read -rp "确认删除 Snell v5 配置与服务？[y/N]: " yes
                if [[ "$yes" =~ ^[Yy]$ ]]; then
                    systemctl disable --now snell-v5 >/dev/null 2>&1 || true
                    rm -f "$SNELL_CONF" "$SNELL_SERVICE"
                    remove_mode_state "snell" || true
                    systemctl daemon-reload || true
                    echo -e "${GREEN}✔ Snell v5 节点已删除，二进制保留。${PLAIN}"
                fi
                pause
                ;;
            0) return ;;
            *) sleep 1 ;;
        esac
    done
}

show_service_status() {
    echo ""
    echo -e "${YELLOW}【sing-box】${PLAIN}"
    systemctl --no-pager --full status sing-box 2>/dev/null | head -n 15 || echo "未安装/未加载"

    echo ""
    echo -e "${YELLOW}【Snell v5】${PLAIN}"
    systemctl --no-pager --full status snell-v5 2>/dev/null | head -n 15 || echo "未安装/未加载"

    echo ""
    echo -e "${YELLOW}【监听端口】${PLAIN}"
    ss -lntup 2>/dev/null | grep -E 'sing-box|snell-server' || echo "未检测到代理监听"
}

full_uninstall() {
    local yes=""
    echo -e "${RED}此操作会删除 sing-box、Snell v5、全部节点配置、服务文件和快捷命令。${PLAIN}"
    read -rp "确认彻底卸载？请输入 YES: " yes
    [[ "$yes" == "YES" ]] || return

    systemctl disable --now sing-box snell-v5 ipv6-keepalive.timer >/dev/null 2>&1 || true
    systemctl stop ipv6-keepalive.service >/dev/null 2>&1 || true

    rm -rf /etc/sing-box /etc/snell "$STATE_DIR"
    rm -f \
        /usr/local/bin/ss2022 \
        /usr/local/bin/proxy \
        "$SINGBOX_BIN" \
        "$SNELL_BIN" \
        "$SINGBOX_SERVICE" \
        "$SNELL_SERVICE" \
        /etc/systemd/system/ipv6-keepalive.service \
        /etc/systemd/system/ipv6-keepalive.timer \
        "$FORCE_IPV6_CONF"

    if [[ -f "$DNS_MARKER" && -f "$BACKUP_DNS" && ! -L /etc/resolv.conf ]]; then
        cp -f "$BACKUP_DNS" /etc/resolv.conf 2>/dev/null || true
        rm -f "$DNS_MARKER"
    fi

    if [[ -f "$SINGBOX_USER_MARKER" ]]; then
        userdel "$SINGBOX_USER" >/dev/null 2>&1 || true
        rm -f "$SINGBOX_USER_MARKER"
    fi

    if [[ -f "$SNELL_USER_MARKER" ]]; then
        userdel "$SNELL_USER" >/dev/null 2>&1 || true
        rm -f "$SNELL_USER_MARKER"
    fi

    systemctl daemon-reload || true
    echo -e "${GREEN}✔ 已彻底卸载。${PLAIN}"
    exit 0
}

service_management() {
    while true; do
        clear
        echo -e "${CYAN}════════════════════ 服务运维管理 ════════════════════${PLAIN}"
        echo "  1. 查看全部服务状态与监听端口"
        echo "  2. 查看 sing-box 实时日志"
        echo "  3. 查看 Snell v5 实时日志"
        echo "  4. 重启 sing-box"
        echo "  5. 重启 Snell v5"
        echo "  6. 查看 IPv6 Keepalive 状态"
        echo "  7. 彻底卸载全部代理组件"
        echo "  0. 返回"
        echo -e "${CYAN}═══════════════════════════════════════════════════════${PLAIN}"
        read -rp "请选择 [0-7]: " c

        case "$c" in
            1) show_service_status; pause ;;
            2) journalctl -u sing-box -f -n 30 ;;
            3) journalctl -u snell-v5 -f -n 30 ;;
            4)
                if systemctl restart sing-box; then echo -e "${GREEN}✔ sing-box 已重启。${PLAIN}"; else journalctl -u sing-box -n 30 --no-pager; fi
                pause
                ;;
            5)
                if systemctl restart snell-v5; then echo -e "${GREEN}✔ Snell v5 已重启。${PLAIN}"; else journalctl -u snell-v5 -n 30 --no-pager; fi
                pause
                ;;
            6)
                systemctl list-timers --all | grep -E 'keepalive|NEXT' || echo "未检测到 Keepalive 定时器。"
                pause
                ;;
            7) full_uninstall ;;
            0) return ;;
            *) sleep 1 ;;
        esac
    done
}

main() {
    check_root

    while true; do
        show_dashboard
        echo "  1. SS2022"
        echo "  2. SS2022 + ShadowTLS v3（增强伪装）"
        echo "  3. VLESS Reality"
        echo "  4. Snell v5"
        echo "  5. 查看当前节点参数与客户端配置"
        echo "  6. 服务运维管理"
        echo "  0. 退出管理面板"
        echo -e "${CYAN}═════════════════════════════════════════════════════════════════${PLAIN}"
        read -rp "请输入选项编号 [0-6]: " choice

        case "$choice" in
            1) protocol_action_menu "SS2022" deploy_ss2022 update_ss2022 delete_ss2022 ;;
            2) protocol_action_menu "SS2022 + ShadowTLS v3" deploy_shadowtls update_shadowtls delete_shadowtls ;;
            3) protocol_action_menu "VLESS Reality" deploy_vless_reality update_vless_reality delete_vless_reality ;;
            4) protocol_action_menu "Snell v5" deploy_snell_v5 update_snell_v5 delete_snell_v5 ;;
            5) view_config_menu ;;
            6) service_management ;;
            0)
                echo "已安全退出。随时输入 ss2022 唤出！"
                exit 0
                ;;
            *)
                echo -e "${RED}请输入有效编号！${PLAIN}"
                sleep 1
                ;;
        esac
    done
}

main
