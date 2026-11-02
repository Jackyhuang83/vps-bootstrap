#!/usr/bin/env bash
# vps-bootstrap Snell v6 module. Loaded only after ss2022.sh verifies SHA256.
# MODULE: OFFICIAL_SURGE_SNELL6_V1
# Source only: this file must not alter services or run commands when imported.

snell6_managed() { [[ -f "$SNELL6_MANAGED_MARKER" ]]; }

snell6_ownership() {
    snell6_managed && return 0
    if [[ -e "$SNELL6_BIN" || -e "$SNELL6_CONF" || -e "$SNELL6_SERVICE" ||
          -e "$SNELL6_CONF_DIR" ]]; then
        echo "[错误] 检测到非本工具箱管理的 Snell v6 文件，拒绝覆盖。"
        return 1
    fi
    return 0
}

snell6_port() {
    [[ -f "$SNELL6_CONF" ]] || return 1
    sed -nE 's/^[[:space:]]*listen[[:space:]]*=[[:space:]]*([^,]*).*/\1/p' "$SNELL6_CONF" |
        head -n1 | grep -oE '[0-9]+$'
}

snell6_port_free() {
    local port="$1" old="" pid=""
    old=$(snell6_port 2>/dev/null || true)
    if [[ -f "$SNELL_CONF" ]] && [[ "$(snell_port_from_config 2>/dev/null || true)" == "$port" ]]; then
        echo "[错误] Snell v5 已预留这个端口。"; return 1
    fi
    if [[ -f "$SINGBOX_CONF" ]] && jq -e --argjson p "$port" \
        '.inbounds[]? | select((.listen_port // 0) == $p)' "$SINGBOX_CONF" >/dev/null 2>&1; then
        echo "[错误] sing-box 已预留这个端口。"; return 1
    fi
    if [[ -f "$XRAY_CONF" ]] && jq -e --argjson p "$port" \
        '.inbounds[]? | select((.port // 0) == $p)' "$XRAY_CONF" >/dev/null 2>&1; then
        echo "[错误] Xray 已预留这个端口。"; return 1
    fi
    if [[ "$port" == "$old" ]] && service_is_active "$SNELL6_SERVICE_NAME"; then
        pid=$(service_main_pid "$SNELL6_SERVICE_NAME" 2>/dev/null || true)
        if [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 0 ]] &&
            ! port_in_use_by_other_process "$port" "$pid" >/dev/null 2>&1; then
            return 0
        fi
    fi
    if port_in_use_by_other_process "$port" "" >/dev/null 2>&1; then
        echo "[错误] 端口被其他程序占用。"; return 1
    fi
    return 0
}

snell6_candidate() {
    local tmp="$1" mode="$2" port="$3" psk="$4" listen ipv6
    case "$mode" in
        ipv4) listen="0.0.0.0:$port"; ipv6=false ;;
        ipv6) listen="[::]:$port"; ipv6=true ;;
        dual) listen="0.0.0.0:$port,[::]:$port"; ipv6=true ;;
        *) return 1 ;;
    esac
    cat > "$tmp" <<CONFIG
[snell-server]
listen = $listen
psk = $psk
version = 6
mode = default
ipv6 = $ipv6
dns-ip-preference = default
CONFIG
    chmod 600 "$tmp"
}

snell6_install_binary() {
    local arch sha tmp zip url actual candidate
    [[ "$PLATFORM_INIT" == systemd ]] && ! platform_is_alpine || {
        echo "[错误] 官方 Snell v6 当前仅开放 Debian/Ubuntu + systemd。"; return 1;
    }
    snell6_ownership || return 1
    install_dependencies || return 1
    case "$(uname -m)" in
        amd64|x86_64) arch=amd64; sha="$SNELL6_SHA256_AMD64" ;;
        arm64|aarch64) arch=aarch64; sha="$SNELL6_SHA256_ARM64" ;;
        *) echo "[错误] Snell v6 仅支持 amd64/aarch64。"; return 1 ;;
    esac
    tmp=$(mktemp -d /tmp/ss2022-snell6-install.XXXXXX) || return 1
    zip="$tmp/download.zip"
    candidate="$SNELL6_CANDIDATE_PREFIX.$$"
    url="https://dl.nssurge.com/snell/snell-server-v$SNELL6_VERSION-linux-$arch.zip"
    echo ">> 下载 Surge 官方 Snell v$SNELL6_VERSION ..."
    if ! curl -4 -fL --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 120 -o "$zip" "$url"; then
        rm -f "$zip"
        if ! curl -6 -fL --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 120 -o "$zip" "$url"; then
            rm -rf "$tmp"; echo "[错误] 官方 Snell v6 IPv4/IPv6 下载均失败。"; return 1
        fi
    fi
    actual=$(sha256sum "$zip" | awk '{print $1}')
    if [[ "$actual" != "$sha" ]]; then
        rm -rf "$tmp"; echo "[错误] Snell v6 SHA256 不匹配，拒绝安装。"; return 1
    fi
    if ! unzip -tq "$zip" >/dev/null 2>&1 ||
       unzip -Z1 "$zip" | grep -Eq '(^/|(^|/)\.\.(/|$))' ||
       ! unzip -Z1 "$zip" | grep -qx snell-server; then
        rm -rf "$tmp"; echo "[错误] Snell v6 ZIP 安全检查失败。"; return 1
    fi
    unzip -oq "$zip" -d "$tmp" || { rm -rf "$tmp"; return 1; }
    install -m 755 "$tmp/snell-server" "$candidate" ||
        { rm -f "$candidate"; rm -rf "$tmp"; return 1; }
    if ! snell_binary_works "$candidate"; then
        rm -f "$candidate"; rm -rf "$tmp"
        echo "[错误] 官方 Snell v6 二进制无法运行。"; return 1
    fi
    mv -f "$candidate" "$SNELL6_BIN" || { rm -f "$candidate"; rm -rf "$tmp"; return 1; }
    touch "$SNELL6_MANAGED_MARKER" || return 1
    chmod 600 "$SNELL6_MANAGED_MARKER"
    rm -rf "$tmp"
    echo "✔ 官方 Snell v6.0.0 SHA256 和运行检查通过。"
}

snell6_service_install() {
    ensure_managed_system_user "$SNELL6_USER" "$SNELL6_GROUP" \
        "$SNELL6_USER_MARKER" "$SNELL6_GROUP_MARKER" || return 1
    [[ "$PLATFORM_INIT" == systemd ]] || return 1
    cat > "$SNELL6_SERVICE" <<'SERVICE'
[Unit]
Description=vps-bootstrap official Surge Snell v6
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ss2022-snell6
Group=ss2022-snell6
ExecStart=/usr/local/bin/snell-server-v6 -c /etc/ss2022-snell-v6/config.conf
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
    service_daemon_reload || return 1
    service_enable "$SNELL6_SERVICE_NAME"
}

snell6_apply() {
    local temp="$1" backup="" existed=0
    grep -Eq '^version[[:space:]]*=[[:space:]]*6$' "$temp" || return 1
    grep -Eq '^mode[[:space:]]*=[[:space:]]*default$' "$temp" || return 1
    ensure_project_config_dir "$SNELL6_CONF_DIR" "$SNELL6_GROUP" \
        "$SNELL6_DIR_MARKER" || return 1
    if [[ -f "$SNELL6_CONF" ]]; then
        existed=1
        backup=$(mktemp "$SNELL6_CONF_DIR/.ss2022-rollback.XXXXXX") || return 1
        cp -a "$SNELL6_CONF" "$backup" || { rm -f "$backup"; return 1; }
    fi
    mv -f "$temp" "$SNELL6_CONF" || { rm -f "$temp" "$backup"; return 1; }
    chown root:"$SNELL6_GROUP" "$SNELL6_CONF" || return 1
    chmod 640 "$SNELL6_CONF"
    if service_restart "$SNELL6_SERVICE_NAME"; then
        sleep 2
        if service_is_active "$SNELL6_SERVICE_NAME"; then
            rm -f "$backup"; return 0
        fi
    fi
    echo "[错误] Snell v6 启动失败，回滚原配置。"
    if [[ "$existed" == 1 && -f "$backup" ]]; then
        mv -f "$backup" "$SNELL6_CONF"
        chown root:"$SNELL6_GROUP" "$SNELL6_CONF" 2>/dev/null || true
        chmod 640 "$SNELL6_CONF"
        service_restart "$SNELL6_SERVICE_NAME" >/dev/null 2>&1 || true
    else
        rm -f "$SNELL6_CONF"
        service_stop "$SNELL6_SERVICE_NAME" >/dev/null 2>&1 || true
    fi
    service_log_tail "$SNELL6_SERVICE_NAME" 20 || true
    return 1
}

snell6_details() {
    local host="$1" port="$2" psk="$3" name="$4"
    echo -e "$CYAN══════════════ Snell v6.0.0（Surge）══════════════$PLAIN"
    echo "名称: $name"
    echo "地址: $host"
    echo "端口: $port"
    echo "PSK : $psk"
    echo "模式: default（加密 + PSK 派生流量混淆）"
    echo ""
    echo "$name = snell, $host, $port, psk=\"$psk\", version=6, mode=default"
    echo "[提示] 仅输出 Surge 官方支持的 v6 配置，不提供未经确认的其它客户端导入格式。"
}

view_snell_v6_config() {
    local port psk host name
    [[ -f "$SNELL6_CONF" ]] || { echo "Snell v6 未部署。"; return 0; }
    port=$(snell6_port) || return 1
    psk=$(sed -nE 's/^[[:space:]]*psk[[:space:]]*=[[:space:]]*(.*)/\1/p' "$SNELL6_CONF" | head -n1)
    host=$(get_mode_state_field snell6 host 2>/dev/null || true)
    host=${host:-请填写服务器地址}
    name=$(get_node_name snell6)
    snell6_details "$host" "$port" "$psk" "$name"
}

deploy_snell_v6() {
    local port="" psk="" tmp state
    [[ ! -f "$SNELL6_CONF" ]] || { echo "Snell v6 已部署，请选择更新。"; pause; return; }
    select_network_mode no yes || return
    snell6_install_binary || { pause; return; }
    while true; do
        read -rp "Snell v6 监听端口 [默认 64444]: " port
        port=${port:-64444}
        validate_port_number "$port" || { echo "端口无效。"; continue; }
        snell6_port_free "$port" && break
    done
    psk=$(openssl rand -hex 24) || { pause; return; }
    ask_server_host
    ask_node_name snell6 || return
    snell6_service_install || { pause; return; }
    ensure_project_config_dir "$SNELL6_CONF_DIR" "$SNELL6_GROUP" "$SNELL6_DIR_MARKER" || { pause; return; }
    tmp=$(mktemp "$SNELL6_CONF_DIR/.ss2022-config.XXXXXX") || { pause; return; }
    snell6_candidate "$tmp" "$NETWORK_MODE" "$port" "$psk" || { rm -f "$tmp"; pause; return; }
    if snell6_apply "$tmp"; then
        state=$(jq -n --arg host "$SERVER_HOST" --arg network "$NETWORK_MODE" --arg name "$NODE_NAME" \
            '{host:$host,network:$network,name:$name}')
        save_mode_state snell6 "$state" || true
        echo "✔ Snell v6 部署完成。未触碰 Snell v5。"
        snell6_details "$SERVER_HOST" "$port" "$psk" "$NODE_NAME"
    fi
    pause
}

update_snell_v6() {
    local choice port psk network host name nport npsk nnetwork tmp state confirm
    [[ -f "$SNELL6_CONF" && -x "$SNELL6_BIN" ]] ||
        { echo "Snell v6 尚未部署。"; pause; return; }
    while true; do
        port=$(snell6_port) || { echo "Snell v6 端口配置错误。"; pause; return; }
        psk=$(sed -nE 's/^[[:space:]]*psk[[:space:]]*=[[:space:]]*(.*)/\1/p' "$SNELL6_CONF" | head -n1)
        network=$(get_mode_state_field snell6 network 2>/dev/null || true)
        network=${network:-ipv4}
        host=$(get_mode_state_field snell6 host 2>/dev/null || true)
        name=$(get_node_name snell6)
        echo "========= Snell v6 更新 ========="
        echo " 1. 网络模式：$network"
        echo " 2. 监听端口：$port"
        echo " 3. 服务器地址/域名"
        echo " 4. 重新生成 PSK（客户端原密钥会失效）"
        echo " 5. 查看当前节点"
        echo " 0. 返回"
        read -rp "请选择 [0-5]: " choice
        nport="$port"; npsk="$psk"; nnetwork="$network"
        case "$choice" in
            1) select_network_mode_for_update "$network" no yes || continue; nnetwork="$NETWORK_MODE" ;;
            2) read -rp "新端口: " nport; validate_port_number "$nport" || continue ;;
            3) ask_server_host_with_default "$host"
               state=$(jq -n --arg host "$SERVER_HOST" --arg network "$network" --arg name "$name" \
                   '{host:$host,network:$network,name:$name}')
               save_mode_state snell6 "$state" || true
               echo "已更新客户端地址，服务不重启。"; pause; continue ;;
            4) read -rp "确认更换 PSK？[y/N]: " confirm
               [[ "$confirm" =~ ^[Yy]$ ]] || continue
               npsk=$(openssl rand -hex 24) || continue ;;
            5) view_snell_v6_config; pause; continue ;;
            0) return ;;
            *) continue ;;
        esac
        snell6_port_free "$nport" || continue
        tmp=$(mktemp "$SNELL6_CONF_DIR/.ss2022-config.XXXXXX") || continue
        snell6_candidate "$tmp" "$nnetwork" "$nport" "$npsk" || { rm -f "$tmp"; continue; }
        if snell6_apply "$tmp"; then
            state=$(jq -n --arg host "$host" --arg network "$nnetwork" --arg name "$name" \
                '{host:$host,network:$network,name:$name}')
            save_mode_state snell6 "$state" || true
            snell6_details "$host" "$nport" "$npsk" "$name"
        fi
        pause
    done
}

delete_snell_v6() {
    local answer=""
    [[ -f "$SNELL6_CONF" ]] || { echo "Snell v6 未部署。"; pause; return; }
    snell6_managed || { echo "[错误] 非本工具箱资源，拒绝删除。"; pause; return; }
    read -rp "删除 Snell v6 节点与服务（保留 v5 和 v6 官方二进制）？[y/N]: " answer
    [[ "$answer" =~ ^[Yy]$ ]] || return
    service_disable_now "$SNELL6_SERVICE_NAME"
    rm -f "$SNELL6_CONF" "$SNELL6_SERVICE"
    service_daemon_reload || true
    remove_mode_state snell6 || true
    echo "✔ Snell v6 已删除，Snell v5 未变更。"
    pause
}
