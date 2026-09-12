
新版本已经输出，版本是 v1.8.0-dev15。

这版正式加入你刚才说的 WARP 双栈补全模型：

IPv4-only VPS
├─ DIRECT → 保留 VPS 原生 IPv4
└─ WARP   → 推荐补 IPv6

IPv6-only VPS
├─ DIRECT → 保留 VPS 原生 IPv6
└─ WARP   → 推荐补 IPv4

双栈 VPS
├─ DIRECT → VPS 原生 IPv4 / IPv6
└─ WARP   → 可选额外 IPv4 / IPv6 出口
Cloudflare 的 Local Proxy 模式只处理显式送入代理的流量，其余系统流量继续走正常 Internet 连接，所以这个设计不会像全局 Tunnel 那样接管 VPS 默认出口。

dev15 具体增加了这些功能
WARP 菜单现在会先自动检测：

VPS 原生网络：
IPv4 : 可用
IPv6 : 不可用

推荐模式：
IPv4-only：WARP 补充 IPv6

DIRECT → VPS 原生 IPv4
WARP   → 推荐仅 IPv6（按分流规则调用）
如果是 IPv6-only，则反过来显示：

DIRECT → VPS 原生 IPv6
WARP   → 推荐仅 IPv4（按分流规则调用）
分流规则里如果你选择：

出口：WARP
脚本会自动推荐缺失的协议族。例如你现在这台 IPv4-only VPS：

请选择 IP 地址族：

1. 默认（不强制）
2. 仅 IPv4
3. 仅 IPv6（WARP 补全推荐）

请选择 [1-3，默认 3]:
直接回车就是 IPv6。

WARP 测试也改成分别测试：

✔ WARP IPv4: x.x.x.x
✔ WARP IPv6: 2606:xxxx:xxxx::xxxx
因此以后不会只显示一个 WARP IP，看不出到底 IPv6 有没有补成功。

另外，如果在这种单栈补全场景里误操作：

全局默认出口 → WARP
脚本现在会警告：

当前 WARP 被识别为“IPv4-only：WARP 补充 IPv6”。

将 WARP 设为全局默认出口会让所有未命中特殊规则的流量都经过 WARP。

如果你的目标只是补全缺失的地址族，
建议保持默认出口为 DIRECT，
只在分流规则中选择 WARP。
这样比较符合我们现在确定的原则：

DIRECT 永远保留 VPS 原生出口；WARP 是补充出口，由分流规则按需调用。

另外也专门处理了 IPv6-only VPS 首次安装 WARP 的情况，包括 IPv6 APT 环境初始化。

已验证：

Bash 语法                     ✅
SCRIPT_VERSION                ✅ dev15
主菜单启动/退出                ✅
WARP IPv6 推荐逻辑             ✅
WARP IPv4 推荐逻辑             ✅
DIRECT 默认地址族              ✅
routing.json 新字段兼容         ✅
重复函数检查                   ✅
SHA256：

c1571babcd5786678689f2e94588b4b97bc931afc4cb898fd42053b056ecf759
下载 ss2022.sh v1.8.0-dev15

也准备了标准文件名：

下载 ss2022.sh

你上传覆盖 GitHub main/ss2022.sh 后，测试机直接：

ss2022
→ 9. 检查脚本更新
然后你这台 IPv4-only VPS 最值得先测的就是：

分流管理
→ WARP 出口管理
→ 安装 / 配置 WARP 双栈补全
看看它是否正确识别成：

IPv4-only：WARP 补充 IPv6
以及最终 WARP IPv6 是否能拿到 Cloudflare IPv6。


ss2022-v1.8.0-dev15.sh
程式碼


ss2022.sh
程式碼


通过测试我发现，我输入1以后它没有选择让我选择只安装Warp IPV6,直接给我把warp ip4和ipv6全安装了，最后现实的也是warp ipv4地址和warp ipv6地址，这个不是我想要的哦！Local Proxy: 127.0.0.1:40000
状态: 未就绪

  1. 安装 / 配置 WARP 双栈补全（Local Proxy）
  2. 测试 WARP IPv4 / IPv6 出口
  3. 重新检测 VPS 原生 IPv4 / IPv6
  4. 重连 WARP
  5. 重新注册 WARP
  6. 卸载 WARP
  0. 返回
请选择 [0-6]: 1
══════════════ WARP 双栈补全检测 ══════════════
VPS 原生网络：
  IPv4 : 可用
  IPv6 : 不可用
推荐模式：IPv4-only：WARP 补充 IPv6
  DIRECT → VPS 原生 IPv4
  WARP   → 推荐仅 IPv6（按分流规则调用）


你这个判断是对的，dev15 只做到了“推荐补 IPv6”，并没有真正把 WARP 限制成 IPv6-only 出口，所以它还会测试并显示 WARP IPv4，这和你的目标不一致。

我已经改成 v1.8.0-dev16。

需要先说明一个底层事实：Cloudflare 官方 Local Proxy 本身没有“只安装 IPv6 WARP”或“只安装 IPv4 WARP”的独立安装模式；同一个 Local Proxy 可能同时具备 IPv4/IPv6 能力。官方定义的是“哪些流量送进本地代理”，并没有按地址族关闭其中一半的安装参数。

所以 dev16 改成由 ss2022.sh 路由层严格限制地址族。

你这台 IPv4-only VPS 现在进入：

分流管理
→ WARP 出口管理
→ 1. 安装 / 配置 WARP 出口模式
会看到：

请选择 WARP 实际出口模式：

1. 仅启用 WARP IPv6（推荐；VPS IPv4 继续 DIRECT）
2. WARP IPv4 + IPv6 双栈
0. 取消

请选择 [0-2，默认 1]:
你直接回车就是：

WARP → 仅 IPv6
DIRECT → VPS 原生 IPv4
而且这次不是单纯提示，脚本会真正约束：

WARP 分流规则自动固定 IPv6

不再让你给 WARP 规则选择 IPv4

状态页显示 WARP IPv4：未启用（IPv4 保持 DIRECT）

测试只测试 WARP IPv6

单地址族 WARP 禁止设置为全局默认出口

Xray 强制使用 route-warp-v6

sing-box DNS/路由强制 ipv6_only

反过来，IPv6-only VPS 会自动推荐：

1. 仅启用 WARP IPv4（推荐；VPS IPv6 继续 DIRECT）
我也分别做了两套模拟：

IPv4-only → WARP IPv6 only   ✅
IPv6-only → WARP IPv4 only   ✅
Xray 地址族强制              ✅
sing-box 地址族强制          ✅
主菜单启动/退出              ✅
Bash 语法                    ✅
SHA256：

d094b7cb1f4a75c4f36d265e8359102fdb851b04916e0f7fb893a9cdd446bbee
下载 ss2022.sh v1.8.0-dev16

下载标准文件名 ss2022.sh

你从 dev15 升到 dev16 后，不用先卸载现在的 WARP。直接：

ss2022
→ 2. 分流管理
→ WARP 出口管理
→ 1. 安装 / 配置 WARP 出口模式
→ 1. 仅启用 WARP IPv6
即可把现有 WARP 改成我们脚本层面的 IPv6-only 出口模式。


ss2022-v1.8.0-dev16.sh
程式碼


ss2022.sh
程式碼


你这个没有补充仅WARP IPv4选项啊？请补充
请选择 WARP 实际出口模式：

1. 仅启用 WARP IPv6（推荐；VPS IPv4 继续 DIRECT）
2. WARP IPv4 + IPv6 双栈
0. 取消

请选择 [0-2，默认 1]:

对，这一项应该始终保留。我已经补成 v1.8.0-dev17。

现在无论 VPS 是 IPv4-only、IPv6-only 还是双栈，WARP 都固定提供三种实际出口模式：

请选择 WARP 实际出口模式：

  1. 仅启用 WARP IPv4
  2. 仅启用 WARP IPv6（推荐；VPS IPv4 继续 DIRECT）
  3. WARP IPv4 + IPv6 双栈
  0. 取消

推荐：仅 WARP IPv6；VPS 原生 IPv4 继续 DIRECT

请选择 [0-3，默认 2]:
你当前这台 IPv4-only VPS 默认回车仍然选择 2，但现在可以主动选：

1 → 仅 WARP IPv4
2 → 仅 WARP IPv6
3 → WARP IPv4 + IPv6
IPv6-only VPS 则自动把 1 标成推荐；双栈 VPS自动把 3 标成推荐。三种模式的底层路由限制、状态页和出口测试逻辑都已经存在，不是只增加一个菜单选项。

我已经验证：

IPv4-only 默认回车 → ipv6_only ✅
IPv6-only 默认回车 → ipv4_only ✅
双栈默认回车       → dual      ✅
IPv4-only 手动选 1 → ipv4_only ✅
Bash 语法           ✅
主菜单 smoke test   ✅
版本显示 dev17      ✅
SHA256：

523a5c622b44072de314f9e4c2b42c5179f7a4befff8fbfdd21000fdd1bd4019
下载 ss2022.sh v1.8.0-dev17

下载标准文件名 ss2022.sh

你上传覆盖 GitHub main 后，直接用 9. 检查脚本更新 升级即可。


ss2022-v1.8.0-dev17.sh
程式碼


ss2022.sh
程式碼



資料庫
/
vps-bootstrap
/
ss2022-v1.8.0-dev17.sh


1
2
3
4
5
6
7
8
9
10
11
12
13
14
15
16
17
18
19
20
21
22
23
24
25
26
27
28
29
30
31
32
33
34
35
36
37
38
39
40
41
42
43
44
45
46
47
48
49
50
51
52
53
54
55
56
57
58
59
60
61
62
63
64
65
66
67
68
69
70
71
72
73
74
75
76
77
#!/bin/bash
# ==============================================================================
# 项目名称: vps-bootstrap / ss2022.sh
# 用途    : VPS 代理协议、服务端分流、Realm 端口转发的一体化管理脚本
# 快捷命令: ss2022 / proxy
# 当前版本: v1.8.0-dev17
#
# ┌──────────────────────────── 架构总览 ────────────────────────────┐
# │ 用户菜单                                                         │
# │   ├─ 协议管理 ────────────────┬─ sing-box: SS2022 / ShadowTLS   │
# │   │                            ├─ Xray: VLESS Reality             │
# │   │                            └─ snell-server: Snell v5          │
# │   ├─ 分流管理 ────────────────┬─ DIRECT                           │
# │   │                            ├─ WARP Local Proxy / 双栈补全      │
# │   │                            └─ Shadowsocks / SOCKS5 落地   │
# │   ├─ 端口转发 ────────────────── Realm                              │
# │   ├─ 协议运维                                                       │
# │   ├─ 组件版本管理                                                   │
# │   ├─ 脚本自更新
# │   ├─ 服务器管理工具                                                 │
# │   ├─ 服务器测试管理                                                 │
# │   └─ 完全卸载                                                       │
# └───────────────────────────────────────────────────────────────────┘
#
# 核心设计原则:
#   1. Snell 保持官方 snell-server v5，不参与 VPS 服务端分流。
#   2. 分流状态只有一个事实来源: /etc/ss2022/routing.json。
#   3. Realm 转发状态只有一个事实来源: /etc/ss2022/forwarding.json。
#   4. 修改配置先生成候选文件并调用核心自检，通过后才替换正式配置。
#   5. Xray / Realm 使用 ss2022 独立命名空间，不覆盖服务器已有同名服务。
#
# 代码导航（按文件从上到下）:
#   [01] 常量与路径
#   [02] 通用工具与状态面板
#   [03] 系统网络环境（DNS / 时间同步 / IPv4 / IPv6）
#   [04] 状态文件与 sing-box 基础设施
#   [05] 节点参数 / 客户端配置输出
#   [06] 协议更新与删除
#   [07] 协议部署、Xray 与 Snell 基础设施
#   [08] 节点配置查看
#   [09] 服务端分流（WARP / Chain / Rules）
#   [10] Realm L4 端口转发
#   [11] 服务运维与彻底卸载
#   [12] 组件版本管理
#   [13] 脚本自更新
#   [14] 菜单与程序入口（含服务器工具/测试预留入口）
#
# v1.8.0-dev6:
#   - 落地节点支持 Shadowsocks（SS2022 / 标准 SS 自动识别）
#   - 支持标准 ss:// URI 与手动输入
#   - 菜单文案去除不必要的“代理”字样，统一使用“协议 / 落地节点”术语
#   - “服务运维管理”更名为“协议运维管理”，为后续“服务器管理工具”留出独立边界
#   - 标准 SS 仅开放 sing-box / Xray 都兼容的 AEAD 算法，拒绝 SIP003 插件节点
#
# v1.8.0-dev7:
#   - 主菜单新增“服务器管理工具”固定入口
#   - 主菜单新增“服务器测试管理”固定入口
#   - 服务器测试预留 IP质量 / 路由 / 流媒体解锁 / AI工具 四类入口
#   - 修复 Realm 服务管理函数命名残留，避免菜单调用不存在的函数
#
# v1.8.0-dev8:
#   - 主菜单新增“检查脚本更新”
#   - 支持从 GitHub main 检查并自更新 /usr/local/bin/ss2022
#   - 同时比较版本号与 SHA256，开发期同版本内容变化也能识别
#   - 更新前执行 Bash 语法与项目标识检查，并保留最近一次脚本备份
#
# v1.8.0-dev9:
#   - 主菜单按三类重新分组并增加虚线分隔
#   - 服务器管理 / 测试前移为 7 / 8
#   - 脚本自更新移至 9，与完全卸载 / 退出归入脚本自身管理区
#
# v1.8.0-dev10:
#   - 标准 Shadowsocks 扩展至 sing-box 支持的 AEAD / 兼容旧算法
#   - Xray 原生支持的标准 SS 继续直连，避免额外本机转发
#   - Xray 不支持的标准 SS 自动使用 sing-box 本地 SOCKS Bridge
#   - VLESS 已部署且缺少 sing-box 时，先说明原因并征得确认后自动安装
#   - 先添加落地、后部署 VLESS 的场景也会自动补齐 Bridge 依赖
