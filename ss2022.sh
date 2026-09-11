#!/bin/bash
# ==============================================================================
# 项目名称: VPS Bootstrap & SS2022 多协议代理管理脚本
# 快捷命令: ss2022 / proxy
# 当前版本: v1.8.0-dev2
#
# v1.8.0-dev2:
#   - 新增 Realm L4 端口转发：单端口 / 端口段、TCP / UDP / TCP+UDP、IPv4 / IPv6 / 双栈
#   - Realm 使用独立命名空间：ss2022-realm.service / /usr/local/lib/ss2022/realm / /etc/ss2022-realm
#   - 转发规则统一保存于 /etc/ss2022/forwarding.json，支持查看 / 修改 / 删除 / 测试
#   - 固定 Realm v2.9.6，并使用 GitHub 官方 Release asset digest 做 SHA256 校验
#   - 不引入 MPTCP、TLS/WS/WSS 隧道、负载均衡、故障转移、流量统计等平台化能力
#
# v1.8.0-dev1:
#   - 新增 VPS 服务端分流：全局默认出口 + 按服务规则覆盖 + IPv4/IPv6 指定
#   - 新增 Cloudflare 官方 WARP Local Proxy 出口（MASQUE / SOCKS5）
#   - 新增 SS2022 / SOCKS5 落地节点，支持多个落地节点与单独测试
#   - 内置 OpenAI、Netflix、YouTube、Google、Telegram、MyTVSuper、Apple TV+、TikTok 规则
#   - SS2022 / SS2022+ShadowTLS / VLESS Reality 参与服务端分流；Snell v5 保持官方 snell-server，由 Surge Rules 分流
#   - 分流状态统一保存于 /etc/ss2022/routing.json，并分别生成 sing-box / Xray 路由配置
#
# v1.7.0:
#   - 修复 Xray 临时配置文件无法自动识别 JSON 格式：校验时显式使用 -format json
#   - Xray 组件全面命名空间隔离：ss2022-xray.service / /usr/local/lib/ss2022/xray / /etc/ss2022-xray/config.json
#   - 不再覆盖或管理服务器已有的 /usr/local/bin/xray、xray.service、/usr/local/etc/xray/config.json
#   - VLESS Reality 仍固定使用 Xray-core v26.3.27 + SHA256 校验
#
# v1.7.0-dev8:
#   - VLESS Reality 服务端由 sing-box 改为 Xray-core v26.3.27（官方稳定版）
#   - 规避 sing-box Reality 客户端/服务端互联的已知 verification failed / processed invalid connection 问题
#   - Xray 固定版本 + SHA256 校验，amd64/arm64
#   - 旧 sing-box VLESS 可识别并删除；为保证回滚清晰，不做隐式跨核心迁移
#   - SS2022 / SS2022+ShadowTLS 继续使用 sing-box；Snell v5 保持不变
#
# v1.7.0-dev7:
#   - 修复 VLESS Reality 服务端 TLS 缺少 server_name 的问题
#   - tls.server_name 与 reality.handshake.server 始终保持一致
#   - 避免客户端 SNI 与服务端 Reality 接受的 ServerName 不一致导致 processed invalid connection
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
#   这是 v1.8.0 分流功能开发版。建议先在测试 VPS 验证，不要直接覆盖 v1.7.0 Release。
# ==============================================================================

SCRIPT_VERSION="v1.8.0-dev3"
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

# ----------------------------- Xray (VLESS Reality) ---------------------------
XRAY_VERSION="26.3.27"
XRAY_BIN="/usr/local/lib/ss2022/xray"
XRAY_CONF="/etc/ss2022-xray/config.json"
XRAY_SERVICE_NAME="ss2022-xray"
XRAY_SERVICE="/etc/systemd/system/${XRAY_SERVICE_NAME}.service"
XRAY_USER="ss2022-xray"
XRAY_GROUP="ss2022-xray"
XRAY_USER_MARKER="/etc/ss2022-xray-user-managed"
XRAY_SHA256_AMD64="23cd9af937744d97776ee35ecad4972cf4b2109d1e0fe6be9930467608f7c8ae"
XRAY_SHA256_ARM64="4d30283ae614e3057f730f67cd088a42be6fdf91f8639d82cb69e48cde80413c"

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

# ----------------------------- Realm L4 端口转发 -------------------------------
# 固定官方稳定版本；下载后使用 GitHub Release API 返回的 asset digest 进行 SHA256 校验。
REALM_VERSION="2.9.6"
REALM_BIN="/usr/local/lib/ss2022/realm"
REALM_CONF="/etc/ss2022-realm/config.json"
REALM_SERVICE_NAME="ss2022-realm"
REALM_SERVICE="/etc/systemd/system/${REALM_SERVICE_NAME}.service"
REALM_USER="ss2022-realm"
REALM_GROUP="ss2022-realm"
REALM_USER_MARKER="/etc/ss2022-realm-user-managed"
FORWARDING_FILE="/etc/ss2022/forwarding.json"
REALM_MAX_RANGE_PORTS=1000

# ----------------------------- 网络环境 ----------------------------------------
BACKUP_DNS="/root/resolv.conf.orig"
DNS_MARKER="/etc/ss2022-ipv6-dns-managed"
FORCE_IPV6_CONF="/etc/apt/apt.conf.d/99force-ipv6"
STATE_DIR="/etc/ss2022"
STATE_FILE="${STATE_DIR}/state.json"
ROUTING_FILE="${STATE_DIR}/routing.json"
WARP_DEFAULT_PORT=40000
WARP_MANAGED_MARKER="${STATE_DIR}/warp-package-managed"

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

get_xray_version() {
    if [[ -x "$XRAY_BIN" ]]; then
        local xv
        xv=$("$XRAY_BIN" version 2>/dev/null | head -n 1 | awk '{print $2}')
        echo "Xray ${xv:-已安装}"
    else
        echo "Xray 未安装"
    fi
}

xray_vless_exists() {
    [[ -f "$XRAY_CONF" ]] || return 1
    jq -e '.inbounds[]? | select(.protocol=="vless" and (.tag // "") == "vless-reality-in")' "$XRAY_CONF" >/dev/null 2>&1
}

get_xray_vless_port() {
    [[ -f "$XRAY_CONF" ]] || return 1
    jq -r '.inbounds[]? | select(.protocol=="vless" and (.tag // "") == "vless-reality-in") | .port // empty' "$XRAY_CONF" 2>/dev/null | head -n1
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
    local sys_info singbox_info xray_info snell_info time_sync_status realm_info realm_status forwarding_count=0
    local sb_status="${YELLOW}○ 未安装${PLAIN}"
    local xray_status="${YELLOW}○ 未安装${PLAIN}"
    local snell_status="${YELLOW}○ 未安装${PLAIN}"
    local keepalive_status="${YELLOW}○ 未配置${PLAIN}"
    realm_info="Realm 未安装"
    realm_status="${YELLOW}○ 未安装${PLAIN}"
    local proto_list="" installed_count=0
    local p=""

    sys_info=$(get_sys_info)
    singbox_info=$(get_singbox_version)
    xray_info=$(get_xray_version)
    snell_info=$(get_snell_version)
    time_sync_status=$(get_time_sync_status)

    if [[ -x "$REALM_BIN" ]]; then
        realm_info=$("$REALM_BIN" --version 2>/dev/null | head -n1)
        realm_info=${realm_info:-"Realm 已安装"}
        if systemctl is-active --quiet "$REALM_SERVICE_NAME" 2>/dev/null; then
            realm_status="${GREEN}● 运行中${PLAIN}"
        else
            realm_status="${RED}○ 已停止${PLAIN}"
        fi
    fi
    if [[ -f "$FORWARDING_FILE" ]]; then
        forwarding_count=$(jq '.rules|length' "$FORWARDING_FILE" 2>/dev/null || echo 0)
    fi

    if systemctl is-active --quiet sing-box 2>/dev/null; then
        sb_status="${GREEN}● 运行中${PLAIN}"
    elif [[ -f "$SINGBOX_CONF" || -x "$SINGBOX_BIN" ]]; then
        sb_status="${RED}○ 已停止${PLAIN}"
    fi

    if systemctl is-active --quiet "$XRAY_SERVICE_NAME" 2>/dev/null; then
        xray_status="${GREEN}● 运行中${PLAIN}"
    elif [[ -f "$XRAY_CONF" || -x "$XRAY_BIN" ]]; then
        xray_status="${RED}○ 已停止${PLAIN}"
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

    if xray_vless_exists; then
        p=$(get_xray_vless_port)
        ((installed_count++))
        proto_list+="\n    • VLESS Reality (Xray) - 端口: ${CYAN}${p}${PLAIN}"
    elif json_has_inbound_tag "$TAG_VLESS"; then
        p=$(get_inbound_port "$TAG_VLESS")
        ((installed_count++))
        proto_list+="\n    • VLESS Reality (旧 sing-box，待迁移) - 端口: ${YELLOW}${p}${PLAIN}"
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
    echo -e "  Xray核心: ${xray_info} / ${xray_status}"
    echo -e "  Snell核心: ${snell_info} / ${snell_status}"
    echo -e "  Realm转发: ${realm_info} / ${realm_status} / 规则 ${forwarding_count} 条"
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
            apply_routing_config >/dev/null 2>&1 || echo -e "${YELLOW}[提示] 节点已更新，但现有分流配置未能自动应用。${PLAIN}"
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
            apply_routing_config >/dev/null 2>&1 || echo -e "${YELLOW}[提示] 节点已更新，但现有分流配置未能自动应用。${PLAIN}"
            echo -e "${GREEN}✔ SS2022 + ShadowTLS v3 更新成功。${PLAIN}"
        else
            journalctl -u sing-box -n 30 --no-pager 2>/dev/null || true
        fi
        pause
    done
}

update_vless_reality() {
    local choice="" confirm="" current_port uuid current_sni private short_id current_listen current_host current_network public
    local new_port new_uuid new_sni new_private new_short_id new_listen new_network new_public out
    local REALITY_PRIVATE_KEY="" REALITY_PUBLIC_KEY=""
    if ! xray_vless_exists; then
        if json_has_inbound_tag "$TAG_VLESS"; then
            echo -e "${YELLOW}[旧 sing-box VLESS] dev8 不做隐式跨核心更新。请先删除旧 VLESS，再部署 Xray 版。${PLAIN}"
        else
            echo -e "${YELLOW}未部署 VLESS Reality，请先选择“部署”。${PLAIN}"
        fi
        pause; return
    fi
    while true; do
        current_port=$(get_xray_vless_port)
        uuid=$(jq -r '.inbounds[] | select(.tag=="vless-reality-in") | .settings.clients[0].id' "$XRAY_CONF")
        current_sni=$(jq -r '.inbounds[] | select(.tag=="vless-reality-in") | .streamSettings.realitySettings.serverNames[0]' "$XRAY_CONF")
        private=$(jq -r '.inbounds[] | select(.tag=="vless-reality-in") | .streamSettings.realitySettings.privateKey' "$XRAY_CONF")
        short_id=$(jq -r '.inbounds[] | select(.tag=="vless-reality-in") | .streamSettings.realitySettings.shortIds[0]' "$XRAY_CONF")
        current_listen=$(jq -r '.inbounds[] | select(.tag=="vless-reality-in") | .listen' "$XRAY_CONF")
        current_host=$(get_mode_state_field "vless" "host" 2>/dev/null || true)
        current_network=$(get_mode_state_field "vless" "network" 2>/dev/null || true)
        public=$(get_mode_state_field "vless" "public_key" 2>/dev/null || true)
        [[ -n "$current_network" ]] || current_network=$(infer_network_from_listen "$current_listen")
        if [[ -z "$public" && -n "$private" ]]; then
            out=$("$XRAY_BIN" x25519 -i "$private" 2>/dev/null || true)
            public=$(printf '%s
' "$out" | awk -F': *' '/^Password \(PublicKey\):/ {print $2; exit}')
            [[ -n "$public" ]] || public=$(printf '%s
' "$out" | awk -F': *' '/^Public key:/ {print $2; exit}')
        fi
        clear
        echo -e "${CYAN}════════════════ VLESS Reality (Xray) 更新 ════════════════${PLAIN}"
        echo -e "当前网络模式 : ${GREEN}${current_network}${PLAIN}"
        echo -e "当前监听端口 : ${GREEN}${current_port}${PLAIN}"
        echo -e "当前 Reality SNI: ${GREEN}${current_sni}${PLAIN}"
        echo -e "当前服务器地址: ${GREEN}${current_host:-未保存}${PLAIN}"
        echo -e "当前 UUID     : ${GREEN}${uuid}${PLAIN}"
        echo "  1. 修改网络模式"
        echo "  2. 修改监听端口"
        echo "  3. 修改 Reality SNI / target"
        echo "  4. 修改服务器地址/域名"
        echo "  5. 重新生成 UUID / Reality Key / Short ID"
        echo "  6. 查看当前节点配置"
        echo "  0. 返回"
        read -rp "请选择 [0-6]: " choice
        new_port="$current_port"; new_uuid="$uuid"; new_sni="$current_sni"; new_private="$private"; new_short_id="$short_id"; new_listen="$current_listen"; new_network="$current_network"; new_public="$public"
        case "$choice" in
            1) select_network_mode_for_update "$current_network" || continue; new_listen="$LISTEN_ADDR"; new_network="$NETWORK_MODE" ;;
            2) ask_xray_port "请输入 VLESS Reality 监听端口" "$current_port" "$current_port" || continue; new_port="$PORT" ;;
            3)
                echo "当前 Reality SNI: ${current_sni}"
                echo "  1. 保持当前 SNI"
                echo "  2. swdist.apple.com"
                echo "  3. www.icloud.com"
                echo "  4. speed.cloudflare.com"
                echo "  5. 自定义域名"
                read -rp "请选择 [1-5，默认 1]: " choice
                case "${choice:-1}" in
                    1) new_sni="$current_sni" ;; 2) new_sni="swdist.apple.com" ;; 3) new_sni="www.icloud.com" ;; 4) new_sni="speed.cloudflare.com" ;; 5) new_sni=""; while [[ -z "$new_sni" ]]; do read -rp "请输入 Reality 握手/SNI 域名: " new_sni; done ;; *) continue ;; esac
                ;;
            4) ask_server_host_with_default "$current_host"; save_mode_state "vless" "$(jq -n --arg host "$SERVER_HOST" --arg network "$current_network" --arg public_key "$public" '{host:$host,network:$network,public_key:$public_key,core:"xray"}')" || true; echo -e "${GREEN}✔ 服务器地址已更新。${PLAIN}"; pause; continue ;;
            5)
                echo -e "${YELLOW}[警告] 此操作会生成全新的 VLESS 节点身份，所有客户端参数都必须重新导入。${PLAIN}"
                read -rp "确认重新生成？[y/N]: " confirm; [[ "$confirm" =~ ^[Yy]$ ]] || continue
                generate_xray_reality_keypair || { echo -e "${RED}[错误] Xray Reality 密钥对生成失败。${PLAIN}"; pause; continue; }
                new_private="$REALITY_PRIVATE_KEY"; new_public="$REALITY_PUBLIC_KEY"; new_uuid=$("$XRAY_BIN" uuid 2>/dev/null | head -n1); new_short_id=$(openssl rand -hex 8) || continue
                ;;
            6) view_vless_config; pause; continue ;;
            0) return ;;
            *) continue ;;
        esac
        if write_xray_vless_config "$new_listen" "$new_port" "$new_uuid" "$new_sni" "$new_private" "$new_short_id"; then
            save_mode_state "vless" "$(jq -n --arg host "$current_host" --arg network "$new_network" --arg public_key "$new_public" '{host:$host,network:$network,public_key:$public_key,core:"xray"}')" || true
            apply_routing_config >/dev/null 2>&1 || echo -e "${YELLOW}[提示] VLESS 已更新，但现有分流配置未能自动应用。${PLAIN}"
            echo -e "${GREEN}✔ VLESS Reality (Xray) 更新成功。${PLAIN}"
        else journalctl -u "$XRAY_SERVICE_NAME" -n 30 --no-pager 2>/dev/null || true; fi
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
    local has_xray=0 has_legacy=0 yes=""
    xray_vless_exists && has_xray=1
    json_has_inbound_tag "$TAG_VLESS" && has_legacy=1
    if [[ $has_xray -eq 0 && $has_legacy -eq 0 ]]; then echo -e "${YELLOW}未部署 VLESS Reality。${PLAIN}"; pause; return; fi
    read -rp "确认删除 VLESS Reality（含旧 sing-box / 新 Xray 配置）？[y/N]: " yes
    if [[ "$yes" =~ ^[Yy]$ ]]; then
        if [[ $has_xray -eq 1 ]]; then systemctl disable --now "$XRAY_SERVICE_NAME" >/dev/null 2>&1 || true; rm -f "$XRAY_CONF"; fi
        if [[ $has_legacy -eq 1 ]]; then remove_singbox_mode vless || true; fi
        remove_mode_state "vless" || true
        echo -e "${GREEN}✔ VLESS Reality 已删除；Xray 二进制保留供后续部署。${PLAIN}"
    fi
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
        apply_routing_config >/dev/null 2>&1 || echo -e "${YELLOW}[提示] 节点已部署，但现有分流配置未能自动应用，请进入“分流管理”重新应用。${PLAIN}"
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
        apply_routing_config >/dev/null 2>&1 || echo -e "${YELLOW}[提示] 节点已部署，但现有分流配置未能自动应用，请进入“分流管理”重新应用。${PLAIN}"
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
    local vless_port uuid sni short_id reality_sni_choice
    local REALITY_PRIVATE_KEY="" REALITY_PUBLIC_KEY=""
    if xray_vless_exists; then
        echo -e "${YELLOW}VLESS Reality (Xray) 已存在。请返回并选择“更新”或“删除”。${PLAIN}"; pause; return
    fi
    if json_has_inbound_tag "$TAG_VLESS"; then
        echo -e "${YELLOW}[检测到旧配置] 当前 VLESS Reality 仍由 sing-box 承载。${PLAIN}"
        echo -e "${YELLOW}dev8 起 VLESS 改用 Xray；dev9 起使用独立 ss2022-xray 服务。为避免端口冲突和隐式迁移，请先：VLESS Reality → 删除，再重新部署。${PLAIN}"
        pause; return
    fi
    select_network_mode || return
    if [[ -x /usr/local/bin/xray ]] || systemctl cat xray.service >/dev/null 2>&1 || [[ -f /usr/local/etc/xray/config.json ]]; then
        echo -e "${YELLOW}[提示] 检测到服务器已有 Xray。dev9 使用独立 ss2022-xray 服务、二进制和配置，不会覆盖或重启现有 xray.service。${PLAIN}"
    fi
    install_xray_core || { pause; return; }
    ask_xray_port "请输入 VLESS Reality 监听端口" "443" || return
    vless_port="$PORT"
    generate_xray_reality_keypair || { echo -e "${RED}[错误] Xray Reality 密钥对生成失败。${PLAIN}"; pause; return; }
    uuid=$("$XRAY_BIN" uuid 2>/dev/null | head -n1)
    [[ -n "$uuid" ]] || uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || true)
    [[ -n "$uuid" ]] || { echo -e "${RED}[错误] UUID 生成失败。${PLAIN}"; pause; return; }
    short_id=$(openssl rand -hex 8) || { echo -e "${RED}[错误] Short ID 生成失败。${PLAIN}"; pause; return; }
    echo "请选择 Reality 握手/SNI："
    echo "  1. swdist.apple.com（本轮兼容性测试）"
    echo "  2. www.icloud.com（本轮兼容性测试）"
    echo "  3. speed.cloudflare.com（更适合作为长期默认候选）"
    echo "  4. 自定义域名"
    read -rp "请选择 [1-4，默认 1]: " reality_sni_choice
    case "${reality_sni_choice:-1}" in
        1) sni="swdist.apple.com" ;;
        2) sni="www.icloud.com" ;;
        3) sni="speed.cloudflare.com" ;;
        4) while [[ -z "$sni" ]]; do read -rp "请输入 Reality 握手/SNI 域名: " sni; done ;;
        *) sni="swdist.apple.com" ;;
    esac
    ask_server_host
    if write_xray_vless_config "$LISTEN_ADDR" "$vless_port" "$uuid" "$sni" "$REALITY_PRIVATE_KEY" "$short_id"; then
        save_mode_state "vless" "$(jq -n --arg host "$SERVER_HOST" --arg network "$NETWORK_MODE" --arg public_key "$REALITY_PUBLIC_KEY" '{host:$host,network:$network,public_key:$public_key,core:"xray"}')" || true
        apply_routing_config >/dev/null 2>&1 || echo -e "${YELLOW}[提示] VLESS 已部署，但现有分流配置未能自动应用。${PLAIN}"
        echo -e "${GREEN}✔ VLESS Reality (Xray) 部署成功。${PLAIN}"
        show_vless_details "$SERVER_HOST" "$vless_port" "$uuid" "$sni" "$REALITY_PUBLIC_KEY" "$short_id"
    else
        journalctl -u "$XRAY_SERVICE_NAME" -n 30 --no-pager 2>/dev/null || true
    fi
    pause
}

ensure_xray_user() {
    local nologin_shell=""
    if id -u "$XRAY_USER" >/dev/null 2>&1; then
        if ! getent group "$XRAY_GROUP" >/dev/null 2>&1; then
            groupadd --system "$XRAY_GROUP" || return 1
        fi
        if ! id -nG "$XRAY_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$XRAY_GROUP"; then
            usermod -a -G "$XRAY_GROUP" "$XRAY_USER" || return 1
        fi
        return 0
    fi
    nologin_shell=$(command -v nologin 2>/dev/null || true)
    nologin_shell=${nologin_shell:-/usr/sbin/nologin}
    useradd --system --user-group --no-create-home --home-dir /nonexistent --shell "$nologin_shell" "$XRAY_USER" || return 1
    touch "$XRAY_USER_MARKER"
    chmod 600 "$XRAY_USER_MARKER"
    return 0
}

write_xray_service() {
    ensure_xray_user || return 1
    cat > "$XRAY_SERVICE" <<'SERVICE'
[Unit]
Description=ss2022.sh managed Xray VLESS Reality service
Documentation=https://github.com/XTLS/Xray-core
After=network.target nss-lookup.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ss2022-xray
Group=ss2022-xray
ExecStart=/usr/local/lib/ss2022/xray run -format json -config /etc/ss2022-xray/config.json
Restart=on-failure
RestartSec=10s
LimitNOFILE=1048576
UMask=0077
NoNewPrivileges=true
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
PrivateTmp=true
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
    systemctl enable "$XRAY_SERVICE_NAME" >/dev/null 2>&1 || return 1
}

install_xray_core() {
    local arch asset sha curl_family tmp zip url actual
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) asset="Xray-linux-64.zip"; sha="$XRAY_SHA256_AMD64" ;;
        aarch64|arm64) asset="Xray-linux-arm64-v8a.zip"; sha="$XRAY_SHA256_ARM64" ;;
        *) echo -e "${RED}[错误] Xray 暂不支持当前 CPU 架构: ${arch}${PLAIN}"; return 1 ;;
    esac
    [[ "$NETWORK_MODE" == "ipv6" ]] && curl_family="-6" || curl_family="-4"
    tmp=$(mktemp -d /tmp/xray-install.XXXXXX) || return 1
    zip="$tmp/$asset"
    url="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/${asset}"
    echo -e "${YELLOW}>> 下载 Xray-core ${XRAY_VERSION} 官方稳定版并校验 SHA256...${PLAIN}"
    if ! curl $curl_family -fL --retry 3 --connect-timeout 15 --max-time 300 -o "$zip" "$url"; then
        rm -rf "$tmp"; echo -e "${RED}[错误] Xray 下载失败。${PLAIN}"; return 1
    fi
    actual=$(sha256sum "$zip" | awk '{print $1}')
    if [[ "$actual" != "$sha" ]]; then
        rm -rf "$tmp"; echo -e "${RED}[错误] Xray SHA256 校验失败。${PLAIN}"; return 1
    fi
    unzip -q "$zip" xray -d "$tmp/unpack" || { rm -rf "$tmp"; return 1; }
    install -d -m 755 "$(dirname "$XRAY_BIN")" || { rm -rf "$tmp"; return 1; }
    install -m 755 "$tmp/unpack/xray" "$XRAY_BIN" || { rm -rf "$tmp"; return 1; }
    rm -rf "$tmp"
    "$XRAY_BIN" version >/dev/null 2>&1 || return 1
    write_xray_service || return 1
    echo -e "${GREEN}✔ Xray-core ${XRAY_VERSION} 已安装并通过固定 SHA256 校验。${PLAIN}"
}

generate_xray_reality_keypair() {
    local out private public
    out=$("$XRAY_BIN" x25519 2>/dev/null) || return 1
    private=$(printf '%s\n' "$out" | awk -F': *' '/^PrivateKey:/ {print $2; exit}')
    public=$(printf '%s\n' "$out" | awk -F': *' '/^Password \(PublicKey\):/ {print $2; exit}')
    # 兼容旧版 Xray 输出
    [[ -n "$private" ]] || private=$(printf '%s\n' "$out" | awk -F': *' '/^Private key:/ {print $2; exit}')
    [[ -n "$public" ]] || public=$(printf '%s\n' "$out" | awk -F': *' '/^Public key:/ {print $2; exit}')
    [[ -n "$public" ]] || public=$(printf '%s\n' "$out" | awk -F': *' '/^Password:/ {print $2; exit}')
    [[ -n "$private" && -n "$public" ]] || return 1
    REALITY_PRIVATE_KEY="$private"
    REALITY_PUBLIC_KEY="$public"
}

xray_port_conflict_configured() {
    local port="$1" exclude_current="${2:-no}"
    if [[ "$exclude_current" != "yes" ]] && xray_vless_exists && [[ "$(get_xray_vless_port)" == "$port" ]]; then
        return 0
    fi
    if singbox_config_port_conflict "$port" '[]'; then return 0; fi
    if [[ -f "$SNELL_CONF" ]] && [[ "$(snell_port_from_config 2>/dev/null || true)" == "$port" ]]; then return 0; fi
    return 1
}

ask_xray_port() {
    local prompt="$1" default="$2" current_port="${3:-}" input pid
    while true; do
        read -rp "${prompt} [默认: ${default}]: " input
        input=${input:-$default}
        validate_port_number "$input" || { echo -e "${RED}输入无效，请输入 1-65535。${PLAIN}"; continue; }
        if [[ -n "$current_port" && "$input" == "$current_port" ]]; then PORT="$input"; return 0; fi
        if xray_port_conflict_configured "$input" no; then
            echo -e "${RED}[错误] 端口 ${input} 已被现有代理配置占用。${PLAIN}"; continue
        fi
        pid=$(systemctl show -p MainPID --value "$XRAY_SERVICE_NAME" 2>/dev/null || true)
        if port_in_use_by_other_process "$input" "$pid" >/tmp/ss2022-port-conflict.$$ 2>/dev/null; then
            echo -e "${RED}[错误] 端口 ${input} 已被其他进程占用：${PLAIN}"; cat /tmp/ss2022-port-conflict.$$; rm -f /tmp/ss2022-port-conflict.$$; continue
        fi
        rm -f /tmp/ss2022-port-conflict.$$ 2>/dev/null || true
        PORT="$input"; return 0
    done
}

write_xray_vless_config() {
    local listen="$1" port="$2" uuid="$3" sni="$4" private="$5" short_id="$6" candidate backup="" had_old=0
    local conf_dir
    conf_dir=$(dirname "$XRAY_CONF")
    mkdir -p "$conf_dir" || return 1
    chown root:"$XRAY_GROUP" "$conf_dir" 2>/dev/null || true
    chmod 750 "$conf_dir"
    candidate=$(mktemp "${conf_dir}/config.tmp.XXXXXX.json") || return 1
    jq -n --arg listen "$listen" --argjson port "$port" --arg uuid "$uuid" --arg sni "$sni" --arg private "$private" --arg sid "$short_id" '{
      log:{loglevel:"warning"},
      inbounds:[{
        listen:$listen, port:$port, protocol:"vless", tag:"vless-reality-in",
        settings:{clients:[{id:$uuid,flow:"xtls-rprx-vision"}],decryption:"none"},
        streamSettings:{network:"tcp",security:"reality",realitySettings:{show:false,dest:($sni+":443"),xver:0,serverNames:[$sni],privateKey:$private,shortIds:[$sid]}}
      }],
      outbounds:[{protocol:"freedom",tag:"direct"}]
    }' > "$candidate" || { rm -f "$candidate"; return 1; }
    chown root:"$XRAY_GROUP" "$candidate" 2>/dev/null || true
    chmod 640 "$candidate"
    echo -e "${YELLOW}>> 校验新 Xray 配置...${PLAIN}"
    if ! "$XRAY_BIN" run -test -format json -config "$candidate"; then
        echo -e "${RED}[错误] 新 Xray 配置未通过测试，原配置保持不变。${PLAIN}"; rm -f "$candidate"; return 1
    fi
    if [[ -f "$XRAY_CONF" ]]; then
        had_old=1; backup=$(mktemp "$(dirname "$XRAY_CONF")/config.rollback.XXXXXX.json") || { rm -f "$candidate"; return 1; }; cp -a "$XRAY_CONF" "$backup"
    fi
    mv -f "$candidate" "$XRAY_CONF" || { rm -f "$candidate" "$backup"; return 1; }
    chown root:"$XRAY_GROUP" "$XRAY_CONF"; chmod 640 "$XRAY_CONF"
    if ! systemctl restart "$XRAY_SERVICE_NAME"; then
        echo -e "${RED}[错误] Xray 新配置启动失败，正在回滚...${PLAIN}"
        if [[ $had_old -eq 1 && -f "$backup" ]]; then mv -f "$backup" "$XRAY_CONF"; chown root:"$XRAY_GROUP" "$XRAY_CONF"; chmod 640 "$XRAY_CONF"; systemctl restart "$XRAY_SERVICE_NAME" || true; else rm -f "$XRAY_CONF"; fi
        return 1
    fi
    rm -f "$backup"
    echo -e "${GREEN}✔ Xray 配置已校验并安全切换。${PLAIN}"
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
    local host port uuid sni private public short_id listen out
    if ! xray_vless_exists; then
        if json_has_inbound_tag "$TAG_VLESS"; then
            echo -e "${YELLOW}检测到旧 sing-box VLESS Reality。dev8 起请删除后重新部署为 Xray 版。${PLAIN}"
        else
            echo -e "${YELLOW}未部署 VLESS Reality。${PLAIN}"
        fi
        return
    fi
    port=$(get_xray_vless_port)
    uuid=$(jq -r '.inbounds[] | select(.tag=="vless-reality-in") | .settings.clients[0].id' "$XRAY_CONF")
    sni=$(jq -r '.inbounds[] | select(.tag=="vless-reality-in") | .streamSettings.realitySettings.serverNames[0]' "$XRAY_CONF")
    private=$(jq -r '.inbounds[] | select(.tag=="vless-reality-in") | .streamSettings.realitySettings.privateKey' "$XRAY_CONF")
    short_id=$(jq -r '.inbounds[] | select(.tag=="vless-reality-in") | .streamSettings.realitySettings.shortIds[0]' "$XRAY_CONF")
    listen=$(jq -r '.inbounds[] | select(.tag=="vless-reality-in") | .listen' "$XRAY_CONF")
    host=$(get_mode_state_field "vless" "host" 2>/dev/null || true)
    public=$(get_mode_state_field "vless" "public_key" 2>/dev/null || true)
    if [[ -z "$public" && -n "$private" ]]; then
        out=$("$XRAY_BIN" x25519 -i "$private" 2>/dev/null || true)
        public=$(printf '%s
' "$out" | awk -F': *' '/^Password \(PublicKey\):/ {print $2; exit}')
        [[ -n "$public" ]] || public=$(printf '%s
' "$out" | awk -F': *' '/^Public key:/ {print $2; exit}')
    fi
    if [[ -z "$host" ]]; then if [[ "$listen" == "::" ]]; then host=$(get_global_ipv6 2>/dev/null || echo "请填写IPv6地址"); else host=$(get_public_ipv4 2>/dev/null || echo "请填写服务器地址"); fi; fi
    show_vless_details "$host" "$port" "$uuid" "$sni" "$public" "$short_id"
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

# ==============================================================================
# v1.8.0 分流模块
# - 适用入口：SS2022 / SS2022+ShadowTLS / VLESS Reality
# - Snell v5 保持官方 snell-server，不参与服务端分流
# - 出口：DIRECT / Cloudflare WARP Local Proxy / SS2022 或 SOCKS5 落地节点
# - 规则：全局默认出口 + 按服务覆盖 + IPv4/IPv6 选择
# ==============================================================================

routing_init_state() {
    mkdir -p "$STATE_DIR" || return 1
    chmod 700 "$STATE_DIR"
    if [[ ! -f "$ROUTING_FILE" ]]; then
        cat > "$ROUTING_FILE" <<EOF
{
  "version": 1,
  "default_outbound": "direct",
  "warp": {
    "proxy_host": "127.0.0.1",
    "proxy_port": ${WARP_DEFAULT_PORT}
  },
  "chain_nodes": [],
  "rules": []
}
EOF
        chmod 600 "$ROUTING_FILE"
        return 0
    fi

    local tmp
    tmp=$(mktemp "${STATE_DIR}/routing.json.tmp.XXXXXX") || return 1
    if ! jq --argjson port "$WARP_DEFAULT_PORT" '
      .version = (.version // 1) |
      .default_outbound = (.default_outbound // "direct") |
      .warp = (.warp // {}) |
      .warp.proxy_host = (.warp.proxy_host // "127.0.0.1") |
      .warp.proxy_port = (.warp.proxy_port // $port) |
      .chain_nodes = (.chain_nodes // []) |
      .rules = (.rules // [])
    ' "$ROUTING_FILE" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    mv -f "$tmp" "$ROUTING_FILE"
    chmod 600 "$ROUTING_FILE"
}




routing_commit_state_candidate() {
    # 原子更新 routing.json：只有 sing-box / Xray 两侧都校验并应用成功后才提交状态。
    local candidate="$1" backup rc=0
    [[ -f "$candidate" ]] || return 1
    jq -e 'type=="object" and (.chain_nodes|type=="array") and (.rules|type=="array") and (.default_outbound|type=="string")' "$candidate" >/dev/null 2>&1 || {
        echo -e "${RED}[错误] 新分流状态文件格式无效。${PLAIN}"
        rm -f "$candidate"
        return 1
    }

    backup=$(mktemp "${STATE_DIR}/routing.json.rollback.XXXXXX") || { rm -f "$candidate"; return 1; }
    cp -a "$ROUTING_FILE" "$backup" || { rm -f "$candidate" "$backup"; return 1; }

    mv -f "$candidate" "$ROUTING_FILE" || { rm -f "$backup"; return 1; }
    chmod 600 "$ROUTING_FILE"

    if ! apply_routing_config; then
        rc=1
        echo -e "${YELLOW}>> 分流状态同步失败，恢复上一版 routing.json...${PLAIN}"
        mv -f "$backup" "$ROUTING_FILE"
        chmod 600 "$ROUTING_FILE"
    else
        rm -f "$backup"
    fi
    return "$rc"
}

routing_service_name() {
    case "$1" in
        openai) echo "OpenAI / ChatGPT" ;;
        netflix) echo "Netflix" ;;
        youtube) echo "YouTube" ;;
        google) echo "Google" ;;
        telegram) echo "Telegram" ;;
        mytvsuper) echo "MyTVSuper" ;;
        appletv) echo "Apple TV+" ;;
        tiktok) echo "TikTok" ;;
        custom) echo "自定义规则" ;;
        *) echo "$1" ;;
    esac
}

routing_preset_match_json() {
    case "$1" in
        openai)
            jq -nc '{domain:[],domain_suffix:["openai.com","chatgpt.com","oaistatic.com","oaiusercontent.com"],domain_keyword:[],ip_cidr:[]}'
            ;;
        netflix)
            jq -nc '{domain:[],domain_suffix:["netflix.com","netflix.net","nflxext.com","nflximg.com","nflximg.net","nflxso.net","nflxvideo.net"],domain_keyword:[],ip_cidr:[]}'
            ;;
        youtube)
            jq -nc '{domain:[],domain_suffix:["youtube.com","youtube-nocookie.com","youtu.be","googlevideo.com","ytimg.com","gvt2.com"],domain_keyword:["youtube"],ip_cidr:[]}'
            ;;
        google)
            jq -nc '{domain:[],domain_suffix:["google.com","googleapis.com","gstatic.com","googleusercontent.com","1e100.net"],domain_keyword:[],ip_cidr:[]}'
            ;;
        telegram)
            jq -nc '{domain:[],domain_suffix:["telegram.org","telegram.me","t.me","telesco.pe"],domain_keyword:[],ip_cidr:["149.154.160.0/20","185.76.151.0/24","91.105.192.0/23","91.108.4.0/22","91.108.8.0/22","91.108.12.0/22","91.108.16.0/22","91.108.20.0/22","91.108.56.0/22","2001:67c:4e8::/48","2001:b28:f23c::/48","2001:b28:f23d::/48","2001:b28:f23f::/48","2a0a:f280::/32"]}'
            ;;
        mytvsuper)
            jq -nc '{domain:[],domain_suffix:["mytvsuper.com","tvb.com"],domain_keyword:["nowtv100","rthklive"],ip_cidr:[]}'
            ;;
        appletv)
            jq -nc '{domain:["hls-amt.itunes.apple.com","hls.itunes.apple.com","np-edge.itunes.apple.com","play-edge.itunes.apple.com","tv.applemusic.com","uts-api.itunes.apple.com"],domain_suffix:["tv.apple.com"],domain_keyword:[],ip_cidr:[]}'
            ;;
        tiktok)
            jq -nc '{domain:["lf16-effectcdn.byteeffecttos-g.com","lf16-pkgcdn.pitaya-clientai.com","p16-tiktokcdn-com.akamaized.net"],domain_suffix:["bytedapm.com","bytegecko-i18n.com","byteintlapi.com","byteoversea.com","ibytedtos.com","ibyteimg.com","ipstatp.com","isnssdk.com","muscdn.com","musical.ly","sgpstatp.com","snssdk.com","tik-tokapi.com","tiktok.com","tiktokcdn-us.com","tiktokcdn.com","tiktokd.net","tiktokd.org","tiktokmusic.app","tiktokv.com","tiktokv.us","ttwebview.com"],domain_keyword:["tiktok","musical.ly"],ip_cidr:[]}'
            ;;
        *)
            jq -nc '{domain:[],domain_suffix:[],domain_keyword:[],ip_cidr:[]}'
            ;;
    esac
}

routing_rule_match_json() {
    local rule_json="$1" service custom_type values preset
    service=$(jq -r '.service // "custom"' <<<"$rule_json")
    if [[ "$service" != "custom" ]]; then
        routing_preset_match_json "$service"
        return
    fi
    custom_type=$(jq -r '.custom_type // "domain_suffix"' <<<"$rule_json")
    values=$(jq -c '.values // []' <<<"$rule_json")
    case "$custom_type" in
        domain) jq -nc --argjson v "$values" '{domain:$v,domain_suffix:[],domain_keyword:[],ip_cidr:[]}' ;;
        domain_suffix) jq -nc --argjson v "$values" '{domain:[],domain_suffix:$v,domain_keyword:[],ip_cidr:[]}' ;;
        domain_keyword) jq -nc --argjson v "$values" '{domain:[],domain_suffix:[],domain_keyword:$v,ip_cidr:[]}' ;;
        ip_cidr) jq -nc --argjson v "$values" '{domain:[],domain_suffix:[],domain_keyword:[],ip_cidr:$v}' ;;
        *) jq -nc '{domain:[],domain_suffix:[],domain_keyword:[],ip_cidr:[]}' ;;
    esac
}

routing_node_name_exists() {
    local name="$1"
    routing_init_state || return 1
    jq -e --arg name "$name" 'any(.chain_nodes[]?; .name==$name)' "$ROUTING_FILE" >/dev/null 2>&1
}

routing_preset_rule_exists() {
    local service="$1"
    routing_init_state || return 1
    [[ "$service" != "custom" ]] || return 1
    jq -e --arg service "$service" 'any(.rules[]?; .service==$service)' "$ROUTING_FILE" >/dev/null 2>&1
}

routing_node_exists() {
    local id="$1"
    routing_init_state || return 1
    jq -e --arg id "$id" '.chain_nodes[]? | select(.id==$id)' "$ROUTING_FILE" >/dev/null 2>&1
}


routing_outbound_label() {
    local ref="$1" id name
    case "$ref" in
        direct) echo "DIRECT（本 VPS）" ;;
        warp) echo "WARP" ;;
        chain:*)
            id=${ref#chain:}
            name=$(jq -r --arg id "$id" '.chain_nodes[]? | select(.id==$id) | .name // empty' "$ROUTING_FILE" 2>/dev/null | head -n1)
            echo "${name:-$id}"
            ;;
        *) echo "$ref" ;;
    esac
}

routing_tag_singbox() {
    local ref="$1"
    case "$ref" in
        direct) echo "direct" ;;
        warp) echo "route-warp" ;;
        chain:*) echo "route-chain-${ref#chain:}" ;;
        *) echo "direct" ;;
    esac
}

routing_tag_xray() {
    local ref="$1" family="${2:-default}" base
    case "$ref" in
        direct) base="route-direct" ;;
        warp) base="route-warp" ;;
        chain:*) base="route-chain-${ref#chain:}" ;;
        *) base="route-direct" ;;
    esac
    case "$family" in
        ipv4) echo "${base}-v4" ;;
        ipv6) echo "${base}-v6" ;;
        *) echo "$base" ;;
    esac
}

warp_proxy_port() {
    routing_init_state || { echo "$WARP_DEFAULT_PORT"; return; }
    jq -r --argjson p "$WARP_DEFAULT_PORT" '.warp.proxy_port // $p' "$ROUTING_FILE" 2>/dev/null
}

warp_proxy_ready() {
    local port
    command -v warp-cli >/dev/null 2>&1 || return 1
    port=$(warp_proxy_port)
    ss -H -ltn 2>/dev/null | awk -v p=":${port}" '$4 ~ p"$" {found=1} END{exit !found}' || return 1
    warp-cli --accept-tos status 2>/dev/null | grep -qi 'Connected' || return 1
    return 0
}

warp_is_referenced() {
    routing_init_state || return 1
    jq -e '.default_outbound=="warp" or any(.rules[]?; .outbound=="warp")' "$ROUTING_FILE" >/dev/null 2>&1
}

routing_node_is_referenced() {
    local id="$1"
    routing_init_state || return 1
    jq -e --arg ref "chain:${id}" '.default_outbound==$ref or any(.rules[]?; .outbound==$ref)' "$ROUTING_FILE" >/dev/null 2>&1
}

url_decode_simple() {
    # SIP002 URI userinfo uses percent-encoding; a literal + is part of a Base64 key, not a space.
    local data="$1"
    printf '%b' "${data//%/\\x}"
}

base64url_decode() {
    local s="$1" mod
    s=${s//-/+}; s=${s//_/\/}
    mod=$(( ${#s} % 4 ))
    [[ $mod -eq 2 ]] && s+="=="
    [[ $mod -eq 3 ]] && s+="="
    printf '%s' "$s" | base64 -d 2>/dev/null
}

parse_ss_uri() {
    local uri="$1" body userinfo hostport decoded host port method pass
    uri=${uri#ss://}
    uri=${uri%%#*}
    uri=${uri%%\?*}
    [[ "$uri" == *"@"* ]] || return 1
    userinfo=${uri%@*}
    hostport=${uri##*@}
    if [[ "$userinfo" == *:* ]]; then
        decoded=$(url_decode_simple "$userinfo")
    else
        decoded=$(base64url_decode "$userinfo") || return 1
    fi
    method=${decoded%%:*}
    pass=${decoded#*:}
    [[ "$decoded" == *:* && -n "$method" && -n "$pass" ]] || return 1
    if [[ "$hostport" =~ ^\[([^]]+)\]:([0-9]+)$ ]]; then
        host=${BASH_REMATCH[1]}; port=${BASH_REMATCH[2]}
    elif [[ "$hostport" =~ ^([^:]+):([0-9]+)$ ]]; then
        host=${BASH_REMATCH[1]}; port=${BASH_REMATCH[2]}
    else
        return 1
    fi
    validate_port_number "$port" || return 1
    CHAIN_SERVER="$host"; CHAIN_PORT="$port"; CHAIN_METHOD="$method"; CHAIN_PASSWORD="$pass"
}

validate_ss2022_outbound() {
    local method="$1" pass="$2" bytes
    case "$method" in
        2022-blake3-aes-128-gcm) bytes=16 ;;
        2022-blake3-aes-256-gcm|2022-blake3-chacha20-poly1305) bytes=32 ;;
        *) return 1 ;;
    esac
    validate_ss2022_key "$pass" "$bytes"
}


routing_choose_outbound() {
    local prompt="${1:-请选择出口}" nodes count idx choice i id name type
    routing_init_state || return 1
    nodes=$(jq -c '.chain_nodes' "$ROUTING_FILE")
    count=$(jq 'length' <<<"$nodes")
    echo "$prompt"
    echo "  1. DIRECT（当前 VPS 本身出口）"
    if warp_proxy_ready; then
        echo "  2. WARP（Cloudflare Local Proxy）"
    else
        echo "  2. WARP（当前不可用，请先安装/连接）"
    fi
    i=0
    while [[ $i -lt $count ]]; do
        name=$(jq -r ".[$i].name" <<<"$nodes")
        type=$(jq -r ".[$i].type" <<<"$nodes")
        printf '  %d. %s [%s]\n' "$((i+3))" "$name" "$type"
        i=$((i+1))
    done
    read -rp "请选择: " choice
    case "$choice" in
        1) SELECTED_OUTBOUND="direct"; return 0 ;;
        2)
            if warp_proxy_ready; then SELECTED_OUTBOUND="warp"; return 0; fi
            echo -e "${RED}[错误] WARP 当前不可用。${PLAIN}"; return 1
            ;;
        *)
            [[ "$choice" =~ ^[0-9]+$ ]] || return 1
            idx=$((choice-3))
            [[ $idx -ge 0 && $idx -lt $count ]] || return 1
            id=$(jq -r ".[$idx].id" <<<"$nodes")
            SELECTED_OUTBOUND="chain:${id}"
            return 0
            ;;
    esac
}

routing_choose_ip_family() {
    local c
    echo "请选择 IP 地址族："
    echo "  1. 默认（不强制）"
    echo "  2. 仅 IPv4"
    echo "  3. 仅 IPv6"
    read -rp "请选择 [1-3，默认 1]: " c
    c=${c:-1}
    case "$c" in
        1) SELECTED_IP_FAMILY="default" ;;
        2) SELECTED_IP_FAMILY="ipv4" ;;
        3) SELECTED_IP_FAMILY="ipv6" ;;
        *) return 1 ;;
    esac
}

build_singbox_routing_candidate() {
    local output="$1" outbounds='[]' rules='[{"action":"sniff","timeout":"300ms"}]' nodes count i node type tag ref default_ref default_tag port
    local rule_count r rmatch family outbound domains suffix keywords ips part action
    [[ -f "$SINGBOX_CONF" && -x "$SINGBOX_BIN" ]] || return 2
    routing_init_state || return 1

    outbounds=$(jq -nc '[{"type":"direct","tag":"direct"}]')
    port=$(warp_proxy_port)
    outbounds=$(jq -c --argjson p "$port" '. + [{"type":"socks","tag":"route-warp","server":"127.0.0.1","server_port":$p}]' <<<"$outbounds")

    nodes=$(jq -c '.chain_nodes' "$ROUTING_FILE")
    count=$(jq 'length' <<<"$nodes")
    i=0
    while [[ $i -lt $count ]]; do
        node=$(jq -c ".[$i]" <<<"$nodes")
        type=$(jq -r '.type' <<<"$node")
        tag="route-chain-$(jq -r '.id' <<<"$node")"
        if [[ "$type" == "ss2022" ]]; then
            outbounds=$(jq -c --arg tag "$tag" --arg server "$(jq -r '.server' <<<"$node")" --argjson port "$(jq -r '.port' <<<"$node")" --arg method "$(jq -r '.method' <<<"$node")" --arg pass "$(jq -r '.password' <<<"$node")" '. + [{type:"shadowsocks",tag:$tag,server:$server,server_port:$port,method:$method,password:$pass}]' <<<"$outbounds")
        else
            outbounds=$(jq -c --arg tag "$tag" --arg server "$(jq -r '.server' <<<"$node")" --argjson port "$(jq -r '.port' <<<"$node")" --arg user "$(jq -r '.username // ""' <<<"$node")" --arg pass "$(jq -r '.password // ""' <<<"$node")" '. + [({type:"socks",tag:$tag,server:$server,server_port:$port} + (if $user!="" then {username:$user,password:$pass} else {} end))]' <<<"$outbounds")
        fi
        i=$((i+1))
    done

    rule_count=$(jq '.rules|length' "$ROUTING_FILE")
    i=0
    while [[ $i -lt $rule_count ]]; do
        r=$(jq -c ".rules[$i]" "$ROUTING_FILE")
        rmatch=$(routing_rule_match_json "$r")
        family=$(jq -r '.ip_family // "default"' <<<"$r")
        outbound=$(jq -r '.outbound' <<<"$r")
        action=$(routing_tag_singbox "$outbound")
        domains=$(jq -c '.domain' <<<"$rmatch")
        suffix=$(jq -c '.domain_suffix' <<<"$rmatch")
        keywords=$(jq -c '.domain_keyword' <<<"$rmatch")
        ips=$(jq -c '.ip_cidr' <<<"$rmatch")

        for part in domain domain_suffix domain_keyword; do
            local arr
            arr=$(jq -c ".$part" <<<"$rmatch")
            [[ $(jq 'length' <<<"$arr") -gt 0 ]] || continue
            if [[ "$family" == "ipv4" || "$family" == "ipv6" ]]; then
                local strategy
                [[ "$family" == "ipv4" ]] && strategy="ipv4_only" || strategy="ipv6_only"
                rules=$(jq -c --arg key "$part" --argjson vals "$arr" --arg strategy "$strategy" '. + [({action:"resolve",strategy:$strategy} + {($key):$vals})]' <<<"$rules")
            fi
            rules=$(jq -c --arg key "$part" --argjson vals "$arr" --arg out "$action" '. + [({action:"route",outbound:$out} + {($key):$vals})]' <<<"$rules")
        done

        if [[ $(jq 'length' <<<"$ips") -gt 0 ]]; then
            if [[ "$family" == "ipv4" ]]; then
                ips=$(jq -c '[.[] | select(contains(":")|not)]' <<<"$ips")
            elif [[ "$family" == "ipv6" ]]; then
                ips=$(jq -c '[.[] | select(contains(":"))]' <<<"$ips")
            fi
            if [[ $(jq 'length' <<<"$ips") -gt 0 ]]; then
                rules=$(jq -c --argjson vals "$ips" --arg out "$action" '. + [{ip_cidr:$vals,action:"route",outbound:$out}]' <<<"$rules")
            fi
        fi
        i=$((i+1))
    done

    default_ref=$(jq -r '.default_outbound' "$ROUTING_FILE")
    default_tag=$(routing_tag_singbox "$default_ref")
    jq --argjson outs "$outbounds" --argjson rules "$rules" --arg final "$default_tag" '
      .dns = (.dns // {}) |
      .dns.servers = ((.dns.servers // []) as $servers |
        if any($servers[]?; .tag == "local-dns") then $servers
        else $servers + [{type:"local",tag:"local-dns"}] end) |
      .outbounds = $outs |
      .route = (.route // {}) |
      .route.rules = $rules |
      .route.final = $final |
      .route.default_domain_resolver = (.route.default_domain_resolver // "local-dns")
    ' "$SINGBOX_CONF" > "$output"
}

xray_outbound_for_node() {
    local node="$1" tag="$2" family="${3:-default}" type strategy="AsIs"
    type=$(jq -r '.type' <<<"$node")
    [[ "$family" == "ipv4" ]] && strategy="ForceIPv4"
    [[ "$family" == "ipv6" ]] && strategy="ForceIPv6"
    if [[ "$type" == "ss2022" ]]; then
        jq -nc --arg tag "$tag" --arg address "$(jq -r '.server' <<<"$node")" --argjson port "$(jq -r '.port' <<<"$node")" --arg method "$(jq -r '.method' <<<"$node")" --arg pass "$(jq -r '.password' <<<"$node")" --arg ts "$strategy" '{protocol:"shadowsocks",tag:$tag,targetStrategy:$ts,settings:{address:$address,port:$port,method:$method,password:$pass}}'
    else
        jq -nc --arg tag "$tag" --arg address "$(jq -r '.server' <<<"$node")" --argjson port "$(jq -r '.port' <<<"$node")" --arg user "$(jq -r '.username // ""' <<<"$node")" --arg pass "$(jq -r '.password // ""' <<<"$node")" --arg ts "$strategy" '{protocol:"socks",tag:$tag,targetStrategy:$ts,settings:({address:$address,port:$port} + (if $user!="" then {user:$user,pass:$pass} else {} end))}'
    fi
}

xray_direct_outbound() {
    local tag="$1" family="${2:-default}" ds="AsIs"
    [[ "$family" == "ipv4" ]] && ds="UseIPv4"
    [[ "$family" == "ipv6" ]] && ds="UseIPv6"
    jq -nc --arg tag "$tag" --arg ds "$ds" '{protocol:"freedom",tag:$tag,settings:{domainStrategy:$ds}}'
}

xray_warp_outbound() {
    local tag="$1" family="${2:-default}" ts="AsIs" port
    [[ "$family" == "ipv4" ]] && ts="ForceIPv4"
    [[ "$family" == "ipv6" ]] && ts="ForceIPv6"
    port=$(warp_proxy_port)
    jq -nc --arg tag "$tag" --argjson port "$port" --arg ts "$ts" '{protocol:"socks",tag:$tag,targetStrategy:$ts,settings:{address:"127.0.0.1",port:$port}}'
}

build_xray_routing_candidate() {
    local output="$1" outbounds='[]' rules='[]' nodes count i node ref family base match
    local rule_count r rmatch domains suffix keywords ips xdomains tag part arr default_ref default_tag
    [[ -f "$XRAY_CONF" && -x "$XRAY_BIN" ]] || return 2
    routing_init_state || return 1

    outbounds=$(jq -nc --argjson a "$(xray_direct_outbound route-direct default)" --argjson b "$(xray_direct_outbound route-direct-v4 ipv4)" --argjson c "$(xray_direct_outbound route-direct-v6 ipv6)" --argjson d "$(xray_warp_outbound route-warp default)" --argjson e "$(xray_warp_outbound route-warp-v4 ipv4)" --argjson f "$(xray_warp_outbound route-warp-v6 ipv6)" '[$a,$b,$c,$d,$e,$f]')

    nodes=$(jq -c '.chain_nodes' "$ROUTING_FILE")
    count=$(jq 'length' <<<"$nodes")
    i=0
    while [[ $i -lt $count ]]; do
        node=$(jq -c ".[$i]" <<<"$nodes")
        local nid b o4 o6
        nid=$(jq -r '.id' <<<"$node")
        b=$(xray_outbound_for_node "$node" "route-chain-${nid}" default)
        o4=$(xray_outbound_for_node "$node" "route-chain-${nid}-v4" ipv4)
        o6=$(xray_outbound_for_node "$node" "route-chain-${nid}-v6" ipv6)
        outbounds=$(jq -c --argjson a "$b" --argjson b "$o4" --argjson c "$o6" '. + [$a,$b,$c]' <<<"$outbounds")
        i=$((i+1))
    done

    rule_count=$(jq '.rules|length' "$ROUTING_FILE")
    i=0
    while [[ $i -lt $rule_count ]]; do
        r=$(jq -c ".rules[$i]" "$ROUTING_FILE")
        rmatch=$(routing_rule_match_json "$r")
        family=$(jq -r '.ip_family // "default"' <<<"$r")
        ref=$(jq -r '.outbound' <<<"$r")
        tag=$(routing_tag_xray "$ref" "$family")
        xdomains='[]'
        domains=$(jq -c '.domain' <<<"$rmatch")
        suffix=$(jq -c '.domain_suffix' <<<"$rmatch")
        keywords=$(jq -c '.domain_keyword' <<<"$rmatch")
        xdomains=$(jq -c --argjson a "$domains" --argjson b "$suffix" --argjson c "$keywords" '$a|map("full:"+.) + ($b|map("domain:"+.)) + ($c|map("keyword:"+.))' <<<"{}")
        if [[ $(jq 'length' <<<"$xdomains") -gt 0 ]]; then
            rules=$(jq -c --argjson d "$xdomains" --arg tag "$tag" '. + [{type:"field",domain:$d,outboundTag:$tag}]' <<<"$rules")
        fi
        ips=$(jq -c '.ip_cidr' <<<"$rmatch")
        if [[ "$family" == "ipv4" ]]; then ips=$(jq -c '[.[]|select(contains(":")|not)]' <<<"$ips"); fi
        if [[ "$family" == "ipv6" ]]; then ips=$(jq -c '[.[]|select(contains(":"))]' <<<"$ips"); fi
        if [[ $(jq 'length' <<<"$ips") -gt 0 ]]; then
            rules=$(jq -c --argjson ip "$ips" --arg tag "$tag" '. + [{type:"field",ip:$ip,outboundTag:$tag}]' <<<"$rules")
        fi
        i=$((i+1))
    done

    default_ref=$(jq -r '.default_outbound' "$ROUTING_FILE")
    default_tag=$(routing_tag_xray "$default_ref" default)
    rules=$(jq -c --arg tag "$default_tag" '. + [{type:"field",network:"tcp,udp",outboundTag:$tag}]' <<<"$rules")

    jq --argjson outs "$outbounds" --argjson rules "$rules" '
      .inbounds = ((.inbounds // []) | map(
        if .tag == "vless-reality-in" then
          .sniffing = {enabled:true,destOverride:["http","tls","quic"],routeOnly:true}
        else . end
      )) |
      .outbounds = $outs |
      .routing = {domainStrategy:"AsIs",rules:$rules}
    ' "$XRAY_CONF" > "$output"
}

apply_routing_config() {
    routing_init_state || return 1
    local sb_tmp="" xr_tmp="" sb_backup="" xr_backup="" sb_active=0 xr_active=0 failed=0

    if [[ -f "$SINGBOX_CONF" && -x "$SINGBOX_BIN" ]]; then
        sb_tmp=$(mktemp "/etc/sing-box/config.routing.XXXXXX.json") || return 1
        build_singbox_routing_candidate "$sb_tmp" || { rm -f "$sb_tmp"; return 1; }
        echo -e "${YELLOW}>> 校验 sing-box 分流配置...${PLAIN}"
        if ! "$SINGBOX_BIN" check -c "$sb_tmp"; then
            echo -e "${RED}[错误] sing-box 分流配置校验失败，未应用任何修改。${PLAIN}"
            rm -f "$sb_tmp"
            return 1
        fi
        sb_active=1
    fi

    if [[ -f "$XRAY_CONF" && -x "$XRAY_BIN" ]]; then
        xr_tmp=$(mktemp "/etc/ss2022-xray/config.routing.XXXXXX.json") || { rm -f "$sb_tmp"; return 1; }
        build_xray_routing_candidate "$xr_tmp" || { rm -f "$sb_tmp" "$xr_tmp"; return 1; }
        chown root:"$XRAY_GROUP" "$xr_tmp" 2>/dev/null || true
        chmod 640 "$xr_tmp"
        echo -e "${YELLOW}>> 校验 Xray 分流配置...${PLAIN}"
        if ! "$XRAY_BIN" run -test -format json -config "$xr_tmp"; then
            echo -e "${RED}[错误] Xray 分流配置校验失败，未应用任何修改。${PLAIN}"
            rm -f "$sb_tmp" "$xr_tmp"
            return 1
        fi
        xr_active=1
    fi

    if [[ $sb_active -eq 0 && $xr_active -eq 0 ]]; then
        echo -e "${YELLOW}[提示] 当前尚未部署 SS2022/ShadowTLS/VLESS；分流状态已保存，部署节点后会自动生效。${PLAIN}"
        return 0
    fi

    if [[ $sb_active -eq 1 ]]; then
        sb_backup=$(mktemp "/etc/sing-box/config.routing.rollback.XXXXXX.json") || { rm -f "$sb_tmp" "$xr_tmp"; return 1; }
        cp -a "$SINGBOX_CONF" "$sb_backup" || return 1
    fi
    if [[ $xr_active -eq 1 ]]; then
        xr_backup=$(mktemp "/etc/ss2022-xray/config.routing.rollback.XXXXXX.json") || { rm -f "$sb_tmp" "$xr_tmp" "$sb_backup"; return 1; }
        cp -a "$XRAY_CONF" "$xr_backup" || return 1
    fi

    if [[ $sb_active -eq 1 ]]; then
        mv -f "$sb_tmp" "$SINGBOX_CONF" || failed=1
        chown root:"$SINGBOX_GROUP" "$SINGBOX_CONF" 2>/dev/null || true
        chmod 640 "$SINGBOX_CONF"
    fi
    if [[ $failed -eq 0 && $xr_active -eq 1 ]]; then
        mv -f "$xr_tmp" "$XRAY_CONF" || failed=1
        chown root:"$XRAY_GROUP" "$XRAY_CONF" 2>/dev/null || true
        chmod 640 "$XRAY_CONF"
    fi

    if [[ $failed -eq 0 && $sb_active -eq 1 ]] && ! systemctl restart sing-box; then failed=1; fi
    if [[ $failed -eq 0 && $xr_active -eq 1 ]] && ! systemctl restart "$XRAY_SERVICE_NAME"; then failed=1; fi

    if [[ $failed -ne 0 ]]; then
        echo -e "${RED}[错误] 分流配置应用失败，正在回滚 sing-box / Xray...${PLAIN}"
        if [[ $sb_active -eq 1 && -f "$sb_backup" ]]; then mv -f "$sb_backup" "$SINGBOX_CONF"; chown root:"$SINGBOX_GROUP" "$SINGBOX_CONF" 2>/dev/null || true; chmod 640 "$SINGBOX_CONF"; systemctl restart sing-box >/dev/null 2>&1 || true; fi
        if [[ $xr_active -eq 1 && -f "$xr_backup" ]]; then mv -f "$xr_backup" "$XRAY_CONF"; chown root:"$XRAY_GROUP" "$XRAY_CONF" 2>/dev/null || true; chmod 640 "$XRAY_CONF"; systemctl restart "$XRAY_SERVICE_NAME" >/dev/null 2>&1 || true; fi
        rm -f "$sb_tmp" "$xr_tmp" "$sb_backup" "$xr_backup"
        return 1
    fi

    rm -f "$sb_backup" "$xr_backup"
    echo -e "${GREEN}✔ 分流配置已通过双核心校验并安全应用。${PLAIN}"
}

warp_install_client() {
    local managed=0 codename port
    routing_init_state || return 1
    port=$(warp_proxy_port)
    if ! command -v warp-cli >/dev/null 2>&1; then
        echo -e "${YELLOW}>> 安装 Cloudflare 官方 WARP Linux 客户端...${PLAIN}"
        apt-get update -y || return 1
        apt-get install -y curl ca-certificates gnupg lsb-release || return 1
        curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg || return 1
        codename=$(. /etc/os-release 2>/dev/null; echo "${VERSION_CODENAME:-}")
        [[ -n "$codename" ]] || codename=$(lsb_release -cs 2>/dev/null || true)
        [[ -n "$codename" ]] || { echo -e "${RED}[错误] 无法识别 Debian/Ubuntu 发行版代号。${PLAIN}"; return 1; }
        echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ ${codename} main" > /etc/apt/sources.list.d/cloudflare-client.list
        apt-get update -y || return 1
        apt-get install -y cloudflare-warp || return 1
        managed=1
        touch "$WARP_MANAGED_MARKER"
    fi

    systemctl enable --now warp-svc >/dev/null 2>&1 || true
    sleep 1
    if ! warp-cli --accept-tos registration show >/dev/null 2>&1; then
        echo -e "${YELLOW}>> 注册 WARP Consumer 客户端...${PLAIN}"
        warp-cli --accept-tos registration new || return 1
    fi
    warp-cli --accept-tos tunnel protocol set MASQUE >/dev/null 2>&1 || true
    warp-cli --accept-tos mode proxy || return 1
    warp-cli --accept-tos proxy port "$port" || return 1
    warp-cli --accept-tos connect || return 1
    local n=0
    while [[ $n -lt 15 ]]; do
        if warp_proxy_ready; then
            echo -e "${GREEN}✔ WARP Local Proxy 已连接：127.0.0.1:${port}${PLAIN}"
            return 0
        fi
        sleep 1; n=$((n+1))
    done
    echo -e "${RED}[错误] WARP 已配置，但 15 秒内未进入 Connected 状态。${PLAIN}"
    warp-cli --accept-tos status 2>/dev/null || true
    return 1
}

warp_show_status() {
    local port
    port=$(warp_proxy_port)
    echo -e "${CYAN}════════════════ WARP 状态 ════════════════${PLAIN}"
    if ! command -v warp-cli >/dev/null 2>&1; then echo "未安装 Cloudflare WARP。"; return; fi
    warp-cli --accept-tos status 2>/dev/null || true
    echo ""
    warp-cli --accept-tos settings 2>/dev/null | grep -Ei 'mode|proxy|protocol' || true
    echo ""
    echo "Local Proxy: 127.0.0.1:${port}"
    if warp_proxy_ready; then echo -e "状态: ${GREEN}可用${PLAIN}"; else echo -e "状态: ${YELLOW}未就绪${PLAIN}"; fi
}

warp_test_exit() {
    local port trace
    port=$(warp_proxy_port)
    warp_proxy_ready || { echo -e "${RED}[错误] WARP Local Proxy 当前不可用。${PLAIN}"; return 1; }
    echo -e "${YELLOW}>> 测试 WARP 出口...${PLAIN}"
    trace=$(curl -fsS --connect-timeout 8 --max-time 15 --socks5-hostname "127.0.0.1:${port}" https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null) || { echo -e "${RED}[错误] WARP 出口请求失败。${PLAIN}"; return 1; }
    printf '%s\n' "$trace" | grep -E '^(ip|loc|warp|colo)=' || true
    if grep -qE '^warp=(on|plus)$' <<<"$trace"; then echo -e "${GREEN}✔ WARP 出口正常。${PLAIN}"; else echo -e "${YELLOW}[警告] 请求成功，但 trace 未显示 warp=on/plus。${PLAIN}"; fi
}

warp_reregister() {
    command -v warp-cli >/dev/null 2>&1 || { echo -e "${YELLOW}WARP 未安装。${PLAIN}"; return 1; }
    warp-cli --accept-tos disconnect >/dev/null 2>&1 || true
    warp-cli --accept-tos registration delete >/dev/null 2>&1 || true
    warp-cli --accept-tos registration new || return 1
    warp-cli --accept-tos tunnel protocol set MASQUE >/dev/null 2>&1 || true
    warp-cli --accept-tos mode proxy || return 1
    warp-cli --accept-tos proxy port "$(warp_proxy_port)" || return 1
    warp-cli --accept-tos connect || return 1
    sleep 2
    warp_test_exit
}

warp_uninstall_client() {
    if warp_is_referenced; then
        echo -e "${RED}[错误] 当前默认出口或分流规则仍引用 WARP。请先修改这些规则再卸载。${PLAIN}"
        return 1
    fi
    command -v warp-cli >/dev/null 2>&1 || { echo -e "${YELLOW}WARP 未安装。${PLAIN}"; return 0; }
    warp-cli --accept-tos disconnect >/dev/null 2>&1 || true
    if [[ -f "$WARP_MANAGED_MARKER" ]]; then
        warp-cli --accept-tos registration delete >/dev/null 2>&1 || true
        apt-get remove -y cloudflare-warp || return 1
        rm -f /etc/apt/sources.list.d/cloudflare-client.list /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg "$WARP_MANAGED_MARKER"
        echo -e "${GREEN}✔ 已卸载由 ss2022.sh 安装的 Cloudflare WARP。${PLAIN}"
    else
        echo -e "${YELLOW}[提示] WARP 不是由本脚本安装，仅执行断开，不删除软件包。${PLAIN}"
    fi
}

warp_management() {
    while true; do
        clear
        warp_show_status
        echo ""
        echo "  1. 安装 / 配置 Cloudflare WARP Local Proxy"
        echo "  2. 测试 WARP 出口"
        echo "  3. 重连 WARP"
        echo "  4. 重新注册 WARP"
        echo "  5. 卸载 WARP"
        echo "  0. 返回"
        read -rp "请选择 [0-5]: " c
        case "$c" in
            1) warp_install_client; pause ;;
            2) warp_test_exit; pause ;;
            3) if command -v warp-cli >/dev/null; then warp-cli --accept-tos disconnect >/dev/null 2>&1 || true; warp-cli --accept-tos connect; sleep 2; warp_test_exit; else echo "WARP 未安装。"; fi; pause ;;
            4) warp_reregister; pause ;;
            5) warp_uninstall_client; pause ;;
            0) return ;;
            *) sleep 1 ;;
        esac
    done
}

chain_add_ss2022() {
    local name mode uri server port method pass id node
    read -rp "节点名称（例如 US-LA）: " name
    [[ -n "$name" ]] || return 1
    if routing_node_name_exists "$name"; then echo -e "${RED}[错误] 落地节点名称 ${name} 已存在，请使用唯一名称。${PLAIN}"; return 1; fi
    echo "  1. 粘贴 ss:// URI"
    echo "  2. 手动输入"
    read -rp "请选择 [1-2，默认 1]: " mode
    mode=${mode:-1}
    if [[ "$mode" == "1" ]]; then
        read -rp "请粘贴 SS2022 ss:// URI: " uri
        if ! parse_ss_uri "$uri"; then echo -e "${RED}[错误] 无法解析该 ss:// URI。${PLAIN}"; return 1; fi
        server="$CHAIN_SERVER"; port="$CHAIN_PORT"; method="$CHAIN_METHOD"; pass="$CHAIN_PASSWORD"
    else
        read -rp "服务器地址/域名: " server
        read -rp "端口: " port
        validate_port_number "$port" || { echo -e "${RED}[错误] 端口无效。${PLAIN}"; return 1; }
        echo "  1. 2022-blake3-aes-128-gcm"
        echo "  2. 2022-blake3-aes-256-gcm"
        echo "  3. 2022-blake3-chacha20-poly1305"
        read -rp "加密算法 [1-3]: " mode
        case "$mode" in
            1) method="2022-blake3-aes-128-gcm" ;;
            2) method="2022-blake3-aes-256-gcm" ;;
            3) method="2022-blake3-chacha20-poly1305" ;;
            *) return 1 ;;
        esac
        read -rp "SS2022 Key: " pass
    fi
    if ! validate_ss2022_outbound "$method" "$pass"; then echo -e "${RED}[错误] SS2022 加密算法或 Key 长度不合法。${PLAIN}"; return 1; fi
    id="n$(date +%s)${RANDOM}"
    node=$(jq -nc --arg id "$id" --arg name "$name" --arg server "$server" --argjson port "$port" --arg method "$method" --arg pass "$pass" '{id:$id,name:$name,type:"ss2022",server:$server,port:$port,method:$method,password:$pass}')
    local tmp
    tmp=$(mktemp "${STATE_DIR}/routing.json.tmp.XXXXXX") || return 1
    jq --argjson n "$node" '.chain_nodes += [$n]' "$ROUTING_FILE" > "$tmp" || { rm -f "$tmp"; return 1; }
    routing_commit_state_candidate "$tmp" || return 1
    echo -e "${GREEN}✔ SS2022 落地节点 ${name} 已添加。${PLAIN}"
}

chain_add_socks5() {
    local name server port auth user="" pass="" id node tmp
    echo -e "${YELLOW}[提示] SOCKS5 本身不加密；公网落地优先建议使用 SS2022，SOCKS5 仅用于可信或已受保护的链路。${PLAIN}"
    read -rp "节点名称（例如 HK-SOCKS）: " name
    [[ -n "$name" ]] || return 1
    if routing_node_name_exists "$name"; then echo -e "${RED}[错误] 落地节点名称 ${name} 已存在，请使用唯一名称。${PLAIN}"; return 1; fi
    read -rp "服务器地址/域名: " server
    read -rp "端口: " port
    validate_port_number "$port" || { echo -e "${RED}[错误] 端口无效。${PLAIN}"; return 1; }
    read -rp "是否需要用户名/密码认证？[y/N]: " auth
    if [[ "$auth" =~ ^[Yy]$ ]]; then read -rp "用户名: " user; read -rsp "密码: " pass; echo ""; fi
    id="n$(date +%s)${RANDOM}"
    node=$(jq -nc --arg id "$id" --arg name "$name" --arg server "$server" --argjson port "$port" --arg user "$user" --arg pass "$pass" '{id:$id,name:$name,type:"socks5",server:$server,port:$port,username:$user,password:$pass}')
    tmp=$(mktemp "${STATE_DIR}/routing.json.tmp.XXXXXX") || return 1
    jq --argjson n "$node" '.chain_nodes += [$n]' "$ROUTING_FILE" > "$tmp" || { rm -f "$tmp"; return 1; }
    routing_commit_state_candidate "$tmp" || return 1
    echo -e "${GREEN}✔ SOCKS5 落地节点 ${name} 已添加。${PLAIN}"
}

chain_list_nodes() {
    routing_init_state || return 1
    local count i node
    count=$(jq '.chain_nodes|length' "$ROUTING_FILE")
    echo -e "${CYAN}════════════════ 落地节点 ════════════════${PLAIN}"
    if [[ $count -eq 0 ]]; then echo "暂无落地节点。"; return; fi
    i=0
    while [[ $i -lt $count ]]; do
        node=$(jq -c ".chain_nodes[$i]" "$ROUTING_FILE")
        printf '  %d. %s [%s] %s:%s\n' "$((i+1))" "$(jq -r '.name' <<<"$node")" "$(jq -r '.type' <<<"$node")" "$(jq -r '.server' <<<"$node")" "$(jq -r '.port' <<<"$node")"
        i=$((i+1))
    done
}

chain_select_id() {
    local count c
    routing_init_state || return 1
    count=$(jq '.chain_nodes|length' "$ROUTING_FILE")
    [[ $count -gt 0 ]] || { echo "暂无落地节点。"; return 1; }
    chain_list_nodes
    read -rp "请选择节点编号: " c
    [[ "$c" =~ ^[0-9]+$ && $c -ge 1 && $c -le $count ]] || return 1
    SELECTED_NODE_ID=$(jq -r ".chain_nodes[$((c-1))].id" "$ROUTING_FILE")
}

ip_echo_url_for_family() {
    case "${1:-default}" in
        ipv4) echo "https://api4.ipify.org" ;;
        ipv6) echo "https://api6.ipify.org" ;;
        *) echo "https://api.ipify.org" ;;
    esac
}

test_ss2022_node_with_singbox() {
    local node="$1" family="${2:-default}" port cfg pid out rc=1 n=19080 url
    url=$(ip_echo_url_for_family "$family")
    [[ -x "$SINGBOX_BIN" ]] || { echo -e "${YELLOW}[提示] 未安装 sing-box，无法执行 SS2022 实连测试。${PLAIN}"; return 1; }
    while ss -H -ltn 2>/dev/null | grep -q ":${n} "; do n=$((n+1)); [[ $n -lt 19150 ]] || return 1; done
    port=$n
    cfg=$(mktemp /tmp/ss2022-chain-test.XXXXXX.json) || return 1
    jq -n --arg server "$(jq -r '.server' <<<"$node")" --argjson sport "$(jq -r '.port' <<<"$node")" --arg method "$(jq -r '.method' <<<"$node")" --arg pass "$(jq -r '.password' <<<"$node")" --argjson lp "$port" '{log:{level:"warn"},inbounds:[{type:"socks",tag:"test-in",listen:"127.0.0.1",listen_port:$lp}],outbounds:[{type:"shadowsocks",tag:"test-out",server:$server,server_port:$sport,method:$method,password:$pass}],route:{final:"test-out"}}' > "$cfg"
    "$SINGBOX_BIN" check -c "$cfg" >/dev/null 2>&1 || { rm -f "$cfg"; return 1; }
    "$SINGBOX_BIN" run -c "$cfg" >/tmp/ss2022-chain-test.log 2>&1 & pid=$!
    sleep 1
    out=$(curl -fsS --connect-timeout 8 --max-time 15 --socks5-hostname "127.0.0.1:${port}" "$url" 2>/dev/null) && rc=0
    kill "$pid" >/dev/null 2>&1 || true; wait "$pid" 2>/dev/null || true; rm -f "$cfg"
    if [[ $rc -eq 0 ]]; then echo -e "${GREEN}✔ 落地节点可用，出口 IP: ${out}${PLAIN}"; return 0; fi
    echo -e "${RED}[错误] SS2022 落地节点测试失败。${PLAIN}"; tail -n 10 /tmp/ss2022-chain-test.log 2>/dev/null || true; return 1
}

chain_test_node() {
    chain_select_id || return 1
    local node type server port user pass out
    node=$(jq -c --arg id "$SELECTED_NODE_ID" '.chain_nodes[]|select(.id==$id)' "$ROUTING_FILE")
    type=$(jq -r '.type' <<<"$node")
    echo -e "${YELLOW}>> 测试 $(jq -r '.name' <<<"$node")...${PLAIN}"
    if [[ "$type" == "ss2022" ]]; then
        test_ss2022_node_with_singbox "$node" default
    else
        server=$(jq -r '.server' <<<"$node"); port=$(jq -r '.port' <<<"$node"); user=$(jq -r '.username // ""' <<<"$node"); pass=$(jq -r '.password // ""' <<<"$node")
        if [[ -n "$user" ]]; then
            out=$(curl -fsS --connect-timeout 8 --max-time 15 --proxy-user "${user}:${pass}" --socks5-hostname "${server}:${port}" https://api.ipify.org 2>/dev/null) || { echo -e "${RED}[错误] SOCKS5 测试失败。${PLAIN}"; return 1; }
        else
            out=$(curl -fsS --connect-timeout 8 --max-time 15 --socks5-hostname "${server}:${port}" https://api.ipify.org 2>/dev/null) || { echo -e "${RED}[错误] SOCKS5 测试失败。${PLAIN}"; return 1; }
        fi
        echo -e "${GREEN}✔ 落地节点可用，出口 IP: ${out}${PLAIN}"
    fi
}

chain_delete_node() {
    chain_select_id || return 1
    local id="$SELECTED_NODE_ID" name tmp yes
    name=$(jq -r --arg id "$id" '.chain_nodes[]|select(.id==$id)|.name' "$ROUTING_FILE")
    if routing_node_is_referenced "$id"; then echo -e "${RED}[错误] ${name} 仍被默认出口或分流规则引用，不能删除。${PLAIN}"; return 1; fi
    read -rp "确认删除落地节点 ${name}？[y/N]: " yes
    [[ "$yes" =~ ^[Yy]$ ]] || return 0
    tmp=$(mktemp "${STATE_DIR}/routing.json.tmp.XXXXXX") || return 1
    jq --arg id "$id" '.chain_nodes |= map(select(.id!=$id))' "$ROUTING_FILE" > "$tmp" || { rm -f "$tmp"; return 1; }
    routing_commit_state_candidate "$tmp" || return 1
    echo -e "${GREEN}✔ 已删除 ${name}。${PLAIN}"
}

routing_set_default_outbound() {
    routing_choose_outbound "请选择全局默认出口（未命中特殊规则的流量使用此出口）：" || return 1
    local tmp label
    label=$(routing_outbound_label "$SELECTED_OUTBOUND")
    tmp=$(mktemp "${STATE_DIR}/routing.json.tmp.XXXXXX") || return 1
    jq --arg out "$SELECTED_OUTBOUND" '.default_outbound=$out' "$ROUTING_FILE" > "$tmp" || { rm -f "$tmp"; return 1; }
    if ! routing_commit_state_candidate "$tmp"; then echo -e "${RED}[错误] 默认出口配置应用失败，已恢复原配置。${PLAIN}"; return 1; fi
    echo -e "${GREEN}✔ 默认出口已设置为：${label}${PLAIN}"
}

chain_management() {
    while true; do
        clear; routing_init_state || return
        local def count
        def=$(jq -r '.default_outbound' "$ROUTING_FILE"); count=$(jq '.chain_nodes|length' "$ROUTING_FILE")
        echo -e "${CYAN}════════════════ 链式代理管理 ════════════════${PLAIN}"
        echo "默认出口 : $(routing_outbound_label "$def")"
        echo "落地节点 : ${count} 个"
        echo ""
        echo "  1. 添加落地节点"
        echo "  2. 查看落地节点"
        echo "  3. 删除落地节点"
        echo "  4. 测试落地节点"
        echo "  5. 设置默认出口"
        echo "  0. 返回"
        read -rp "请选择 [0-5]: " c
        case "$c" in
            1)
                echo "  1. SS2022"
                echo "  2. SOCKS5"
                read -rp "节点类型 [1-2]: " t
                [[ "$t" == "1" ]] && chain_add_ss2022
                [[ "$t" == "2" ]] && chain_add_socks5
                pause ;;
            2) chain_list_nodes; pause ;;
            3) chain_delete_node; pause ;;
            4) chain_test_node; pause ;;
            5) routing_set_default_outbound; pause ;;
            0) return ;;
            *) sleep 1 ;;
        esac
    done
}

routing_add_rule() {
    routing_init_state || return 1
    local c service name custom_type values='[]' v id rule tmp
    echo "请选择服务："
    echo "  1. OpenAI / ChatGPT"
    echo "  2. Netflix"
    echo "  3. YouTube"
    echo "  4. Google"
    echo "  5. Telegram"
    echo "  6. MyTVSuper"
    echo "  7. Apple TV+"
    echo "  8. TikTok"
    echo "  9. 自定义域名 / IP"
    echo "  0. 返回"
    read -rp "请选择 [0-9]: " c
    case "$c" in
        1) service=openai ;; 2) service=netflix ;; 3) service=youtube ;; 4) service=google ;;
        5) service=telegram ;; 6) service=mytvsuper ;; 7) service=appletv ;; 8) service=tiktok ;;
        9) service=custom ;;
        0) return 0 ;;
        *) return 1 ;;
    esac
    name=$(routing_service_name "$service")
    if [[ "$service" != "custom" ]] && routing_preset_rule_exists "$service"; then
        echo -e "${RED}[错误] ${name} 已存在分流规则。请先修改或删除现有规则，避免重复匹配。${PLAIN}"
        return 1
    fi
    if [[ "$service" == "custom" ]]; then
        echo "自定义匹配类型："
        echo "  1. 精确域名"
        echo "  2. 域名后缀"
        echo "  3. 域名关键字"
        echo "  4. IP / CIDR"
        read -rp "请选择 [1-4]: " c
        case "$c" in 1) custom_type=domain;; 2) custom_type=domain_suffix;; 3) custom_type=domain_keyword;; 4) custom_type=ip_cidr;; *) return 1;; esac
        read -rp "请输入匹配值（多个用英文逗号分隔）: " v
        values=$(printf '%s' "$v" | jq -R 'split(",")|map(gsub("^\\s+|\\s+$";""))|map(select(length>0))')
        [[ $(jq 'length' <<<"$values") -gt 0 ]] || return 1
        read -rp "规则名称 [默认: 自定义规则]: " name
        name=${name:-自定义规则}
    fi
    routing_choose_outbound "请选择该规则的实际出口：" || return 1
    routing_choose_ip_family || return 1
    id="r$(date +%s)${RANDOM}"
    rule=$(jq -nc --arg id "$id" --arg name "$name" --arg service "$service" --arg ctype "${custom_type:-}" --argjson vals "$values" --arg out "$SELECTED_OUTBOUND" --arg fam "$SELECTED_IP_FAMILY" '{id:$id,name:$name,service:$service,custom_type:$ctype,values:$vals,outbound:$out,ip_family:$fam}')
    tmp=$(mktemp "${STATE_DIR}/routing.json.tmp.XXXXXX") || return 1
    jq --argjson r "$rule" '.rules += [$r]' "$ROUTING_FILE" > "$tmp" || { rm -f "$tmp"; return 1; }
    routing_commit_state_candidate "$tmp" || return 1
    echo -e "${GREEN}✔ 分流规则已添加：${name} → $(routing_outbound_label "$SELECTED_OUTBOUND") / ${SELECTED_IP_FAMILY}${PLAIN}"
}

routing_list_rules() {
    routing_init_state || return 1
    local count i r
    count=$(jq '.rules|length' "$ROUTING_FILE")
    echo -e "${CYAN}════════════════ 当前分流规则 ════════════════${PLAIN}"
    printf '%-4s %-24s %-22s %-10s\n' "序号" "服务" "出口" "地址族"
    printf '%s\n' "----------------------------------------------------------------"
    if [[ $count -eq 0 ]]; then echo "暂无特殊规则；所有流量使用全局默认出口。"; fi
    i=0
    while [[ $i -lt $count ]]; do
        r=$(jq -c ".rules[$i]" "$ROUTING_FILE")
        printf '%-4s %-24s %-22s %-10s\n' "$((i+1))" "$(jq -r '.name' <<<"$r")" "$(routing_outbound_label "$(jq -r '.outbound' <<<"$r")")" "$(jq -r '.ip_family' <<<"$r")"
        i=$((i+1))
    done
    echo ""
    echo "默认出口: $(routing_outbound_label "$(jq -r '.default_outbound' "$ROUTING_FILE")")"
}

routing_select_rule_index() {
    local count c
    routing_init_state || return 1
    count=$(jq '.rules|length' "$ROUTING_FILE")
    [[ $count -gt 0 ]] || { echo "暂无分流规则。"; return 1; }
    routing_list_rules
    read -rp "请选择规则编号: " c
    [[ "$c" =~ ^[0-9]+$ && $c -ge 1 && $c -le $count ]] || return 1
    SELECTED_RULE_INDEX=$((c-1))
}

routing_modify_rule() {
    routing_select_rule_index || return 1
    local idx="$SELECTED_RULE_INDEX" c tmp service custom_type values v n
    service=$(jq -r ".rules[$idx].service" "$ROUTING_FILE")
    echo "  1. 修改出口"
    echo "  2. 修改 IP 地址族"
    echo "  3. 修改规则名称"
    if [[ "$service" == "custom" ]]; then echo "  4. 修改自定义匹配条件"; fi
    read -rp "请选择: " c
    tmp=$(mktemp "${STATE_DIR}/routing.json.tmp.XXXXXX") || return 1
    case "$c" in
        1)
            routing_choose_outbound "请选择新出口：" || { rm -f "$tmp"; return 1; }
            jq --argjson idx "$idx" --arg out "$SELECTED_OUTBOUND" '.rules[$idx].outbound=$out' "$ROUTING_FILE" > "$tmp" ;;
        2)
            routing_choose_ip_family || { rm -f "$tmp"; return 1; }
            jq --argjson idx "$idx" --arg fam "$SELECTED_IP_FAMILY" '.rules[$idx].ip_family=$fam' "$ROUTING_FILE" > "$tmp" ;;
        3)
            read -rp "新名称: " n; [[ -n "$n" ]] || { rm -f "$tmp"; return 1; }
            jq --argjson idx "$idx" --arg n "$n" '.rules[$idx].name=$n' "$ROUTING_FILE" > "$tmp" ;;
        4)
            [[ "$service" == "custom" ]] || { rm -f "$tmp"; return 1; }
            echo "自定义匹配类型："
            echo "  1. 精确域名"
            echo "  2. 域名后缀"
            echo "  3. 域名关键字"
            echo "  4. IP / CIDR"
            read -rp "请选择 [1-4]: " c
            case "$c" in 1) custom_type=domain;; 2) custom_type=domain_suffix;; 3) custom_type=domain_keyword;; 4) custom_type=ip_cidr;; *) rm -f "$tmp"; return 1;; esac
            read -rp "请输入匹配值（多个用英文逗号分隔）: " v
            values=$(printf '%s' "$v" | jq -R 'split(",")|map(gsub("^\\s+|\\s+$";""))|map(select(length>0))')
            [[ $(jq 'length' <<<"$values") -gt 0 ]] || { rm -f "$tmp"; return 1; }
            jq --argjson idx "$idx" --arg ctype "$custom_type" --argjson vals "$values" '.rules[$idx].custom_type=$ctype | .rules[$idx].values=$vals' "$ROUTING_FILE" > "$tmp" ;;
        *) rm -f "$tmp"; return 1 ;;
    esac
    routing_commit_state_candidate "$tmp"
}

routing_delete_rule() {
    routing_select_rule_index || return 1
    local idx="$SELECTED_RULE_INDEX" name tmp yes
    name=$(jq -r ".rules[$idx].name" "$ROUTING_FILE")
    read -rp "确认删除规则 ${name}？[y/N]: " yes
    [[ "$yes" =~ ^[Yy]$ ]] || return 0
    tmp=$(mktemp "${STATE_DIR}/routing.json.tmp.XXXXXX") || return 1
    jq --argjson idx "$idx" 'del(.rules[$idx])' "$ROUTING_FILE" > "$tmp" || { rm -f "$tmp"; return 1; }
    routing_commit_state_candidate "$tmp"
}

routing_move_rule() {
    routing_select_rule_index || return 1
    local idx="$SELECTED_RULE_INDEX" count c new tmp
    count=$(jq '.rules|length' "$ROUTING_FILE")
    echo "  1. 上移"
    echo "  2. 下移"
    read -rp "请选择 [1-2]: " c
    [[ "$c" == "1" && $idx -gt 0 ]] && new=$((idx-1))
    [[ "$c" == "2" && $idx -lt $((count-1)) ]] && new=$((idx+1))
    [[ -n "${new:-}" ]] || { echo "无法继续移动。"; return 1; }
    tmp=$(mktemp "${STATE_DIR}/routing.json.tmp.XXXXXX") || return 1
    jq --argjson a "$idx" --argjson b "$new" '.rules as $r | .rules[$a]=$r[$b] | .rules[$b]=$r[$a]' "$ROUTING_FILE" > "$tmp" || { rm -f "$tmp"; return 1; }
    routing_commit_state_candidate "$tmp"
}

routing_rule_management() {
    while true; do
        clear
        routing_list_rules
        echo ""
        echo "  1. 新增规则"
        echo "  2. 修改规则"
        echo "  3. 删除规则"
        echo "  4. 调整规则优先级"
        echo "  5. 设置全局默认出口"
        echo "  0. 返回"
        read -rp "请选择 [0-5]: " c
        case "$c" in
            1) routing_add_rule; pause ;;
            2) routing_modify_rule; pause ;;
            3) routing_delete_rule; pause ;;
            4) routing_move_rule; pause ;;
            5) routing_set_default_outbound; pause ;;
            0) return ;;
            *) sleep 1 ;;
        esac
    done
}

routing_show_config() {
    routing_init_state || return 1
    local def count i r
    echo -e "${CYAN}════════════════ 当前分流配置 ════════════════${PLAIN}"
    echo ""
    echo "【入口】"
    protocol_exists_singbox_tag "$TAG_SS" && echo "  SS2022                : 服务端分流 ✓" || echo "  SS2022                : 未部署"
    protocol_exists_singbox_tag "$TAG_STLS" && echo "  SS2022 + ShadowTLS     : 服务端分流 ✓" || echo "  SS2022 + ShadowTLS     : 未部署"
    xray_vless_exists && echo "  VLESS Reality          : 服务端分流 ✓" || echo "  VLESS Reality          : 未部署"
    protocol_exists_snell && echo "  Snell v5               : 官方 snell-server；服务端分流 —（请用 Surge Rules）" || echo "  Snell v5               : 未部署"
    echo ""
    echo "【默认出口】"
    def=$(jq -r '.default_outbound' "$ROUTING_FILE")
    echo "  $(routing_outbound_label "$def")"
    echo ""
    echo "【WARP】"
    if warp_proxy_ready; then echo "  Running / 127.0.0.1:$(warp_proxy_port)"; else echo "  未连接"; fi
    echo ""
    echo "【落地节点】"
    chain_list_nodes
    echo ""
    echo "【规则】"
    routing_list_rules
}

routing_test_exit_ref() {
    local ref="$1" family="${2:-default}" label out="" rc=1 url
    label=$(routing_outbound_label "$ref")
    url=$(ip_echo_url_for_family "$family")
    if [[ "$ref" == "direct" ]]; then
        if [[ "$family" == "ipv4" ]]; then out=$(curl -4fsS --connect-timeout 6 --max-time 10 "$url" 2>/dev/null) && rc=0
        elif [[ "$family" == "ipv6" ]]; then out=$(curl -6fsS --connect-timeout 6 --max-time 10 "$url" 2>/dev/null) && rc=0
        else out=$(curl -fsS --connect-timeout 6 --max-time 10 "$url" 2>/dev/null) && rc=0; fi
    elif [[ "$ref" == "warp" ]]; then
        if warp_proxy_ready; then
            out=$(curl -fsS --connect-timeout 8 --max-time 15 --socks5-hostname "127.0.0.1:$(warp_proxy_port)" "$url" 2>/dev/null) && rc=0
        fi
    elif [[ "$ref" == chain:* ]]; then
        local id=${ref#chain:} node type server sport user pass
        node=$(jq -c --arg id "$id" '.chain_nodes[]? | select(.id==$id)' "$ROUTING_FILE")
        [[ -n "$node" ]] || return 1
        type=$(jq -r '.type' <<<"$node")
        if [[ "$type" == "socks5" ]]; then
            server=$(jq -r '.server' <<<"$node"); sport=$(jq -r '.port' <<<"$node"); user=$(jq -r '.username // ""' <<<"$node"); pass=$(jq -r '.password // ""' <<<"$node")
            if [[ -n "$user" ]]; then out=$(curl -fsS --connect-timeout 8 --max-time 15 --proxy-user "${user}:${pass}" --socks5-hostname "${server}:${sport}" "$url" 2>/dev/null) && rc=0
            else out=$(curl -fsS --connect-timeout 8 --max-time 15 --socks5-hostname "${server}:${sport}" "$url" 2>/dev/null) && rc=0; fi
        else
            test_ss2022_node_with_singbox "$node" "$family" && return 0 || return 1
        fi
    fi
    if [[ $rc -eq 0 ]]; then echo -e "${GREEN}✔ ${label} / ${family}: ${out}${PLAIN}"; return 0; fi
    echo -e "${RED}✘ ${label} / ${family}: 测试失败${PLAIN}"; return 1
}

routing_test_effect() {
    routing_init_state || return 1
    echo -e "${CYAN}════════════════ 基础出口测试 ════════════════${PLAIN}"
    routing_test_exit_ref direct ipv4 || true
    if ip -6 route show default 2>/dev/null | grep -q default; then routing_test_exit_ref direct ipv6 || true; fi
    command -v warp-cli >/dev/null 2>&1 && routing_test_exit_ref warp default || true
    local count i id rule_count r ref fam key tested='|'
    count=$(jq '.chain_nodes|length' "$ROUTING_FILE")
    i=0
    while [[ $i -lt $count ]]; do id=$(jq -r ".chain_nodes[$i].id" "$ROUTING_FILE"); routing_test_exit_ref "chain:${id}" default || true; i=$((i+1)); done

    echo ""
    echo -e "${CYAN}════════════════ 规则出口验证 ════════════════${PLAIN}"
    rule_count=$(jq '.rules|length' "$ROUTING_FILE")
    if [[ $rule_count -eq 0 ]]; then
        echo "暂无特殊规则；未命中规则的流量使用全局默认出口：$(routing_outbound_label "$(jq -r '.default_outbound' "$ROUTING_FILE")")"
    else
        i=0
        while [[ $i -lt $rule_count ]]; do
            r=$(jq -c ".rules[$i]" "$ROUTING_FILE")
            ref=$(jq -r '.outbound' <<<"$r")
            fam=$(jq -r '.ip_family // "default"' <<<"$r")
            key="${ref}@${fam}"
            echo "$(jq -r '.name' <<<"$r") → $(routing_outbound_label "$ref") / ${fam}"
            if [[ "$tested" != *"|${key}|"* ]]; then
                routing_test_exit_ref "$ref" "$fam" || true
                tested+="${key}|"
            else
                echo "  （同一出口/地址族已在上方验证）"
            fi
            i=$((i+1))
        done
    fi
    echo ""
    echo -e "${YELLOW}[说明] 规则出口验证会验证“目标出口 + 地址族”是否可用；服务域名匹配仍以运行时规则命中为准。${PLAIN}"
    echo -e "${YELLOW}WARP Local Proxy 为应用层代理；QUIC/UDP 不作为 v1.8.0-dev1 的 WARP 分流保证范围。${PLAIN}"
}

routing_management() {
    while true; do
        clear
        routing_init_state || return
        local def count rules warp_state="未连接"
        def=$(jq -r '.default_outbound' "$ROUTING_FILE")
        count=$(jq '.chain_nodes|length' "$ROUTING_FILE")
        rules=$(jq '.rules|length' "$ROUTING_FILE")
        warp_proxy_ready && warp_state="Running"
        echo -e "${CYAN}════════════════════ 分流管理 ════════════════════${PLAIN}"
        echo "服务端分流适用：SS2022 / SS2022+ShadowTLS / VLESS Reality"
        echo "Snell v5：保持官方 snell-server，分流请使用 Surge Rules"
        echo ""
        echo "默认出口 : $(routing_outbound_label "$def")"
        echo "WARP     : ${warp_state}"
        echo "落地节点 : ${count} 个"
        echo "规则     : ${rules} 条"
        echo ""
        echo "  1. WARP 出口管理"
        echo "  2. 链式代理管理"
        echo "  3. 分流规则管理"
        echo "  4. 查看当前分流配置"
        echo "  5. 测试分流效果"
        echo "  0. 返回"
        echo -e "${CYAN}══════════════════════════════════════════════════${PLAIN}"
        read -rp "请选择 [0-5]: " c
        case "$c" in
            1) warp_management ;;
            2) chain_management ;;
            3) routing_rule_management ;;
            4) routing_show_config; pause ;;
            5) routing_test_effect; pause ;;
            0) return ;;
            *) sleep 1 ;;
        esac
    done
}



# ==============================================================================
# v1.8.0-dev2 Realm L4 端口转发模块
# - 只保留核心端口转发：单端口 / 端口段、TCP / UDP / TCP+UDP、IPv4 / IPv6 / 双栈
# - 不启用 MPTCP / TLS / WS / WSS / Proxy Protocol / 负载均衡 / 故障转移
# - 独立命名空间，避免覆盖服务器已有 realm.service / /usr/local/bin/realm
# ==============================================================================

ensure_realm_user() {
    local nologin_shell=""
    if getent group "$REALM_GROUP" >/dev/null 2>&1; then
        :
    else
        groupadd --system "$REALM_GROUP" || return 1
    fi

    if id -u "$REALM_USER" >/dev/null 2>&1; then
        if ! id -nG "$REALM_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$REALM_GROUP"; then
            usermod -a -G "$REALM_GROUP" "$REALM_USER" || return 1
        fi
        return 0
    fi

    nologin_shell=$(command -v nologin 2>/dev/null || true)
    nologin_shell=${nologin_shell:-/usr/sbin/nologin}
    useradd --system --gid "$REALM_GROUP" --no-create-home --home-dir /nonexistent --shell "$nologin_shell" "$REALM_USER" || return 1
    touch "$REALM_USER_MARKER"
    chmod 600 "$REALM_USER_MARKER"
    return 0
}

write_realm_service() {
    ensure_realm_user || return 1
    mkdir -p "$(dirname "$REALM_CONF")" "$(dirname "$REALM_BIN")" || return 1

    cat > "$REALM_SERVICE" <<SERVICE
[Unit]
Description=ss2022.sh managed Realm L4 forwarding service
Documentation=https://github.com/zhboner/realm
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=${REALM_USER}
Group=${REALM_GROUP}
ExecStart=${REALM_BIN} -c ${REALM_CONF}
Restart=on-failure
RestartSec=3s
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
    return 0
}

forwarding_init_state() {
    mkdir -p "$STATE_DIR" || return 1
    chmod 700 "$STATE_DIR"
    if [[ ! -f "$FORWARDING_FILE" ]]; then
        cat > "$FORWARDING_FILE" <<'EOF'
{
  "version": 1,
  "rules": []
}
EOF
        chmod 600 "$FORWARDING_FILE"
        return 0
    fi

    if ! jq -e 'type=="object" and ((.rules // [])|type=="array")' "$FORWARDING_FILE" >/dev/null 2>&1; then
        echo -e "${RED}[错误] ${FORWARDING_FILE} 格式损坏，请先备份后修复。${PLAIN}"
        return 1
    fi

    local tmp=""
    tmp=$(mktemp "${STATE_DIR}/forwarding.json.tmp.XXXXXX") || return 1
    if ! jq '.version=(.version // 1) | .rules=(.rules // [])' "$FORWARDING_FILE" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    mv -f "$tmp" "$FORWARDING_FILE"
    chmod 600 "$FORWARDING_FILE"
}

realm_asset_name() {
    case "$(uname -m)" in
        x86_64|amd64) echo "realm-x86_64-unknown-linux-musl.tar.gz" ;;
        aarch64|arm64) echo "realm-aarch64-unknown-linux-musl.tar.gz" ;;
        *) return 1 ;;
    esac
}

realm_fetch_asset_metadata() {
    local asset="$1" api tmp expected url
    api="https://api.github.com/repos/zhboner/realm/releases/tags/v${REALM_VERSION}"
    tmp=$(mktemp) || return 1

    if ! curl -fsSL --retry 2 --connect-timeout 10 --max-time 30 \
        -H 'Accept: application/vnd.github+json' "$api" -o "$tmp"; then
        rm -f "$tmp"
        return 1
    fi

    url=$(jq -r --arg a "$asset" '.assets[]? | select(.name==$a) | .browser_download_url // empty' "$tmp" | head -n1)
    expected=$(jq -r --arg a "$asset" '.assets[]? | select(.name==$a) | .digest // empty' "$tmp" | head -n1)
    rm -f "$tmp"

    expected=${expected#sha256:}
    [[ -n "$url" && "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || return 1
    printf '%s\t%s\n' "$url" "$expected"
}

install_realm_core() {
    install_dependencies || return 1

    local asset="" metadata="" url="" expected="" archive="" actual="" tmpdir="" src="" download_url=""
    asset=$(realm_asset_name) || {
        echo -e "${RED}[错误] Realm 当前仅支持 x86_64 / aarch64 Linux。${PLAIN}"
        return 1
    }

    echo -e "${YELLOW}>> 获取 Realm v${REALM_VERSION} 官方 Release 校验信息...${PLAIN}"
    metadata=$(realm_fetch_asset_metadata "$asset") || {
        echo -e "${RED}[错误] 无法从 GitHub 官方 Release 获取 ${asset} 的 SHA256 digest，拒绝不校验安装。${PLAIN}"
        return 1
    }
    url=${metadata%%$'\t'*}
    expected=${metadata#*$'\t'}

    archive="/tmp/${asset}"
    rm -f "$archive"
    local sources=(
        "$url"
        "https://ghproxy.net/${url}"
        "https://gh-proxy.com/${url}"
        "https://ghps.cc/${url}"
    )

    local ok=0
    for download_url in "${sources[@]}"; do
        echo -e "   尝试下载: ${CYAN}${download_url}${PLAIN}"
        rm -f "$archive"
        if ! curl -fL --retry 2 --retry-delay 1 --connect-timeout 10 --max-time 120 "$download_url" -o "$archive"; then
            echo -e "${YELLOW}   下载失败，尝试下一个源。${PLAIN}"
            continue
        fi
        actual=$(sha256sum "$archive" | awk '{print $1}')
        if [[ "${actual,,}" != "${expected,,}" ]]; then
            echo -e "${RED}   SHA256 校验失败，拒绝安装。${PLAIN}"
            echo "   期望: $expected"
            echo "   实际: $actual"
            continue
        fi
        if ! tar -tzf "$archive" >/dev/null 2>&1; then
            echo -e "${RED}   Realm 压缩包结构无效。${PLAIN}"
            continue
        fi
        if tar -tzf "$archive" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
            echo -e "${RED}   Realm 压缩包包含不安全路径，拒绝解压。${PLAIN}"
            continue
        fi
        ok=1
        break
    done
    [[ $ok -eq 1 ]] || { rm -f "$archive"; return 1; }

    tmpdir=$(mktemp -d) || { rm -f "$archive"; return 1; }
    tar -xzf "$archive" -C "$tmpdir" || { rm -rf "$tmpdir" "$archive"; return 1; }
    src=$(find "$tmpdir" -type f -name realm -perm -u+x -print -quit 2>/dev/null || true)
    if [[ -z "$src" ]]; then
        src=$(find "$tmpdir" -type f -name realm -print -quit 2>/dev/null || true)
    fi
    [[ -n "$src" ]] || {
        echo -e "${RED}[错误] Realm 压缩包中未找到二进制。${PLAIN}"
        rm -rf "$tmpdir" "$archive"
        return 1
    }

    mkdir -p "$(dirname "$REALM_BIN")"
    install -m 0755 "$src" "$REALM_BIN" || { rm -rf "$tmpdir" "$archive"; return 1; }
    rm -rf "$tmpdir" "$archive"

    local installed_version=""
    installed_version=$("$REALM_BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)
    if [[ "$installed_version" != "$REALM_VERSION" ]]; then
        echo -e "${RED}[错误] Realm 安装后版本校验失败：期望 ${REALM_VERSION}，实际 ${installed_version:-未知}。${PLAIN}"
        rm -f "$REALM_BIN"
        return 1
    fi

    write_realm_service || return 1
    echo -e "${GREEN}✔ Realm v${REALM_VERSION} 已安装并通过 SHA256/版本校验。${PLAIN}"
}

forwarding_format_host_port() {
    local host="$1" port="$2"
    host=${host#[}
    host=${host%]}
    if [[ "$host" == *:* ]]; then
        printf '[%s]:%s' "$host" "$port"
    else
        printf '%s:%s' "$host" "$port"
    fi
}

forwarding_network_json() {
    local proto="$1" ipv6_only="${2:-false}"
    case "$proto" in
        tcp) jq -nc --argjson v6 "$ipv6_only" '{no_tcp:false,use_udp:false,ipv6_only:$v6}' ;;
        udp) jq -nc --argjson v6 "$ipv6_only" '{no_tcp:true,use_udp:true,ipv6_only:$v6}' ;;
        both) jq -nc --argjson v6 "$ipv6_only" '{no_tcp:false,use_udp:true,ipv6_only:$v6}' ;;
        *) return 1 ;;
    esac
}

realm_build_config_from_state() {
    local state="$1" out="$2"
    [[ -f "$state" ]] || return 1

    local endpoints='[]' rule="" id="" type="" family="" proto="" host=""
    local lport="" rport="" lstart="" lend="" rstart="" p="" rp=""
    local remote="" network="" ep="" listen=""
    while IFS= read -r rule; do
        [[ -n "$rule" ]] || continue
        id=$(jq -r '.id' <<<"$rule")
        type=$(jq -r '.type' <<<"$rule")
        family=$(jq -r '.listen_family' <<<"$rule")
        proto=$(jq -r '.protocol' <<<"$rule")
        host=$(jq -r '.remote_host' <<<"$rule")

        if [[ "$type" == "single" ]]; then
            lstart=$(jq -r '.listen_port' <<<"$rule")
            lend="$lstart"
            rstart=$(jq -r '.remote_port' <<<"$rule")
        else
            lstart=$(jq -r '.listen_start' <<<"$rule")
            lend=$(jq -r '.listen_end' <<<"$rule")
            rstart=$(jq -r '.remote_start' <<<"$rule")
        fi

        p="$lstart"
        while [[ "$p" -le "$lend" ]]; do
            rp=$((rstart + p - lstart))
            remote=$(forwarding_format_host_port "$host" "$rp")

            case "$family" in
                ipv4)
                    listen="0.0.0.0:${p}"
                    network=$(forwarding_network_json "$proto" false) || return 1
                    ep=$(jq -nc --arg l "$listen" --arg r "$remote" --argjson n "$network" --arg id "$id" \
                        '{listen:$l,remote:$r,network:$n}')
                    endpoints=$(jq -nc --argjson a "$endpoints" --argjson e "$ep" '$a + [$e]')
                    ;;
                ipv6)
                    listen="[::]:${p}"
                    network=$(forwarding_network_json "$proto" true) || return 1
                    ep=$(jq -nc --arg l "$listen" --arg r "$remote" --argjson n "$network" --arg id "$id" \
                        '{listen:$l,remote:$r,network:$n}')
                    endpoints=$(jq -nc --argjson a "$endpoints" --argjson e "$ep" '$a + [$e]')
                    ;;
                dual)
                    # Realm 官方语义：[::]:port + ipv6_only=false 会同时接受 IPv6 与 IPv4-mapped IPv6，
                    # 因此双栈只生成一个 endpoint，避免同端口重复 bind。
                    listen="[::]:${p}"
                    network=$(forwarding_network_json "$proto" false) || return 1
                    ep=$(jq -nc --arg l "$listen" --arg r "$remote" --argjson n "$network" --arg id "$id" \
                        '{listen:$l,remote:$r,network:$n}')
                    endpoints=$(jq -nc --argjson a "$endpoints" --argjson e "$ep" '$a + [$e]')
                    ;;
                *) return 1 ;;
            esac
            p=$((p+1))
        done
    done < <(jq -c '.rules[]?' "$state")

    jq -n --argjson eps "$endpoints" '{
      log:{level:"warn",output:"stdout"},
      network:{
        no_tcp:false,
        use_udp:false,
        tcp_timeout:5,
        udp_timeout:30,
        tcp_keepalive:15,
        tcp_keepalive_probe:3
      },
      endpoints:$eps
    }' > "$out"
    jq -e '.endpoints|type=="array"' "$out" >/dev/null 2>&1
}

forwarding_rule_interval() {
    local rule="$1"
    if [[ "$(jq -r '.type' <<<"$rule")" == "single" ]]; then
        printf '%s %s\n' "$(jq -r '.listen_port' <<<"$rule")" "$(jq -r '.listen_port' <<<"$rule")"
    else
        printf '%s %s\n' "$(jq -r '.listen_start' <<<"$rule")" "$(jq -r '.listen_end' <<<"$rule")"
    fi
}

forwarding_state_port_conflict() {
    local start="$1" end="$2" exclude_id="${3:-}" rule="" s="" e=""
    while IFS= read -r rule; do
        [[ -n "$rule" ]] || continue
        [[ -n "$exclude_id" && "$(jq -r '.id' <<<"$rule")" == "$exclude_id" ]] && continue
        read -r s e < <(forwarding_rule_interval "$rule")
        if (( start <= e && end >= s )); then
            return 0
        fi
    done < <(jq -c '.rules[]?' "$FORWARDING_FILE")
    return 1
}

forwarding_os_port_conflict_range() {
    local start="$1" end="$2" allowed_pid=""
    allowed_pid=$(systemctl show -p MainPID --value "$REALM_SERVICE_NAME" 2>/dev/null || true)
    local p lines conflicts
    lines=$(ss -H -lntup 2>/dev/null || true)
    p="$start"
    while [[ "$p" -le "$end" ]]; do
        conflicts=$(printf '%s\n' "$lines" | awk -v p="$p" '
          {
            addr=$5; n=split(addr,a,":");
            if (a[n] == p) print
          }')
        if [[ -n "$conflicts" && "$allowed_pid" =~ ^[0-9]+$ && "$allowed_pid" -gt 0 ]]; then
            conflicts=$(printf '%s\n' "$conflicts" | grep -v "pid=${allowed_pid}," || true)
        fi
        if [[ -n "$conflicts" ]]; then
            echo -e "${RED}[错误] 端口 ${p} 已被其他进程占用：${PLAIN}"
            printf '%s\n' "$conflicts"
            return 0
        fi
        p=$((p+1))
    done
    return 1
}

forwarding_apply_state_candidate() {
    local candidate="$1" cfg_tmp="" state_backup="" cfg_backup="" old_count=0 new_count=0
    [[ -f "$candidate" ]] || return 1
    jq -e 'type=="object" and (.rules|type=="array")' "$candidate" >/dev/null 2>&1 || {
        rm -f "$candidate"
        return 1
    }

    new_count=$(jq '.rules|length' "$candidate")
    if [[ "$new_count" -gt 0 && ! -x "$REALM_BIN" ]]; then
        install_realm_core || { rm -f "$candidate"; return 1; }
    fi
    [[ "$new_count" -eq 0 ]] || write_realm_service || { rm -f "$candidate"; return 1; }

    mkdir -p /etc/ss2022-realm || { rm -f "$candidate"; return 1; }
    cfg_tmp=$(mktemp "/etc/ss2022-realm/config.json.tmp.XXXXXX") || { rm -f "$candidate"; return 1; }
    if ! realm_build_config_from_state "$candidate" "$cfg_tmp"; then
        rm -f "$candidate" "$cfg_tmp"
        echo -e "${RED}[错误] Realm 配置生成失败。${PLAIN}"
        return 1
    fi

    state_backup=$(mktemp "${STATE_DIR}/forwarding.rollback.XXXXXX") || { rm -f "$candidate" "$cfg_tmp"; return 1; }
    cp -a "$FORWARDING_FILE" "$state_backup" || { rm -f "$candidate" "$cfg_tmp" "$state_backup"; return 1; }
    old_count=$(jq '.rules|length' "$state_backup" 2>/dev/null || echo 0)

    mkdir -p "$(dirname "$REALM_CONF")"
    if [[ -f "$REALM_CONF" ]]; then
        cfg_backup=$(mktemp "/etc/ss2022-realm/config.rollback.XXXXXX") || { rm -f "$candidate" "$cfg_tmp" "$state_backup"; return 1; }
        cp -a "$REALM_CONF" "$cfg_backup"
    fi

    mv -f "$candidate" "$FORWARDING_FILE"
    chmod 600 "$FORWARDING_FILE"
    mv -f "$cfg_tmp" "$REALM_CONF"
    chmod 600 "$REALM_CONF"

    if [[ "$new_count" -eq 0 ]]; then
        systemctl disable --now "$REALM_SERVICE_NAME" >/dev/null 2>&1 || true
        rm -f "$state_backup" "$cfg_backup"
        echo -e "${GREEN}✔ Realm 转发规则已清空，服务已停止。${PLAIN}"
        return 0
    fi

    systemctl daemon-reload || true
    systemctl enable "$REALM_SERVICE_NAME" >/dev/null 2>&1 || true
    if systemctl restart "$REALM_SERVICE_NAME" && sleep 1 && systemctl is-active --quiet "$REALM_SERVICE_NAME"; then
        rm -f "$state_backup" "$cfg_backup"
        echo -e "${GREEN}✔ Realm 转发配置已应用。${PLAIN}"
        return 0
    fi

    echo -e "${RED}[错误] Realm 新配置启动失败，正在恢复旧配置和旧规则...${PLAIN}"
    mv -f "$state_backup" "$FORWARDING_FILE"
    if [[ -n "$cfg_backup" && -f "$cfg_backup" ]]; then
        mv -f "$cfg_backup" "$REALM_CONF"
    else
        rm -f "$REALM_CONF"
    fi
    if [[ "$old_count" -gt 0 ]]; then
        systemctl restart "$REALM_SERVICE_NAME" >/dev/null 2>&1 || true
    else
        systemctl disable --now "$REALM_SERVICE_NAME" >/dev/null 2>&1 || true
    fi
    journalctl -u "$REALM_SERVICE_NAME" -n 30 --no-pager 2>/dev/null || true
    return 1
}

forwarding_choose_family() {
    local default="${1:-ipv4}" c=""
    echo "请选择监听网络：" >&2
    echo "  1. IPv4" >&2
    echo "  2. IPv6" >&2
    echo "  3. 双栈 IPv4 + IPv6" >&2
    local d=1
    [[ "$default" == "ipv6" ]] && d=2
    [[ "$default" == "dual" ]] && d=3
    read -rp "请选择 [1-3，默认 ${d}]: " c
    c=${c:-$d}
    case "$c" in
        1) echo ipv4 ;;
        2) echo ipv6 ;;
        3) echo dual ;;
        *) return 1 ;;
    esac
}

forwarding_choose_protocol() {
    local default="${1:-both}" c=""
    echo "请选择转发协议：" >&2
    echo "  1. TCP" >&2
    echo "  2. UDP" >&2
    echo "  3. TCP + UDP" >&2
    local d=3
    [[ "$default" == "tcp" ]] && d=1
    [[ "$default" == "udp" ]] && d=2
    read -rp "请选择 [1-3，默认 ${d}]: " c
    c=${c:-$d}
    case "$c" in
        1) echo tcp ;;
        2) echo udp ;;
        3) echo both ;;
        *) return 1 ;;
    esac
}

forwarding_sanitize_host() {
    local h="$1"
    h=${h#[}
    h=${h%]}
    [[ -n "$h" && "$h" != *[[:space:]]* ]] || return 1
    printf '%s' "$h"
}

forwarding_next_name() {
    local base="$1" name="" n=2
    name="$base"
    while jq -e --arg n "$name" '.rules[]? | select(.name==$n)' "$FORWARDING_FILE" >/dev/null 2>&1; do
        name="${base}-${n}"
        n=$((n+1))
    done
    echo "$name"
}

forwarding_add_single() {
    forwarding_init_state || return
    local port="" rhost="" rport="" family="" proto="" name="" candidate="" id=""
    while true; do
        read -rp "本机监听端口: " port
        validate_port_number "$port" && break
        echo -e "${RED}端口必须为 1-65535。${PLAIN}"
    done

    if forwarding_state_port_conflict "$port" "$port"; then
        echo -e "${RED}[错误] 端口 ${port} 已存在 Realm 转发规则。${PLAIN}"
        pause; return
    fi
    if forwarding_os_port_conflict_range "$port" "$port"; then
        pause; return
    fi

    family=$(forwarding_choose_family ipv4) || { echo "无效选择"; pause; return; }
    proto=$(forwarding_choose_protocol both) || { echo "无效选择"; pause; return; }

    while true; do
        read -rp "目标服务器 IP/域名: " rhost
        rhost=$(forwarding_sanitize_host "$rhost" 2>/dev/null || true)
        [[ -n "$rhost" ]] && break
        echo -e "${RED}目标地址不能为空或包含空格。${PLAIN}"
    done
    while true; do
        read -rp "目标端口 [默认: ${port}]: " rport
        rport=${rport:-$port}
        validate_port_number "$rport" && break
        echo -e "${RED}目标端口必须为 1-65535。${PLAIN}"
    done

    read -rp "规则备注 [默认: PF-${port}]: " name
    name=${name:-"PF-${port}"}
    name=$(forwarding_next_name "$name")
    id="pf-$(date +%s)-${RANDOM}"

    echo ""
    echo "确认添加：${name}"
    echo "  监听 : ${family} / ${port}"
    echo "  目标 : ${rhost}:${rport}"
    echo "  协议 : ${proto}"
    local yes=""
    read -rp "确认？[Y/n]: " yes
    [[ ! "$yes" =~ ^[Nn]$ ]] || return

    candidate=$(mktemp "${STATE_DIR}/forwarding.candidate.XXXXXX") || return
    if ! jq \
        --arg id "$id" --arg name "$name" --arg family "$family" --arg proto "$proto" \
        --arg host "$rhost" --argjson lp "$port" --argjson rp "$rport" \
        '.rules += [{id:$id,name:$name,type:"single",listen_family:$family,protocol:$proto,listen_port:$lp,remote_host:$host,remote_port:$rp}]' \
        "$FORWARDING_FILE" > "$candidate"; then
        rm -f "$candidate"; return
    fi
    forwarding_apply_state_candidate "$candidate"
    pause
}

forwarding_add_range() {
    forwarding_init_state || return
    local start="" end="" rhost="" rstart="" rend="" family="" proto="" name="" candidate="" id="" count=""
    while true; do
        read -rp "本机起始端口: " start
        validate_port_number "$start" && break
        echo -e "${RED}端口必须为 1-65535。${PLAIN}"
    done
    while true; do
        read -rp "本机结束端口: " end
        if validate_port_number "$end" && [[ "$end" -ge "$start" ]]; then break; fi
        echo -e "${RED}结束端口必须 >= 起始端口且 <= 65535。${PLAIN}"
    done
    count=$((end-start+1))
    if [[ "$count" -gt "$REALM_MAX_RANGE_PORTS" ]]; then
        echo -e "${RED}[错误] 单条端口段最多 ${REALM_MAX_RANGE_PORTS} 个端口。${PLAIN}"
        pause; return
    fi
    if forwarding_state_port_conflict "$start" "$end"; then
        echo -e "${RED}[错误] ${start}-${end} 与现有 Realm 转发规则端口重叠。${PLAIN}"
        pause; return
    fi
    if forwarding_os_port_conflict_range "$start" "$end"; then
        pause; return
    fi

    family=$(forwarding_choose_family ipv4) || { echo "无效选择"; pause; return; }
    proto=$(forwarding_choose_protocol both) || { echo "无效选择"; pause; return; }

    while true; do
        read -rp "目标服务器 IP/域名: " rhost
        rhost=$(forwarding_sanitize_host "$rhost" 2>/dev/null || true)
        [[ -n "$rhost" ]] && break
        echo -e "${RED}目标地址不能为空或包含空格。${PLAIN}"
    done
    while true; do
        read -rp "目标起始端口 [默认: ${start}]: " rstart
        rstart=${rstart:-$start}
        if validate_port_number "$rstart"; then
            rend=$((rstart+count-1))
            [[ "$rend" -le 65535 ]] && break
        fi
        echo -e "${RED}目标端口段必须落在 1-65535。${PLAIN}"
    done

    read -rp "规则备注 [默认: PF-${start}-${end}]: " name
    name=${name:-"PF-${start}-${end}"}
    name=$(forwarding_next_name "$name")
    id="pf-$(date +%s)-${RANDOM}"

    echo ""
    echo "确认添加：${name}"
    echo "  监听 : ${family} / ${start}-${end}"
    echo "  目标 : ${rhost}:${rstart}-${rend}"
    echo "  协议 : ${proto}"
    local yes=""
    read -rp "确认？[Y/n]: " yes
    [[ ! "$yes" =~ ^[Nn]$ ]] || return

    candidate=$(mktemp "${STATE_DIR}/forwarding.candidate.XXXXXX") || return
    if ! jq \
        --arg id "$id" --arg name "$name" --arg family "$family" --arg proto "$proto" \
        --arg host "$rhost" --argjson ls "$start" --argjson le "$end" --argjson rs "$rstart" \
        '.rules += [{id:$id,name:$name,type:"range",listen_family:$family,protocol:$proto,listen_start:$ls,listen_end:$le,remote_host:$host,remote_start:$rs}]' \
        "$FORWARDING_FILE" > "$candidate"; then
        rm -f "$candidate"; return
    fi
    forwarding_apply_state_candidate "$candidate"
    pause
}

forwarding_print_rules() {
    forwarding_init_state || return 1
    local count="" i=0 r="" type="" ports="" remote="" rstart="" rend="" lstart="" lend=""
    count=$(jq '.rules|length' "$FORWARDING_FILE")
    if [[ "$count" -eq 0 ]]; then
        echo "暂无 Realm 转发规则。"
        return 0
    fi
    printf "%-4s %-22s %-9s %-7s %-15s %s\n" "序号" "备注" "监听" "协议" "本机端口" "目标"
    echo "------------------------------------------------------------------------------------------------"
    while [[ "$i" -lt "$count" ]]; do
        r=$(jq -c ".rules[$i]" "$FORWARDING_FILE")
        type=$(jq -r '.type' <<<"$r")
        if [[ "$type" == "single" ]]; then
            ports=$(jq -r '.listen_port|tostring' <<<"$r")
            remote="$(jq -r '.remote_host' <<<"$r"):$(jq -r '.remote_port' <<<"$r")"
        else
            lstart=$(jq -r '.listen_start' <<<"$r"); lend=$(jq -r '.listen_end' <<<"$r")
            rstart=$(jq -r '.remote_start' <<<"$r"); rend=$((rstart+lend-lstart))
            ports="${lstart}-${lend}"
            remote="$(jq -r '.remote_host' <<<"$r"):${rstart}-${rend}"
        fi
        printf "%-4s %-22s %-9s %-7s %-15s %s\n" \
            "$((i+1))" "$(jq -r '.name' <<<"$r")" "$(jq -r '.listen_family' <<<"$r")" \
            "$(jq -r '.protocol' <<<"$r")" "$ports" "$remote"
        i=$((i+1))
    done
}

forwarding_select_rule_index() {
    forwarding_print_rules >&2
    local count="" c=""
    count=$(jq '.rules|length' "$FORWARDING_FILE")
    [[ "$count" -gt 0 ]] || return 1
    read -rp "请选择规则序号 [1-${count}]: " c
    [[ "$c" =~ ^[0-9]+$ && "$c" -ge 1 && "$c" -le "$count" ]] || return 1
    echo $((c-1))
}

forwarding_edit_rule() {
    forwarding_init_state || return
    local idx="" rule="" id="" c="" candidate="" new="" old_start="" old_end="" start="" end="" rstart="" count="" rend=""
    idx=$(forwarding_select_rule_index) || { echo "无效选择。"; pause; return; }
    rule=$(jq -c ".rules[$idx]" "$FORWARDING_FILE")
    id=$(jq -r '.id' <<<"$rule")

    while true; do
        clear
        rule=$(jq -c --arg id "$id" '.rules[] | select(.id==$id)' "$FORWARDING_FILE")
        [[ -n "$rule" ]] || return
        echo -e "${CYAN}════════════════════ 修改转发规则 ════════════════════${PLAIN}"
        echo "备注 : $(jq -r '.name' <<<"$rule")"
        echo "监听 : $(jq -r '.listen_family' <<<"$rule")"
        echo "协议 : $(jq -r '.protocol' <<<"$rule")"
        if [[ "$(jq -r '.type' <<<"$rule")" == "single" ]]; then
            echo "端口 : $(jq -r '.listen_port' <<<"$rule") → $(jq -r '.remote_host' <<<"$rule"):$(jq -r '.remote_port' <<<"$rule")"
        else
            old_start=$(jq -r '.listen_start' <<<"$rule"); old_end=$(jq -r '.listen_end' <<<"$rule")
            rstart=$(jq -r '.remote_start' <<<"$rule"); rend=$((rstart+old_end-old_start))
            echo "端口 : ${old_start}-${old_end} → $(jq -r '.remote_host' <<<"$rule"):${rstart}-${rend}"
        fi
        echo ""
        echo "  1. 修改备注"
        echo "  2. 修改监听网络"
        echo "  3. 修改转发协议"
        echo "  4. 修改目标服务器/目标端口"
        echo "  5. 修改本机监听端口/端口段"
        echo "  0. 返回"
        read -rp "请选择 [0-5]: " c
        [[ "$c" == "0" ]] && return

        candidate=$(mktemp "${STATE_DIR}/forwarding.candidate.XXXXXX") || return
        case "$c" in
            1)
                read -rp "新备注: " new
                [[ -n "$new" ]] || { rm -f "$candidate"; continue; }
                jq --arg id "$id" --arg v "$new" '(.rules[]|select(.id==$id)|.name)=$v' "$FORWARDING_FILE" > "$candidate"
                ;;
            2)
                new=$(forwarding_choose_family "$(jq -r '.listen_family' <<<"$rule")") || { rm -f "$candidate"; continue; }
                jq --arg id "$id" --arg v "$new" '(.rules[]|select(.id==$id)|.listen_family)=$v' "$FORWARDING_FILE" > "$candidate"
                ;;
            3)
                new=$(forwarding_choose_protocol "$(jq -r '.protocol' <<<"$rule")") || { rm -f "$candidate"; continue; }
                jq --arg id "$id" --arg v "$new" '(.rules[]|select(.id==$id)|.protocol)=$v' "$FORWARDING_FILE" > "$candidate"
                ;;
            4)
                local nhost="" nr=""
                read -rp "目标服务器 IP/域名 [当前: $(jq -r '.remote_host' <<<"$rule")]: " nhost
                nhost=${nhost:-$(jq -r '.remote_host' <<<"$rule")}
                nhost=$(forwarding_sanitize_host "$nhost" 2>/dev/null || true)
                [[ -n "$nhost" ]] || { rm -f "$candidate"; continue; }
                if [[ "$(jq -r '.type' <<<"$rule")" == "single" ]]; then
                    nr=$(jq -r '.remote_port' <<<"$rule")
                    read -rp "目标端口 [当前: ${nr}]: " new
                    new=${new:-$nr}
                    validate_port_number "$new" || { rm -f "$candidate"; continue; }
                    jq --arg id "$id" --arg h "$nhost" --argjson p "$new" \
                        '(.rules[]|select(.id==$id)|.remote_host)=$h | (.rules[]|select(.id==$id)|.remote_port)=$p' \
                        "$FORWARDING_FILE" > "$candidate"
                else
                    nr=$(jq -r '.remote_start' <<<"$rule")
                    count=$(( $(jq -r '.listen_end' <<<"$rule") - $(jq -r '.listen_start' <<<"$rule") + 1 ))
                    read -rp "目标起始端口 [当前: ${nr}]: " new
                    new=${new:-$nr}
                    validate_port_number "$new" || { rm -f "$candidate"; continue; }
                    [[ $((new+count-1)) -le 65535 ]] || { echo "目标端口段越界。"; rm -f "$candidate"; pause; continue; }
                    jq --arg id "$id" --arg h "$nhost" --argjson p "$new" \
                        '(.rules[]|select(.id==$id)|.remote_host)=$h | (.rules[]|select(.id==$id)|.remote_start)=$p' \
                        "$FORWARDING_FILE" > "$candidate"
                fi
                ;;
            5)
                read -r old_start old_end < <(forwarding_rule_interval "$rule")
                if [[ "$(jq -r '.type' <<<"$rule")" == "single" ]]; then
                    read -rp "新监听端口 [当前: ${old_start}]: " start
                    start=${start:-$old_start}
                    validate_port_number "$start" || { rm -f "$candidate"; continue; }
                    end="$start"
                else
                    read -rp "新起始端口 [当前: ${old_start}]: " start
                    start=${start:-$old_start}
                    read -rp "新结束端口 [当前: ${old_end}]: " end
                    end=${end:-$old_end}
                    if ! validate_port_number "$start" || ! validate_port_number "$end" || [[ "$end" -lt "$start" ]]; then
                        rm -f "$candidate"; continue
                    fi
                    count=$((end-start+1))
                    [[ "$count" -le "$REALM_MAX_RANGE_PORTS" ]] || { echo "端口段过大。"; rm -f "$candidate"; pause; continue; }
                fi
                if forwarding_state_port_conflict "$start" "$end" "$id"; then
                    echo "与其他 Realm 转发规则端口重叠。"; rm -f "$candidate"; pause; continue
                fi
                if [[ "$start" != "$old_start" || "$end" != "$old_end" ]] && forwarding_os_port_conflict_range "$start" "$end"; then
                    rm -f "$candidate"; pause; continue
                fi
                if [[ "$(jq -r '.type' <<<"$rule")" == "single" ]]; then
                    jq --arg id "$id" --argjson p "$start" '(.rules[]|select(.id==$id)|.listen_port)=$p' "$FORWARDING_FILE" > "$candidate"
                else
                    rstart=$(jq -r '.remote_start' <<<"$rule")
                    count=$((end-start+1))
                    [[ $((rstart+count-1)) -le 65535 ]] || { echo "目标端口段会越界，请先修改目标起始端口。"; rm -f "$candidate"; pause; continue; }
                    jq --arg id "$id" --argjson s "$start" --argjson e "$end" \
                        '(.rules[]|select(.id==$id)|.listen_start)=$s | (.rules[]|select(.id==$id)|.listen_end)=$e' \
                        "$FORWARDING_FILE" > "$candidate"
                fi
                ;;
            *) rm -f "$candidate"; continue ;;
        esac

        if forwarding_apply_state_candidate "$candidate"; then
            echo -e "${GREEN}✔ 规则已更新。${PLAIN}"
        fi
        pause
    done
}

forwarding_delete_rule() {
    forwarding_init_state || return
    local idx="" rule="" id="" candidate="" yes=""
    idx=$(forwarding_select_rule_index) || { echo "无效选择。"; pause; return; }
    rule=$(jq -c ".rules[$idx]" "$FORWARDING_FILE")
    id=$(jq -r '.id' <<<"$rule")
    read -rp "确认删除“$(jq -r '.name' <<<"$rule")”？[y/N]: " yes
    [[ "$yes" =~ ^[Yy]$ ]] || return
    candidate=$(mktemp "${STATE_DIR}/forwarding.candidate.XXXXXX") || return
    jq --arg id "$id" '.rules |= map(select(.id != $id))' "$FORWARDING_FILE" > "$candidate" || { rm -f "$candidate"; return; }
    forwarding_apply_state_candidate "$candidate"
    pause
}

forwarding_test_tcp_target() {
    local host="$1" port="$2" hp=""
    hp=$(forwarding_format_host_port "$host" "$port")
    local out=""
    out=$(curl -v --connect-timeout 3 --max-time 3 "telnet://${hp}" </dev/null 2>&1 || true)
    if grep -qE 'Connected to .* port|Connected to ' <<<"$out"; then
        return 0
    fi
    return 1
}

forwarding_test_rule() {
    forwarding_init_state || return
    local idx="" rule="" type="" proto="" family="" host="" lp="" rp="" ls="" le="" rs="" re="" tcp_test_port=""
    idx=$(forwarding_select_rule_index) || { echo "无效选择。"; pause; return; }
    rule=$(jq -c ".rules[$idx]" "$FORWARDING_FILE")
    type=$(jq -r '.type' <<<"$rule")
    proto=$(jq -r '.protocol' <<<"$rule")
    family=$(jq -r '.listen_family' <<<"$rule")
    host=$(jq -r '.remote_host' <<<"$rule")
    if [[ "$type" == "single" ]]; then
        lp=$(jq -r '.listen_port' <<<"$rule")
        rp=$(jq -r '.remote_port' <<<"$rule")
        echo "规则：$(jq -r '.name' <<<"$rule")  ${lp} → ${host}:${rp} (${proto}/${family})"
        tcp_test_port="$rp"
    else
        ls=$(jq -r '.listen_start' <<<"$rule"); le=$(jq -r '.listen_end' <<<"$rule")
        rs=$(jq -r '.remote_start' <<<"$rule"); re=$((rs+le-ls))
        echo "规则：$(jq -r '.name' <<<"$rule")  ${ls}-${le} → ${host}:${rs}-${re} (${proto}/${family})"
        lp="$ls"; tcp_test_port="$rs"
    fi

    echo ""
    echo "【服务状态】"
    if systemctl is-active --quiet "$REALM_SERVICE_NAME"; then
        echo -e "  Realm : ${GREEN}Running${PLAIN}"
    else
        echo -e "  Realm : ${RED}Stopped${PLAIN}"
    fi

    echo "【监听检查】"
    if [[ "$proto" == "tcp" || "$proto" == "both" ]]; then
        if ss -H -lntp 2>/dev/null | awk -v p="$lp" '{a=$4; n=split(a,x,":"); if(x[n]==p) ok=1} END{exit !ok}'; then
            echo -e "  TCP ${lp}: ${GREEN}✓ 已监听${PLAIN}"
        else
            echo -e "  TCP ${lp}: ${RED}✗ 未监听${PLAIN}"
        fi
    fi
    if [[ "$proto" == "udp" || "$proto" == "both" ]]; then
        if ss -H -lnup 2>/dev/null | awk -v p="$lp" '{a=$4; n=split(a,x,":"); if(x[n]==p) ok=1} END{exit !ok}'; then
            echo -e "  UDP ${lp}: ${GREEN}✓ 已监听${PLAIN}"
        else
            echo -e "  UDP ${lp}: ${RED}✗ 未监听${PLAIN}"
        fi
    fi

    if [[ "$proto" == "tcp" || "$proto" == "both" ]]; then
        echo "【目标 TCP 连通性】"
        if forwarding_test_tcp_target "$host" "$tcp_test_port"; then
            echo -e "  ${host}:${tcp_test_port}: ${GREEN}✓ TCP 可连接${PLAIN}"
        else
            echo -e "  ${host}:${tcp_test_port}: ${YELLOW}未能建立 TCP 连接（目标服务可能拒绝探测；请结合实际客户端验证）${PLAIN}"
        fi
    fi
    if [[ "$proto" == "udp" || "$proto" == "both" ]]; then
        echo -e "${YELLOW}[说明] UDP 没有通用握手，脚本只验证监听状态；最终以真实 UDP 应用流量为准。${PLAIN}"
    fi
    pause
}

forwarding_show_config() {
    forwarding_init_state || return
    forwarding_print_rules
    echo ""
    echo "Realm 二进制 : ${REALM_BIN}"
    if [[ -x "$REALM_BIN" ]]; then
        echo "Realm 版本   : $("$REALM_BIN" --version 2>/dev/null | head -n1)"
    else
        echo "Realm 版本   : 未安装"
    fi
    echo "Realm 配置   : ${REALM_CONF}"
    echo "规则状态文件 : ${FORWARDING_FILE}"
    echo "systemd      : ${REALM_SERVICE_NAME}.service"
}

uninstall_realm_forwarding() {
    local yes=""
    echo -e "${YELLOW}此操作只删除 ss2022.sh 管理的 Realm 转发组件和 forwarding.json；不会删除服务器已有 realm.service 或 /usr/local/bin/realm。${PLAIN}"
    read -rp "确认卸载 Realm 转发组件？[y/N]: " yes
    [[ "$yes" =~ ^[Yy]$ ]] || return

    systemctl disable --now "$REALM_SERVICE_NAME" >/dev/null 2>&1 || true
    rm -f "$REALM_SERVICE" "$REALM_BIN" "$FORWARDING_FILE"
    rm -rf /etc/ss2022-realm
    if [[ -f "$REALM_USER_MARKER" ]]; then
        userdel "$REALM_USER" >/dev/null 2>&1 || true
        rm -f "$REALM_USER_MARKER"
    fi
    getent group "$REALM_GROUP" >/dev/null 2>&1 && groupdel "$REALM_GROUP" >/dev/null 2>&1 || true
    systemctl daemon-reload || true
    echo -e "${GREEN}✔ ss2022.sh Realm 转发组件已卸载。${PLAIN}"
    pause
}

realm_service_management() {
    while true; do
        clear
        echo -e "${CYAN}════════════════════ Realm 服务管理 ════════════════════${PLAIN}"
        echo "  1. 安装 / 重新安装固定版本 Realm v${REALM_VERSION}"
        echo "  2. 查看服务状态"
        echo "  3. 查看实时日志"
        echo "  4. 重启服务"
        echo "  5. 停止服务"
        echo "  6. 启动服务"
        echo "  7. 卸载 Realm 转发组件"
        echo "  0. 返回"
        read -rp "请选择 [0-7]: " c
        case "$c" in
            1)
                if install_realm_core; then
                    forwarding_init_state || true
                    if [[ $(jq '.rules|length' "$FORWARDING_FILE" 2>/dev/null || echo 0) -gt 0 ]]; then
                        local tmp=""
                        tmp=$(mktemp "${STATE_DIR}/forwarding.candidate.XXXXXX") || { pause; continue; }
                        cp -a "$FORWARDING_FILE" "$tmp"
                        forwarding_apply_state_candidate "$tmp" || true
                    fi
                fi
                pause
                ;;
            2) systemctl --no-pager --full status "$REALM_SERVICE_NAME" 2>/dev/null || echo "未运行"; pause ;;
            3) journalctl -u "$REALM_SERVICE_NAME" -f -n 30 ;;
            4) systemctl restart "$REALM_SERVICE_NAME" && echo "已重启" || journalctl -u "$REALM_SERVICE_NAME" -n 30 --no-pager; pause ;;
            5) systemctl stop "$REALM_SERVICE_NAME" && echo "已停止"; pause ;;
            6) systemctl start "$REALM_SERVICE_NAME" && echo "已启动" || journalctl -u "$REALM_SERVICE_NAME" -n 30 --no-pager; pause ;;
            7) uninstall_realm_forwarding ;;
            0) return ;;
            *) sleep 1 ;;
        esac
    done
}

forwarding_management() {
    forwarding_init_state || { pause; return; }
    while true; do
        clear
        forwarding_init_state || return
        local count="" state="未安装"
        count=$(jq '.rules|length' "$FORWARDING_FILE")
        if [[ -x "$REALM_BIN" ]]; then
            if systemctl is-active --quiet "$REALM_SERVICE_NAME"; then state="Running"; else state="Stopped"; fi
        fi
        echo -e "${CYAN}════════════════════ Realm 端口转发 ════════════════════${PLAIN}"
        echo "Realm     : ${state}"
        echo "版本      : v${REALM_VERSION}"
        echo "转发规则  : ${count} 条"
        echo ""
        echo "  1. 添加单端口转发"
        echo "  2. 添加端口段转发"
        echo "  3. 查看转发规则"
        echo "  4. 修改转发规则"
        echo "  5. 删除转发规则"
        echo "  6. 测试转发规则"
        echo "  7. Realm 服务管理"
        echo "  0. 返回"
        echo -e "${CYAN}═════════════════════════════════════════════════════════${PLAIN}"
        read -rp "请选择 [0-7]: " c
        case "$c" in
            1) forwarding_add_single ;;
            2) forwarding_add_range ;;
            3) clear; forwarding_show_config; pause ;;
            4) forwarding_edit_rule ;;
            5) forwarding_delete_rule ;;
            6) forwarding_test_rule ;;
            7) realm_service_management ;;
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
    echo -e "${YELLOW}【ss2022-xray / VLESS Reality】${PLAIN}"
    systemctl --no-pager --full status "$XRAY_SERVICE_NAME" 2>/dev/null | head -n 15 || echo "未安装/未加载"

    echo ""
    echo -e "${YELLOW}【Snell v5】${PLAIN}"
    systemctl --no-pager --full status snell-v5 2>/dev/null | head -n 15 || echo "未安装/未加载"

    echo ""
    echo -e "${YELLOW}【Realm 端口转发】${PLAIN}"
    systemctl --no-pager --full status "$REALM_SERVICE_NAME" 2>/dev/null | head -n 15 || echo "未安装/未加载"

    echo ""
    echo -e "${YELLOW}【监听端口】${PLAIN}"
    ss -lntup 2>/dev/null | grep -E 'sing-box|xray|snell-server|ss2022-realm|realm' || echo "未检测到相关监听"
}

full_uninstall() {
    local yes=""
    echo -e "${RED}========== 完全卸载 ss2022.sh ==========${PLAIN}"
    echo ""
    echo -e "${RED}此操作会删除 sing-box、ss2022-xray、Snell v5、ss2022-realm 以及本脚本管理的全部节点/分流/端口转发配置；若 WARP 由本脚本安装，也会一并卸载。不会删除服务器原有 xray.service 或 realm.service。${PLAIN}"
    echo ""
    echo -e "${YELLOW}将删除由 ss2022.sh 管理的代理核心、节点配置、分流配置、Realm 转发、Keepalive 与快捷命令。${PLAIN}"
    echo -e "${GREEN}不会删除服务器原有 xray.service / realm.service 或其它非本脚本管理的软件。${PLAIN}"
    read -rp "确认彻底卸载？请输入 DELETE: " yes
    [[ "$yes" == "DELETE" ]] || { echo "已取消。"; sleep 1; return; }

    systemctl disable --now sing-box "$XRAY_SERVICE_NAME" snell-v5 "$REALM_SERVICE_NAME" ipv6-keepalive.timer >/dev/null 2>&1 || true
    systemctl stop ipv6-keepalive.service >/dev/null 2>&1 || true

    if [[ -f "$WARP_MANAGED_MARKER" ]] && command -v warp-cli >/dev/null 2>&1; then
        warp-cli --accept-tos disconnect >/dev/null 2>&1 || true
        warp-cli --accept-tos registration delete >/dev/null 2>&1 || true
        apt-get remove -y cloudflare-warp >/dev/null 2>&1 || true
        rm -f /etc/apt/sources.list.d/cloudflare-client.list /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    fi

    rm -rf /etc/sing-box /etc/snell /etc/ss2022-xray /etc/ss2022-realm "$STATE_DIR" /usr/local/lib/ss2022
    rm -f \
        /usr/local/bin/ss2022 \
        /usr/local/bin/proxy \
        "$SINGBOX_BIN" \
        "$XRAY_BIN" \
        "$SNELL_BIN" \
        "$SINGBOX_SERVICE" \
        "$XRAY_SERVICE" \
        "$SNELL_SERVICE" \
        "$REALM_SERVICE" \
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

    if [[ -f "$XRAY_USER_MARKER" ]]; then
        userdel "$XRAY_USER" >/dev/null 2>&1 || true
        rm -f "$XRAY_USER_MARKER"
    fi

    if [[ -f "$SNELL_USER_MARKER" ]]; then
        userdel "$SNELL_USER" >/dev/null 2>&1 || true
        rm -f "$SNELL_USER_MARKER"
    fi

    if [[ -f "$REALM_USER_MARKER" ]]; then
        userdel "$REALM_USER" >/dev/null 2>&1 || true
        rm -f "$REALM_USER_MARKER"
    fi

    systemctl daemon-reload || true
    echo -e "${GREEN}✔ 已彻底卸载。${PLAIN}"
    exit 0
}


get_singbox_version_raw() {
    if [[ -x "$SINGBOX_BIN" ]]; then
        "$SINGBOX_BIN" version 2>/dev/null | head -n1 | awk '{print $3}'
    fi
}

get_xray_version_raw() {
    if [[ -x "$XRAY_BIN" ]]; then
        "$XRAY_BIN" version 2>/dev/null | head -n1 | awk '{print $2}'
    fi
}

get_snell_version_raw() {
    [[ -x "$SNELL_BIN" ]] && printf '%s\n' "$SNELL_VERSION" || true
}

get_realm_version_raw() {
    if [[ -x "$REALM_BIN" ]]; then
        "$REALM_BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1
    fi
}

component_current_version() {
    case "$1" in
        singbox) get_singbox_version_raw ;;
        xray) get_xray_version_raw ;;
        snell) get_snell_version_raw ;;
        realm) get_realm_version_raw ;;
    esac
}

component_recommended_version() {
    case "$1" in
        singbox) echo "$SINGBOX_VERSION" ;;
        xray) echo "$XRAY_VERSION" ;;
        snell) echo "$SNELL_VERSION" ;;
        realm) echo "$REALM_VERSION" ;;
    esac
}

component_label() {
    case "$1" in
        singbox) echo "sing-box" ;;
        xray) echo "Xray-core" ;;
        snell) echo "Snell Server" ;;
        realm) echo "Realm" ;;
    esac
}

component_bin_path() {
    case "$1" in
        singbox) echo "$SINGBOX_BIN" ;;
        xray) echo "$XRAY_BIN" ;;
        snell) echo "$SNELL_BIN" ;;
        realm) echo "$REALM_BIN" ;;
    esac
}

component_service_name() {
    case "$1" in
        singbox) echo "sing-box" ;;
        xray) echo "$XRAY_SERVICE_NAME" ;;
        snell) echo "snell-v5" ;;
        realm) echo "$REALM_SERVICE_NAME" ;;
    esac
}

component_config_exists() {
    case "$1" in
        singbox) [[ -f "$SINGBOX_CONF" ]] ;;
        xray) [[ -f "$XRAY_CONF" ]] ;;
        snell) [[ -f "$SNELL_CONF" ]] ;;
        realm) [[ -f "$REALM_CONF" ]] ;;
    esac
}

component_validate_existing_config() {
    local c="$1"
    case "$c" in
        singbox)
            [[ -f "$SINGBOX_CONF" ]] || return 0
            "$SINGBOX_BIN" check -c "$SINGBOX_CONF"
            ;;
        xray)
            [[ -f "$XRAY_CONF" ]] || return 0
            "$XRAY_BIN" run -test -format json -config "$XRAY_CONF"
            ;;
        snell)
            [[ -f "$SNELL_CONF" ]] || return 0
            snell_binary_works "$SNELL_BIN"
            ;;
        realm)
            [[ -f "$REALM_CONF" ]] || return 0
            "$REALM_BIN" --version >/dev/null 2>&1
            ;;
    esac
}

component_install_recommended() {
    local c="$1" label bin svc tmp old_active=0 had_bin=0 ok=0
    label=$(component_label "$c")
    bin=$(component_bin_path "$c")
    svc=$(component_service_name "$c")
    tmp=$(mktemp -d /tmp/ss2022-core-upgrade.XXXXXX) || return 1

    if [[ -x "$bin" ]]; then
        cp -a "$bin" "$tmp/old.bin" || { rm -rf "$tmp"; return 1; }
        had_bin=1
    fi
    systemctl is-active --quiet "$svc" 2>/dev/null && old_active=1 || true

    echo -e "${YELLOW}>> ${label}: 安装/修复到脚本推荐版本 $(component_recommended_version "$c")...${PLAIN}"
    case "$c" in
        singbox) install_singbox_core && ok=1 ;;
        xray) install_xray_core && ok=1 ;;
        snell) install_snell_v5_core && write_snell_service && ok=1 ;;
        realm) install_realm_core && ok=1 ;;
    esac

    if [[ $ok -eq 1 ]] && ! component_validate_existing_config "$c"; then
        echo -e "${RED}[错误] 新 ${label} 无法兼容当前配置，开始恢复旧二进制。${PLAIN}"
        ok=0
    fi

    if [[ $ok -eq 1 ]] && component_config_exists "$c"; then
        systemctl daemon-reload >/dev/null 2>&1 || true
        if ! systemctl restart "$svc" >/dev/null 2>&1; then
            echo -e "${RED}[错误] ${label} 新版本启动失败，开始回滚。${PLAIN}"
            ok=0
        else
            sleep 1
            systemctl is-active --quiet "$svc" || ok=0
        fi
    fi

    if [[ $ok -ne 1 ]]; then
        if [[ $had_bin -eq 1 && -f "$tmp/old.bin" ]]; then
            install -m 755 "$tmp/old.bin" "$bin" || true
        elif [[ $had_bin -eq 0 ]]; then
            rm -f "$bin"
        fi
        systemctl daemon-reload >/dev/null 2>&1 || true
        [[ $old_active -eq 1 ]] && systemctl restart "$svc" >/dev/null 2>&1 || true
        rm -rf "$tmp"
        echo -e "${RED}[错误] ${label} 升级/修复失败，已尽力恢复原核心。${PLAIN}"
        return 1
    fi

    rm -rf "$tmp"
    echo -e "${GREEN}✔ ${label} 当前版本: $(component_current_version "$c")${PLAIN}"
    return 0
}

fetch_github_latest_tag() {
    local repo="$1"
    curl -fsSL --retry 1 --connect-timeout 5 --max-time 12 \
      -H 'Accept: application/vnd.github+json' \
      "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
      | jq -r '.tag_name // empty' 2>/dev/null | sed 's/^v//'
}

show_component_versions() {
    local sb xr sn re
    sb=$(get_singbox_version_raw); sb=${sb:-未安装}
    xr=$(get_xray_version_raw); xr=${xr:-未安装}
    sn=$(get_snell_version_raw); sn=${sn:-未安装}
    re=$(get_realm_version_raw); re=${re:-未安装}
    clear
    echo -e "${CYAN}════════════════════ 组件版本管理 ════════════════════${PLAIN}"
    echo "【代理核心】"
    printf '  sing-box      已安装: %-12s 推荐: %s\n' "$sb" "$SINGBOX_VERSION"
    printf '  Xray-core     已安装: %-12s 推荐: %s\n' "$xr" "$XRAY_VERSION"
    printf '  Snell Server  已安装: %-12s 推荐: %s\n' "$sn" "$SNELL_VERSION"
    echo ""
    echo "【网络组件】"
    printf '  Realm         已安装: %-12s 推荐: %s\n' "$re" "$REALM_VERSION"
    if command -v warp-cli >/dev/null 2>&1; then
        echo "  Cloudflare WARP: 已安装（版本由 Cloudflare 客户端自身管理）"
    else
        echo "  Cloudflare WARP: 未安装"
    fi
}

check_upstream_versions() {
    clear
    echo -e "${CYAN}════════════════════ 上游版本检查 ════════════════════${PLAIN}"
    echo "说明：仅查询并提示，不会自动安装官方 Latest。"
    echo ""
    local latest current
    current=$(get_singbox_version_raw); current=${current:-未安装}
    latest=$(fetch_github_latest_tag 'SagerNet/sing-box'); latest=${latest:-查询失败}
    printf 'sing-box      当前 %-12s 推荐 %-12s 上游 %s\n' "$current" "$SINGBOX_VERSION" "$latest"
    current=$(get_xray_version_raw); current=${current:-未安装}
    latest=$(fetch_github_latest_tag 'XTLS/Xray-core'); latest=${latest:-查询失败}
    printf 'Xray-core     当前 %-12s 推荐 %-12s 上游 %s\n' "$current" "$XRAY_VERSION" "$latest"
    current=$(get_snell_version_raw); current=${current:-未安装}
    printf 'Snell Server  当前 %-12s 推荐 %-12s 上游 %s\n' "$current" "$SNELL_VERSION" "请以 Surge 官方发布为准"
    current=$(get_realm_version_raw); current=${current:-未安装}
    latest=$(fetch_github_latest_tag 'zhboner/realm'); latest=${latest:-查询失败}
    printf 'Realm         当前 %-12s 推荐 %-12s 上游 %s\n' "$current" "$REALM_VERSION" "$latest"
    echo ""
    echo -e "${YELLOW}上游 Latest 不代表本脚本已验证。请优先使用脚本推荐版本。${PLAIN}"
    pause
}

component_single_menu() {
    local c="$1" label current recommended choice
    label=$(component_label "$c")
    while true; do
        clear
        current=$(component_current_version "$c"); current=${current:-未安装}
        recommended=$(component_recommended_version "$c")
        echo -e "${CYAN}════════════════════ ${label} ════════════════════${PLAIN}"
        echo "当前版本 : $current"
        echo "推荐版本 : $recommended"
        echo ""
        echo "  1. 升级 / 重装到推荐版本"
        echo "  2. 查看当前版本"
        echo "  0. 返回"
        read -rp "请选择 [0-2]: " choice
        case "$choice" in
            1) component_install_recommended "$c"; pause ;;
            2) current=$(component_current_version "$c"); echo "${label}: ${current:-未安装}"; pause ;;
            0) return ;;
            *) sleep 1 ;;
        esac
    done
}

upgrade_all_to_recommended() {
    local c current target failed=0
    for c in singbox xray snell realm; do
        current=$(component_current_version "$c")
        target=$(component_recommended_version "$c")
        if [[ -z "$current" ]]; then
            case "$c" in
                singbox) [[ -f "$SINGBOX_CONF" ]] || continue ;;
                xray) [[ -f "$XRAY_CONF" ]] || continue ;;
                snell) [[ -f "$SNELL_CONF" ]] || continue ;;
                realm) [[ -f "$REALM_CONF" || -f "$FORWARDING_FILE" ]] || continue ;;
            esac
        fi
        if [[ "$current" == "$target" ]]; then
            echo -e "${GREEN}✔ $(component_label "$c") 已是推荐版本 $target${PLAIN}"
            continue
        fi
        component_install_recommended "$c" || failed=1
    done
    [[ $failed -eq 0 ]]
}

component_version_management() {
    while true; do
        show_component_versions
        echo ""
        echo "  1. sing-box"
        echo "  2. Xray-core"
        echo "  3. Snell Server"
        echo "  4. Realm"
        echo "  5. 检查官方上游版本（仅提示）"
        echo "  6. 全部升级到脚本推荐版本"
        echo "  0. 返回"
        echo -e "${CYAN}═════════════════════════════════════════════════════════${PLAIN}"
        read -rp "请选择 [0-6]: " c
        case "$c" in
            1) component_single_menu singbox ;;
            2) component_single_menu xray ;;
            3) component_single_menu snell ;;
            4) component_single_menu realm ;;
            5) check_upstream_versions ;;
            6) upgrade_all_to_recommended; pause ;;
            0) return ;;
            *) sleep 1 ;;
        esac
    done
}

protocol_management() {
    while true; do
        clear
        echo -e "${CYAN}════════════════════ 协议管理 ════════════════════${PLAIN}"
        echo "  1. SS2022"
        echo "  2. SS2022 + ShadowTLS v3（增强伪装）"
        echo "  3. VLESS Reality"
        echo "  4. Snell v5"
        echo "  0. 返回"
        echo -e "${CYAN}═══════════════════════════════════════════════════${PLAIN}"
        read -rp "请选择 [0-4]: " c
        case "$c" in
            1) protocol_action_menu "SS2022" deploy_ss2022 update_ss2022 delete_ss2022 ;;
            2) protocol_action_menu "SS2022 + ShadowTLS v3" deploy_shadowtls update_shadowtls delete_shadowtls ;;
            3) protocol_action_menu "VLESS Reality" deploy_vless_reality update_vless_reality delete_vless_reality ;;
            4) protocol_action_menu "Snell v5" deploy_snell_v5 update_snell_v5 delete_snell_v5 ;;
            0) return ;;
            *) sleep 1 ;;
        esac
    done
}

service_management() {
    while true; do
        clear
        echo -e "${CYAN}════════════════════ 服务运维管理 ════════════════════${PLAIN}"
        echo "  1. 查看全部服务状态与监听端口"
        echo "  2. 查看 sing-box 实时日志"
        echo "  3. 查看 ss2022-xray 实时日志"
        echo "  4. 查看 Snell v5 实时日志"
        echo "  5. 查看 Realm 转发实时日志"
        echo "  6. 重启 sing-box"
        echo "  7. 重启 ss2022-xray"
        echo "  8. 重启 Snell v5"
        echo "  9. 重启 Realm 转发"
        echo " 10. 查看 IPv6 Keepalive 状态"
        echo "  0. 返回"
        echo -e "${CYAN}═══════════════════════════════════════════════════════${PLAIN}"
        read -rp "请选择 [0-10]: " c
        case "$c" in
            1) show_service_status; pause ;;
            2) journalctl -u sing-box -f -n 30 ;;
            3) journalctl -u "$XRAY_SERVICE_NAME" -f -n 30 ;;
            4) journalctl -u snell-v5 -f -n 30 ;;
            5) journalctl -u "$REALM_SERVICE_NAME" -f -n 30 ;;
            6) if systemctl restart sing-box; then echo -e "${GREEN}✔ sing-box 已重启。${PLAIN}"; else journalctl -u sing-box -n 30 --no-pager; fi; pause ;;
            7) if systemctl restart "$XRAY_SERVICE_NAME"; then echo -e "${GREEN}✔ ss2022-xray 已重启。${PLAIN}"; else journalctl -u "$XRAY_SERVICE_NAME" -n 30 --no-pager; fi; pause ;;
            8) if systemctl restart snell-v5; then echo -e "${GREEN}✔ Snell v5 已重启。${PLAIN}"; else journalctl -u snell-v5 -n 30 --no-pager; fi; pause ;;
            9) if systemctl restart "$REALM_SERVICE_NAME"; then echo -e "${GREEN}✔ Realm 转发已重启。${PLAIN}"; else journalctl -u "$REALM_SERVICE_NAME" -n 30 --no-pager; fi; pause ;;
            10) systemctl list-timers --all | grep -E 'keepalive|NEXT' || echo "未检测到 Keepalive 定时器。"; pause ;;
            0) return ;;
            *) sleep 1 ;;
        esac
    done
}

main() {
    check_root

    while true; do
        show_dashboard
        echo "  1. 协议管理"
        echo "  2. 分流管理"
        echo "  3. 端口转发（Realm）"
        echo "  4. 查看当前节点参数与客户端配置"
        echo "  5. 服务运维管理"
        echo "  6. 组件版本管理"
        echo -e "${RED}  7. 完全卸载脚本${PLAIN}"
        echo "  0. 退出管理面板"
        echo -e "${CYAN}═════════════════════════════════════════════════════════════════${PLAIN}"
        read -rp "请输入选项编号 [0-7]: " choice

        case "$choice" in
            1) protocol_management ;;
            2) routing_management ;;
            3) forwarding_management ;;
            4) view_config_menu ;;
            5) service_management ;;
            6) component_version_management ;;
            7) full_uninstall ;;
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
