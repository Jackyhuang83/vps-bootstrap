# VPS Bootstrap Management Suite

一体化 VPS 网络协议、服务端分流、端口转发与日常运维脚本。

当前正式版本：**v1.9.0**

当前开发版本：**v1.10.0-dev8**（独立开发分支，未发布，v1.9.0 正式版不变）

项目以单一交互式 Bash 脚本 `ss2022.sh` 为入口，整合 **SS2022、SS2022 + ShadowTLS v3、VLESS Reality、Snell v5**，并提供 WARP 出口、链式落地、规则分流、Realm L4 端口转发、组件管理、服务器工具、服务器测试与脚本自更新。

> v1.9.0 为当前稳定正式版。Debian / Ubuntu + systemd 正式支持；Alpine 3.21 + OpenRC 正式支持 SS2022、ShadowTLS v3、VLESS Reality、Realm 以及服务器管理/测试。Snell v5 与 Cloudflare WARP 在 Alpine 暂不开放。

---

## 网络调优（v1.10.0-dev8 开发预览）

入口：**服务器管理工具 → 6. 网络调优**。

本阶段实现：只读查看 IPv4/IPv6 实际出站设备、拥塞控制算法与 qdisc；保存首次网络状态快照；在内核支持时启用 BBR + fq；识别官方旧版 `99-ss2022-bbr.conf` 并安全迁移；基于首次快照恢复 BBR/fq 和旧版配置状态。首次快照永久保存在 `/var/lib/ss2022-network-tuning/original.json`（权限 600），不在完全卸载时删除，避免“保留 BBR、丢失恢复依据”。

**安全边界：**遇到修改过的旧 BBR 文件、管理员已有同名 sysctl 项、新版管理文件遭修改，拒绝接管；不替换内核、不改 SSH/DNS/路由、不修改已有活动根 qdisc。当前阶段已支持手工 iperf3 安全测速，但尚不包含 HTB 整形、initcwnd 或 TCP 缓冲区更改。测速已加入发送流量预算监测及异常终止保护；应用整形所需的独立恢复保护仍留待后续版本。

**v1.10.0-dev2 安全测速：**新增独立菜单选项 5，手动提供可信的 iperf3 测速服务端，选择 IPv4 或 IPv6；脚本解析实际路由出口，并拒绝 WARP/TUN、容器、loopback 等不适合直接测速的接口。测试单流 TCP 发送，解析 iperf3 JSON 中的发送吞吐、接收有效吞吐与重传次数。不会自动安装 iperf3；缺少时会提示安装。

dev2 的默认设置：5Mbps、8 秒、32MiB 流量预算，最大限制 100Mbps、20 秒、256MiB；开始前必须输入 `RUN`。执行时有独立 watchdog 监控出口网卡的总发送字节（包含其他正常业务，因此可能提前触发保护），并对测试时长设置额外截止时间。预算不是服务商流量计费值，IPv6/IPv4 协议开销、系统调度和远程测试服务端行为可能造成差异；不承诺精确到字节的绝对上限。出现异常、超预算或无效 JSON 时拒绝采信结果。单次测速仅是吞吐诊断，不足以证明有 policer，也不会据此自动整形。

**线路机优先范围（后续自动调优）：**仅支持 `10 / 20 / 30 / 100 / 200 / 300 / 500 Mbps` 七个套餐档位，**最高 500Mbps**；`1Gbps` 或更高带宽不进行自动整形。未来自动流程只需要选择真实套餐档位，不要求用户自行填写 HTB 速率、扫描步长或 TCP 参数。已在代码中实现只读的 `network_tuning_profile()` 预设与 500Mbps 扫描上界防线，**尚未实现 dev3 拐点扫描及自动应用**。尤其注意：网卡链接速度（1G/10G）通常不等于运营商套餐速率，脚本不能据此自动确定套餐。

小带宽采用更细的固定点扫描计划：10M 档细扫 0.1M、20M 档 0.2M、30M 档 0.25M；大带宽 100/200/300/500M 逐级增加步长，避免重复无效测速。上述预设仅是后续检测计划，**没有经过实机拐点验证，不能直接当作最终整形值**。dev2 安全初筛仍限制单次最高 100Mbps；500Mbps 是后续整个自动调优功能的最高范围，不表示 dev2 已能以 500Mbps 测速。

### 网络调优验收目标：实际使用体验优先

**目标顺序：① 视频连续播放不卡顿；② 网页打开与滚动加载响应快；③ 即时通信 App 连接稳定、消息发送接收不长时间转圈。** 测速峰值和漂亮的基准测试分数不作为单独的成功判据；这三个目标都不能因为优化其中一项而显著损害另一项。

| 使用场景 | 优先观察什么 | 诊断意义及限制 |
|---|---|---|
| 视频 / 直播 | 加载等待、持续缓冲次数、实际下载 goodput 稳定性、满载往返时延和 TCP 重传 | 稳定吞吐和低排队时延有助于播放；服务商/CDN 速度、内容码率、播放器缓存、DRM 或地区限制不属于 qdisc 可修复范围 |
| 浏览网页 | DNS/TCP/TLS 连接耗时、首字节时间 TTFB、负载下 RTT P95、丢包与重传 | 优先减少高负载下的排队延迟；不能只看平均 Ping，也不能用 iperf 单流结果代表网页体验 |
| 聊天 / 即时通信 | 连接建立成功率、持续连接稳定性、消息交互延时及重连情况 | 与 WebSocket/TLS、DNS、服务端封锁、IPv4/IPv6 分流等有关；VPS 吞吐变快不能证明 App 不再转圈 |

**后续 dev3 必须执行的比较：**先采集调优前的空闲/带载 RTT（中位数和 P95）、波动（jitter）、接收有效吞吐、TCP 重传与超时；然后只在可信候选配置下复测相同目标与时段，避免把随机线路波动归因于调优。单次 iperf3 的 `retransmits` 是 TCP 重传次数，**不等于直接测得的链路丢包率**，不能用它独立判断视频或聊天质量。指标冲突时优先保障实际吞吐与稳定连接，决不以牺牲明显的播放能力换取一个好看的 RTT。

**方向边界：**VPS 上的出口整形只影响被整形设备发送的数据；视频回程可能经过「内容源 → 落地 → 主 VPS → 客户端」多个瓶颈。若卡顿来自服务商入向限速、主/落地节点之间的线路、设备端 Wi-Fi、远端 CDN 或 APP 自身，单机出口 HTB 不一定有益，应该输出“原因未确定/暂不修改”，而不是强制整形。任何自动应用都要满足：原始配置可恢复、应用后测试没有显著退化、异常自动回滚。

**当前交付边界：**dev2 仅有初步非侵入式 iperf3 TCP 诊断，**没有测量上述完整 QoE 指标，也尚不能宣称能改善视频、网页或聊天 App**。本节是 dev3/dev4 的验收标准，不是当前已实现的功能。

**v1.10.0-dev3 已实现的非侵入式 QoE 双轮诊断：**服务器管理工具 → 网络调优 → 6。选择真实套餐速率（10/20/30/100/200/300/500Mbps）、IPv4/IPv6、可信 iperf3 测试对端并确认后，自动进行两轮「空闲 ICMP RTT → 8 秒有界 TCP 发送负载 + 带载 ICMP RTT」，提取空闲/带载 RTT P50/P95、回复缺失比例、邻接 RTT 变化均值、TCP 有效吞吐及重传次数。两轮都出现同类明显异常才报告「疑似排队延迟」或「疑似 ICMP 回复丢失」，否则输出「该采样负载下未见明确异常」或「不确定」；绝不生成整形值，更不会改变网卡。每轮调用 dev2 的 96MiB 流量预算 watchdog，最多执行两轮；诊断优先采用小负载而非冲击套餐上限。**这不是视频 CDN、网页首字节或聊天 APP 的真实端到端测试**，其结果不能证明终端 QoE 已得到改善，也不能单独确认存在 policer。服务端屏蔽 ICMP、对端性能不足、两轮不一致或样本过少时拒绝给出调优结论。

**v1.10.0-dev4 只读候选计算：**在网络调优菜单新增选项 7，可从符合 `schema=1` 的完整 JSON 文件审查 **3 个不同发送速率×每档 2 次** 的测速证据。每条数据须包含 `rate_mbps`、`round`、`sender_mbps`、`received_mbps`、`idle_p95_ms`、`loaded_p95_ms`、`retransmits`，根节点还需指定 `tier_mbps`。验证两次复测稳定性、低中档正常、高档发送与接收偏差、可重复高载时延增大及接收平台期后，才输出 `candidate_for_validation`；其余返回 `no_confirmed_knee` 或 `inconclusive`。候选最高不得超过真实套餐，也受 500Mbps 绝对限制，**始终标注 `auto_apply:false`**。目前仅提供算法验收与离线证据输入，**不会自动执行完整三档扫描，也不把 dev3 的低负载样本当作拐点证据**。

**tc/qdisc 审计：**以只读方式检查根队列、class 和 filter。外部 HTB、mq、clsact、ingress、已存在 class/filter 或无法读到可靠根队列，均按不安全情况拒绝自动接管。即使是普通 fq/fq_codel 根队列，也只返回 `inspect_only`，不视为具备可靠回滚能力。当前不会执行 HTB、修改路由、内核参数或活动 qdisc；候选值还需独立对端、真实设备 A/B 的视频/网页/聊天体验测试和受控回滚后才能考虑应用。手工录入或来源不明的 JSON 文件不是自动调优授权凭证。

**v1.10.0-dev5 六样本实时诊断（开发预览）：**网络调优菜单第 8 项在用户指定可信 iperf3 服务端并输入 `RUN` 后，可对 10/20/30/100/200/300/500Mbps 七档套餐执行自动三档发送测试（40%、80%、100% 套餐速率）×两轮，每轮 6 秒。逐轮检验真实 IPv4/IPv6 出口、ICMP 完整度、吞吐有效性，沿用独立发送字节 watchdog，并增加总预算上限 2560MiB。500M 套餐六轮的预设预算约为 2250MiB，高带宽测试可能短时占满线路、影响视频及聊天，请只在低峰期和可信测速对端手动执行。完成后保存仅本机 600 权限证据，自动提交给 dev4 候选审核；**仍未实现自动应用 HTB、可靠自动回滚或真实 VPS + 终端视频/网页/聊天 A/B 实测**。结果不足则不产生调优建议，正式版不会要求用户自行输入整形系数。

**v1.10.0-dev6 独立回滚看门狗演练（仅 dry-run）：**菜单新增选项 9 / 10。由用户输入 `RUN` 后，程序先在项目专属的 700 私有目录创建固定 schema 的模拟事务并启动脱离 SSH 终端的 `setsid` / `nohup` 独立看门狗；只有收到 `READY` 确认才创建模拟变更文件。3–30 秒后守护进程清理该文件并写入 `rolled_back_simulated`。CI 增加启动 Shell 被 `SIGKILL` 的模拟用例。**这是文件层面的故障恢复演练，不是生产网络恢复；绝不调用真实 tc/qdisc 修改，尚未验证真实 VPS、系统重启、外部 tc/网络管理器冲突或视频/网页/聊天体验。**演练记录位于 `/var/lib/ss2022-network-tuning/rollback-rehearsals`，卸载后依旧保留以便审计。

**v1.10.0-dev7 实验性、临时 HTB 整形（未实机验证）：**网络调优菜单新增选项 11（60 秒临时 HTB）、12（查看状态）、13（提前恢复）。只允许 root 在 Debian/Ubuntu systemd 上执行；须持有本机 dev5 完整六样本报告并经 dev4 复核得到候选；使用 `TRIAL` 明确确认风险。网卡必须只有可解析完整选项的 `fq_codel` 根队列且不存在其他 qdisc/class/filter，拒绝外部设置、mq、clsact、ingress、fq 和未知 qdisc。保存原状态（含 ifindex/恢复参数）后，**先注册并验证独立 systemd 回滚定时器，再应用 HTB 根队列与 fq_codel 叶队列**，60 秒后自动尝试恢复；如果发现外部配置变化则不覆盖并留下冲突记录。试验不持久化、不自动采纳候选值，OpenRC 不开放真实 HTB。**非常重要：此代码只有模拟 CI 验证，尚未经过真实 VPS、掉线与多网卡环境测试，自动恢复不构成可用性保证；在没有服务商 Web Console/救援控制台之前，不要对正在提供服务的 VPS 运行选项 11。**正式版 v1.9.0、main 不变。

**v1.10.0-dev8：实验室内核验证 + 视频优先 A/B 验收准备。** CI 新增 `tests/network-htb-veth-integration.sh`，使用不接入任何公网路由的临时 veth 测试真实内核 HTB→fq_codel 恢复、外部配置冲突、启动器 SIGKILL 后独立进程恢复。如果 CI 无 CAP_NET_ADMIN，测试将明确 SKIP，不可冒充验证成功。菜单 14 增加完全只读的 A/B 现场数据审核：同直播、清晰度、设备、基线和试验各两轮，每轮至少 5 分钟；视频退化、网页退化或聊天延迟/丢包退化必须保留原配置。有明显重复收益也仅输出需继续实机核验的候选，**不会自动或持久化应用**。真实 VPS/客户端验收仍未执行，流程及人工 JSON 示例见 `docs/network-tuning-dev8-validation.md`。

**升级提醒：**开发分支尚未合并到 `main`，一键安装仍使用稳定正式版。旧版主动启用过 BBR 的 VPS，首次快照保存的是**当前**状态，无法推断更早之前的未知内核参数。

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
| **稳定正式版** | v1.9.0：Debian / Ubuntu + systemd；Alpine 3.21 + OpenRC |
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

# 版本策略

## v1.8.x

v1.8.1 为上一稳定正式版。

后续 v1.8.x 仅处理：

- Bug 修复
- 稳定性优化
- 交互优化

原则上不再增加大型功能模块。

## v1.9.0

当前稳定正式版为 **v1.9.0**，本版本完成 Alpine / OpenRC 与卸载闭环收口：

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

v1.9.0 已完成发布前收口并成为当前稳定正式版；后续优先处理 Bug、稳定性和兼容性问题。

---

# 说明

本项目中的网络测试功能会调用第三方公开项目或服务。第三方项目的可用性、检测逻辑和结果准确性由对应项目维护者负责，本脚本仅提供调用入口。

IP 地理位置、IP 风险、流媒体和 AI 解锁结果均可能受数据库、CDN、地区策略、账号状态及检测时间影响，仅供参考。

---

# License

本项目基于 [MIT License](LICENSE) 开源。

仅用于网络工程技术研究、个人服务器运维及合规测试。使用者应遵守所在地法律法规、网络服务条款和 VPS 提供商规则，并自行承担使用风险。
