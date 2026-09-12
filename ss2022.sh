#!/bin/bash
# ==============================================================================
# vps-bootstrap / ss2022.sh
# v1.8.0-dev17 / dev18 -> v1.8.0-dev19 综合升级补丁
#
# dev19:
#   1) 若当前仍为 dev17，自动补齐 dev18 的“服务器测试管理”四项测试
#   2) 四种协议节点支持自定义节点名称
#   3) 节点名称保存到 /etc/ss2022/state.json
#   4) 查看节点配置时复用已保存名称
#   5) 已部署旧节点可直接改名，不需要重新部署
#
# 默认节点名:
#   SS2022                  -> Proxy-SS2022
#   SS2022 + ShadowTLS v3   -> Proxy-SS2022-ShadowTLS
#   VLESS Reality           -> Proxy-VLESS-Reality
#   Snell v5                -> Proxy-Snell-v5
#
# 用法:
#   bash ss2022-v1.8.0-dev19-patch.sh
# 或:
#   bash ss2022-v1.8.0-dev19-patch.sh /path/to/ss2022.sh
#
# 默认目标:
#   /usr/local/bin/ss2022
# ==============================================================================

set -euo pipefail

TARGET="${1:-/usr/local/bin/ss2022}"
BACKUP="${TARGET}.bak-dev19-$(date +%Y%m%d-%H%M%S)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

die() {
    echo -e "${RED}[错误] $*${PLAIN}" >&2
    exit 1
}

[[ -f "$TARGET" ]] || die "未找到目标脚本: $TARGET"
grep -q '项目名称: vps-bootstrap / ss2022.sh' "$TARGET" || die "目标文件不是 vps-bootstrap / ss2022.sh"

CURRENT_VERSION=$(grep -E '^SCRIPT_VERSION=' "$TARGET" | head -n1 | cut -d'"' -f2)
case "$CURRENT_VERSION" in
    v1.8.0-dev17|v1.8.0-dev18)
        ;;
    v1.8.0-dev19)
        echo -e "${YELLOW}[提示] 当前已经是 v1.8.0-dev19，无需重复升级。${PLAIN}"
        exit 0
        ;;
    *)
        die "当前版本为 ${CURRENT_VERSION:-未知}。本补丁仅支持 v1.8.0-dev17 / dev18。"
        ;;
esac

cp -a "$TARGET" "$BACKUP"
echo -e "${GREEN}✔ 已备份: ${BACKUP}${PLAIN}"

python3 - "$TARGET" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")


def fail(msg):
    raise SystemExit(msg)


def patch_function(name, mutator):
    global text
    pattern = re.compile(
        rf'^{re.escape(name)}\(\) \{{.*?(?=^[A-Za-z_][A-Za-z0-9_]*\(\) \{{|\Z)',
        re.MULTILINE | re.DOTALL,
    )
    match = pattern.search(text)
    if not match:
        fail(f"无法定位函数: {name}()")
    old = match.group(0)
    new = mutator(old)
    text = text[:match.start()] + new + text[match.end():]


# -----------------------------------------------------------------------------
# 版本号 / changelog
# -----------------------------------------------------------------------------
text = re.sub(
    r'^# 当前版本: v1\.8\.0-dev(?:17|18)$',
    '# 当前版本: v1.8.0-dev19',
    text,
    count=1,
    flags=re.MULTILINE,
)
text = re.sub(
    r'^SCRIPT_VERSION="v1\.8\.0-dev(?:17|18)"$',
    'SCRIPT_VERSION="v1.8.0-dev19"',
    text,
    count=1,
    flags=re.MULTILINE,
)

DEV19_LOG = """# v1.8.0-dev19:
#   - 四种协议节点统一支持自定义节点名称
#   - 默认名称保持旧版风格：Proxy-SS2022 / Proxy-SS2022-ShadowTLS / Proxy-VLESS-Reality / Proxy-Snell-v5
#   - 节点名称保存到 /etc/ss2022/state.json，查看配置时持续复用
#   - state.json 的 save_mode_state 改为字段合并，更新协议参数时不会丢失节点名称
#   - “查看节点配置”新增“修改节点名称”，已部署旧节点无需重装即可改名
#   - 节点名称同步用于 URI fragment、Surge/Loon、Mihomo/FlClash 与二维码内容
#
"""
if DEV19_LOG not in text:
    marker = None
    for candidate in ('# v1.8.0-dev18:\n', '# v1.8.0-dev17:\n'):
        if candidate in text:
            marker = candidate
            break
    if marker is None:
        fail('无法定位 changelog 插入点')
    text = text.replace(marker, DEV19_LOG + marker, 1)

line17 = '#   v1.8.0-dev17 WARP 三种出口模式固定可选 / 按 VPS 网络自动推荐\n'
line18 = '#   v1.8.0-dev18 服务器测试工具正式接入\n'
line19 = '#   v1.8.0-dev19 协议节点自定义名称 / 旧节点在线改名\n'
if line17 in text:
    if line18 not in text:
        text = text.replace(line17, line17 + line18, 1)
    if line19 not in text:
        text = text.replace(line18, line18 + line19, 1)


# -----------------------------------------------------------------------------
# dev17 -> 补齐 dev18 服务器测试管理
# -----------------------------------------------------------------------------
if 'test_ai_unlock() {' not in text:
    server_test_block = r'''ensure_test_dependency() {
    local cmd="$1"
    local pkg="${2:-$1}"

    command -v "$cmd" >/dev/null 2>&1 && return 0

    echo -e "${YELLOW}>> 缺少 ${cmd}，正在安装 ${pkg}...${PLAIN}"

    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y >/dev/null 2>&1 || return 1
        apt-get install -y "$pkg" >/dev/null 2>&1 || return 1
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y "$pkg" >/dev/null 2>&1 || return 1
    elif command -v yum >/dev/null 2>&1; then
        yum install -y "$pkg" >/dev/null 2>&1 || return 1
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache "$pkg" >/dev/null 2>&1 || return 1
    else
        echo -e "${RED}[错误] 未识别包管理器，请手动安装 ${pkg}。${PLAIN}"
        return 1
    fi

    command -v "$cmd" >/dev/null 2>&1
}

show_external_test_source() {
    local name="$1"
    local source="$2"

    echo ""
    echo -e "${CYAN}════════════════════ ${name} ════════════════════${PLAIN}"
    echo -e "${YELLOW}测试来源: ${source}${PLAIN}"
    echo -e "${YELLOW}说明: 以下功能调用第三方开源测试脚本，仅用于检测，不修改 ss2022 协议/分流配置。${PLAIN}"
    echo ""
}

test_ip_quality() {
    clear
    show_external_test_source "IP 质量测试" "IP.Check.Place"

    ensure_test_dependency curl curl || {
        echo -e "${RED}[错误] curl 安装失败。${PLAIN}"
        pause
        return
    }

    bash <(curl -fsSL https://IP.Check.Place) || \
        echo -e "${RED}[错误] IP 质量测试脚本执行失败。${PLAIN}"

    echo ""
    pause
}

test_return_route() {
    local tmp=""
    clear
    show_external_test_source \
        "回程路由测试" \
        "https://github.com/Chennhaoo/Shell_Bash/blob/master/AutoTrace.sh"

    ensure_test_dependency wget wget || {
        echo -e "${RED}[错误] wget 安装失败。${PLAIN}"
        pause
        return
    }

    tmp=$(mktemp /tmp/ss2022-autotrace.XXXXXX.sh) || {
        echo -e "${RED}[错误] 无法创建临时文件。${PLAIN}"
        pause
        return
    }

    if wget -q --no-check-certificate \
        -O "$tmp" \
        "https://raw.githubusercontent.com/Chennhaoo/Shell_Bash/master/AutoTrace.sh"; then
        chmod +x "$tmp"
        bash "$tmp" || \
            echo -e "${RED}[错误] AutoTrace 执行失败。${PLAIN}"
    else
        echo -e "${RED}[错误] AutoTrace 下载失败。${PLAIN}"
    fi

    rm -f "$tmp"
    echo ""
    pause
}

test_streaming_unlock() {
    clear
    show_external_test_source \
        "流媒体解锁测试" \
        "https://github.com/1-stream/RegionRestrictionCheck"

    ensure_test_dependency curl curl || {
        echo -e "${RED}[错误] curl 安装失败。${PLAIN}"
        pause
        return
    }

    bash <(curl -fsSL \
        "https://github.com/1-stream/RegionRestrictionCheck/raw/main/check.sh") || \
        echo -e "${RED}[错误] 流媒体解锁测试脚本执行失败。${PLAIN}"

    echo ""
    pause
}

test_ai_unlock() {
    clear
    show_external_test_source \
        "AI 工具测试" \
        "https://github.com/adsorgcn/vpscheck"

    echo -e "${CYAN}检测范围: ChatGPT / OpenAI API / Gemini / Claude / Copilot / Grok / Perplexity / Mistral / Poe / Sora / DeepSeek / Kimi 等${PLAIN}"
    echo ""

    ensure_test_dependency curl curl || {
        echo -e "${RED}[错误] curl 安装失败。${PLAIN}"
        pause
        return
    }

    bash <(curl -fsSL \
        "https://raw.githubusercontent.com/adsorgcn/vpscheck/main/vpscheck.sh") -r 5 || \
        echo -e "${RED}[错误] AI 工具测试脚本执行失败。${PLAIN}"

    echo ""
    pause
}

server_test_management() {
    while true; do
        clear
        echo -e "${CYAN}════════════════════ 服务器测试管理 ════════════════════${PLAIN}"
        echo "  1. IP 质量测试"
        echo "  2. 回程路由测试"
        echo "  3. 流媒体解锁测试"
        echo "  4. AI 工具测试"
        echo "  0. 返回"
        echo -e "${CYAN}═══════════════════════════════════════════════════════${PLAIN}"
        read -rp "请选择 [0-4]: " c
        case "$c" in
            1) test_ip_quality ;;
            2) test_return_route ;;
            3) test_streaming_unlock ;;
            4) test_ai_unlock ;;
            0) return ;;
            *) sleep 1 ;;
        esac
    done
}

'''
    pattern = re.compile(
        r'^server_test_management\(\) \{.*?(?=^protocol_operations_management\(\) \{)',
        re.MULTILINE | re.DOTALL,
    )
    if not pattern.search(text):
        fail('无法定位 server_test_management()，无法从 dev17 补齐服务器测试')
    text = pattern.sub(server_test_block, text, count=1)


# -----------------------------------------------------------------------------
# state.json 改为字段合并；后续更新协议时不会擦掉 name
# -----------------------------------------------------------------------------
old_save = "'.[$mode] = $obj'"
new_save = "'.[$mode] = ((.[$mode] // {}) + $obj)'"
if old_save in text:
    text = text.replace(old_save, new_save, 1)
elif new_save not in text:
    fail('无法修改 save_mode_state() 合并逻辑')


# -----------------------------------------------------------------------------
# 节点名称公共函数
# -----------------------------------------------------------------------------
if 'default_node_name() {' not in text:
    helpers = r'''default_node_name() {
    case "$1" in
        ss)        printf '%s' "Proxy-SS2022" ;;
        shadowtls) printf '%s' "Proxy-SS2022-ShadowTLS" ;;
        vless)     printf '%s' "Proxy-VLESS-Reality" ;;
        snell)     printf '%s' "Proxy-Snell-v5" ;;
        *)         printf '%s' "Proxy-Node" ;;
    esac
}

get_node_name() {
    local mode="$1"
    local name=""

    name=$(get_mode_state_field "$mode" "name" 2>/dev/null || true)
    if [[ -n "$name" ]]; then
        printf '%s' "$name"
    else
        default_node_name "$mode"
    fi
}

validate_node_name() {
    local name="$1"

    [[ -n "$name" ]] || return 1
    [[ ${#name} -le 64 ]] || return 1

    # 兼容 Surge/Loon 左侧名称、YAML 双引号与 URI fragment。
    case "$name" in
        *$'\n'*|*$'\r'*|*'='*|*','*|*'"'*|*'\\'*)
            return 1
            ;;
    esac

    return 0
}

ask_node_name() {
    local mode="$1"
    local current="${2:-}"
    local default input=""

    default=${current:-$(default_node_name "$mode")}

    while true; do
        read -rp "节点名称 [默认: ${default}]: " input
        input=${input:-$default}

        if validate_node_name "$input"; then
            NODE_NAME="$input"
            return 0
        fi

        echo -e "${RED}节点名称无效：不能为空、最多 64 个字符，且不能包含 = , \" 或反斜杠。${PLAIN}"
    done
}

protocol_mode_exists() {
    case "$1" in
        ss)        json_has_inbound_tag "$TAG_SS" ;;
        shadowtls) json_has_inbound_tag "$TAG_STLS" ;;
        vless)     xray_vless_exists ;;
        snell)     protocol_exists_snell ;;
        *)         return 1 ;;
    esac
}

rename_node_name() {
    local mode="$1"
    local label="$2"
    local current=""

    if ! protocol_mode_exists "$mode"; then
        echo -e "${YELLOW}${label} 尚未部署。${PLAIN}"
        return 1
    fi

    current=$(get_node_name "$mode")
    echo -e "当前节点名称: ${GREEN}${current}${PLAIN}"
    ask_node_name "$mode" "$current" || return 1

    if save_mode_state "$mode" "$(jq -n --arg name "$NODE_NAME" '{name:$name}')"; then
        echo -e "${GREEN}✔ ${label} 节点名称已修改为: ${NODE_NAME}${PLAIN}"
        echo -e "${YELLOW}提示: 仅修改客户端导出名称，不需要重启代理服务。${PLAIN}"
        return 0
    fi

    echo -e "${RED}[错误] 节点名称保存失败。${PLAIN}"
    return 1
}

node_name_management() {
    while true; do
        clear
        echo -e "${CYAN}════════════════════ 修改节点名称 ════════════════════${PLAIN}"

        if protocol_mode_exists ss; then
            echo -e "  1. SS2022                  [${GREEN}$(get_node_name ss)${PLAIN}]"
        else
            echo "  1. SS2022                  [未部署]"
        fi

        if protocol_mode_exists shadowtls; then
            echo -e "  2. SS2022 + ShadowTLS v3   [${GREEN}$(get_node_name shadowtls)${PLAIN}]"
        else
            echo "  2. SS2022 + ShadowTLS v3   [未部署]"
        fi

        if protocol_mode_exists vless; then
            echo -e "  3. VLESS Reality           [${GREEN}$(get_node_name vless)${PLAIN}]"
        else
            echo "  3. VLESS Reality           [未部署]"
        fi

        if protocol_mode_exists snell; then
            echo -e "  4. Snell v5                [${GREEN}$(get_node_name snell)${PLAIN}]"
        else
            echo "  4. Snell v5                [未部署]"
        fi

        echo "  0. 返回"
        echo -e "${CYAN}═══════════════════════════════════════════════════════${PLAIN}"
        read -rp "请选择 [0-4]: " c

        case "$c" in
            1) rename_node_name "ss" "SS2022"; pause ;;
            2) rename_node_name "shadowtls" "SS2022 + ShadowTLS v3"; pause ;;
            3) rename_node_name "vless" "VLESS Reality"; pause ;;
            4) rename_node_name "snell" "Snell v5"; pause ;;
            0) return ;;
            *) sleep 1 ;;
        esac
    done
}

'''
    pattern = re.compile(
        r'^(get_mode_state_field\(\) \{.*?^\}\n\n)(?=ensure_singbox_user\(\) \{)',
        re.MULTILINE | re.DOTALL,
    )
    match = pattern.search(text)
    if not match:
        fail('无法定位 get_mode_state_field() 后的插入位置')
    text = text[:match.end()] + helpers + text[match.end():]

if 'NODE_NAME=""' not in text:
    marker = 'LISTEN_ADDR=""\n'
    if marker not in text:
        fail('无法定位全局临时参数 LISTEN_ADDR')
    text = text.replace(marker, marker + 'NODE_NAME=""\n', 1)


# -----------------------------------------------------------------------------
# 四种客户端配置输出函数：tag 改为可传入名称
# -----------------------------------------------------------------------------
def patch_show_ss(block):
    if 'local tag="Proxy-SS2022"' in block:
        block = block.replace(
            '    local tag="Proxy-SS2022"\n',
            '    local tag="${5:-$(default_node_name ss)}"\n',
            1,
        )
    heading = '    echo -e "${CYAN}════════════════════ SS2022 节点配置 ════════════════════${PLAIN}"\n'
    if '  节点名称:' not in block and heading in block:
        block = block.replace(
            heading,
            heading + '    echo -e "  节点名称: ${GREEN}${tag}${PLAIN}"\n',
            1,
        )
    return block


def patch_show_shadowtls(block):
    if 'local tag="Proxy-SS2022-ShadowTLS"' in block:
        block = block.replace(
            '    local tag="Proxy-SS2022-ShadowTLS"\n',
            '    local tag="${9:-$(default_node_name shadowtls)}"\n',
            1,
        )
    heading = '    echo -e "${CYAN}════════════════ SS2022 + ShadowTLS v3 配置 ════════════════${PLAIN}"\n'
    if '  节点名称:' not in block and heading in block:
        block = block.replace(
            heading,
            heading + '    echo -e "  节点名称: ${GREEN}${tag}${PLAIN}"\n',
            1,
        )
    block = block.replace(
        '--arg type "ss2022-shadowtls" --arg server "$host"',
        '--arg name "$tag" --arg type "ss2022-shadowtls" --arg server "$host"',
        1,
    )
    block = block.replace(
        "'{type:$type,server:$server,port:$port,cipher:$cipher,password:$password,shadow_tls:",
        "'{name:$name,type:$type,server:$server,port:$port,cipher:$cipher,password:$password,shadow_tls:",
        1,
    )
    return block


def patch_show_vless(block):
    if 'local url_host tag="Proxy-VLESS-Reality"' in block:
        block = block.replace(
            '    local url_host tag="Proxy-VLESS-Reality"\n',
            '    local tag="${7:-$(default_node_name vless)}"\n    local url_host\n',
            1,
        )
    heading = '    echo -e "${CYAN}════════════════════ VLESS Reality 配置 ════════════════════${PLAIN}"\n'
    if '  节点名称:' not in block and heading in block:
        block = block.replace(
            heading,
            heading + '    echo -e "  节点名称: ${GREEN}${tag}${PLAIN}"\n',
            1,
        )
    return block


def patch_show_snell(block):
    if 'local tag="Proxy-Snell-v5"' in block:
        block = block.replace(
            '    local tag="Proxy-Snell-v5"\n',
            '    local tag="${4:-$(default_node_name snell)}"\n',
            1,
        )
    heading = '    echo -e "${CYAN}════════════════════ Snell v5 配置 ════════════════════${PLAIN}"\n'
    if '  节点名称:' not in block and heading in block:
        block = block.replace(
            heading,
            heading + '    echo -e "  节点名称: ${GREEN}${tag}${PLAIN}"\n',
            1,
        )
    block = block.replace(
        '--arg type "snell" --arg server "$host"',
        '--arg name "$tag" --arg type "snell" --arg server "$host"',
        1,
    )
    block = block.replace(
        "'{type:$type,server:$server,port:$port,psk:$psk,version:5,udp:true}'",
        "'{name:$name,type:$type,server:$server,port:$port,psk:$psk,version:5,udp:true}'",
        1,
    )
    return block


patch_function('show_ss_details', patch_show_ss)
patch_function('show_shadowtls_details', patch_show_shadowtls)
patch_function('show_vless_details', patch_show_vless)
patch_function('show_snell_details', patch_show_snell)


# -----------------------------------------------------------------------------
# 部署流程：安装时询问名称、保存 name、首次输出使用该名称
# -----------------------------------------------------------------------------
def deploy_ss(block):
    if 'ask_node_name "ss"' not in block:
        block = block.replace(
            '    ask_server_host\n',
            '    ask_server_host\n    ask_node_name "ss" || return\n',
            1,
        )
    block = block.replace(
        "save_mode_state \"ss\" \"$(jq -n --arg host \"$SERVER_HOST\" --arg network \"$NETWORK_MODE\" '{host:$host,network:$network}')\"",
        "save_mode_state \"ss\" \"$(jq -n --arg host \"$SERVER_HOST\" --arg network \"$NETWORK_MODE\" --arg name \"$NODE_NAME\" '{host:$host,network:$network,name:$name}')\"",
        1,
    )
    block = block.replace(
        'show_ss_details "$SERVER_HOST" "$PORT" "$METHOD" "$SS_KEY"',
        'show_ss_details "$SERVER_HOST" "$PORT" "$METHOD" "$SS_KEY" "$NODE_NAME"',
        1,
    )
    return block


def deploy_shadow(block):
    if 'ask_node_name "shadowtls"' not in block:
        block = block.replace(
            '    ask_server_host\n',
            '    ask_server_host\n    ask_node_name "shadowtls" || return\n',
            1,
        )
    block = block.replace(
        "save_mode_state \"shadowtls\" \"$(jq -n --arg host \"$SERVER_HOST\" --arg network \"$NETWORK_MODE\" '{host:$host,network:$network}')\"",
        "save_mode_state \"shadowtls\" \"$(jq -n --arg host \"$SERVER_HOST\" --arg network \"$NETWORK_MODE\" --arg name \"$NODE_NAME\" '{host:$host,network:$network,name:$name}')\"",
        1,
    )
    block = block.replace(
        'show_shadowtls_details "$SERVER_HOST" "$tcp_port" "$METHOD" "$SS_KEY" "$stls_pass" "$sni" "$udp_enabled" "$udp_port"',
        'show_shadowtls_details "$SERVER_HOST" "$tcp_port" "$METHOD" "$SS_KEY" "$stls_pass" "$sni" "$udp_enabled" "$udp_port" "$NODE_NAME"',
        1,
    )
    return block


def deploy_vless(block):
    if 'ask_node_name "vless"' not in block:
        block = block.replace(
            '    ask_server_host\n',
            '    ask_server_host\n    ask_node_name "vless" || return\n',
            1,
        )
    block = block.replace(
        "save_mode_state \"vless\" \"$(jq -n --arg host \"$SERVER_HOST\" --arg network \"$NETWORK_MODE\" --arg public_key \"$REALITY_PUBLIC_KEY\" '{host:$host,network:$network,public_key:$public_key,core:\"xray\"}')\"",
        "save_mode_state \"vless\" \"$(jq -n --arg host \"$SERVER_HOST\" --arg network \"$NETWORK_MODE\" --arg public_key \"$REALITY_PUBLIC_KEY\" --arg name \"$NODE_NAME\" '{host:$host,network:$network,public_key:$public_key,core:\"xray\",name:$name}')\"",
        1,
    )
    block = block.replace(
        'show_vless_details "$SERVER_HOST" "$vless_port" "$uuid" "$sni" "$REALITY_PUBLIC_KEY" "$short_id"',
        'show_vless_details "$SERVER_HOST" "$vless_port" "$uuid" "$sni" "$REALITY_PUBLIC_KEY" "$short_id" "$NODE_NAME"',
        1,
    )
    return block


def deploy_snell(block):
    if 'ask_node_name "snell"' not in block:
        block = block.replace(
            '    ask_server_host\n',
            '    ask_server_host\n    ask_node_name "snell" || return\n',
            1,
        )
    block = block.replace(
        "save_mode_state \"snell\" \"$(jq -n --arg host \"$SERVER_HOST\" --arg network \"$NETWORK_MODE\" '{host:$host,network:$network}')\"",
        "save_mode_state \"snell\" \"$(jq -n --arg host \"$SERVER_HOST\" --arg network \"$NETWORK_MODE\" --arg name \"$NODE_NAME\" '{host:$host,network:$network,name:$name}')\"",
        1,
    )
    block = block.replace(
        'show_snell_details "$SERVER_HOST" "$snell_port" "$psk"',
        'show_snell_details "$SERVER_HOST" "$snell_port" "$psk" "$NODE_NAME"',
        1,
    )
    return block


patch_function('deploy_ss2022', deploy_ss)
patch_function('deploy_shadowtls', deploy_shadow)
patch_function('deploy_vless_reality', deploy_vless)
patch_function('deploy_snell_v5', deploy_snell)


# -----------------------------------------------------------------------------
# 查看配置：读取已保存名称；旧节点无 name 时回退到默认名
# -----------------------------------------------------------------------------
def view_ss(block):
    block = block.replace(
        '    local host port method pass listen ip_type\n',
        '    local host port method pass listen ip_type name\n',
        1,
    )
    if 'name=$(get_node_name "ss")' not in block:
        block = block.replace(
            '    show_ss_details "$host" "$port" "$method" "$pass"\n',
            '    name=$(get_node_name "ss")\n    show_ss_details "$host" "$port" "$method" "$pass" "$name"\n',
            1,
        )
    return block


def view_shadow(block):
    block = block.replace(
        '    local host port method ss_pass stls_pass sni listen udp_enabled="false" udp_port=""\n',
        '    local host port method ss_pass stls_pass sni listen udp_enabled="false" udp_port="" name\n',
        1,
    )
    if 'name=$(get_node_name "shadowtls")' not in block:
        block = block.replace(
            '    show_shadowtls_details "$host" "$port" "$method" "$ss_pass" "$stls_pass" "$sni" "$udp_enabled" "$udp_port"\n',
            '    name=$(get_node_name "shadowtls")\n    show_shadowtls_details "$host" "$port" "$method" "$ss_pass" "$stls_pass" "$sni" "$udp_enabled" "$udp_port" "$name"\n',
            1,
        )
    return block


def view_vless(block):
    block = block.replace(
        '    local host port uuid sni private public short_id listen out\n',
        '    local host port uuid sni private public short_id listen out name\n',
        1,
    )
    if 'name=$(get_node_name "vless")' not in block:
        block = block.replace(
            '    show_vless_details "$host" "$port" "$uuid" "$sni" "$public" "$short_id"\n',
            '    name=$(get_node_name "vless")\n    show_vless_details "$host" "$port" "$uuid" "$sni" "$public" "$short_id" "$name"\n',
            1,
        )
    return block


def view_snell(block):
    block = block.replace(
        '    local host port psk listen\n',
        '    local host port psk listen name\n',
        1,
    )
    if 'name=$(get_node_name "snell")' not in block:
        block = block.replace(
            '    show_snell_details "$host" "$port" "$psk"\n',
            '    name=$(get_node_name "snell")\n    show_snell_details "$host" "$port" "$psk" "$name"\n',
            1,
        )
    return block


patch_function('view_ss2022_config', view_ss)
patch_function('view_shadowtls_config', view_shadow)
patch_function('view_vless_config', view_vless)
patch_function('view_snell_config', view_snell)


# -----------------------------------------------------------------------------
# 查看节点配置菜单：新增“修改节点名称”
# -----------------------------------------------------------------------------
def patch_view_menu(block):
    if '5. 修改节点名称' in block:
        return block

    block = block.replace(
        '        echo "  4. Snell v5"\n        echo "  0. 返回"\n',
        '        echo "  4. Snell v5"\n        echo "  5. 修改节点名称"\n        echo "  0. 返回"\n',
        1,
    )
    block = block.replace(
        '        read -rp "请选择 [0-4]: " c\n',
        '        read -rp "请选择 [0-5]: " c\n',
        1,
    )
    block = block.replace(
        '            4) view_snell_config; pause ;;\n            0) return ;;\n',
        '            4) view_snell_config; pause ;;\n            5) node_name_management ;;\n            0) return ;;\n',
        1,
    )
    return block


patch_function('view_config_menu', patch_view_menu)


# -----------------------------------------------------------------------------
# 结构校验
# -----------------------------------------------------------------------------
required = [
    'SCRIPT_VERSION="v1.8.0-dev19"',
    'default_node_name() {',
    'ask_node_name() {',
    'node_name_management() {',
    'local tag="${5:-$(default_node_name ss)}"',
    'local tag="${9:-$(default_node_name shadowtls)}"',
    'local tag="${7:-$(default_node_name vless)}"',
    'local tag="${4:-$(default_node_name snell)}"',
    'ask_node_name "ss" || return',
    'ask_node_name "shadowtls" || return',
    'ask_node_name "vless" || return',
    'ask_node_name "snell" || return',
    '5. 修改节点名称',
    'test_ai_unlock() {',
]
missing = [item for item in required if item not in text]
if missing:
    fail('修改后结构校验失败，缺少: ' + ' | '.join(missing))

path.write_text(text, encoding='utf-8')
PY

chmod +x "$TARGET"

if ! bash -n "$TARGET"; then
    echo -e "${RED}[错误] 修改后的主脚本 Bash 语法检查失败，正在恢复备份。${PLAIN}"
    cp -af "$BACKUP" "$TARGET"
    exit 1
fi

if command -v shellcheck >/dev/null 2>&1; then
    if ! shellcheck --severity=error "$TARGET"; then
        echo -e "${RED}[错误] ShellCheck(error) 未通过，正在恢复备份。${PLAIN}"
        cp -af "$BACKUP" "$TARGET"
        exit 1
    fi
fi

echo -e "${GREEN}✔ 已升级到 v1.8.0-dev19。${PLAIN}"
echo ""
echo "新增节点名称逻辑："
echo "  SS2022                默认: Proxy-SS2022"
echo "  SS2022 + ShadowTLS     默认: Proxy-SS2022-ShadowTLS"
echo "  VLESS Reality          默认: Proxy-VLESS-Reality"
echo "  Snell v5               默认: Proxy-Snell-v5"
echo ""
echo "新部署协议时会询问节点名称，直接回车使用默认值。"
echo "已部署旧节点可进入："
echo "  查看节点配置 -> 5. 修改节点名称"
echo ""
echo -e "${YELLOW}备份文件: ${BACKUP}${PLAIN}"
