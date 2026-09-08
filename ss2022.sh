#!/bin/bash
# ==============================================================================
# 项目名称: VPS Bootstrap & SS2022 全球通用自适应管理脚本
# 快捷命令: ss2022 / proxy
# 当前版本: v1.6.1 (Security Hardening+)
# ==============================================================================

SCRIPT_VERSION="v1.6.1"
AUTHOR="DevOps"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

SINGBOX_BIN="/usr/local/bin/sing-box"
SINGBOX_CONF="/etc/sing-box/config.json"
SINGBOX_SERVICE="/etc/systemd/system/sing-box.service"
BACKUP_DNS="/root/resolv.conf.orig"
DNS_MARKER="/etc/ss2022-ipv6-dns-managed"
FORCE_IPV6_CONF="/etc/apt/apt.conf.d/99force-ipv6"
SINGBOX_USER="sing-box"
SINGBOX_GROUP="sing-box"
SINGBOX_USER_MARKER="/etc/ss2022-singbox-user-managed"
SINGBOX_VERSION="1.13.20"

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[错误] 必须使用 root 权限运行此脚本！${PLAIN}"
        exit 1
    fi
}

get_sys_info() {
    local os=""
    local ver=""
    local kernel=""

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

get_core_version() {
    if [[ -x "$SINGBOX_BIN" ]]; then
        local sb_v
        sb_v=$($SINGBOX_BIN version 2>/dev/null | head -n 1 | awk '{print $3}')
        echo "Sing-box ${sb_v:-已安装}"
    elif command -v sing-box &>/dev/null; then
        local sb_v
        sb_v=$(sing-box version 2>/dev/null | head -n 1 | awk '{print $3}')
        echo "Sing-box ${sb_v:-已安装}"
    else
        echo "未检测到已安装核心"
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

show_dashboard() {
    clear
    local sys_info
    local core_info
    local status_icon=""
    local time_sync_status=""
    local keepalive_status="${YELLOW}○ 未配置${PLAIN}"
    local installed_count=0
    local proto_list=""

    sys_info=$(get_sys_info)
    core_info=$(get_core_version)
    time_sync_status=$(get_time_sync_status)

    if systemctl is-active --quiet sing-box 2>/dev/null; then
        status_icon="${GREEN}● 运行中${PLAIN}"
    elif [[ -f "$SINGBOX_CONF" ]]; then
        status_icon="${RED}○ 已停止${PLAIN}"
    else
        status_icon="${YELLOW}○ 未安装${PLAIN}"
    fi

    if systemctl is-active --quiet ipv6-keepalive.timer 2>/dev/null; then
        keepalive_status="${GREEN}● 已激活 (5min轮询)${PLAIN}"
    fi

    if [[ -f "$SINGBOX_CONF" ]] && command -v jq &>/dev/null; then
        local ss_port
        ss_port=$(jq -r '.inbounds[]? | select(.type=="shadowsocks") | .listen_port' "$SINGBOX_CONF" 2>/dev/null | head -n 1)
        if [[ -n "$ss_port" && "$ss_port" != "null" ]]; then
            ((installed_count++))
            proto_list+="\n    • SS2022 - 端口: ${CYAN}${ss_port}${PLAIN}"
        fi
    fi

    echo -e "${CYAN}═════════════════════════════════════════════════════════════════${PLAIN}"
    echo -e "      SS2022 多协议代理管理脚本 ${SCRIPT_VERSION} [安全强化版]"
    echo -e "      快捷命令: ${GREEN}ss2022${PLAIN} 或 ${GREEN}proxy${PLAIN}"
    echo -e "${CYAN}═════════════════════════════════════════════════════════════════${PLAIN}"
    echo -e "  系统信息: ${sys_info}"
    echo -e "  核心状态: ${core_info}"
    echo -e "  服务状态: ${status_icon}"
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

    # 恢复 v1.5.0 明确接管过的 DNS；同时兼容 v1.4.0 已写入的固定 IPv6 DNS。
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

    echo -e "${YELLOW}>> 检查系统时间同步状态（SS2022 要求客户端/服务端时钟准确）...${PLAIN}"

    if time_sync_is_healthy; then
        echo -e "${GREEN}✔ 系统时间已同步。当前 UTC: $(date -u '+%Y-%m-%d %H:%M:%S UTC')${PLAIN}"
        return 0
    fi

    echo -e "${YELLOW}[提示] 检测到系统时钟尚未同步，准备使用 chrony 自动校时。${PLAIN}"

    if ! command -v chronyc &>/dev/null; then
        if ! apt-get install -y chrony; then
            echo -e "${RED}[错误] chrony 安装失败，无法保证 SS2022 时间戳校验正常。${PLAIN}"
            return 1
        fi
    fi

    if ! systemctl enable --now chrony >/dev/null 2>&1; then
        echo -e "${RED}[错误] chrony 服务启动失败。${PLAIN}"
        return 1
    fi

    if ! systemctl restart chrony >/dev/null 2>&1; then
        echo -e "${RED}[错误] chrony 服务重启失败。${PLAIN}"
        return 1
    fi

    # 请求快速采样并在需要时立即校正系统时间。
    chronyc -a burst 4/4 >/dev/null 2>&1 || true
    sleep 2
    chronyc -a makestep >/dev/null 2>&1 || true

    # 最多等待约 30 秒确认同步成功。
    for attempt in {1..15}; do
        if time_sync_is_healthy; then
            echo -e "${GREEN}✔ 系统时间同步完成。当前 UTC: $(date -u '+%Y-%m-%d %H:%M:%S UTC')${PLAIN}"
            return 0
        fi
        sleep 2
    done

    echo -e "${RED}[错误] 30 秒内未确认系统时间同步。为避免 SS2022 出现 bad timestamp，停止部署。${PLAIN}"
    echo -e "${YELLOW}请检查 NTP 网络连通性，随后执行：chronyc tracking${PLAIN}"
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
    if ! apt-get install -y curl jq openssl coreutils qrencode ca-certificates iproute2 tar; then
        echo -e "${RED}[错误] 依赖安装失败。${PLAIN}"
        return 1
    fi

    return 0
}

prepare_ipv4_env() {
    echo -e "${YELLOW}>> [1/3] 初始化 IPv4 / 双栈部署环境...${PLAIN}"

    # IPv4 模式不强制 IPv6，避免纯 IPv4 VPS 被错误配置。
    restore_ipv4_apt_and_dns_if_needed

    if ! install_dependencies; then
        return 1
    fi

    if ! ensure_time_sync; then
        return 1
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
    echo -e "${YELLOW}>> [1/4] 初始化 IPv6-only 部署环境...${PLAIN}"

    if ! ip -6 addr show scope global 2>/dev/null | grep -q 'inet6 '; then
        echo -e "${RED}[错误] 未检测到全局 IPv6 地址，无法使用 IPv6-only 模式。${PLAIN}"
        return 1
    fi

    sed -i '/github/d' /etc/hosts 2>/dev/null || true
    sed -i '/ghproxy/d' /etc/hosts 2>/dev/null || true
    sed -i '/danwin/d' /etc/hosts 2>/dev/null || true

    # 先使用 VPS 当前 DNS。只有 IPv6 DNS 解析确实失败时才接管普通 resolv.conf。
    if dns_ipv6_resolution_works; then
        echo -e "${GREEN}✔ 当前 DNS 可正常解析 IPv6 地址，不修改 /etc/resolv.conf。${PLAIN}"
    else
        echo -e "${YELLOW}[提示] 当前 DNS 无法完成 IPv6 解析，准备使用公共 IPv6 DNS 兜底。${PLAIN}"

        if [[ -f /etc/resolv.conf && ! -L /etc/resolv.conf ]]; then
            if [[ ! -f "$BACKUP_DNS" ]]; then
                if ! cp -a /etc/resolv.conf "$BACKUP_DNS"; then
                    echo -e "${RED}[错误] 无法备份 /etc/resolv.conf，停止 DNS 接管。${PLAIN}"
                    return 1
                fi
            fi

            if ! cat > /etc/resolv.conf <<'DNS'
nameserver 2001:4860:4860::8888
nameserver 2606:4700:4700::1111
options timeout:2 attempts:2
DNS
            then
                echo -e "${RED}[错误] IPv6 DNS 写入失败。${PLAIN}"
                return 1
            fi
            touch "$DNS_MARKER"

            if ! dns_ipv6_resolution_works; then
                echo -e "${RED}[错误] 切换公共 IPv6 DNS 后仍无法解析，正在恢复原 DNS。${PLAIN}"
                if [[ -f "$BACKUP_DNS" ]]; then
                    cp -f "$BACKUP_DNS" /etc/resolv.conf 2>/dev/null || true
                fi
                rm -f "$DNS_MARKER"
                return 1
            fi
            echo -e "${GREEN}✔ 公共 IPv6 DNS 已启用并验证通过。${PLAIN}"
        else
            echo -e "${RED}[错误] 当前 DNS 解析失败，且 /etc/resolv.conf 由系统服务管理。${PLAIN}"
            echo -e "${YELLOW}为避免破坏 systemd-resolved/NetworkManager，本脚本不会强制覆盖该符号链接。${PLAIN}"
            return 1
        fi
    fi

    mkdir -p /etc/apt/apt.conf.d/
    if ! printf '%s\n' 'Acquire::ForceIPv6 "true";' > "$FORCE_IPV6_CONF"; then
        echo -e "${RED}[错误] 无法写入 APT IPv6 配置。${PLAIN}"
        return 1
    fi

    # Debian 新式 mirrors 文件继续使用官方 Anycast CDN。
    if [[ -f /etc/apt/mirrors/debian.list ]]; then
        if ! printf '%s\n' 'https://deb.debian.org/debian' > /etc/apt/mirrors/debian.list; then
            echo -e "${RED}[错误] Debian 软件源配置失败。${PLAIN}"
            return 1
        fi
    fi
    if [[ -f /etc/apt/mirrors/debian-security.list ]]; then
        if ! printf '%s\n' 'https://deb.debian.org/debian-security' > /etc/apt/mirrors/debian-security.list; then
            echo -e "${RED}[错误] Debian Security 软件源配置失败。${PLAIN}"
            return 1
        fi
    fi

    if ! install_dependencies; then
        echo -e "${YELLOW}[提示] IPv6 环境初始化未完成，请检查 IPv6 路由、DNS 与 APT 源。${PLAIN}"
        return 1
    fi

    if ! ensure_time_sync; then
        echo -e "${YELLOW}[提示] 时间同步未完成。SS2022 对时钟偏差敏感，本次部署已停止。${PLAIN}"
        return 1
    fi

    return 0
}

ensure_singbox_user() {
    local nologin_shell=""

    if id -u "$SINGBOX_USER" >/dev/null 2>&1; then
        if ! getent group "$SINGBOX_GROUP" >/dev/null 2>&1; then
            if ! groupadd --system "$SINGBOX_GROUP"; then
                echo -e "${RED}[错误] 无法创建 sing-box 专用系统组。${PLAIN}"
                return 1
            fi
        fi
        if ! id -nG "$SINGBOX_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$SINGBOX_GROUP"; then
            if ! usermod -a -G "$SINGBOX_GROUP" "$SINGBOX_USER"; then
                echo -e "${RED}[错误] 无法将现有 sing-box 用户加入专用组。${PLAIN}"
                return 1
            fi
        fi
        return 0
    fi

    nologin_shell=$(command -v nologin 2>/dev/null || true)
    nologin_shell=${nologin_shell:-/usr/sbin/nologin}

    if ! useradd --system --user-group --no-create-home --home-dir /nonexistent --shell "$nologin_shell" "$SINGBOX_USER"; then
        echo -e "${RED}[错误] 无法创建 sing-box 专用系统用户。${PLAIN}"
        return 1
    fi

    touch "$SINGBOX_USER_MARKER"
    chmod 600 "$SINGBOX_USER_MARKER"
    return 0
}

write_singbox_service() {
    if ! ensure_singbox_user; then
        return 1
    fi

    if ! cat > "$SINGBOX_SERVICE" <<'SERVICE'
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
    then
        echo -e "${RED}[错误] sing-box systemd 服务文件写入失败。${PLAIN}"
        return 1
    fi

    if ! systemctl daemon-reload; then
        echo -e "${RED}[错误] systemctl daemon-reload 失败。${PLAIN}"
        return 1
    fi

    if ! systemctl enable sing-box >/dev/null 2>&1; then
        echo -e "${RED}[错误] sing-box 开机自启设置失败。${PLAIN}"
        return 1
    fi

    return 0
}

install_singbox_core() {
    local network_mode="$1"
    local arch
    local s_arch=""
    local expected_sha256=""
    local tar_file=""
    local target_url=""
    local curl_family=""
    local success=0
    local download_url=""
    local actual_sha256=""

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

    if [[ "$network_mode" == "ipv6" ]]; then
        curl_family="-6"
    else
        curl_family="-4"
    fi

    # 每次部署都重新下载并校验固定稳定版本，避免沿用未校验或版本不一致的旧核心。
    if [[ -x "$SINGBOX_BIN" ]]; then
        echo -e "${YELLOW}>> 已检测到现有 sing-box，将重新下载官方发布包并进行 SHA256 校验后覆盖。${PLAIN}"
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

    cd /tmp || {
        echo -e "${RED}[错误] 无法进入 /tmp。${PLAIN}"
        return 1
    }
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
            echo -e "${RED}   压缩包结构校验失败，尝试下一个源。${PLAIN}"
            rm -f "/tmp/${tar_file}"
            continue
        fi

        echo -e "${GREEN}✔ SHA256 与压缩包结构校验均通过。${PLAIN}"
        success=1
        break
    done

    if [[ $success -ne 1 ]]; then
        echo -e "${RED}[错误] 所有下载源均失败或未通过 SHA256 校验，已停止安装。${PLAIN}"
        return 1
    fi

    mkdir -p /tmp/sb-temp
    if ! tar -xzf "/tmp/${tar_file}" -C /tmp/sb-temp --strip-components=1; then
        echo -e "${RED}[错误] sing-box 解压失败。${PLAIN}"
        rm -rf /tmp/sb-temp "/tmp/${tar_file}"
        return 1
    fi

    if [[ ! -f /tmp/sb-temp/sing-box ]]; then
        echo -e "${RED}[错误] 压缩包中未找到 sing-box 二进制。${PLAIN}"
        rm -rf /tmp/sb-temp "/tmp/${tar_file}"
        return 1
    fi

    if ! install -m 755 /tmp/sb-temp/sing-box "$SINGBOX_BIN"; then
        echo -e "${RED}[错误] sing-box 安装到 ${SINGBOX_BIN} 失败。${PLAIN}"
        rm -rf /tmp/sb-temp "/tmp/${tar_file}"
        return 1
    fi

    rm -rf /tmp/sb-temp "/tmp/${tar_file}"

    if ! "$SINGBOX_BIN" version >/dev/null 2>&1; then
        echo -e "${RED}[错误] sing-box 安装后无法正常执行。${PLAIN}"
        rm -f "$SINGBOX_BIN"
        return 1
    fi

    if ! write_singbox_service; then
        return 1
    fi

    echo -e "${GREEN}✔ sing-box 核心与 systemd 服务注册完成。${PLAIN}"
    return 0
}

setup_keepalive() {
    echo -e "${YELLOW}>> [3/4] 部署 IPv6 HTTPS 链路保活定时器...${PLAIN}"

    if ! cat > /etc/systemd/system/ipv6-keepalive.service <<'KSERVICE'
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
    then
        echo -e "${RED}[错误] Keepalive service 写入失败。${PLAIN}"
        return 1
    fi

    if ! cat > /etc/systemd/system/ipv6-keepalive.timer <<'KTIMER'
[Unit]
Description=Run IPv6 Keepalive Every 5 Minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
Unit=ipv6-keepalive.service

[Install]
WantedBy=timers.target
KTIMER
    then
        echo -e "${RED}[错误] Keepalive timer 写入失败。${PLAIN}"
        return 1
    fi

    if ! systemctl daemon-reload; then
        echo -e "${RED}[错误] systemd 配置重载失败。${PLAIN}"
        return 1
    fi

    if ! systemctl enable --now ipv6-keepalive.timer >/dev/null 2>&1; then
        echo -e "${RED}[错误] Keepalive 定时器启用失败。${PLAIN}"
        return 1
    fi

    echo -e "${GREEN}✔ IPv6 Keepalive 定时器已激活。${PLAIN}"
    return 0
}

disable_keepalive_for_ipv4() {
    if systemctl is-enabled --quiet ipv6-keepalive.timer 2>/dev/null || \
       systemctl is-active --quiet ipv6-keepalive.timer 2>/dev/null; then
        if ! systemctl disable --now ipv6-keepalive.timer >/dev/null 2>&1; then
            echo -e "${YELLOW}[警告] IPv6 Keepalive 定时器未能自动停用，请稍后手动检查。${PLAIN}"
        fi
    fi
}

port_is_available_for_singbox() {
    local port="$1"
    local listeners=""
    local current_pid=""
    local conflicts=""

    listeners=$(ss -H -lntup 2>/dev/null | awk -v p="$port" '{ addr=$5; n=split(addr,a,":"); if (a[n] == p) print }')
    [[ -z "$listeners" ]] && return 0

    current_pid=$(systemctl show -p MainPID --value sing-box 2>/dev/null || true)
    if [[ "$current_pid" =~ ^[0-9]+$ ]] && [[ "$current_pid" -gt 0 ]]; then
        conflicts=$(printf '%s\n' "$listeners" | grep -v "pid=${current_pid}," || true)
        [[ -z "$conflicts" ]] && return 0
    else
        conflicts="$listeners"
    fi

    echo -e "${RED}[错误] 端口 ${port} 已被其他进程占用：${PLAIN}"
    printf '%s\n' "$conflicts"
    return 1
}

validate_ss2022_key() {
    local key="$1"
    local expected_bytes="$2"
    local tmp=""
    local decoded_bytes=""

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

get_ss_params() {
    while true; do
        read -rp "请输入监听端口 (1-65535) [默认: 58588]: " input_port
        PORT=${input_port:-58588}
        if [[ ! "$PORT" =~ ^[0-9]+$ ]] || [[ "$PORT" -lt 1 ]] || [[ "$PORT" -gt 65535 ]]; then
            echo -e "${RED}输入无效，请输入 1-65535 纯数字！${PLAIN}"
            continue
        fi

        if ! port_is_available_for_singbox "$PORT"; then
            echo -e "${YELLOW}请更换端口后重试。${PLAIN}"
            continue
        fi

        echo -e "已选端口: ${GREEN}${PORT}${PLAIN}"
        break
    done

    echo ""
    echo "请选择加密算法："
    echo "  1) 2022-blake3-aes-128-gcm (推荐，16 字节密钥，高吞吐低开销)"
    echo "  2) 2022-blake3-aes-256-gcm (32 字节密钥，高规格防护)"
    read -rp "请选择 [默认: 1]: " cipher_choice
    cipher_choice=${cipher_choice:-1}

    if [[ "$cipher_choice" == "2" ]]; then
        METHOD="2022-blake3-aes-256-gcm"
        KEY_BYTES=32
    else
        METHOD="2022-blake3-aes-128-gcm"
        KEY_BYTES=16
    fi

    echo -e "已选算法: ${GREEN}${METHOD}${PLAIN}"
    echo ""
    read -rp "是否自动生成合规随机密钥？[Y/n]: " auto_key
    auto_key=${auto_key:-Y}

    if [[ "$auto_key" =~ ^[Yy]$ ]]; then
        if ! SS_KEY=$(openssl rand -base64 "$KEY_BYTES"); then
            echo -e "${RED}[错误] 随机密钥生成失败。${PLAIN}"
            return 1
        fi
        echo -e "已生成密钥: ${GREEN}${SS_KEY}${PLAIN}"
    else
        while true; do
            read -rp "请输入自定义 ${KEY_BYTES} 字节 Base64 密钥: " SS_KEY
            if validate_ss2022_key "$SS_KEY" "$KEY_BYTES"; then
                echo -e "${GREEN}✔ 自定义密钥 Base64 格式及解码长度校验通过。${PLAIN}"
                break
            fi
            echo -e "${RED}[错误] 密钥必须是有效标准 Base64，且解码后正好为 ${KEY_BYTES} 字节。${PLAIN}"
        done
    fi

    return 0
}

write_and_start_ss() {
    local listen_addr="$1"
    local conf_dir="/etc/sing-box"
    local tmp_conf=""
    local backup_conf=""
    local had_old=0

    if ! ensure_singbox_user; then
        return 1
    fi

    if ! mkdir -p "$conf_dir"; then
        echo -e "${RED}[错误] 无法创建 ${conf_dir}。${PLAIN}"
        return 1
    fi
    chown root:"$SINGBOX_GROUP" "$conf_dir"
    chmod 750 "$conf_dir"

    tmp_conf=$(mktemp "${conf_dir}/config.json.tmp.XXXXXX") || {
        echo -e "${RED}[错误] 无法创建临时配置文件。${PLAIN}"
        return 1
    }

    # 临时配置在校验阶段仅 root 可读；正式切换后改为 root:sing-box 640。
    chmod 600 "$tmp_conf"

    if ! cat > "$tmp_conf" <<CONFIG
{
  "log": {
    "level": "warn"
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "${listen_addr}",
      "listen_port": ${PORT},
      "method": "${METHOD}",
      "password": "${SS_KEY}"
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
CONFIG
    then
        echo -e "${RED}[错误] sing-box 临时配置写入失败。${PLAIN}"
        rm -f "$tmp_conf"
        return 1
    fi

    echo -e "${YELLOW}>> 校验新 sing-box 配置...${PLAIN}"
    if ! "$SINGBOX_BIN" check -c "$tmp_conf"; then
        echo -e "${RED}[错误] 新配置未通过 sing-box check，原配置保持不变。${PLAIN}"
        rm -f "$tmp_conf"
        return 1
    fi

    if [[ -f "$SINGBOX_CONF" ]]; then
        had_old=1
        backup_conf=$(mktemp "${conf_dir}/config.json.rollback.XXXXXX") || {
            echo -e "${RED}[错误] 无法创建回滚配置。${PLAIN}"
            rm -f "$tmp_conf"
            return 1
        }
        if ! cp -a "$SINGBOX_CONF" "$backup_conf"; then
            echo -e "${RED}[错误] 原配置备份失败，停止更新。${PLAIN}"
            rm -f "$tmp_conf" "$backup_conf"
            return 1
        fi
        chown root:"$SINGBOX_GROUP" "$backup_conf"
        chmod 640 "$backup_conf"
    fi

    # 同目录 mv，确保配置替换为原子操作。
    if ! mv -f "$tmp_conf" "$SINGBOX_CONF"; then
        echo -e "${RED}[错误] 新配置切换失败。${PLAIN}"
        rm -f "$tmp_conf" "$backup_conf"
        return 1
    fi
    chown root:"$SINGBOX_GROUP" "$SINGBOX_CONF"
    chmod 640 "$SINGBOX_CONF"

    if ! systemctl restart sing-box; then
        echo -e "${RED}[错误] sing-box 使用新配置启动失败，正在自动回滚...${PLAIN}"

        if [[ $had_old -eq 1 && -f "$backup_conf" ]]; then
            if mv -f "$backup_conf" "$SINGBOX_CONF"; then
                chown root:"$SINGBOX_GROUP" "$SINGBOX_CONF"
                chmod 640 "$SINGBOX_CONF"
                if systemctl restart sing-box; then
                    echo -e "${YELLOW}✔ 已恢复原配置并重新启动服务。${PLAIN}"
                else
                    echo -e "${RED}[严重] 原配置已恢复，但 sing-box 仍无法启动，请查看日志。${PLAIN}"
                fi
            else
                echo -e "${RED}[严重] 自动回滚失败，请立即检查 ${SINGBOX_CONF}。${PLAIN}"
            fi
        else
            rm -f "$SINGBOX_CONF"
            systemctl stop sing-box >/dev/null 2>&1 || true
            echo -e "${YELLOW}已移除首次部署失败的新配置。${PLAIN}"
        fi

        return 1
    fi

    rm -f "$backup_conf"
    echo -e "${GREEN}✔ 新配置校验通过并已安全切换（root:${SINGBOX_GROUP} 640）。${PLAIN}"
    return 0
}

urlencode() {
    local value="$1"
    jq -nr --arg v "$value" '$v|@uri'
}

show_ss_details() {
    local host="$1"
    local port="$2"
    local method="$3"
    local pass="$4"
    local tag_type="$5"
    local tag="Proxy-${tag_type}-SS2022"
    local url_host="$host"
    local method_enc=""
    local pass_enc=""
    local tag_enc=""
    local ss_url=""

    if [[ "$host" == *:* ]]; then
        url_host="[${host}]"
    fi

    # SIP002 / SIP022: AEAD-2022 userinfo 禁止 Base64URL，method/password 必须 percent-encode。
    method_enc=$(urlencode "$method")
    pass_enc=$(urlencode "$pass")
    tag_enc=$(urlencode "$tag")
    ss_url="ss://${method_enc}:${pass_enc}@${url_host}:${port}#${tag_enc}"

    echo ""
    echo -e "${CYAN}═══════════════════════════ 节点配置明细 ═══════════════════════════${PLAIN}"
    echo -e "${YELLOW}【通用参数】${PLAIN}"
    echo -e "  • 协议类型: Shadowsocks (SS2022)"
    echo -e "  • 节点地址: ${CYAN}${host}${PLAIN}"
    echo -e "  • 服务端口: ${CYAN}${port}${PLAIN}"
    echo -e "  • 加密算法: ${CYAN}${method}${PLAIN}"
    echo -e "  • 连接密码: ${CYAN}${pass}${PLAIN}"
    echo -e "  • UDP 转发: 开启 (True)"
    echo ""

    echo -e "${YELLOW}【Surge 导出格式】${PLAIN}"
    echo -e "${GREEN}${tag} = ss, ${host}, ${port}, encrypt-method=${method}, password=\"${pass}\", udp-relay=true${PLAIN}"
    echo ""

    echo -e "${YELLOW}【Loon 导出格式】${PLAIN}"
    echo -e "${GREEN}${tag} = Shadowsocks, ${host}, ${port}, ${method}, \"${pass}\", udp=true${PLAIN}"
    echo ""

    echo -e "${YELLOW}【Clash / Mihomo 导出格式】${PLAIN}"
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

    echo -e "${YELLOW}【通用导入链接 (SIP002 / SS2022)】${PLAIN}"
    echo -e "${GREEN}${ss_url}${PLAIN}"
    echo ""

    echo -e "${YELLOW}【二维码 (手机扫码直连)】${PLAIN}"
    if command -v qrencode &>/dev/null; then
        qrencode -t ANSIUTF8 "$ss_url"
    else
        echo -e "${RED}未安装 qrencode。${PLAIN}"
    fi
    echo -e "${CYAN}═════════════════════════════════════════════════════════════════${PLAIN}"
}

get_public_ipv4() {
    local ip=""

    ip=$(curl -4fsS --connect-timeout 5 --max-time 10 https://api.ipify.org 2>/dev/null) || true
    if [[ -z "$ip" ]]; then
        ip=$(curl -4fsS --connect-timeout 5 --max-time 10 https://ip.sb 2>/dev/null) || true
    fi

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

menu_ss2022() {
    while true; do
        clear
        echo -e "${CYAN}═══════════════════ Shadowsocks 2022 部署管理 ═══════════════════${PLAIN}"
        echo "  1. 部署 IPv4 节点 (监听 0.0.0.0，支持 IPv4-only / 双栈 VPS)"
        echo "  2. 部署 IPv6-only 节点 (监听 ::，含 IPv6 链路保活)"
        echo "  0. 返回主菜单"
        echo -e "${CYAN}═════════════════════════════════════════════════════════════════${PLAIN}"
        read -rp "请选择模式 [0-2]: " ss_opt

        case "$ss_opt" in
            1)
                if ! prepare_ipv4_env; then
                    read -rp "按回车返回..."
                    continue
                fi
                disable_keepalive_for_ipv4

                if ! install_singbox_core "ipv4"; then
                    read -rp "按回车返回..."
                    continue
                fi

                if ! get_ss_params; then
                    read -rp "按回车返回..."
                    continue
                fi

                local ip=""
                local s_ip=""
                if ip=$(get_public_ipv4); then
                    read -rp "服务器地址/域名 [回车默认使用: ${ip}]: " s_ip
                    s_ip=${s_ip:-$ip}
                else
                    echo -e "${YELLOW}[提示] 自动获取公网 IPv4 失败，请手动输入服务器地址或域名。${PLAIN}"
                    while [[ -z "$s_ip" ]]; do
                        read -rp "服务器地址/域名: " s_ip
                    done
                fi

                if write_and_start_ss "0.0.0.0"; then
                    echo -e "${GREEN}IPv4 节点部署成功！${PLAIN}"
                    show_ss_details "$s_ip" "$PORT" "$METHOD" "$SS_KEY" "IPv4"
                else
                    echo -e "${RED}IPv4 节点部署失败，原配置已尽可能保留/恢复。${PLAIN}"
                    journalctl -u sing-box -n 20 --no-pager 2>/dev/null || true
                fi
                read -rp "按回车继续..."
                ;;
            2)
                local ip6=""
                local s_ip=""

                if ! ip6=$(get_global_ipv6); then
                    echo -e "${RED}[错误] 未检测到全局 IPv6 地址。${PLAIN}"
                    read -rp "按回车返回..."
                    continue
                fi

                if ! prepare_ipv6_env; then
                    read -rp "按回车返回..."
                    continue
                fi

                if ! install_singbox_core "ipv6"; then
                    read -rp "按回车返回..."
                    continue
                fi

                if ! setup_keepalive; then
                    read -rp "按回车返回..."
                    continue
                fi

                if ! get_ss_params; then
                    read -rp "按回车返回..."
                    continue
                fi

                read -rp "服务器 IPv6 地址 [回车默认使用: ${ip6}]: " s_ip
                s_ip=${s_ip:-$ip6}

                if write_and_start_ss "::"; then
                    echo -e "${GREEN}IPv6 节点部署成功！${PLAIN}"
                    show_ss_details "$s_ip" "$PORT" "$METHOD" "$SS_KEY" "IPv6"
                else
                    echo -e "${RED}IPv6 节点部署失败，原配置已尽可能保留/恢复。${PLAIN}"
                    journalctl -u sing-box -n 20 --no-pager 2>/dev/null || true
                fi
                read -rp "按回车继续..."
                ;;
            0)
                break
                ;;
            *)
                echo -e "${RED}输入无效！${PLAIN}"
                sleep 1
                ;;
        esac
    done
}

view_config() {
    if [[ ! -f "$SINGBOX_CONF" ]]; then
        echo -e "${RED}[提示] 未检测到配置文件 (${SINGBOX_CONF})，请先安装节点！${PLAIN}"
        return
    fi

    if ! command -v jq &>/dev/null; then
        echo -e "${RED}[错误] 未安装 jq，无法解析配置。${PLAIN}"
        return
    fi

    local method
    local port
    local pass
    local listen
    local current_ip=""
    local ip_type="Node"

    method=$(jq -r '.inbounds[0].method // empty' "$SINGBOX_CONF")
    port=$(jq -r '.inbounds[0].listen_port // empty' "$SINGBOX_CONF")
    pass=$(jq -r '.inbounds[0].password // empty' "$SINGBOX_CONF")
    listen=$(jq -r '.inbounds[0].listen // empty' "$SINGBOX_CONF")

    if [[ -z "$method" || -z "$port" || -z "$pass" ]]; then
        echo -e "${RED}[错误] 当前配置缺少 SS2022 必要参数。${PLAIN}"
        return
    fi

    if [[ "$listen" == "::" ]]; then
        if ! current_ip=$(get_global_ipv6); then
            current_ip="未检测到IPv6"
        fi
        ip_type="IPv6"
    else
        if ! current_ip=$(get_public_ipv4); then
            current_ip="未检测到IPv4"
        fi
        ip_type="IPv4"
    fi

    show_ss_details "$current_ip" "$port" "$method" "$pass" "$ip_type"
}

service_action() {
    local action="$1"
    local success_text="$2"
    local fail_text="$3"

    if systemctl "$action" sing-box; then
        echo -e "${GREEN}${success_text}${PLAIN}"
        return 0
    fi

    echo -e "${RED}${fail_text}${PLAIN}"
    journalctl -u sing-box -n 20 --no-pager 2>/dev/null || true
    return 1
}

service_management() {
    while true; do
        clear
        echo -e "${CYAN}════════════════════════════ 服务运维管理 ════════════════════════════${PLAIN}"
        echo "  1. 查看实时连接日志 (按 Ctrl+C 退出)"
        echo "  2. 重启 sing-box 代理服务"
        echo "  3. 停止 sing-box 代理服务"
        echo "  4. 启动 sing-box 代理服务"
        echo "  5. 查看 Keepalive 保活定时器状态"
        echo "  6. 彻底卸载核心、保活与所有配置"
        echo "  0. 返回主菜单"
        echo -e "${CYAN}═════════════════════════════════════════════════════════════════${PLAIN}"
        read -rp "请输入选项 [0-6]: " s_choice

        case "$s_choice" in
            1)
                echo -e "${YELLOW}正在输出实时日志 (按 Ctrl+C 退出)...${PLAIN}"
                journalctl -u sing-box -f -n 20
                ;;
            2)
                service_action restart "服务已重启！" "服务重启失败！"
                sleep 1
                ;;
            3)
                service_action stop "服务已停止！" "服务停止失败！"
                sleep 1
                ;;
            4)
                service_action start "服务已启动！" "服务启动失败！"
                sleep 1
                ;;
            5)
                echo ""
                if ! systemctl list-timers --all | grep -E 'keepalive|NEXT'; then
                    echo -e "${YELLOW}未检测到 Keepalive 定时器。${PLAIN}"
                fi
                echo ""
                read -rp "按回车返回..."
                ;;
            6)
                systemctl stop sing-box ipv6-keepalive.timer 2>/dev/null || true
                systemctl disable sing-box ipv6-keepalive.timer 2>/dev/null || true

                rm -rf /etc/sing-box \
                    /usr/local/bin/ss2022 \
                    /usr/local/bin/proxy \
                    "$SINGBOX_BIN" \
                    "$SINGBOX_SERVICE" \
                    /etc/systemd/system/ipv6-keepalive.service \
                    /etc/systemd/system/ipv6-keepalive.timer

                # 清理由本版本创建的 IPv6 APT/DNS 设置。
                rm -f "$FORCE_IPV6_CONF"
                if [[ -f "$DNS_MARKER" && -f "$BACKUP_DNS" && ! -L /etc/resolv.conf ]]; then
                    cp -f "$BACKUP_DNS" /etc/resolv.conf 2>/dev/null || true
                    rm -f "$DNS_MARKER"
                fi

                if [[ -f "$SINGBOX_USER_MARKER" ]]; then
                    userdel "$SINGBOX_USER" >/dev/null 2>&1 || true
                    rm -f "$SINGBOX_USER_MARKER"
                fi

                if ! systemctl daemon-reload; then
                    echo -e "${YELLOW}[警告] systemd daemon-reload 失败，请手动执行。${PLAIN}"
                fi
                echo -e "${GREEN}核心、保活任务、专用账户及配置已彻底清理！${PLAIN}"
                exit 0
                ;;
            0)
                break
                ;;
            *)
                echo -e "${RED}输入无效！${PLAIN}"
                sleep 1
                ;;
        esac
    done
}

main() {
    check_root

    while true; do
        show_dashboard
        echo "  1. 部署 / 管理 Shadowsocks 2022 (IPv4 / IPv6-only)"
        echo "  2. 查看当前节点参数与客户端配置 (Surge / Loon / Clash / 二维码)"
        echo "  3. 服务运维管理 (查看实时日志 / 重启 / Keepalive 状态 / 卸载)"
        echo "  0. 退出管理面板"
        echo -e "${CYAN}═════════════════════════════════════════════════════════════════${PLAIN}"
        read -rp "请输入选项编号 [0-3]: " choice

        case "$choice" in
            1)
                menu_ss2022
                ;;
            2)
                view_config
                read -rp "按回车键返回主菜单..."
                ;;
            3)
                service_management
                ;;
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
