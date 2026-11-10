# VPS Bootstrap Management Suite

一体化 VPS 网络协议、服务端分流、端口转发与日常运维脚本。

当前正式版本：**v1.9.1**

项目以单一交互式 Bash 脚本 `ss2022.sh` 为入口，整合 **SS2022、SS2022 + ShadowTLS v3、VLESS Reality、Snell v5**，并提供 WARP 出口、链式落地、规则分流、Realm L4 端口转发、组件管理、服务器工具、服务器测试与脚本自更新。

> v1.9.1 为当前稳定正式版。Debian / Ubuntu + systemd 正式支持；Alpine 3.21 + OpenRC 正式支持 SS2022、ShadowTLS v3、VLESS Reality、Realm 以及服务器管理/测试。Snell v5 与 Cloudflare WARP 在 Alpine 暂不开放。

---

## SS2022 IPv6 优先 + WARP IPv4 补全：v1.9.1（正式稳定基线）

日本 IPv6-only VPS 已通过 A/B 和 Surge 实机验证：**双栈网站优先 VPS 原生 IPv6，IPv4-only 网站使用系统级 Cloudflare WARP IPv4**。注意：fscarmen 菜单集成本身已通过 CI，但尚未在全新 VPS 上进行从零安装实测。

- **菜单入口：** `ss2022 → 2 分流管理 → 6 SS2022 IPv6 优先 / WARP IPv4 补全（稳定基线）`。
- **3. 安装系统 WARP IPv4（fscarmen 作者原版）**：直接调用 `https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh` 的 `4` 模式；无需另找下载命令。检测已有 WARP 或 IPv4 默认路由时拒绝覆盖。
- **4. fscarmen 官方 WARP 管理菜单**：安装完成后从工具箱直接进入作者原生管理界面，不复制其内部实现。
- **5. 一键启用 SS2022 IPv6 优先**：在作者上游安装好系统级 WARP IPv4 后再选择该项。
- 包含策略状态、独立只读 A/B 检测、fscarmen 上游安装/管理、一键启用、菜单备份恢复。重复启用已生效的配置时不重启服务。
- 只控制 sing-box `direct` 出站，其他节点、链式转发、显式地址族分流以及 SSH/防火墙/系统路由保持不变。
- 启用前要求**原生 IPv6、已存在的系统 WARP IPv4、sing-box 候选配置检查和真实双栈/IPv4-only 出口**全部通过，失败不应用。
- 分流配置重建会保留已明确启用的 `prefer_ipv6`，但不会对其他 VPS 默认开启；高版本核心若不兼容旧参数会拒绝修改。
- 详细安全边界与验收记录：[SS2022 IPv6-first 实机稳定基线](docs/SS2022-IPV6-FIRST-BASELINE.md)。此功能自 dev16 开始验证，并在 v1.9.1 正式版中固定为可复用基线。

## Snell v5 专用 WARP IPv6 TCP 自动出站：v1.9.1-dev15（开发版）

针对 **IPv4-only VPS + Snell v5 + WARP Local Proxy**：使用独立 sing-box TUN（不启用 auto_route），只将 `snell` 系统用户发起的 **公网 IPv6 TCP** 连接，通过私有路由表 `16381` 转发给 WARP SOCKS5（本机代理）。IPv4 流量、其他 UID、SSH 和全局默认路由不变，**任意 IPv6 TCP 落地无需逐个桥接**，Surge 保留原有 Snell 前置链式配置。

- 菜单：`5. 协议运维管理 → 16. Snell 专用 WARP IPv6 TCP 自动出站`
- 安全前提：Debian/Ubuntu systemd、工具箱托管的 Snell v5（systemd User=snell）、已有 sing-box 核心、可用 WARP Local SOCKS5 IPv6、/dev/net/tun、独占 TUN `swipv6tun` 与路由偏好/表 `16381`。
- 启用前需输入 `YES`；若 Snell 原配置 `ipv6=false`，会备份并重启 Snell 一次（可能短暂断连）。卸载时仅在校验通过且用户未另行修改原配置的情况下恢复。
- 本功能仅适用于 **IPv6 TCP**（IPv6 UDP/QUIC 不支持），不更改 Cloudflare WARP 模式、不添加 nftables/iptables 规则、不覆盖现有代理配置或系统默认路由。
- 自动化测试验证配置/ownership/回滚逻辑；**尚未通过实际 VPS 上的 TUN + Surge 全链路测试**，不要将 CI 通过视为真实可用性保证。
- 旧菜单 15 的 `dev14` 固定目标桥接保留为旧版兼容选项，不是新方案的必需组件。

---

## Snell → WARP IPv6 TCP 桥接：v1.9.1-dev14（开发版）

IPv4-only VPS 上的 WARP Local Proxy 只提供本机 SOCKS5，不会给 Snell 创建原生 IPv6 路由。因此新增单独的桥接服务，在 **协议运维管理 → 15. Snell v5 → WARP IPv6 TCP 桥接** 中选装。

- **适用**：IPv4-only 的 Snell v5 前置，WARP IPv6 已启用，需要访问 IPv6-only SS2022 落地 TCP 端口。
- **路径**：Surge → Snell (IPv4) → 前置 VPS 本地 127.0.0.1:16001 → sing-box 独立 Direct TCP Inbound → WARP Local SOCKS5 → SS2022 IPv6:10000。
- **Surge 第二跳必须新建**：`SS2022-WARP = ss, 127.0.0.1, 16001, encrypt-method=<原方法>, password=<原密钥>, underlying-proxy=<Snell策略名>, udp-relay=false`。旧的 SS2022 IPv6 节点保持不变；不能继续让 Snell 直接访问它的 IPv6 地址。
- **隔离**：不开放公网端口，不修改系统 IPv6 默认路由、不切 WARP 全局模式，不改 Snell/SS2022 密钥或现有节点。独立 systemd unit、独立配置、独立卸载；对已有非托管文件拒绝覆盖。若本工具箱 sing-box 核心缺失，明确 STOP 而不安装或覆盖原有核心。
- **边界**：只支持 TCP；尚未通过用户 Surge 实机完成 Snell → loopback → WARP → SS2022 全链路验证，需在 VPS 配置校验后再测试。WARP TCP 可达并不等于链式协议握手成功。

---

## IPv6 链式代理兼容性修复：v1.9.1-dev13

已在 Surge 实机确认：Snell v5 采用 IPv4 入站监听且配置为 `ipv6=false` 时，双栈 VPS 无法转发到 IPv6-only SS2022 落地；开启 `ipv6=true` 后恢复。修复原则是将「客户端接入的监听地址族」与「服务端访问下一跳的目标地址族」分离，而不是强制所有服务器只用 IPv6。

- **Snell v5 / v6**：首次部署和更新时，通过本地 IPv6 源路由判断双栈出站；即便监听 `0.0.0.0`，有可路由公网 IPv6 时仍生成 `ipv6=true`。更新时保留原来已经开启的 IPv6 能力，避免临时路由故障导致回退。真正 IPv4-only 的服务器继续采用 `ipv6=false`。
- **SS2022 / SS2022 + ShadowTLS v3**：sing-box `direct` 默认支持 IPv4/IPv6，不因 `listen=0.0.0.0` 限制 IPv6 出站。已加入回归测试，不添加无效配置字段；如已有自定义分流强制 IPv4，将在诊断页给出提示，不擅自改用户分流。
- **VLESS Reality（Xray）/ HY2**：官方 Freedom / direct 默认支持双栈出口，增加自动化回归检查；不修改现有密钥、端口或证书。
- **诊断入口**：「服务器测试管理 → 5. 代理协议 IPv6 出站 / 链式兼容性检查」。只读检查各核心配置、默认出站与用户分流，并允许输入 IPv6 落地地址和 TCP 端口检查基础网络可达性。TCP 通不等于协议转发成功；需要 Surge 或实际客户端完成第二跳验收。
- 不自动修改正在运行的 VPS 配置，不重启原有节点；新脚本只有在用户执行协议部署或更新时才应用配置。

---

## HY2（Hysteria 2）开发版：v1.9.1-dev12

通过「协议管理 → 6. Hysteria 2（HY2 / QUIC-UDP）」部署，使用 Hysteria 官方 v2.13.0 独立核心（固定 SHA256 校验），基于 QUIC/UDP、TLS 加密与密码认证。首期仅开放 Debian / Ubuntu + systemd、amd64/arm64。

- 支持 IPv4-only、IPv6-only、双栈独立监听；不修改现有 sing-box、Xray、Snell、Realm 和全局网络设置。
- 提供部署、修改监听端口/地址族/TLS 域名/密码、查看配置、删除、运行日志与重启。
- 生成 Surge Hysteria 2 配置及 `hysteria2://` URI。Surge 官方支持最低 iOS 5.8、macOS 5.4；默认不启用实验性混淆和端口跳跃。
- 使用官方 ACME HTTP-01：需要域名 A/AAAA 能从公网解析至 VPS；服务器 TCP/80 与云平台防火墙必须允许证书验证；客户端连接需开放 HY2 UDP 端口（默认 34443）。不使用不安全 TLS 证书跳过选项。
- CI 通过也不代表真实 VPS 已完成证书签发和客户端 QUIC 握手。首次部署需单独进行实机连通验收。

官方文档：[Hysteria 2](https://v2.hysteria.network/docs/advanced/Full-Server-Config/) · [Surge Hysteria 2](https://manual.nssurge.com/policies/hysteria2.html)。

---

## 主要特性

### 四种网络协议模式

| 模式 | 服务端核心 | 说明 |
|---|---|---|
| **SS2022** | sing-box | Shadowsocks 2022 独立节点 |
| **SS2022 + ShadowTLS v3** | sing-box | 在 SS2022 基础上增加 ShadowTLS v3 流量伪装 |
| **VLESS Reality** | Xray-core | 独立 Xray 服务运行，不与 sing-box Reality 混用 |
| **Snell v5** | 官方 snell-server | Debian / Ubuntu 支持；Alpine 3.21 暂不支持 |

在 Debian / Ubuntu 上四种协议均可独立部署、更新参数、查看配置和删除；Alpine 3.21 当前支持前三种协议，Snell v5 因官方 glibc 二进制无法在 gcompat 下启动而关闭。

---

## 系统与架构支持

| 维度 | 当前支持 |
|---|---|
| **稳定正式版** | v1.9.1：Debian / Ubuntu + systemd；Alpine 3.21 + OpenRC |
| **CPU 架构** | x86_64 / amd64、aarch64 / arm64 |
| **网络环境** | IPv4-only、IPv6-only、IPv4 + IPv6 双栈 |
| **NAT VPS** | 可使用服务商映射端口部署节点 |
| **权限要求** | root |
| **Shell** | Bash |
| **Alpine 注意** | Snell v5 官方二进制不兼容 Alpine 3.21 + gcompat；WARP 官方客户端暂不支持 Alpine |

### 当前固定 / 推荐组件版本

| 组件 | 版本 |
|---|---|
| sing-box | 1.13.20 |
| Xray-core | 26.3.27 |
| Snell Server | 5.0.1 |
| Realm | 2.9.6 |

---

## 一键安装

在 VPS 中使用 **root** 权限执行：

```bash
curl -fsSL https://raw.githubusercontent.com/Jackyhuang83/vps-bootstrap/main/ss2022.sh \
  -o /usr/local/bin/ss2022 \
  && chmod +x /usr/local/bin/ss2022 \
  && { [ -e /usr/local/bin/proxy ] || [ -L /usr/local/bin/proxy ] || ln -s /usr/local/bin/ss2022 /usr/local/bin/proxy; } \
  && /usr/local/bin/ss2022
```

安装后可随时执行：

```bash
ss2022
```

如果 `/usr/local/bin/proxy` 没有被其它程序占用，安装/更新也会保留快捷命令：

```bash
proxy
```

进入管理面板。

---

## 首页 Realm 信息精简（v1.9.1-dev10）

Realm 首页只显示简短版本号、运行状态和规则数量，例如 `Realm 2.9.6 / ● 运行中 / 规则 1 条`。不再展示 `[brutal][batched-udp][proxy][balance][transport][multi-thread]` 等编译功能标签。原始 `realm --version` 信息与实际转发配置不变，功能没有被关闭。

## 首页协议状态（v1.9.1-dev9）

首页将「核心运行状态」与「节点部署状态」分开显示：sing-box 列出 SS2022 和 ShadowTLS v3（含已配置的 TCP/UDP 端口）；Xray 列出 VLESS Reality；Snell 列出 Snell v5。仅下载/安装了核心程序且没有节点配置时，显示「仅安装核心」，并明确标记对应协议「未部署」。

「已部署」只表示检测到对应节点配置，并不代表网络连通；「运行中」表示服务活跃，不等于客户端已通过连接测试。原有已部署协议统计仍保留，避免误解为所有核心都需要同时运行。

---

## 主菜单

```text
1. 协议管理
2. 分流管理
3. 端口转发（Realm）
4. 查看当前节点参数与客户端配置
5. 协议运维管理
6. 组件版本管理
--------------------------------
7. 服务器管理工具
8. 服务器测试管理
--------------------------------
9. 检查脚本更新
10. 完全卸载脚本
0. 退出管理面板
```

---

# 协议管理

## 1. SS2022

基于 sing-box 部署 Shadowsocks 2022。

支持：

- `2022-blake3-aes-128-gcm`
- `2022-blake3-aes-256-gcm`
- `2022-blake3-chacha20-poly1305`
- 自动生成合规 PSK
- TCP / UDP
- IPv4 / IPv6 / 双栈
- 自定义节点名称
- 节点参数修改
- 独立删除

---

## 2. SS2022 + ShadowTLS v3

基于 sing-box 部署 SS2022 + ShadowTLS v3。

ShadowTLS 主要用于增加 TLS-like 流量特征与主动探测抵抗能力，并不是额外增加一层内容加密。

支持：

- ShadowTLS v3
- SS2022 后端
- TCP ShadowTLS
- 可选独立 UDP
- 自定义 SNI / TLS 目标
- 自定义节点名称
- 配置修改与独立删除

---

## 3. VLESS Reality

使用独立 **Xray-core** 服务实现 VLESS Reality。

设计原则：

- Xray 使用独立二进制与配置目录
- Debian / Ubuntu 使用 systemd 服务 `ss2022-xray`；Alpine 使用对应 OpenRC 服务
- 不覆盖服务器已有的 Xray 安装
- 支持 Reality 参数自动生成
- 支持节点名称修改
- 支持服务端分流

---

## 5. Snell v6.0.0（独立可选）

从 `协议管理 → 5. Snell v6` 进入，支持独立部署、更新网络模式和端口、更换 PSK、查看 Surge 节点参数、删除节点；在协议运维中有独立日志与重启入口。服务名 `snell-v6`，与旧 `snell-v5` 独立，不自动迁移、覆盖、重启旧节点。默认仅采用官方加密与流量混淆 `mode=default`，不开放 `unsafe-raw` 明文模式。

支持 Debian / Ubuntu + systemd 的 amd64 / aarch64；Alpine 暂不开放。官方固定版本 `v6.0.0`，安装 ZIP 包固定 SHA256；Snell v6 管理代码作为 `modules/snell-v6.sh` 从本仓库加载，主脚本对模块执行固定 SHA256、文件标识和 Bash 语法检查后才允许运行。首次进入 v6 菜单需要能够访问 GitHub Raw 官方仓库路径。默认支持 IPv4、IPv6-only 和双栈监听。客户端需为支持 Snell v6 的 Surge，`version=6, mode=default`；**没有验证其它客户端时不生成 v6 假配置**。v6 已配置不等于已通过公网连通测试。

官方文档：https://kb.nssurge.com/surge-knowledge-base/release-notes/snell

## 6. Hysteria 2（HY2，独立选装）

从 **协议管理 → 6. Hysteria 2（HY2）** 进入。基于 Hysteria 官方 v2.13.0（官方 GitHub Release 下载，AMD64 / ARM64 固定 SHA-256 校验），使用独立的 `ss2022-hy2.service` 与 `/etc/ss2022-hy2/config.json`，不修改已有 sing-box、Xray、Snell 或 Realm 节点。

**首阶段支持范围：** Debian / Ubuntu + systemd；支持 IPv4、IPv6-only、双栈 UDP 监听。操作包括部署、更新地址族 / UDP 端口 / 域名 / 密码、删除、查看 Surge / 通用 HY2 URI 节点参数，以及日志、状态、重启。默认不启用端口跳跃或额外混淆；后续可在客户端版本验证后扩展。该阶段不做 VPS 服务端链式分流，分流仍由 Surge 或已有协议管理。

**证书约束：** 必须提供指向 VPS 的真实域名，官方 ACME HTTP-01 自动获取受信任 TLS 证书（需要 TCP/80 可入站，IPv6-only 使用 IPv6 监听）；需自行放行所选 **UDP 端口**。Cloudflare 代理 DNS（橙云）不能替代对 HY2 UDP 入站的直达；建议使用灰云（DNS only）的 HY2 专属子域名。为安全起见，不提供 `skip-cert-verify` 作为部署默认值。未获得证书前不能认为节点可用。

**Surge 兼容：** iOS 5.8.0+，Mac 5.4.0+；标准示例：

```ini
[Proxy]
MY-HY2 = hysteria2, hy2.example.com, 34443, password=REPLACE_WITH_YOUR_PASSWORD, sni=hy2.example.com
```

Hysteria 2 基于 **QUIC / UDP**，适合丢包线路，但在阻断 UDP 的网络上可能无法连接，建议保留 SS2022 / VLESS Reality 作为备选。服务端部署完成并不代表外部网络已通过连接测试。

参考：<https://hysteria.network/docs/getting-started/Server/>、<https://manual.nssurge.com/policies/hysteria2.html>。

## 4. Snell v5

使用 Surge 官方 `snell-server`。

设计原则：

- 始终使用 Surge 官方 Snell Server v5，不替换成兼容实现
- Debian / Ubuntu 使用 systemd，Snell v5 保持正式支持
- Alpine 3.21 + gcompat 已通过 CI 实测：官方 Snell v5.0.1 无法启动，报 `Not a valid dynamic program`
- 因此 v1.9 在 Alpine 上暂不开放 Snell；不注入第三方 glibc，也不改用非官方 Snell 实现
- 早期 v1.9 dev 版本若留下 Snell OpenRC 服务，“完全卸载”仍会负责清理
- 不经过 sing-box
- 不参与 VPS 服务端分流
- 如需 Snell 分流，建议在 Surge 客户端使用 Rules

---

# 节点配置输出

脚本可根据不同协议输出相应客户端配置。

包括：

- 通用 URI / SIP002（适用时）
- Surge
- Loon（协议支持时）
- FlClash / Mihomo
- Shadowrocket
- 二维码
- 节点名称自定义

不同客户端对 ShadowTLS、Snell、独立 UDP 等参数支持程度不同，脚本会按照对应协议能力输出，不生成已知无效的伪配置。

---

# 服务端分流

服务端分流适用于：

- SS2022
- SS2022 + ShadowTLS v3
- VLESS Reality

Snell v5 保持官方 `snell-server` 架构，不参与 VPS 服务端分流。

## 可用出口

### DIRECT

直接使用 VPS 原生网络出口。

### WARP

通过 Cloudflare WARP Local Proxy 作为出口。

支持：

- 安装 / 配置 WARP
- 自动检测 VPS 原生 IPv4 / IPv6
- IPv4 / IPv6 / 双栈出口模式
- 测试 WARP 实际出口
- WARP 重连
- WARP 重新注册
- WARP 卸载

### 落地节点

支持添加：

- Shadowsocks
  - 自动识别标准 SS / SS2022
  - 支持粘贴 `ss://` URI
  - 支持手动输入
- SOCKS5

可对落地节点进行查看、删除、测试，并设置为默认出口。

---

## 分流规则

内置规则类型：

- OpenAI / ChatGPT
- Netflix
- YouTube
- Google
- Telegram
- MyTVSuper
- Apple TV+
- TikTok
- Google Gemini（网页、AI Studio、Gemini API）
- Claude（网页、Anthropic API）
- 4GTV（台湾四季线上）
- 自定义域名 / IP / CIDR

自定义规则支持：

- 精确域名
- 域名后缀
- 域名关键字
- IP / CIDR

每条规则可以独立指定：

- DIRECT
- WARP
- 指定落地节点
- IPv4 / IPv6 / 默认地址族

同时支持规则顺序调整和全局默认出口。

### 4GTV（台湾四季线上）独立分流（v1.9.1-dev4 开发分支）

通过 `分流管理 → 分流规则管理 → 新增规则 → 11. 4GTV` 创建可选规则，可选择 DIRECT、WARP 或已有落地节点；在「应用 IPv4 / IPv6 分流」中也增加第 11 项 4GTV，可独立指定地址族。两个菜单的「自定义域名 / IP」选项均调整为第 12 项。

- 官网与子域名：`4gtv.tv`。
- 指定 CDN 主机：`4gtvfreepc-cds.cdn.hinet.net`、`4gtvfreepcvod-cds.cdn.hinet.net`、`4gtvpc-cds.cdn.hinet.net`、`4gtvpcvod-cds.cdn.hinet.net`。
- 不泛匹配共享的 `cdn.hinet.net` 或 `ftv.com.tw`，避免波及其它服务。
- 只新增可选预置；升级不会自动创建规则或修改 `routing.json`。实际播放可能仍受登录、授权、CDN 变化、DRM 和地区限制影响。

### Gemini / Claude 独立分流（v1.9.1-dev3 开发分支）

> v1.9.1-dev3 修复 sing-box 1.14+ 的分流与 Shadowsocks 落地测试兼容问题：将废弃的 `domain_strategy` 改为 `domain_resolver`，保留 IPv4/IPv6 指定解析及 WARP 中转，并继续在正式应用前进行配置校验与失败回滚。

进入 `分流管理 → 分流规则管理 → 添加规则`，选择 **9. Google Gemini** 或 **10. Claude**，再分别选择 DIRECT、WARP 或已添加的落地节点；在 `应用 IPv4 / IPv6 分流` 中也可单独调整两者的地址族。

- **Gemini**：`gemini.google.com`、`aistudio.google.com`、`generativelanguage.googleapis.com`、`ai.google.dev`（含其子域名）。
- **Claude**：`claude.ai`、`anthropic.com`、`claude.com`、`claudeusercontent.com`（含其子域名）。
- **规则优先级**：如果已有 Google 规则排在 Gemini 前，生成 sing-box/Xray 配置时自动将 Gemini 放在 Google 前，避免广泛的 `google.com` / `googleapis.com` 覆盖 Gemini；**不改写** `routing.json` 中的规则顺序，也不改变其他规则的相对顺序。
- **边界**：`accounts.google.com` 等通用 Google 登录域名不单独纳入 Gemini，以免影响 Google 账户等其它服务；涉及共享域名时，登录流量仍可能走 Google 规则或默认出口。
- **升级保护**：只新增可选预置规则，不自动添加、不修改用户现有出站或规则。更改分流后仍走现有候选配置校验与失败回滚流程。

---

# Realm L4 端口转发

集成 Realm 作为独立 L4 端口转发组件。

支持：

- 单端口转发
- 端口段转发
- 查看规则
- 修改规则
- 删除规则
- 测试规则
- Realm 服务管理

Realm 使用独立二进制、配置和独立服务；Debian/Ubuntu 使用 systemd，Alpine 使用 OpenRC，不覆盖服务器已有同名服务。

---

# 协议运维管理

**v1.9.1-dev8 的 Xray 重启修复**：首页将“仅安装 Xray 核心、尚未部署 VLESS Reality”与“已部署但服务停止”分开显示。菜单「协议运维管理 → 7. 重启 ss2022-xray」会预检本项目独立 Xray 二进制、VLESS 配置与配置语法；缺少专用服务时先征得确认才注册。重启后验证实际运行状态，失败时展示服务状态和最近日志。不会触碰其它 xray.service、sing-box、Snell 或节点参数。仅安装核心时请通过「协议管理 → VLESS Reality → 部署」创建节点，重启无法代替部署。

支持：

- 查看全部服务状态与监听端口
- sing-box 实时日志
- Xray 实时日志
- Snell v5 实时日志
- Realm 实时日志
- 重启 sing-box
- 重启 Xray
- 重启 Snell
- 重启 Realm
- IPv6 Keepalive 状态
- 各协议独立管理

---

# 组件版本管理

可查看和管理：

- sing-box
- Xray-core
- Snell Server
- Realm

在 Alpine 3.21 上，Snell Server 会明确显示“暂不支持”，单独升级入口会被阻断，“全部升级”会自动跳过 Snell。Debian / Ubuntu 的 Snell v5 管理保持不变。

核心下载会进行必要的来源与完整性校验，避免直接运行损坏或异常文件。

---

# 服务器管理工具

当前脚本集成了一组轻量服务器运维工具，不做“大而全”的系统工具箱。

## 系统信息

显示：

- 主机名
- 系统版本
- CPU 型号
- CPU 核心与频率
- 内存
- 虚拟内存
- 硬盘占用
- 运行时间（天）
- 本月入站流量
- 本月出站流量
- 时区
- IPv4
- IPv6
- IP 地理位置
- ISP / ASN
- IP 性质
- IP 风险
- DNS
- 网络算法，例如 `bbr fq_pie`

月流量状态会持久化保存，VPS 重启后继续累计，并按自然月进入新的统计周期。

---

## 端口占用

支持：

- 查看全部监听端口
- 查询指定端口
- 显示 PID / 进程 / systemd 或 OpenRC 服务 / Docker 映射
- 安全释放指定端口

释放端口支持：

- 停止 systemd / OpenRC 服务
- 停止并禁用 systemd / OpenRC 服务
- 停止 Docker 容器
- 结束监听进程

安全机制：

- 当前 SSH 会话使用的端口禁止释放
- 直接结束进程时优先发送 SIGTERM
- SIGTERM 无效时需要再次确认才执行 SIGKILL

---

## TG-BOT 流量监控

支持 Telegram Bot 流量监控：

- RX / 入站月流量
- TX / 出站月流量
- 自定义流量额度
- 自定义重置日
- 默认 80% / 90% / 100% 预警
- 自动关机阈值独立配置
- 默认自动关机阈值：**95%**
- Telegram 测试消息
- 状态查看
- 手动重置累计
- 停用 / 删除监控

自动关机默认关闭，需要用户主动开启并确认。

---

## 其它服务器工具

还包括：

- 系统更新 / 清理
- Swap 虚拟内存
- BBR
- DNS 管理
- IPv4 / IPv6 优先级
- 系统时区
- SSH 端口管理
- 重启服务器

DNS 管理支持：

- Cloudflare + Google
- Quad9 + Cloudflare
- 阿里 DNS + DNSPod
- **自定义 DNS**
- 支持厂商提供的流媒体 / 解锁专用 DNS
- IPv4 / IPv6 DNS
- 多 DNS 地址

SSH 端口修改采用安全方式：

- 保留原端口
- `sshd -t` 验证
- reload 后检查监听状态

重启服务器必须完整输入 `REBOOT`，避免误触。

---

# 服务器测试管理

当前服务器测试提供四个入口：

| 测试 | 使用项目 / 方式 |
|---|---|
| IP 质量 / 风险测试 | oneclickvirt / securityCheck |
| IPv4 / IPv6 三网逐跳回程 | nxtrace / NTrace-core（NextTrace 逐跳 traceroute） |
| 平台流媒体AI通信软件解锁测试 | 流媒体：1-stream / RegionRestrictionCheck；AI：oneclickvirt / UnlockTests；通信：curl 可达性检测 |
| Google 测试 | Google 搜索 IP 定位 / YouTube 地区辅助；澳门与所在地定位尝试 |

## Google 测试（v1.9.1-dev7）

入口：`ss2022 → 8. 服务器测试管理 → 4. Google 测试`。包含三个功能菜单：

1. **Google 送中检测**：按 IPv4 / IPv6 分开检测，显示当前出口 IP、出口地理库地区、Google 搜索底栏中明确标注来自 IP 的定位，以及 YouTube 客户端地区辅助信号。搜索底栏缺失时，追加一次匿名 Google 服务（Gemini）IP 地区查询；只解析指定 RPC 帧中明确标注 `SWML_DESCRIPTION_FROM_YOUR_INTERNET_ADDRESS` 的地区，不接受设备定位、账号活动或其他 RPC 字段。明确区分中国大陆 CN、香港 HK、澳门 MO、台湾 TW；搜索与 YouTube 冲突会单独提示，验证码、限流、超时、页面结构变化或证据不足均不报“正常”。搜索底栏有效时不追加接口请求；各服务分开列出，不把 Gemini 地区冒充搜索地区。若仅 YouTube 有台湾结果，会显示“部分结果——YouTube 地区为 TW，未见大陆信号；Google 搜索定位尚未确认”；接口与 YouTube 都为台湾时显示“未发现送中信号，Google 服务 IP 地区 TW，搜索定位未确认”；服务冲突及 CN 信号单独提示。检测使用全新无 Cookie 请求，不带 `gl` / `uule` 等强制地区参数，也不会把不跳转到国家域名解释为美国。
2. **尝试主动定位澳门**：向 Google 搜索和地图发送澳门地区及参考坐标请求。可手动运行，或主动启用每 6 小时的定时尝试。
3. **尝试拉回 VPS 所在地**：先查询 IP 地理库作为建议，再由用户按 VPS 实际机房位置核对国家代码、纬度和经度；查询失败可手动输入。提供 Google 官方 IP 定位纠错入口。

后两项各自提供“执行一轮 / 启用定时 / 查看状态 / 停止”操作。定时任务默认关闭；澳门和拉回共用一个任务，切换目标会替换旧任务。每轮每个地址族最多两个页面请求，遇到异常停止该地址族本轮请求。systemd 使用独立 timer；Alpine 使用已经运行的 crond，保留原有 cron 条目。停止会取消后续调度；已开始的 cron 请求最多 60 秒内结束。“完全卸载”会清理本功能创建的任务和文件。

**定位尝试的边界**：这些请求只能表达目标地区偏好，不能直接改写 Google 的 IP 定位数据库，不等同于浏览器 GPS，不保证送澳或拉回成功。HTTP 200 仅表示取得页面；执行后需回到第 1 项，用不带地区参数的请求独立复测。即使搜索显示目标地区，也不能证明其他 Google 产品已同步。Google 官方提供 [报告 IP 问题](https://support.google.com/websearch/workflow/9308722?hl=zh-Hans)，说明更正可能需要一个月以上。

所有请求使用系统当前路由并绕过 curl 环境代理和 `.curlrc`；已存在的全局 WARP、透明代理或策略路由仍可改变实际出口。IP 地理库与 Google 的识别结果可能不同，均不能证明实际机房位置。本功能不调整 DNS、WARP、代理节点、防火墙或已有分流规则。首次使用按需安装 curl / Python 3；无第三方脚本下载执行。

接口协议参考 [RegionRestrictionCheck 的 Google 地区探测](https://github.com/1-stream/RegionRestrictionCheck/blob/main/check.sh) 和 [GetUserLocation 响应结构](https://github.com/Leechael/gemini-web-cli/blob/main/internal/client/protocol/rpcs/get_user_location.go)，以独立的结构化解析实现，不下载或导入第三方代码。该接口非稳定公开 API；拒绝访问或结构变化时仍会显示未知，不推测成功。

验证：`bash tests/test-google.sh` 使用离线页面和 HTTP / systemd / cron 替身，检查识别、失败路径、配置、生成的独立 worker、定时替换和停止。该回归不证明真实 VPS 的地区已改变；页面解析与长期定位效果仍需实机验证。

## IPv4 / IPv6 回程路由

回程测试使用 `nxtrace/NTrace-core` 的 NextTrace，核心目标是显示**完整逐跳回程路径**，而不是只给线路分类结果。

默认测试：

- 北京：电信 / 联通 / 移动
- 上海：电信 / 联通 / 移动
- 广州：电信 / 联通 / 移动

共 9 条线路 / 地址族。每条线路使用 TCP 80 traceroute，最大 30 跳，并逐跳显示经过的 IP、ASN、运营商 / 地区信息和延迟。

支持：

- IPv4 + IPv6
- 仅 IPv4
- 仅 IPv6

测试目标使用 NextTrace 官方维护的运营商 endpoint；NextTrace tiny 二进制从官方 Release 临时下载，校验 SHA256 后执行，用完删除，不常驻安装。

逐跳结果才是判断实际回程路径的主要依据。线路名称（例如 CN2、9929、CMIN2、4837、CMI）应结合路由中出现的 ASN 和实际 hop 判断，而不是只依赖自动汇总标签。


## 平台流媒体AI通信软件解锁测试

服务器测试菜单中的第 3 项为一键综合流程。只需要选择一次流媒体地区和一次地址族，脚本会依次执行：

1. 流媒体解锁
2. AI 工具解锁
3. 通信软件可达性

三部分仍使用各自最合适的实现，不为了“单一脚本”而降低检测质量。通信软件部分的“解锁”仅表示网络可达性，不代表账号区服或消息发送能力。

## 流媒体 / 区域解锁

流媒体与 AI 完全分开。流媒体检测改用 `1-stream/RegionRestrictionCheck`，脚本固定到已验证的上游 commit，临时下载并校验 Git blob SHA 后执行，用完删除。

通用流媒体固定检测包括：

- Netflix
- YouTube Premium
- Disney+
- Amazon Prime Video
- Spotify
- Google Location
- YouTube CDN / Netflix CDN 等辅助项目

随后可按需追加台湾、香港、日本、韩国、北美、南美、欧洲、非洲、东南亚、大洋洲、体育平台或自定义多地区组合。通用流媒体只执行一次；“全部流媒体平台”不会调用上游 AI 检测函数。

流媒体与 AI 均支持：

- IPv4 + IPv6
- 仅 IPv4
- 仅 IPv6

流媒体测试会先分别显示 IPv4 / IPv6 的出口 IP 与出口国家/地区代码。这里的“出口地区”表示 VPS 网络出口所在地；Netflix、YouTube Premium、Prime Video 等平台结果中的 `Region` 表示平台自身识别到的解锁区服，两者分开显示。


## AI 工具测试

AI 测试使用 UnlockTests 的 AI-only 模式，可检测包括：

- ChatGPT
- Gemini
- Claude
- Copilot
- Grok
- Perplexity
- Poe

结果会区分 YES、NO、Restricted、Banned、RateLimited、TIMEOUT、DNS 失败等状态。

## 通信软件网络可达性

当前检测：

- Telegram
- WhatsApp
- Signal
- Discord

通信软件测试按 IPv4 / IPv6 分开执行，并显示对应地址族的出口 IP 与出口国家/地区代码。这里只检测 DNS、TCP、TLS 与 HTTPS 可达性，不登录账号、不读取账号凭据，也不把“网页可达”解释为消息一定可以正常发送。

第三方测试组件通过临时文件运行，用后删除；第三方组件自身退出码不会被简单误判为 `ss2022.sh` 执行失败。

---

# 脚本自更新

v1.9.1-dev6 修复 BusyBox / Alpine 下更新时报 `mktemp: : Invalid argument` 的问题：临时文件模板统一以 `XXXXXX` 结尾，避免 GNU mktemp 支持而 BusyBox 不支持的尾部扩展名写法。配置生成、落地节点测试和流媒体测试中的同类模板同时修正；原有语法校验、备份和回滚机制保留。旧版本无法通过自身菜单下载这个修复，需要先手动运行修复版更新器一次。

更新源：

```text
https://raw.githubusercontent.com/Jackyhuang83/vps-bootstrap/main/ss2022.sh
```

更新检查会分别显示：

```text
当前运行版本
系统安装版本
GitHub main 版本
```

支持识别：

- 远程版本更新
- 远程版本更旧
- 相同版本但内容 SHA256 不同
- 当前运行脚本与 GitHub main 一致，但系统安装版本落后

为避免误操作：

- 更新前备份 `/usr/local/bin/ss2022`
- 新脚本必须通过 `bash -n`
- 远程版本比当前运行版本更旧时默认拒绝自动降级
- 更新完成后重新进入安装后的管理面板

---

# 状态与配置文件

主要状态文件：

```text
/etc/ss2022/state.json
/etc/ss2022/routing.json
/etc/ss2022/forwarding.json
```

服务器工具相关：

```text
/etc/ss2022/system-info-traffic.state
/etc/ss2022/tg-monitor.conf
/etc/ss2022/tg-monitor.state
```

核心配置：

```text
/etc/sing-box/config.json
/etc/ss2022-xray/config.json
/etc/snell/snell-v5.conf
```

---

# 常用命令

## 打开管理面板

```bash
ss2022
```

或：

```bash
proxy
```

## 查看核心服务

Debian / Ubuntu（systemd）示例：

```bash
systemctl status sing-box
systemctl status ss2022-xray
systemctl status snell-v5
```

Alpine / OpenRC 示例：

```bash
rc-service sing-box status
rc-service ss2022-xray status
rc-service ss2022-realm status
```

Alpine 当前不提供 Snell v5 服务。

## 查看监听端口

```bash
ss -lntup
```

通常不需要手动维护这些服务，推荐直接通过 `ss2022` 管理面板操作。

---

# 安全设计

当前脚本的主要安全原则：

- 配置修改前生成候选配置
- 核心配置通过自检后才覆盖正式配置
- 配置失败时尽量回滚
- sing-box / Xray / Snell 使用独立运行用户
- Xray / Realm 使用 `ss2022` 独立命名空间
- Xray / Realm 使用项目独立命名空间，不覆盖服务器已有同名服务
- sing-box 与 Snell 使用通用路径，但安装前都会执行 ownership 检查；检测到外部安装时拒绝覆盖
- 服务用户/组仅在确认由本脚本创建时才会在卸载阶段删除
- 下载核心进行来源 / SHA256 校验
- SSH 端口修改保留旧端口并验证配置
- 端口释放保护当前 SSH 会话
- BBR 不自动替换内核
- DNS 管理不通过 `chattr` 锁死 `/etc/resolv.conf`
- 脚本自更新拒绝自动降级

---

# 完全卸载

主菜单提供：

```text
10. 完全卸载脚本
```

用于清理本项目创建的协议核心、服务、节点/分流/端口转发配置、状态文件和运行文件。Debian/Ubuntu 会清理对应 systemd 单元；Alpine/OpenRC 会同时移除本项目注册的 runlevel 服务与 `/etc/init.d` 脚本。对通用路径上的 sing-box / Snell，只有确认由 vps-bootstrap 管理时才会删除；外部已有安装会保留。

“完全卸载”**不会自动回滚用户通过服务器工具主动修改的系统设置**，包括 BBR、DNS、SSH 端口以及 IPv4/IPv6 地址优先级。这样做是为了避免卸载过程中意外改变网络或 SSH 可达性。需要恢复这些设置时，请在卸载前进入对应管理菜单手动恢复。

执行前请确认不再需要当前节点配置。

---

# 版本策略

## v1.8.x

v1.8.1 为上一稳定正式版。

后续 v1.8.x 仅处理：

- Bug 修复
- 稳定性优化
- 交互优化

原则上不再增加大型功能模块。

## v1.9.0

**v1.9.0 的发布记录：**该版本完成 Alpine / OpenRC 与卸载闭环收口：

- SS2022、ShadowTLS v3、VLESS Reality、Realm 已接入 OpenRC
- Snell v5 官方二进制已确认无法在 Alpine 3.21 + gcompat 下启动，因此 Alpine 暂不开放 Snell；Debian / Ubuntu 保持支持
- 服务器管理工具与服务器测试已完成主要 Alpine 适配
- Alpine 3.21 / OpenRC 已加入 GitHub Actions smoke test，覆盖平台识别、服务生成、runlevel、PID 与完全卸载闭环
- WARP 官方 Linux 客户端在 Alpine 暂不开放
- 完全卸载已覆盖脚本备份、OpenRC PID、TG-BOT lockdir、脚本命名空间临时文件；WARP 中途安装失败也可按 managed marker 清理
- Snell 安装候选文件使用 vps-bootstrap 专属隐藏前缀，异常中断后可由完全卸载安全清理；SSH 端口修改成功后会删除本次事务回滚备份
- systemd IPv6 Keepalive 使用 `ss2022-ipv6-keepalive.service/timer`；旧 `ipv6-keepalive.*` 只有在内容签名确认属于历史 vps-bootstrap 时才迁移/清理
- `/usr/local/bin/proxy` 快捷命令只在路径空闲或已属于本项目时创建/更新；已有外部文件或链接会原样保留，完全卸载也只删除本项目链接
- IPv6-only 的 APT 强制配置使用 `/etc/apt/apt.conf.d/99ss2022-force-ipv6`；历史通用 `99force-ipv6` 仅提示人工确认，不自动删除
- WARP 软件包与 Cloudflare APT 仓库分别记录 ownership；已有标准 Cloudflare source/keyring 只复用，卸载不会删除外部仓库配置
- `/etc/sing-box` 与 `/etc/snell` 视为可共享目录：只有脚本新建目录才记录 dir ownership；完全卸载只删除本项目配置与 `.ss2022-*` 临时文件，不再递归删除整个目录
- IPv6-only 临时 DNS 使用 vps-bootstrap 专属备份路径；旧 /root/resolv.conf.orig 仅用于兼容历史版本恢复，不再由新版本创建
- Debian / Ubuntu + systemd 路径继续保持兼容

v1.9.0 已完成上一稳定阶段的收口；v1.9.1 在其基础上增加可复用的 SS2022 IPv6 优先基线和 WARP IPv4 接入。

---

# 说明

本项目中的网络测试功能会调用第三方公开项目或服务。第三方项目的可用性、检测逻辑和结果准确性由对应项目维护者负责，本脚本仅提供调用入口。

IP 地理位置、IP 风险、流媒体和 AI 解锁结果均可能受数据库、CDN、地区策略、账号状态及检测时间影响，仅供参考。

---

# License

本项目基于 [MIT License](LICENSE) 开源。

仅用于网络工程技术研究、个人服务器运维及合规测试。使用者应遵守所在地法律法规、网络服务条款和 VPS 提供商规则，并自行承担使用风险。

