#!/usr/bin/env bash
# MODULE: OFFICIAL_HYSTERIA2_V1
# Hysteria 2 isolated server. Source only; never starts or changes a service at import.
# Requires ss2022.sh helpers and Debian/Ubuntu with systemd.

hy2_managed() {
    [[ -f "$HY2_MANAGED_MARKER" ]]
}

hy2_ownership() {
    hy2_managed && return 0
    if [[ -e "$HY2_BIN" || -e "$HY2_CONF" || -e "$HY2_SERVICE" ]]; then
        echo "[错误] 已有非 vps-bootstrap 管理的 HY2 二进制、配置或服务；拒绝覆盖。"
        return 1
    fi
}

hy2_validate_domain() {
    local domain="$1" tld label
    local -a labels=()
    [[ ${#domain} -le 253 && "$domain" == *.* ]] || return 1
    [[ "$domain" =~ ^[A-Za-z0-9.-]+$ ]] || return 1
    tld="${domain##*.}"
    [[ "$tld" =~ ^[A-Za-z]{2,63}$ ]] || return 1
    IFS=. read -r -a labels <<< "$domain"
    for label in "${labels[@]}"; do
        [[ ${#label} -le 63 && "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
    done
    return 0
}

hy2_prompt_network() {
    local select=""
    echo "HY2 监听地址族（仅改变 HY2，不修改全局 IPv6 / DNS / Keepalive）："
    echo "  1. IPv4    2. IPv6-only    3. 双栈"
    while true; do
        read -rp "请选择 [1-3，默认 3]: " select || return 1
        select=${select:-3}
        case "$select" in
            1) HY2_NETWORK=ipv4; return 0 ;;
            2) HY2_NETWORK=ipv6; return 0 ;;
            3) HY2_NETWORK=dual; return 0 ;;
            *) echo "[错误] 请选择 1-3。" ;;
        esac
    done
}

hy2_listen() {
    local mode="$1" port="$2"
    validate_port_number "$port" || return 1
    case "$mode" in
        ipv4) printf '0.0.0.0:%s' "$port" ;;
        ipv6) printf '[::]:%s' "$port" ;;
        dual) printf ':%s' "$port" ;;
        *) return 1 ;;
    esac
}

hy2_current_port() {
    [[ -f "$HY2_CONF" ]] || return 1
    jq -er '.listen | capture(":(?<port>[0-9]+)$").port' "$HY2_CONF" 2>/dev/null
}

hy2_port_free() {
    local port="$1" previous=""
    validate_port_number "$port" || return 1
    previous=$(hy2_current_port 2>/dev/null || true)
    # Existing HY2 may be listening on its own port; do not reject a safe update.
    [[ "$port" == "$previous" && -n "$previous" ]] && return 0
    command -v ss >/dev/null 2>&1 || { echo "[错误] 缺少 ss，不能检查 UDP 端口。"; return 1; }
    local sockets
    sockets=$(ss -H -lunp) || { echo "[错误] UDP 监听端口检查失败。"; return 1; }
    if awk -v p="$port" '{a=$5; sub(/^.*:/,"",a); if(a==p) found=1} END{exit !found}' <<< "$sockets"; then
        echo "[错误] UDP 端口 $port 已被占用（HY2 独立 UDP 监听）。"
        return 1
    fi
    return 0
}

hy2_candidate() {
    local dest="$1" network="$2" port="$3" domain="$4" password="$5" listen="" acme_host=""
    hy2_validate_domain "$domain" || return 1
    [[ "$password" =~ ^[A-Za-z0-9_-]{32,128}$ ]] || return 1
    listen=$(hy2_listen "$network" "$port") || return 1
    [[ "$network" != ipv6 ]] || acme_host="::"
    jq -n --arg listen "$listen" --arg domain "$domain" --arg password "$password" \
        --arg acme_dir "$HY2_CONF_DIR/acme" --arg acme_host "$acme_host" \
        '{
          listen:$listen,
          acme:({domains:[$domain],type:"http",dir:$acme_dir} +
            (if $acme_host == "" then {} else {listenHost:$acme_host} end)),
          auth:{type:"password",password:$password},
          masquerade:{type:"proxy",proxy:{url:"https://www.wikipedia.org/",rewriteHost:true}}
        }' > "$dest" || return 1
    chmod 600 "$dest"
}

hy2_install_binary() {
    local arch expected path temp file actual url
    [[ "$PLATFORM_INIT" == systemd ]] && ! platform_is_alpine || {
        echo "[提示] HY2 第一阶段仅支持 Debian/Ubuntu + systemd。"
        return 1
    }
    hy2_ownership || return 1
    for path in curl jq sha256sum openssl; do
        command -v "$path" >/dev/null 2>&1 || {
            echo "[错误] 缺少 $path，请先安装基础依赖。"
            return 1
        }
    done
    case "$(uname -m)" in
        x86_64|amd64) arch=amd64; expected="$HY2_SHA256_AMD64" ;;
        aarch64|arm64) arch=arm64; expected="$HY2_SHA256_ARM64" ;;
        *) echo "[错误] HY2 仅支持 x86_64/arm64。"; return 1 ;;
    esac
    if [[ -x "$HY2_BIN" ]] && hy2_managed; then
        echo "HY2 官方核心已安装，保留现有二进制。"
        return 0
    fi
    temp=$(mktemp -d /tmp/ss2022-hy2.XXXXXX) || return 1
    file="$temp/hysteria"
    url="https://github.com/HyNetworks/hysteria/releases/download/app/v$HY2_VERSION/hysteria-linux-$arch"
    echo ">> 下载 Hysteria 官方 v$HY2_VERSION（固定 SHA256）..."
    if ! curl -4 -fL --retry 2 --connect-timeout 15 --max-time 140 -o "$file" "$url"; then
        rm -f "$file"
        if ! curl -6 -fL --retry 2 --connect-timeout 15 --max-time 140 -o "$file" "$url"; then
            rm -rf "$temp"
            echo "[错误] 官方 Hysteria 二进制下载失败。"
            return 1
        fi
    fi
    actual=$(sha256sum "$file" | awk '{print $1}')
    if [[ "$actual" != "$expected" ]]; then
        rm -rf "$temp"
        echo "[错误] Hysteria 官方 SHA256 不匹配，停止安装。"
        return 1
    fi
    chmod 755 "$file"
    if ! "$file" version >/dev/null 2>&1; then
        rm -rf "$temp"
        echo "[错误] HY2 官方二进制运行时检查失败。"
        return 1
    fi
    install -d -m 755 "$(dirname "$HY2_BIN")" || { rm -rf "$temp"; return 1; }
    install -m 755 "$file" "$HY2_BIN" || { rm -rf "$temp"; return 1; }
    touch "$HY2_MANAGED_MARKER" || { rm -rf "$temp"; return 1; }
    chmod 600 "$HY2_MANAGED_MARKER"
    rm -rf "$temp"
    echo "✔ 官方 HY2 核心安装成功；未操作任何旧协议。"
}

hy2_service_install() {
    [[ "$PLATFORM_INIT" == systemd ]] || return 1
    hy2_ownership || return 1
    ensure_managed_system_user "$HY2_USER" "$HY2_GROUP" \
        "$HY2_USER_MARKER" "$HY2_GROUP_MARKER" || return 1
    ensure_project_config_dir "$HY2_CONF_DIR" "$HY2_GROUP" "$HY2_DIR_MARKER" || return 1
    install -d -o "$HY2_USER" -g "$HY2_GROUP" -m 700 "$HY2_CONF_DIR/acme" || return 1
    cat > "$HY2_SERVICE" <<'SERVICE'
[Unit]
Description=vps-bootstrap official Hysteria 2 isolated QUIC/UDP
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=ss2022-hy2
Group=ss2022-hy2
ExecStart=/usr/local/lib/ss2022/hysteria server -c /etc/ss2022-hy2/config.json
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576
UMask=0077
NoNewPrivileges=true
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=/etc/ss2022-hy2/acme
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

[Install]
WantedBy=multi-user.target
SERVICE
    service_daemon_reload || return 1
    service_enable "$HY2_SERVICE_NAME"
}

hy2_apply() {
    local new="$1" backup="" existed=0
    hy2_managed || { echo "[错误] HY2 未由本工具箱管理。"; return 1; }
    jq -e '.listen and .acme.domains[0] and .auth.type=="password" and .auth.password' "$new" >/dev/null || return 1
    if [[ -f "$HY2_CONF" ]]; then
        existed=1
        backup=$(mktemp "$HY2_CONF_DIR/.ss2022-rollback.XXXXXX") || return 1
        cp -a "$HY2_CONF" "$backup" || { rm -f "$backup"; return 1; }
    fi
    chown root:"$HY2_GROUP" "$new" || return 1
    chmod 640 "$new" || return 1
    mv -f "$new" "$HY2_CONF" || { rm -f "$backup"; return 1; }
    if service_restart "$HY2_SERVICE_NAME"; then
        sleep 3
        if service_is_active "$HY2_SERVICE_NAME"; then
            rm -f "$backup"
            return 0
        fi
    fi
    echo "[错误] HY2 服务启动失败，正在恢复原配置。"
    if [[ "$existed" == 1 && -f "$backup" ]]; then
        mv -f "$backup" "$HY2_CONF"
        service_restart "$HY2_SERVICE_NAME" >/dev/null 2>&1 || true
    else
        rm -f "$HY2_CONF"
        service_disable_now "$HY2_SERVICE_NAME"
    fi
    rm -f "$backup"
    service_log_tail "$HY2_SERVICE_NAME" 20 || true
    return 1
}

hy2_details() {
    local host="$1" port="$2" domain="$3" password="$4" name="$5" uri_host auth_enc domain_enc name_enc
    uri_host=$(format_host_for_uri "$host")
    auth_enc=$(urlencode "$password")
    domain_enc=$(urlencode "$domain")
    name_enc=$(urlencode "$name")
    echo "════════════ Hysteria 2 (QUIC / UDP) ════════════"
    echo "名称: $name"
    echo "入口: $host:$port/UDP"
    echo "SNI / TLS 证书域名: $domain（证书必须由受信任 CA 签发）"
    echo "密码: $password"
    echo ""
    echo "【Surge iOS 5.8+ / Mac 5.4+】"
    echo "$name = hysteria2, $host, $port, password=$password, sni=$domain"
    echo ""
    echo "【HY2 URI / 通用导入】"
    echo "hysteria2://$auth_enc@$uri_host:$port?sni=$domain_enc#$name_enc"
    echo "[注意] 请在云防火墙放行 UDP/$port；ACME HTTP-01 需要 TCP/80 入站。"
    echo "[注意] 不启用 skip-cert-verify / 不提供不安全证书跳过选项。"
    echo "[注意] 仅显示配置不代表证书签发成功或公网可连。"
}

view_hy2_config() {
    local port password domain host name
    [[ -f "$HY2_CONF" ]] && hy2_managed || { echo "HY2 未部署。"; return 0; }
    port=$(hy2_current_port) || return 1
    password=$(jq -r '.auth.password' "$HY2_CONF")
    domain=$(jq -r '.acme.domains[0]' "$HY2_CONF")
    host=$(get_mode_state_field hy2 host 2>/dev/null || true)
    host=${host:-$domain}
    name=$(get_node_name hy2)
    hy2_details "$host" "$port" "$domain" "$password" "$name"
}

hy2_prompt_domain() {
    local domain=""
    while true; do
        read -rp "TLS 证书域名（A/AAAA 需指向本 VPS，不可填 IP）: " domain || return 1
        if hy2_validate_domain "$domain"; then
            HY2_DOMAIN="$domain"
            return 0
        fi
        echo "[错误] 请输入格式正确的域名。"
    done
}

hy2_prompt_host() {
    local default="$1" entered=""
    read -rp "客户端连接地址 / IP [默认: $default]: " entered || return 1
    entered=${entered:-$default}
    [[ "$entered" != *[[:space:]]* && "$entered" != *","* && "$entered" != *"="* ]] || return 1
    HY2_HOST="$entered"
}

hy2_prompt_port() {
    local default="$1" port=""
    while true; do
        read -rp "HY2 UDP 端口 [默认: $default]: " port || return 1
        port=${port:-$default}
        validate_port_number "$port" || { echo "[错误] 无效端口。"; continue; }
        hy2_port_free "$port" && { HY2_PORT="$port"; return 0; }
    done
}

deploy_hy2() {
    local password candidate state
    if [[ -f "$HY2_CONF" ]]; then
        echo "HY2 已部署，请从更新菜单修改。"; pause; return
    fi
    hy2_ownership || { pause; return; }
    echo "HY2 第一阶段：官方 Hysteria 2 独立 systemd 服务；TLS 证书通过 Let's Encrypt HTTP-01 获取。"
    echo "需确保域名 A/AAAA 正确、TCP/80 可用，并在云防火墙开放选定 UDP 端口。"
    hy2_prompt_network || return
    hy2_prompt_domain || return
    hy2_prompt_port 34443 || return
    hy2_prompt_host "$HY2_DOMAIN" || return
    ask_node_name hy2 || return
    password=$(openssl rand -hex 24) || { pause; return; }
    hy2_install_binary || { pause; return; }
    hy2_service_install || { pause; return; }
    candidate=$(mktemp "$HY2_CONF_DIR/.ss2022-config.XXXXXX") || { pause; return; }
    hy2_candidate "$candidate" "$HY2_NETWORK" "$HY2_PORT" "$HY2_DOMAIN" "$password" || {
        rm -f "$candidate"; pause; return;
    }
    if hy2_apply "$candidate"; then
        state=$(jq -n --arg host "$HY2_HOST" --arg network "$HY2_NETWORK" --arg name "$NODE_NAME" \
            '{host:$host,network:$network,name:$name}')
        save_mode_state hy2 "$state" || true
        echo "✔ HY2 已部署，独立于 sing-box、Xray、Snell；请执行客户端公网连接验证。"
        hy2_details "$HY2_HOST" "$HY2_PORT" "$HY2_DOMAIN" "$password" "$NODE_NAME"
    fi
    pause
}

update_hy2() {
    local choice port domain password host network name new_port new_domain new_password new_network candidate state reply
    [[ -f "$HY2_CONF" && -x "$HY2_BIN" ]] && hy2_managed || {
        echo "HY2 尚未部署。"; pause; return;
    }
    while true; do
        port=$(hy2_current_port) || return 1
        domain=$(jq -r '.acme.domains[0]' "$HY2_CONF")
        password=$(jq -r '.auth.password' "$HY2_CONF")
        network=$(get_mode_state_field hy2 network 2>/dev/null || true)
        network=${network:-dual}
        host=$(get_mode_state_field hy2 host 2>/dev/null || true)
        host=${host:-$domain}
        name=$(get_node_name hy2)
        echo "════════════ HY2 参数更新 ════════════"
        echo "网络: $network  UDP端口: $port  TLS域名: $domain"
        echo " 1. 变更监听地址族"
        echo " 2. 变更 UDP 端口"
        echo " 3. 变更 TLS 域名（重新签发证书）"
        echo " 4. 更换认证密码（旧客户端失效）"
        echo " 5. 变更客户端连接地址（不重启服务）"
        echo " 6. 修改节点名称（不重启服务）"
        echo " 7. 查看节点配置"
        echo " 0. 返回"
        read -rp "请选择 [0-7]: " choice || return
        new_port="$port"; new_domain="$domain"; new_password="$password"; new_network="$network"
        case "$choice" in
            1) hy2_prompt_network || continue; new_network="$HY2_NETWORK" ;;
            2) hy2_prompt_port "$port" || continue; new_port="$HY2_PORT" ;;
            3) hy2_prompt_domain || continue; new_domain="$HY2_DOMAIN" ;;
            4) read -rp "确认更换密码？[y/N]: " reply
               [[ "$reply" =~ ^[Yy]$ ]] || continue
               new_password=$(openssl rand -hex 24) || continue ;;
            5) hy2_prompt_host "$host" || continue
               save_mode_state hy2 "$(jq -n --arg host "$HY2_HOST" '{host:$host}')" || true
               echo "已更新客户端地址。"; pause; continue ;;
            6) rename_node_name hy2 "Hysteria 2"; pause; continue ;;
            7) view_hy2_config; pause; continue ;;
            0) return ;;
            *) continue ;;
        esac
        candidate=$(mktemp "$HY2_CONF_DIR/.ss2022-config.XXXXXX") || continue
        hy2_candidate "$candidate" "$new_network" "$new_port" "$new_domain" "$new_password" || {
            rm -f "$candidate"; continue;
        }
        if hy2_apply "$candidate"; then
            state=$(jq -n --arg host "$host" --arg network "$new_network" '{host:$host,network:$network}')
            save_mode_state hy2 "$state" || true
            hy2_details "$host" "$new_port" "$new_domain" "$new_password" "$name"
        fi
        pause
    done
}

delete_hy2() {
    local confirm=""
    [[ -f "$HY2_CONF" ]] || { echo "HY2 未部署。"; pause; return; }
    hy2_managed || { echo "[错误] 非本工具箱服务，拒绝删除。"; pause; return; }
    read -rp "删除 HY2 节点、服务及本项目 ACME 证书数据？[y/N]: " confirm || return
    [[ "$confirm" =~ ^[Yy]$ ]] || return
    service_disable_now "$HY2_SERVICE_NAME"
    rm -f "$HY2_CONF" "$HY2_SERVICE"
    rm -rf "$HY2_CONF_DIR/acme"
    service_daemon_reload || true
    remove_mode_state hy2 || true
    echo "✔ HY2 节点已删除；其他协议不受影响。官方 HY2 核心保留。"
    pause
}
