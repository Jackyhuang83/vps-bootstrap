# vps-bootstrap Project State

> 本文件记录项目“当前事实、已确认架构、关键技术决策、已知问题与维护原则”。
> 它不是 CHANGELOG，也不用于记录每一次讨论过程。
> 只有项目状态发生实质变化时才更新。

## 1. 当前状态

- 项目名称：`vps-bootstrap`
- 核心脚本：`ss2022.sh`
- 当前正式版本：`v1.8.0`
- 正式版状态：稳定 / 默认冻结
- 发布原则：
  - 不主动为正式版增加新功能。
  - 仅在用户明确提出新需求，或实际使用发现 BUG 时开启后续开发。
  - `main` 中若存在正式版之后的 dev 提交，均视为开发 / 验证线，不等同于新的正式版本。

## 2. 项目定位

轻量、模块化、易维护的 VPS 工具箱。

设计原则：

- 一个功能一个模块。
- 优先复用经过验证的成熟开源方案。
- 不重复设计已有成熟实现。
- 对第三方方案做集成、兼容、安全控制与统一交互。
- 重要修改应先验证，再进入正式版本。

## 3. 协议架构

### SS2022
- 核心：sing-box
- 独立协议入口。

### SS2022 + ShadowTLS v3
- 核心：sing-box
- ShadowTLS v3 主要用于 TLS 外观与抗识别能力，不作为额外加密层理解。

### VLESS Reality
- 核心：独立 Xray-core
- 已放弃 sing-box Reality 方案。
- Xray Reality 已通过 Loon 实际验证。

### Snell v5
- 使用官方 snell-server。
- 不迁移到 sing-box。
- 主要由 Surge / Loon 客户端进行分流。

## 4. 客户端

主要使用 iOS。

常用客户端：
- Surge
- Loon
- Shadowrocket
- FlClash

节点输出重点支持：
- 节点参数
- 客户端配置
- 二维码

## 5. 落地与分流架构

支持的落地类型：
- SS2022
- 标准 Shadowsocks
- VLESS / Xray 链路
- SOCKS5

逻辑模型：
- A：默认出口 / 默认落地
- B / C：独立分流落地
- DEFAULT：跟随默认出口
- DIRECT：主 VPS 直接出口
- 指定落地：直接走对应 B / C

关键原则：
- B / C 的链路为：`主 VPS -> B/C -> 目标服务`
- B / C 不经过 A。
- A 故障不应影响 B / C 分流业务。
- A 故障时，应保留主 VPS 直接出口的能力。

典型规则：
- MyTVSuper
- Apple TV+
- TikTok
- YouTube
- AI 服务（ChatGPT / Gemini / Claude 等）

## 6. WARP / IPv4 / IPv6

WARP 主要作为缺失地址族补充与指定出口使用，不默认接管所有系统流量。

典型场景：
- IPv4-only VPS：DIRECT 保留原生 IPv4，WARP 可补充 IPv6。
- IPv6-only VPS：保留原生 IPv6，WARP 可补充 IPv4。
- 双栈 VPS：WARP 作为可选额外出口。

长期要求：
- 明确区分 IPv4-only、IPv6-only、双栈。
- 节点接入地址族与最终业务出口地址族不能混淆。
- 测试链路与正式分流链路应使用一致的地址族策略。

## 7. Realm

- Realm 用于轻量 L4 端口转发。
- 不扩展为复杂转发平台。
- 保持独立、简单、可维护。

## 8. 服务器管理与测试

服务器管理包括：
- 系统信息
- 端口占用与安全释放
- BBR
- DNS
- DDNS
- WARP
- TG-BOT 月流量监控
- 自动关机阈值
- 重启确认
- IPv4 / IPv6 优先级
- 时区
- SSH 端口管理

服务器测试包括：
- IP 质量
- 回程路由
- 流媒体解锁
- AI 工具测试

测试模块原则：
- 优先调用成熟第三方项目。
- 临时下载、临时执行、执行后清理。
- 第三方程序自身的非 0 返回码不应被简单解释为 `ss2022.sh` 执行失败。

## 9. 已确认的重要问题与结论

### 9.1 sing-box local DNS / gstatic connection reset

现象示例：

```text
Remote proxy server error: connection reset by peer
(SNConnectorNetworkErrorDomain:4)
```

可能出现在：

```text
www.gstatic.com
```

已确认根因：
- sing-box 1.13.20 使用 `type: local` DNS 时，在部分精简 VPS 环境中可能依赖系统 resolver / `systemd-resolved` / `org.freedesktop.resolve1`。
- 系统环境缺失相关能力时，会导致域名解析异常，最终在客户端表现为远端连接 reset。

已验证修正：

```json
{
  "type": "local",
  "tag": "local-dns",
  "prefer_go": true
}
```

作用：
- 优先使用 Go resolver。
- 降低对 systemd-resolved / D-Bus resolver 的依赖。
- 不改变协议加密、端口、分流逻辑。

维护要求：
- 后续 sing-box DNS 配置应保留该兼容策略，除非新版 sing-box 行为经过重新验证。

## 10. 版本维护原则

- `v1.8.0` 是当前正式稳定基线。
- 正式版默认冻结。
- 新需求或 BUG 修复从开发版本开始。
- 不因为发现一个局部问题而重构已经验证稳定的其它模块。
- 修改必须继承既有 changelog、历史决策和已验证方案。

## 11. 本文件什么时候更新

只有以下情况需要更新：
1. 正式版本发生变化。
2. 核心架构或技术选型发生变化。
3. 已确认重要 BUG 的根因或修复方案发生变化。
4. 默认行为发生变化。
5. 关键依赖被替换。
6. 项目维护策略发生变化。

以下情况通常不需要更新：
- 普通讨论。
- 尚未验证的想法。
- 临时测试命令。
- 没有形成结论的排障过程。
- 单次环境问题且不影响项目设计。

## 12. 新聊天接续原则

开始新的 vps-bootstrap 对话时，优先按以下顺序恢复上下文：
1. 读取 `PROJECT_STATE.md`
2. 查看当前正式 Release / CHANGELOG
3. 检索同项目历史聊天中的相关问题
4. 查看 GitHub 当前代码
5. 在已有结论无法覆盖时，再进行新的分析

目标：避免重复排障、重复推翻已经验证的设计。
