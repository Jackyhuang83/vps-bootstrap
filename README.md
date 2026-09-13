
已经正式收口成 v1.8.0 Release，并加入正式版 Release 记录；功能逻辑没有再改。

下载 ss2022.sh

下载 ss2022-v1.8.0.sh

正式版记录里包含：

v1.8.0 Release
- 正式发布 v1.8.0
- SS2022
- SS2022 + ShadowTLS v3
- VLESS Reality
- Snell v5
- WARP / 分流 / Realm
- 服务器管理与测试工具
- TG-BOT 月流量监控
- 端口安全释放
- 自定义 DNS
- 系统信息增强
- 自更新版本判断与防降级
- 基于 v1.8.0-dev29 收口
最终校验：

版本：v1.8.0
完整脚本：8836 行
函数：292 个
功能逻辑变化：0
bash -n：通过
SHA256：
cf4a1b43d746c3bb9be0736540b3fb7247c779312660913927c177ccdca6744d



ss2022.sh
程式碼


ss2022-v1.8.0.sh
程式碼


已经发布了，告一段落

好，这个阶段就正式收口了。

v1.8.0 已经发布，接下来先不要再加功能，后续如果有用户实测反馈，就按：

Bug 修复 → v1.8.1 / v1.8.x

等稳定一段时间，再进入下一阶段的：

v1.9.0 → Alpine / OpenRC / NAT VPS 兼容

这样版本节奏最稳。


但是readme好像一直没有改哦

对，README 之前确实严重落后，还是 v1.6.1 + 单一 SS2022 的介绍。


我已经按正式版 v1.8.0 重写成完整 README，内容覆盖：

SS2022

SS2022 + ShadowTLS v3

VLESS Reality

Snell v5

WARP / 服务端分流 / 落地节点

Realm L4 转发

节点配置输出

服务器管理工具

TG-BOT 月流量监控

端口安全释放

服务器测试

脚本自更新

安全设计

v1.8.x 稳定策略

v1.9.x Alpine / OpenRC Roadmap

下载更新后的 README.md

这份可以直接替换 GitHub 仓库根目录现在的 README.md。 


README.md
文件



資料庫
/
vps-bootstrap
/
README.md


VPS Bootstrap Management Suite
一体化 VPS 代理协议、服务端分流、端口转发与日常运维脚本。

当前正式版本：v1.8.0

项目以单一交互式 Bash 脚本 ss2022.sh 为入口，整合 SS2022、SS2022 + ShadowTLS v3、VLESS Reality、Snell v5，并提供 WARP 出口、链式落地、规则分流、Realm L4 端口转发、组件管理、服务器工具、服务器测试与脚本自更新。

当前 v1.8.x 正式支持 Debian / Ubuntu + systemd。
Alpine / OpenRC 暂未正式支持，计划在后续 v1.9.x 适配。

主要特性
四种代理模式
模式	服务端核心	说明
SS2022	sing-box	Shadowsocks 2022 独立节点
SS2022 + ShadowTLS v3	sing-box	在 SS2022 基础上增加 ShadowTLS v3 流量伪装
VLESS Reality	Xray-core	独立 Xray 服务运行，不与 sing-box Reality 混用
Snell v5	官方 snell-server	使用 Surge 官方 Snell Server
四种协议可独立部署、更新参数、查看配置和删除。

系统与架构支持
维度	当前支持
操作系统	Debian / Ubuntu（systemd）
CPU 架构	x86_64 / amd64、aarch64 / arm64
网络环境	IPv4-only、IPv6-only、IPv4 + IPv6 双栈
NAT VPS	可使用服务商映射端口部署节点
权限要求	root
Shell	Bash
当前正式版本	v1.8.0
v1.8.0 固定 / 推荐组件版本
组件	版本
sing-box	1.13.20
Xray-core	26.3.27
Snell Server	5.0.1
Realm	2.9.6
一键安装
在 VPS 中使用 root 权限执行：

curl -fsSL https://raw.githubusercontent.com/Jackyhuang83/vps-bootstrap/main/ss2022.sh \
  -o /usr/local/bin/ss2022 \
  && chmod +x /usr/local/bin/ss2022 \
  && ln -sf /usr/local/bin/ss2022 /usr/local/bin/proxy \
  && ss2022
安装后可随时执行：

ss2022
或：

proxy
进入管理面板。

主菜单
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
协议管理
1. SS2022
基于 sing-box 部署 Shadowsocks 2022。

支持：

2022-blake3-aes-128-gcm

2022-blake3-aes-256-gcm

2022-blake3-chacha20-poly1305

自动生成合规 PSK

TCP / UDP

IPv4 / IPv6 / 双栈

自定义节点名称

节点参数修改

独立删除

2. SS2022 + ShadowTLS v3
基于 sing-box 部署 SS2022 + ShadowTLS v3。

ShadowTLS 主要用于增加 TLS-like 流量特征与主动探测抵抗能力，并不是额外增加一层内容加密。

支持：

ShadowTLS v3

SS2022 后端

TCP ShadowTLS

可选独立 UDP

自定义 SNI / TLS 目标

自定义节点名称

配置修改与独立删除

3. VLESS Reality
使用独立 Xray-core 服务实现 VLESS Reality。

设计原则：

Xray 使用独立二进制与配置目录

systemd 服务名为 ss2022-xray

不覆盖服务器已有的 Xray 安装

支持 Reality 参数自动生成

支持节点名称修改

支持服务端分流

4. Snell v5
使用 Surge 官方 snell-server。

设计原则：

使用官方 Snell Server

独立配置和 systemd 服务

不经过 sing-box

不参与 VPS 服务端分流

如需 Snell 分流，建议在 Surge 客户端使用 Rules

节点配置输出
脚本可根据不同协议输出相应客户端配置。

包括：

通用 URI / SIP002（适用时）

Surge

Loon（协议支持时）

FlClash / Mihomo

Shadowrocket

二维码

节点名称自定义

不同客户端对 ShadowTLS、Snell、独立 UDP 等参数支持程度不同，脚本会按照对应协议能力输出，不生成已知无效的伪配置。

服务端分流
服务端分流适用于：

SS2022

SS2022 + ShadowTLS v3

VLESS Reality

Snell v5 保持官方 snell-server 架构，不参与 VPS 服务端分流。

可用出口
DIRECT
直接使用 VPS 原生网络出口。

WARP
通过 Cloudflare WARP Local Proxy 作为出口。

支持：

安装 / 配置 WARP

自动检测 VPS 原生 IPv4 / IPv6

IPv4 / IPv6 / 双栈出口模式

测试 WARP 实际出口

WARP 重连

WARP 重新注册

WARP 卸载

落地节点
支持添加：

Shadowsocks

自动识别标准 SS / SS2022

支持粘贴 ss:// URI

支持手动输入

SOCKS5

可对落地节点进行查看、删除、测试，并设置为默认出口。

分流规则
内置规则类型：

OpenAI / ChatGPT

Netflix

YouTube

Google

Telegram

MyTVSuper

Apple TV+

TikTok

自定义域名 / IP / CIDR

自定义规则支持：

精确域名

域名后缀

域名关键字

IP / CIDR

每条规则可以独立指定：

DIRECT

WARP

指定落地节点

IPv4 / IPv6 / 默认地址族

同时支持规则顺序调整和全局默认出口。

Realm L4 端口转发
集成 Realm 作为独立 L4 端口转发组件。

支持：

单端口转发

端口段转发

查看规则

修改规则

删除规则

测试规则

Realm 服务管理

Realm 使用独立二进制、配置和 systemd 服务，不覆盖服务器已有同名服务。

协议运维管理
支持：

查看全部服务状态与监听端口

sing-box 实时日志

Xray 实时日志

Snell v5 实时日志

Realm 实时日志

重启 sing-box

重启 Xray

重启 Snell

重启 Realm

IPv6 Keepalive 状态

各协议独立管理

组件版本管理
可查看和管理：

sing-box

Xray-core

Snell Server

Realm

核心下载会进行必要的来源与完整性校验，避免直接运行损坏或异常文件。

服务器管理工具
v1.8.0 集成了一组轻量服务器运维工具，不做“大而全”的系统工具箱。

系统信息
显示：

主机名

系统版本

CPU 型号

CPU 核心与频率

内存

虚拟内存

硬盘占用

运行时间（天）

本月入站流量

本月出站流量

时区

IPv4

IPv6

IP 地理位置

ISP / ASN

IP 性质

IP 风险

DNS

网络算法，例如 bbr fq_pie

月流量状态会持久化保存，VPS 重启后继续累计，并按自然月进入新的统计周期。

端口占用
支持：

查看全部监听端口

查询指定端口

显示 PID / 进程 / systemd 服务 / Docker 映射

安全释放指定端口

释放端口支持：

停止 systemd 服务

停止并禁用 systemd 服务

停止 Docker 容器

结束监听进程

安全机制：

当前 SSH 会话使用的端口禁止释放

直接结束进程时优先发送 SIGTERM

SIGTERM 无效时需要再次确认才执行 SIGKILL

TG-BOT 流量监控
支持 Telegram Bot 流量监控：

RX / 入站月流量

TX / 出站月流量

自定义流量额度

自定义重置日

默认 80% / 90% / 100% 预警

自动关机阈值独立配置

默认自动关机阈值：95%

Telegram 测试消息

状态查看

手动重置累计

停用 / 删除监控

自动关机默认关闭，需要用户主动开启并确认。

其它服务器工具
还包括：

系统更新 / 清理

Swap 虚拟内存

BBR

DNS 管理

IPv4 / IPv6 优先级

系统时区

SSH 端口管理

重启服务器

DNS 管理支持：

Cloudflare + Google

Quad9 + Cloudflare

阿里 DNS + DNSPod

自定义 DNS

支持厂商提供的流媒体 / 解锁专用 DNS

IPv4 / IPv6 DNS

多 DNS 地址

SSH 端口修改采用安全方式：

保留原端口

sshd -t 验证

reload 后检查监听状态

重启服务器必须完整输入 REBOOT，避免误触。

服务器测试管理
集成四类常用 VPS 测试：

测试	使用项目 / 来源
IP 质量测试	IP.Check.Place
回程路由测试	Chennhaoo / AutoTrace
流媒体解锁测试	1-stream / RegionRestrictionCheck
AI 工具测试	oneclickvirt / UnlockTests
AI 测试使用 UnlockTests 的 AI-only 模式，可检测包括：

ChatGPT

Gemini

Claude

Copilot

Grok

Perplexity

Poe

并区分 YES、NO、Restricted、Banned、RateLimited、TIMEOUT、DNS 失败等状态。

第三方测试脚本的自身退出码不会被简单误判成 ss2022.sh 执行失败。

脚本自更新
更新源：

https://raw.githubusercontent.com/Jackyhuang83/vps-bootstrap/main/ss2022.sh
更新检查会分别显示：

当前运行版本
系统安装版本
GitHub main 版本
支持识别：

远程版本更新

远程版本更旧

相同版本但内容 SHA256 不同

当前运行脚本与 GitHub main 一致，但系统安装版本落后

为避免误操作：

更新前备份 /usr/local/bin/ss2022

新脚本必须通过 bash -n

远程版本比当前运行版本更旧时默认拒绝自动降级

更新完成后重新进入安装后的管理面板

状态与配置文件
主要状态文件：

/etc/ss2022/state.json
/etc/ss2022/routing.json
/etc/ss2022/forwarding.json
服务器工具相关：

/etc/ss2022/system-info-traffic.state
/etc/ss2022/tg-monitor.conf
/etc/ss2022/tg-monitor.state
核心配置：

/etc/sing-box/config.json
/etc/ss2022-xray/config.json
/etc/snell/snell-v5.conf
常用命令
打开管理面板
ss2022
或：

proxy
查看核心服务
systemctl status sing-box
systemctl status ss2022-xray
systemctl status snell-v5
查看监听端口
ss -lntup
通常不需要手动维护这些服务，推荐直接通过 ss2022 管理面板操作。

安全设计
v1.8.0 的主要安全原则：

配置修改前生成候选配置

核心配置通过自检后才覆盖正式配置

配置失败时尽量回滚

sing-box / Xray / Snell 使用独立运行用户

Xray / Realm 使用 ss2022 独立命名空间

不覆盖服务器已有同名服务

下载核心进行来源 / SHA256 校验

SSH 端口修改保留旧端口并验证配置

端口释放保护当前 SSH 会话

BBR 不自动替换内核

DNS 管理不通过 chattr 锁死 /etc/resolv.conf

脚本自更新拒绝自动降级

完全卸载
主菜单提供：

10. 完全卸载脚本
用于清理本项目创建的协议服务、配置、状态文件和相关组件。

执行前请确认不再需要当前节点配置。

当前开发策略
v1.8.x
v1.8.0 已进入稳定阶段。

后续 v1.8.x 仅处理：

Bug 修复

稳定性优化

交互优化

原则上不再增加大型功能模块。

v1.9.x
计划重点：

Alpine Linux

OpenRC

apk

轻量 NAT VPS 环境适配

systemd / OpenRC 服务抽象

当前 v1.8.0 不要在 Alpine 上作为正式支持版本使用。

说明
本项目中的网络测试功能会调用第三方公开项目或服务。第三方项目的可用性、检测逻辑和结果准确性由对应项目维护者负责，本脚本仅提供调用入口。

IP 地理位置、IP 风险、流媒体和 AI 解锁结果均可能受数据库、CDN、地区策略、账号状态及检测时间影响，仅供参考。

License
本项目基于 MIT License 开源。

仅用于网络工程技术研究、个人服务器运维及合规测试。使用者应遵守所在地法律法规、网络服务条款和 VPS 提供商规则，并自行承担使用风险。

