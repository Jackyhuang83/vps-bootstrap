# VPS Bootstrap Management Suite

一体化 VPS 网络协议、服务端分流、端口转发与日常运维脚本。

当前正式版本：**v1.8.1**  
当前开发版本：**v1.9.0-dev37**

项目以单一交互式 Bash 脚本 `ss2022.sh` 为入口，整合 **SS2022、SS2022 + ShadowTLS v3、VLESS Reality、Snell v5**，并提供 WARP 出口、链式落地、规则分流、Realm L4 端口转发、组件管理、服务器工具、服务器测试与脚本自更新。

> v1.8.1 为当前稳定正式版，正式支持 **Debian / Ubuntu + systemd**。  
> v1.9.x 为当前开发线，已接入 **Alpine 3.21 + OpenRC**；核心 OpenRC 服务路径已通过 Alpine 3.21 CI smoke test。**Snell v5 官方二进制已确认无法在 Alpine 3.21 + gcompat 下正常启动，因此 Alpine 暂不开放 Snell；Cloudflare WARP 官方客户端也暂不在 Alpine 开放。**

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
| **稳定正式版** | v1.8.1：Debian / Ubuntu + systemd |
| **v1.9 开发版** | Debian / Ubuntu + systemd；Alpine 3.21 + OpenRC |
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
  && ln -sf /usr/local/bin/ss2022 /usr/local/bin/proxy \
  && ss2022
```

安装后可随时执行：

```bash
ss2022
```

或：

```bash
proxy
```

进入管理面板。

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

当前服务器测试收敛为三个入口：

| 测试 | 使用项目 / 方式 |
|---|---|
| IP 质量 / 风险测试 | oneclickvirt / securityCheck |
| IPv4 / IPv6 三网逐跳回程 | nxtrace / NTrace-core（NextTrace 逐跳 traceroute） |
| 平台流媒体AI通信软件解锁测试 | 流媒体：1-stream / RegionRestrictionCheck；AI：oneclickvirt / UnlockTests；通信：curl 可达性检测 |

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

# 当前开发策略

## v1.8.x

v1.8.1 为当前稳定正式版。

后续 v1.8.x 仅处理：

- Bug 修复
- 稳定性优化
- 交互优化

原则上不再增加大型功能模块。

## v1.9.x

当前开发版为 **v1.9.0-dev37**，重点是 Alpine / OpenRC 与卸载闭环收口：

- SS2022、ShadowTLS v3、VLESS Reality、Realm 已接入 OpenRC
- Snell v5 官方二进制已确认无法在 Alpine 3.21 + gcompat 下启动，因此 Alpine 暂不开放 Snell；Debian / Ubuntu 保持支持
- 服务器管理工具与服务器测试已完成主要 Alpine 适配
- Alpine 3.21 / OpenRC 已加入 GitHub Actions smoke test，覆盖平台识别、服务生成、runlevel、PID 与完全卸载闭环
- WARP 官方 Linux 客户端在 Alpine 暂不开放
- 完全卸载已覆盖脚本备份、OpenRC PID、TG-BOT lockdir、脚本命名空间临时文件；WARP 中途安装失败也可按 managed marker 清理
- IPv6-only 临时 DNS 使用 vps-bootstrap 专属备份路径；旧 /root/resolv.conf.orig 仅用于兼容历史版本恢复，不再由新版本创建
- Debian / Ubuntu + systemd 路径继续保持兼容

v1.9.x 在完成更充分的 Alpine 实机验证前仍属于开发线，不替代 v1.8.1 稳定版。

---

# 说明

本项目中的网络测试功能会调用第三方公开项目或服务。第三方项目的可用性、检测逻辑和结果准确性由对应项目维护者负责，本脚本仅提供调用入口。

IP 地理位置、IP 风险、流媒体和 AI 解锁结果均可能受数据库、CDN、地区策略、账号状态及检测时间影响，仅供参考。

---

# License

本项目基于 [MIT License](LICENSE) 开源。

仅用于网络工程技术研究、个人服务器运维及合规测试。使用者应遵守所在地法律法规、网络服务条款和 VPS 提供商规则，并自行承担使用风险。
