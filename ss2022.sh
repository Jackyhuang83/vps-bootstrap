#!/bin/bash
# ==============================================================================
# 项目名称: vps-bootstrap / ss2022.sh
# 用途    : VPS 代理协议、服务端分流、Realm 端口转发的一体化管理脚本
# 快捷命令: ss2022（proxy 仅在路径未被其它程序占用时创建）
# 当前版本: v1.10.0-dev8
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
#   - 标准 SS 解析错误提示拆分为“算法不支持 / 密码解析失败”
#
# v1.8.0-dev11:
#   - ss:// 导入自动识别标准 Shadowsocks / SS2022
#
# v1.8.0-dev12:
#   - 落地节点入口合并为 Shadowsocks / SOCKS5
#   - Shadowsocks 粘贴 ss:// 后按 method 自动识别 SS2022 / 标准 SS
#   - 手动输入也统一在一个 Shadowsocks 菜单中选择算法
#   - 内部仍保留真实 method/type，用于 Xray 直连或 sing-box Bridge 自动决策
#
# v1.9.0-dev34:
#   - Realm 单独卸载补齐 OpenRC PID / 日志清理
#   - Realm 组仅在 REALM_GROUP_MARKER 确认由本脚本创建时删除，不再无条件 delete group
#   - 与完全卸载的服务账号 ownership 规则保持一致
#
# v1.10.0-dev8:
#   - 使用无公网路由的虚拟 veth 测试真实 Linux 内核 qdisc 恢复及冲突保护
#   - 视频优先、网页其次、聊天稳定：同终端双轮 A/B 证据只读审核
#   - 未完成真实 VPS 验收，候选值不自动应用也不持久化
#
# v1.10.0-dev7:
#   - 临时 60 秒、显式 TRIAL 的 HTB 出口整形实验；仅接受可信 scan 证据和可恢复独占 fq_codel
#   - systemd 预注册独立恢复 timer、前后配置再次校验、故障拒绝覆盖外部网络配置
#   - 非持久化、未经过真实 VPS 验证；禁止将开发试验当作已上线网络优化
#
# v1.10.0-dev6:
#   - 独立 watchdog 模拟恢复演练（支持启动 shell SIGKILL）、顺序就绪保护
#   - 严格 dry-run：仅撤销私有文件标记，不触及活动网卡、HTB/qdisc/sysctl
#
# v1.10.0-dev5:
#   - 可信 iperf3 三档 × 双轮 QoE 采样，独立单次 watchdog/聚合流量预算
#   - 自动将 6 份实测样本输出为私有 JSON 并交给 dev4 只读候选评估，不应用整形
#
# v1.10.0-dev4:
#   - 3档速率×2轮完整数据重复验证，只有可重复吞吐拐点加带载时延增长才计算候选速率
#   - 只读检查 tc qdisc/classes/filters，发现外部 mq/clsact 等配置即拒绝接管
#   - 本阶段永不自动写入候选值，不修改 SSH/路由/网卡 qdisc
#
# v1.10.0-dev3:
#   - 双轮 QoE 诊断：空闲/带载 P95 RTT、往返延迟波动、ICMP 响应缺失、TCP 有效吞吐
#   - 两轮一致才标注疑似排队或响应缺失；没有可重复信号则不建议整形
#   - 诊断只读；不改变路由、根队列或 TCP 内核参数
#
# v1.10.0-dev2:
#   - 新增 IPv4/IPv6 安全测速（指定 iperf3 对端、路由出口核验、速率/时长/流量预算三重约束）
#   - 独立 watchdog 监控网卡发送总流量，使用 JSON 结果和异常数据审查；不改 sysctl、路由、qdisc
#
# v1.10.0-dev1:
#   - 网络调优第一阶段：只读网络诊断、原始状态快照、原生 BBR/fq 安全迁移与恢复
#   - 拒绝接管管理员自定义 sysctl 和修改过的旧 BBR 配置；默认不触及 HTB、测速和路由
#   - 快照保存在 /var/lib/ss2022-network-tuning；完全卸载保留 BBR 与快照
#
# v1.9.0 Release:
#   - 正式支持 Debian / Ubuntu + systemd，并将 Alpine 3.21 + OpenRC 纳入稳定支持范围
#   - Alpine 正式支持 SS2022、SS2022 + ShadowTLS v3、VLESS Reality、Realm、服务器管理工具与服务器测试
#   - Snell v5 在 Debian / Ubuntu 保持官方 snell-server v5；Alpine 因官方 glibc 二进制不兼容而明确关闭，不注入第三方 glibc
#   - Cloudflare WARP 官方 Linux 客户端在 Debian / Ubuntu 保持支持；Alpine 暂不开放
#   - 完成完全卸载闭环：systemd/OpenRC 服务、PID、日志、临时文件、候选/回滚文件、WARP 资产与脚本备份均按 ownership 清理
#   - 完成 sing-box、Snell、proxy 快捷命令、IPv6 Keepalive、ForceIPv6、DNS 备份、WARP APT 仓库与共享配置目录 ownership 保护
#   - 保留用户主动设置的 BBR、DNS、SSH 端口和 IPv4/IPv6 地址优先级，避免卸载时破坏系统网络可达性
#   - GitHub Actions 覆盖 Bash 语法、ShellCheck、关键 ownership 回归保护、Alpine 3.21/OpenRC smoke test 与正式发布版本一致性校验
#
# v1.9.0-dev43:
#   - 首页仅在 /usr/local/bin/proxy 确认属于本项目时显示 proxy 快捷命令
#   - 安装文档不再使用 ln -sf 强制覆盖已有 proxy 路径
#
# v1.9.0-dev42:
#   - sing-box / Snell 配置目录增加独立 dir ownership marker；预先存在目录不再被 chown/chmod 接管
#   - 完全卸载只删除本项目配置与 .ss2022-* 临时文件，不再 rm -rf 整个 /etc/sing-box 或 /etc/snell
#   - sing-box / Snell 配置事务临时文件统一使用 .ss2022-* 前缀
#   - local-dns 自动迁移仅对确认属于 vps-bootstrap 的 sing-box 执行
#
# v1.9.0-dev41:
#   - IPv6-only APT 强制配置改为 99ss2022-force-ipv6，停止创建/删除通用 99force-ipv6
#   - 历史 99force-ipv6 因无法可靠证明 ownership，仅提示人工确认，不自动删除
#   - WARP ownership 拆分为软件包与 APT 仓库两层；已有 Cloudflare 仓库只复用、不接管
#   - 新增 WARP ownership v2 marker，兼容旧版单 marker 的卸载语义
#
# v1.9.0-dev40:
#   - /usr/local/bin/proxy 快捷命令增加 ownership 保护，不再覆盖服务器已有同名文件/链接
#   - 完全卸载仅删除确实指向本项目 /usr/local/bin/ss2022 的 proxy 链接
#
# v1.9.0-dev39:
#   - systemd IPv6 Keepalive unit 改为 ss2022-ipv6-keepalive.service/timer，避免占用通用服务名
#   - 历史 ipv6-keepalive.service/timer 仅在内容签名确认属于旧版 vps-bootstrap 时迁移/清理
#   - 完全卸载不再无条件 stop/delete 通用 ipv6-keepalive unit
#
# v1.9.0-dev38:
#   - Snell 安装候选文件改用 vps-bootstrap 专属隐藏前缀，完全卸载可安全清理中断残留
#   - SSH 新增端口事务在确认新端口监听成功后删除临时回滚备份，失败场景仍保留用于恢复
#
# v1.9.0-dev37:
#   - WARP managed marker 提前到 keyring / apt 源写入之前，覆盖中途安装失败清理路径
#   - IPv6-only DNS 备份改用 vps-bootstrap 专属路径，旧 /root/resolv.conf.orig 仅兼容读取
#   - 所有可识别安装/测试临时目录统一进入 /tmp/ss2022-* 命名空间，完全卸载统一清理
#
# v1.9.0-dev36:
#   - 增加 Snell 安装 ownership 保护，拒绝覆盖服务器预先存在的非 vps-bootstrap Snell
#   - 旧版项目 Snell 通过用户 marker / state.json 自动认领迁移
#   - 完全卸载仅在确认 Snell 属于本项目时停止并删除通用 Snell 二进制、配置和服务
#
# v1.9.0-dev35:
#   - Alpine 3.21 CI 实测确认 Surge 官方 Snell v5.0.1 在 gcompat 下无法启动（Not a valid dynamic program）
#   - Alpine 协议/组件菜单正式关闭 Snell v5，全部组件升级自动跳过 Snell
#   - 坚持仅使用 Surge 官方 snell-server：不注入第三方 glibc、不改用非官方实现
#   - Debian / Ubuntu 的 Snell v5 路径保持不变；完全卸载仍兼容清理早期 dev 版本可能留下的 Alpine Snell 文件
#
# v1.9.0-dev33:
#   - 增加 sing-box 安装 ownership 保护，拒绝覆盖服务器预先存在的非 vps-bootstrap sing-box
#   - 旧版 vps-bootstrap 通过 legacy user marker / 状态 / Alpine runtime 自动认领迁移，不影响升级
#   - 完全卸载只有确认 sing-box 属于本项目时才停止并删除通用 sing-box 二进制、配置和服务
#
# v1.9.0-dev32:
#   - 修复服务账号 ownership：仅本脚本新建的 sing-box / Xray / Realm / Snell 用户与组才写 managed marker
#   - 完全卸载仅删除有对应 managed marker 的用户/组，避免误删服务器预先存在的同名账号
#   - Snell 不再因“用户由脚本创建”而无条件删除可能预先存在的 snell 组
#
# v1.9.0-dev31:
#   - 明确“完全卸载”边界：协议核心/服务/运行文件清零，用户主动系统设置默认保留
#   - 卸载前明确提示 BBR、DNS、SSH 端口、IPv4/IPv6 地址优先级不会自动回滚
#   - 避免卸载脚本自动恢复系统设置导致 SSH 失联、DNS 变化或用户调优被意外撤销
#
# v1.9.0-dev30:
#   - 完全卸载补齐 /usr/local/bin/ss2022.bak、OpenRC PID 与 TG-BOT lockdir 清理
#   - IPv6-only DNS marker 在卸载结束前无条件移除；无法自动恢复 DNS 时给出明确提示
#   - 仅清理脚本自身运行残留，不自动回滚用户主动设置的 BBR / SSH / DNS 管理项
#
# v1.9.0-dev29:
#   - 修复 WARP 中途安装失败后完全卸载可能遗留 Cloudflare apt 源/keyring 的问题
#   - WARP managed marker 成为清理主判断；warp-cli 缺失时仍清理脚本创建的软件源与标记
#   - warp-cli 仅用于可选 disconnect/registration delete，不再阻断卸载闭环
#
# v1.9.0-dev28:
#   - IPv6-only 不再改写 /etc/apt/mirrors/debian.list 与 debian-security.list
#   - APT 仅通过独立 99force-ipv6 配置强制 IPv6，切回 IPv4/双栈时可直接删除
#   - 保留管理员原有 Debian/Ubuntu 镜像选择，消除不可逆镜像修改
#
# v1.9.0-dev27:
#   - 移除 IPv6-only 初始化对 /etc/hosts 中 github / ghproxy / danwin 记录的无条件删除
#   - 避免误删用户自定义 hosts、内网映射或第三方加速记录
#   - IPv6-only 仅检测 DNS/连通性，不再修改非本脚本拥有的 hosts 内容
#
# v1.9.0-dev26:
#   - 修复完全卸载未停用/删除 TG-BOT systemd timer/service 的残留
#   - Debian/Ubuntu 卸载时先 disable --now ss2022-tg-monitor.timer，再删除对应 service/timer 单元
#   - OpenRC crond 路径保持原有仅删除本项目 cron 条目的行为，不影响系统其他 cron 任务
#
# v1.9.0-dev25:
#   - 收口 v1.9 当前状态文案：移除 Alpine “dev1 首批开放”等过期提示
#   - Alpine 启动提示改为当前 OpenRC 支持范围，并明确 Snell 运行时自检与 WARP 官方客户端限制
#   - 不改变协议、路由、服务器工具或测试业务逻辑
#
# v1.9.0-dev24:
#   - 增加 SS2022_LIB_ONLY 测试加载模式，CI 可 source 全部函数而不进入交互主菜单
#   - 新增 Alpine 3.21 / OpenRC smoke test：平台识别、四核心服务生成、runlevel、PID 与完全卸载闭环
#   - 正常交互运行路径保持不变；测试加载模式仅由 CI 显式启用
#   - 修复 Alpine /etc/os-release 缺少 ID_LIKE 时严格模式读取未定义变量的问题
#
# v1.9.0-dev23:
#   - Snell v5 接入 systemd/OpenRC 统一服务抽象，Alpine 菜单正式开放运行时自检入口
#   - Alpine 仅使用系统仓库 gcompat/libstdc++/libgcc 兼容官方 snell-server，不注入第三方 glibc、不改用非官方实现
#   - 官方二进制下载/SHA256 校验后立即运行时自检；兼容失败则拒绝启动并输出 ldd/gcompat 诊断
#   - Snell 用户创建、PID、状态、日志、重启、回滚、删除、组件管理与完全卸载完成 OpenRC 适配
#   - OpenRC Snell 使用 supervise-daemon、独立非 root 用户、独立日志与 ambient CAP_NET_BIND_SERVICE，不修改官方二进制文件 capability
#
# v1.9.0-dev22:
#   - 修复 Alpine/OpenRC 完全卸载未停用 ss2022-ip-family 服务的问题
#   - 完全卸载补齐 Xray / Realm / IP-family 的 OpenRC init.d 服务脚本清理
#   - 保持 TG-BOT 仅删除本项目 crond 任务，不停止或修改系统其他 cron 任务
#
# v1.9.0-dev21:
#   - 修复 Realm 规则测试在 Alpine/OpenRC 下仍直接调用 systemctl 的残留
#   - Realm 服务状态统一使用 service_is_active() 抽象层
#   - Realm 配置页根据当前 init 正确显示 systemd 或 OpenRC 服务信息
#
# v1.9.0-dev20:
#   - 修复 systemd 服务状态抽象递归：service_is_active() 现在正确调用 systemctl is-active
#   - 避免 Debian/Ubuntu 下仪表盘、组件升级与服务状态判断进入递归调用
#
# v1.9.0-dev19:
#   - 服务器测试菜单收敛为三个入口：IP质量、三网逐跳回程、平台流媒体AI通信软件解锁测试
#   - 流媒体 / AI / 通信软件合并为一次测试流程，只选择一次地址族
#   - 流媒体地区选择后依次执行 RegionRestrictionCheck、UnlockTests AI-only 与通信软件可达性检测
#   - 保留三个检测模块各自成熟实现，不强行依赖单一万能上游
#
# v1.9.0-dev18:
#   - 修正回程测试定位：核心改为“逐跳 traceroute”，不再以线路分类汇总表作为主结果
#   - 回程上游切换为 nxtrace/NTrace-core（NextTrace）
#   - 固定测试北京 / 上海 / 广州 × 电信 / 联通 / 移动，共 9 条线路/地址族
#   - 每条线路使用 TCP/80，逐跳显示 IP / ASN / 地区 / 延迟，最大 30 跳
#   - IPv4+IPv6 / 仅 IPv4 / 仅 IPv6 继续独立选择
#   - NextTrace 使用官方 Release tiny 二进制，SHA256 校验后临时执行，用完删除
#
# v1.9.0-dev17:
#   - 回程路由从 backtrace legacy 终端模式切换到 backtrace.routes/v1 结构化报告
#   - 增加 IPv4+IPv6 / 仅 IPv4 / 仅 IPv6 地址族选择，与其他服务器测试保持一致
#   - 每个国内运营商目标默认并发探测 3 次，输出线路分类、确认度与成功次数
#   - 避免 legacy 模式自身 ipinfo.io / PreCheck / BGP 展示逻辑干扰回程结果
#   - 双栈时一次生成结构化报告，再分别渲染 IPv4 / IPv6，避免重复执行整套旧测试
#
# v1.9.0-dev16:
#   - 流媒体检测上游从 oneclickvirt/UnlockTests 切换为 1-stream/RegionRestrictionCheck
#   - 通用流媒体恢复原生 YouTube Premium，并保留 Netflix / Disney+ / Prime Video / Spotify / Google 等
#   - 上游作为临时函数库执行：通用平台只跑一次，再追加所选地区；AI 函数不会在流媒体模块调用
#   - 保留台湾/香港/日本/韩国/北美/南美/欧洲/非洲/东南亚/大洋洲/体育与自定义多地区组合
#   - 上游固定到已验证 commit，并使用 Git blob SHA 校验；执行完成后删除临时文件
#
# v1.9.0-dev15:
#   - 修复通用流媒体整组无输出：白名单误用了 UnlockTests 不存在的 YoutubePremium 检测名
#   - 通用流媒体改用已核对的上游函数短名：Netflix / NetflixCDN / DisneyPlus / PrimeVideo / Youtube / YoutubeCDN / GoogleSearch / GooglePlayStore / Apple
#   - 避免单个无效平台名触发 RunNamedTests 整组失败，恢复 Netflix / Google / Disney+ / Prime Video 等通用检测输出
#
# v1.9.0-dev14:
#   - 流媒体解锁测试增加 IPv4 / IPv6 各自出口 IP 与出口国家/地区显示
#   - 出口地区与平台自身 Region 分开显示：前者表示 VPS 出口地，后者表示平台识别/解锁区服
#   - 通信软件与流媒体复用同一套 Cloudflare trace 出口地区识别逻辑
#
# v1.9.0-dev13:
#   - 通信软件测试增加 IPv4 / IPv6 各自出口 IP 与出口国家/地区显示
#   - 出口地区使用 Cloudflare trace 的 loc 国家代码，不需要 API Token
#   - Telegram / WhatsApp / Signal / Discord 继续只表示网络可达性，不伪装成流媒体“区服解锁”
#
# v1.9.0-dev12:
#   - 流媒体与 AI 检测彻底拆分；不再使用会混入 AI 平台的“跨国平台”作为流媒体默认入口
#   - 流媒体固定增加 Netflix、YouTube、Disney+、Amazon Prime Video、Google、Apple 等通用平台白名单
#   - 选择欧洲/亚洲等地区时，先输出通用平台，再追加所选地区平台；“全部流媒体”明确排除 AI-only
#   - 新增通信软件网络可达性测试：Telegram、WhatsApp、Signal、Discord
#   - 通信软件按 IPv4 / IPv6 分开检测 DNS、TCP、TLS、HTTPS 可达性，不读取账号或凭据
#
# v1.9.0-dev11:
#   - 流媒体 / 区域解锁测试新增地区选择，不再固定扫描“全部平台”
#   - 地区菜单覆盖跨国、台湾、香港、日本、韩国、北美、南美、欧洲、非洲、东南亚、大洋洲、体育与全部平台
#   - 支持自定义多地区组合，并转换为 UnlockTests 官方 -region 参数
#   - 流媒体测试新增地址族选择：IPv4+IPv6 / 仅 IPv4 / 仅 IPv6
#   - AI 测试同样新增地址族选择，便于单独验证 IPv4/IPv6 AI 解锁状态
#   - 默认流媒体范围改为“跨国平台”，避免一次输出所有区域造成结果过长
#
# v1.9.0-dev10:
#   - 服务器测试统一改为跨发行版零依赖 Go 测试组件，Debian/Ubuntu 与 Alpine/OpenRC 共用同一条路径
#   - IP 质量测试替换旧 IP.Check.Place 入口，改用 oneclickvirt/securityCheck，避免旧入口配额/网页异常
#   - 回程路由替换 AutoTrace Shell 依赖，改用 oneclickvirt/backtrace，并自动覆盖可用 IPv4 / IPv6
#   - 流媒体与 AI 测试统一使用 oneclickvirt/UnlockTests；流媒体使用全部平台，AI 使用 AI-only
#   - 第三方测试二进制通过 GitHub Release API 获取官方 asset digest，并在执行前强制 SHA256 校验
#   - 测试组件只落到 /tmp，用后即删；不写系统服务、不修改协议配置、不长期安装第三方测试程序
#
# v1.9.0-dev9:
#   - Alpine / OpenRC 服务器管理工具由精简预览升级为完整菜单
#   - Swap / BBR / DNS / 时区 / SSH / 端口释放 / TG-BOT 流量监控完成 Alpine 适配
#   - IPv4 / IPv6 协议族硬关闭新增 OpenRC+nftables 持久化，保留 SSH 地址族安全保护与回滚
#   - 端口释放支持识别 systemd 或 OpenRC 服务；OpenRC 通过 PID 文件映射服务，无法识别时仍保留安全进程模式
#   - TG-BOT 在 systemd 使用 timer，在 Alpine/OpenRC 使用 root crond 每分钟任务；不停止或接管系统其他 cron 任务
#   - SSH 新端口支持 systemd/OpenRC reload，并兼容没有 sshd_config.d Include 的 Alpine 配置
#   - Alpine/musl 明确禁用无效的 /etc/gai.conf 地址优先级修改，业务地址族仍由现有分流规则控制
#
# v1.9.0-dev8:
#   - Alpine / OpenRC 开放 VLESS Reality（独立 Xray-core）与 Realm 端口转发
#   - Xray 新增 OpenRC 服务、非 root 用户、独立日志、低端口 capability 与安全重启/回滚
#   - Realm 继续使用官方 musl 资产，并新增 OpenRC 服务、非 root 用户、独立日志与低端口 capability
#   - Realm 配置权限统一修正为 root:服务组 0640，避免非 root 服务无法读取 config.json
#   - VLESS / Realm 的状态、日志、启动、停止、重启与卸载统一走 systemd/OpenRC 服务抽象
#   - Alpine 组件版本管理开放 Xray-core 与 Realm；Snell v5 继续暂缓
#
# v1.9.0-dev7:
#   - 修正“IPv4 / 双栈”旧菜单语义：0.0.0.0 只作为 IPv4 入站，不再误标为双栈
#   - SS2022 / ShadowTLS 新增真正的 IPv4 + IPv6 双栈入站模式，监听 :: 并要求 bindv6only=0
#   - 双栈模式部署前同时验证公网 IPv4、公网 IPv6 与内核 IPv4-mapped IPv6 监听能力
#   - 双栈节点自动保存 IPv4 / IPv6 两个服务器地址
#   - SS2022 / ShadowTLS 部署成功和“查看节点配置”时同时输出 IPv4 节点与 IPv6 节点
#   - IPv6 URI 自动使用方括号格式；IPv4/IPv6 两个节点共用同一端口、密钥与服务端实例
#
# v1.9.0-dev6:
#   - 修复 Alpine 3.21 apk-tools v2 无法读取上游 apk mkpkg 生成的 APK v3，导致 IO ERROR
#   - Alpine 改为 gcompat + sing-box 官方标准 Linux release 归档，不混用 Alpine edge 仓库
#   - 完整保留 sing-box 与 libcronet.so，避免仅复制单一二进制破坏官方运行时布局
#   - Alpine 运行时固定在 /usr/local/lib/ss2022/sing-box-runtime，/usr/local/bin/sing-box 仅作为安全包装入口
#   - capability 施加到真实 sing-box 二进制，并在设置前后分别做执行验证
#   - Debian / Ubuntu 安装路径保持不变
#
# v1.9.0-dev5:
#   - Alpine sing-box 安装切换为官方原生 .apk 资产，不再直接复制 Linux tar 包二进制
#   - x86_64 / aarch64 分别固定官方 Alpine APK SHA256，并由 apk 安装其运行依赖
#   - APK 安装成功后先验证 /usr/bin/sing-box，再复制到项目固定路径并设置低端口能力
#   - 新增 Alpine sing-box 包管理标记，后续彻底卸载时只清理由本脚本安装的 sing-box 包
#   - Debian / Ubuntu 继续使用原有 tar.gz + SHA256 安装路径，不受影响
#
# v1.9.0-dev4:
#   - 修复 Alpine 下载了 glibc/通用 Linux sing-box 后无法执行的问题
#   - Alpine x86_64 / arm64 改用 sing-box 官方 musl 构建，并固定对应官方 SHA256
#   - Debian / Ubuntu 继续使用原有 Linux 构建，不改变 v1.8.1 稳定路径
#   - sing-box 安装后执行失败时增加 Alpine ABI 提示，便于区分架构/动态链接器问题
#
# v1.9.0-dev3:
#   - 修复 Alpine/OpenRC 时间同步策略：不再强制以 chronyd 启动成功作为部署前提
#   - 新增 HTTPS Date 时钟偏差校验；当前系统时间已在安全范围内时直接继续部署
#   - Alpine 优先复用现有 chronyd / BusyBox ntpd / openntpd，避免重复安装时间守护进程
#   - 无可用时间服务时优先启用 Alpine 自带 BusyBox ntpd；失败再回退 chrony
#   - 时间同步失败时保留完整 OpenRC / ntpd / chronyd 诊断，不再误判“服务未运行=时钟一定不安全”
#
# v1.9.0-dev2:
#   - 修复 Alpine 部署前置阶段失败后界面立即清屏，导致错误原因不可见的问题
#   - SS2022 / ShadowTLS 增加“环境初始化 / sing-box 核心 / 端口参数”三阶段提示
#   - 环境初始化或核心安装失败时停留在错误页面并显示失败阶段，不再直接返回协议菜单
#   - Alpine chrony 启动/同步失败时追加 OpenRC 服务状态与 chronyc tracking
#   - Alpine setcap / OpenRC 服务注册失败时输出明确错误
#
# v1.9.0-dev1:
#   - 启动 Alpine / OpenRC 适配主线；Debian / Ubuntu + systemd 行为保持兼容
#   - 新增操作系统、init 与包管理器抽象：Debian/Ubuntu + systemd + apt，Alpine + OpenRC + apk
#   - 新增统一服务控制接口，首批覆盖 sing-box 的启动、停止、重启、状态、PID 与日志
#   - SS2022 / SS2022 + ShadowTLS v3 首批接入 OpenRC；Alpine 使用独立 init.d 服务并保持非 root 运行
#   - Alpine 基础依赖、chrony 时间同步、IPv6-only 环境与 IPv6 Keepalive 首批适配
#   - Alpine dev1 暂不开放 VLESS Reality、Snell v5、Realm、WARP 与完整服务器管理，避免未验证功能误操作
#   - 本版本为开发预览，需 Alpine VPS 实机验证后再继续扩大支持范围
#
# v1.8.1 Release:
#   - 正式发布 v1.8.1，基于已实机验证的 v1.8.1-dev10 收口，不引入新的业务逻辑
#   - 修复 sing-box 1.13.20 local DNS / prefer_go 兼容问题，并保留安全迁移与失败回滚
#   - 完善 IPv6-only、双栈与 WARP 补充地址族场景下的落地节点接入和出口测试
#   - 新增 IPv4 / IPv6 全局业务出口、应用级地址族分流以及可逆协议族关闭 / 恢复
#   - 新增应用地址族一键出口测试，已完成 YouTube 指定 IPv6 的实例验证
#   - 候选脚本采用版本化文件名并由 GitHub Actions 自动校验、晋级与清理
#
# v1.8.1-dev10:
#   - 应用 IPv4 / IPv6 分流新增“一键地址族出口测试”，无需手工安装 tcpdump
#   - 测试会读取应用当前规则、全局地址族与实际出口，计算最终生效的 IPv4 / IPv6 策略
#   - DIRECT / WARP / Shadowsocks / SOCKS5 落地均复用现有出口测试链路，直接回显最终出口 IP
#   - 应用固定 IPv4 / IPv6 时验证对应地址族；双栈/默认模式会分别探测 IPv4 与 IPv6 可用性
#   - 落地节点场景验证的是落地后的最终业务出口地址族，不把“主 VPS -> 落地”的接入地址族混为业务出口
#
# v1.8.1-dev9:
#   - 服务器管理新增统一 IPv4 / IPv6 管理：地址优先级、业务出口地址族、应用地址族分流、协议族关闭/恢复
#   - 新增全局业务出口：双栈 / 仅 IPv4 / 仅 IPv6；仅影响 vps-bootstrap 承载的分流业务流量
#   - 应用地址族复用现有 OpenAI / Netflix / YouTube / Google / Telegram / MyTVSuper / Apple TV+ / TikTok 规则库
#   - 应用可独立指定 默认 / 仅 IPv4 / 仅 IPv6；未单独指定时跟随全局业务出口地址族
#   - 新增可逆 IPv4 / IPv6 公网关闭：保留地址配置，以独立 nftables 表阻断指定协议族并通过 systemd 持久化
#   - 关闭当前 SSH 所使用的地址族会被拒绝；恢复双栈只删除本脚本自己的 nftables 规则
#
# v1.8.1-dev8:
#   - 修复 sing-box 1.13.20 local DNS 在部分精简系统中依赖 systemd-resolved / resolve1 导致解析异常
#   - 新生成的 local-dns 默认写入 prefer_go:true，优先使用 Go resolver
#   - 老用户启动新版脚本时自动检测已有 local-dns；缺少 prefer_go:true 时先生成候选配置并执行 sing-box check
#   - 候选配置校验通过后才替换；替换/重启失败自动回滚，且保持升级前服务运行状态
#
# v1.8.1-dev7:
#   - 修复双栈落地服务器域名可能优先拨号 IPv6 导致超时
#   - 双栈落地优先使用 VPS 原生 IPv4，其次原生 IPv6，再考虑 WARP
#   - Xray 使用 sockopt.domainStrategy 控制代理服务器域名地址族
#   - sing-box 使用 domain_strategy 控制代理服务器域名地址族
#   - 测试与正式分流统一使用相同的落地服务器接入地址族
#
# v1.8.1-dev6:
#   - 拆分落地节点地址族识别结果，不再把“双栈”和“无法确定”混为 default
#   - A + AAAA 同时存在时明确显示“IPv4 + IPv6 双栈”
#   - DNS 无法明确判断地址族时显示“地址族无法确定”
#
# v1.8.1-dev5:
#   - Shadowsocks 落地测试增加双检测站容错，避免单一 IP 查询站超时造成假失败
#   - ipify 失败后自动尝试 ident.me；IPv4 / IPv6 分别使用对应专用入口
#
# v1.8.1-dev4:
#   - 修复 dev3 IPv6-only 落地测试请求未进入 Xray SOCKS 入站的问题
#   - curl 仅连接本地 SOCKS；IPv6 目标解析交由 Xray ForceIPv6 / sing-box 处理
#
# v1.8.1-dev3:
#   - 修复“原生 IPv4 + WARP 补 IPv6”环境无法连接 IPv6-only 落地节点
#   - IPv6-only 落地在无原生 IPv6 时自动以 WARP 作为节点接入链路
#   - Xray 使用 dialerProxy，sing-box 使用 detour；测试与正式分流配置保持一致
#   - IPv4-only VPS 通过 WARP IPv6 连接落地后，最终业务出口仍为落地节点
#
# v1.8.1-dev2:
#   - 修复 IPv6-only Shadowsocks 落地节点被“默认地址族”测试误判失败
#   - 落地节点测试会根据节点服务器地址自动识别 IPv4-only / IPv6-only / 双栈
#   - IPv6-only Shadowsocks 测试自动使用 api6.ipify.org + Xray ForceIPv6
#   - 基础出口测试同样按落地节点地址族自动选择测试目标
#
# v1.8.1-dev1:
#   - 修复系统信息无法显示 WARP 补充 IPv6 的问题
#   - IPv6 显示优先使用 VPS 原生 IPv6；无原生 IPv6 时检测 WARP IPv6 出口
#   - WARP IPv6 显示增加“（WARP）”标识，避免与 VPS 原生 IPv6 混淆
#
# v1.8.0 Release:
#   - 正式发布 v1.8.0
#   - 集成 SS2022、SS2022 + ShadowTLS v3、VLESS Reality、Snell v5
#   - 集成 WARP、链式/分流路由、Realm L4 转发、节点管理与组件管理
#   - 集成服务器管理工具、服务器测试工具、TG-BOT 月流量监控与自动关机
#   - 完成端口占用识别与安全释放、自定义 DNS、系统信息增强
#   - 完成脚本自更新版本判断与防降级逻辑
#   - 本正式版基于 v1.8.0-dev29 收口，不再引入新的功能逻辑
#
# v1.8.0-dev29:
#   - 修复脚本自更新检查混用“当前运行脚本”和 /usr/local/bin/ss2022 导致的误判
#   - 更新界面分别显示当前运行版本、系统安装版本、GitHub main 远程版本
#   - 当前运行脚本与远程一致、但系统安装版本落后时，可同步安装到 /usr/local/bin/ss2022
#   - 增加版本新旧比较；GitHub main 比当前运行版本旧时明确提示并拒绝自动降级
#
# v1.8.0-dev28:
#   - “释放指定端口”进入后先显示全部监听端口，便于选择目标端口
#   - 端口输入阶段增加 0=返回，可随时取消释放操作
#
# v1.8.0-dev27:
#   - “查看端口占用”新增“释放指定端口”
#   - 释放前识别监听进程、PID、systemd 服务及 Docker 容器映射
#   - 支持停止服务、停止并禁用服务、停止 Docker 容器、结束监听进程
#   - 当前 SSH 会话所用端口禁止释放，避免远程失联
#   - 直接结束进程优先 SIGTERM；仍未退出时需再次输入 KILL 才执行 SIGKILL
#
# v1.8.0-dev26:
#   - 系统信息内存 / 虚拟内存单位去除 Gi / Mi 中的 i，统一显示 G / M
#   - 系统信息入站 / 出站流量改为按自然月累计
#   - 月流量状态持久化到 /etc/ss2022，VPS 重启后继续累计
#   - 每月 1 日自动进入新的统计周期
#
# v1.8.0-dev25:
#   - 系统信息页面将“主机名”移动到第一行显示
#
# v1.8.0-dev24:
#   - 系统信息运行时间统一改为“X 天”，不再显示 weeks
#   - 系统信息增加公网流量入站 / 出站累计
#   - 系统信息增加 IP 地理位置（国家 / 地区 / 城市）
#   - “根分区”更名为“硬盘占用”，“Swap”更名为“虚拟内存”
#   - TCP 拥塞算法与 qdisc 合并显示为“网络算法”
#   - 系统信息底部增加主机名
#
# v1.8.0-dev23:
#   - 系统信息增加 CPU 当前平均频率显示
#   - 删除“修改主机名”工具项
#   - 服务器重启改为输入 REBOOT 明文确认，避免误触
#   - DNS 管理增加自定义 DNS，支持厂商解锁 DNS 与多个 IPv4/IPv6 地址
#   - TG-BOT 自动关机阈值独立配置，默认 95%，不再写死 100%
#   - AI 工具测试切换到 oneclickvirt/ecs 使用的 UnlockTests AI-only 模块
#   - AI 测试临时下载对应架构二进制，测试后删除，不常驻安装
#
# v1.8.0-dev22:
#   - 服务器管理工具新增 TG-BOT 月流量监控 / 分级预警 / 可选自动关机
#   - 流量统计状态持久化，VPS 重启后累计值不清零；支持自定义每月重置日
#   - 端口占用查看增强：协议 / 监听地址 / PID / 进程，Docker 环境显示容器端口映射
#   - 系统信息新增公网 IPv4 / IPv6、IP 性质、ISP/ASN、IP 危险性评分
#   - IP 性质使用轻量 IP 元数据判断；IP 危险性优先显示 Scamalytics 0-100 风险分
#   - 服务器管理工具菜单重新排序，把日常高频项目放在前面
#
# v1.8.0-dev21:
#   - 完善“服务器管理工具”菜单，参考 kejilion.sh 常用系统工具但按本项目安全策略重写
#   - 新增系统信息、系统更新/清理、Swap、BBR、DNS、IPv4/IPv6 优先级、端口占用
#   - 新增时区、SSH 端口安全新增、主机名修改、服务器重启
#   - DNS 不锁死 resolv.conf；systemd-resolved 使用独立 drop-in，可恢复
#   - Swap 仅管理 /swapfile，不清理服务器已有其他 Swap
#   - BBR 仅启用当前内核已支持的原生 BBR，不自动更换内核
#   - SSH 新端口部署保留现有端口，先 sshd -t 校验，再 reload，降低远程失联风险
#
# v1.8.0-dev20:
#   - 修复服务器测试工具对第三方脚本 exit code 的误判
#   - IP质量 / 流媒体 / AI 测试先下载到临时文件，再执行，下载失败与脚本运行结果分离
#   - 第三方检测脚本完成后即使返回非 0，也不再额外显示“执行失败”
#   - AutoTrace 同步取消对第三方返回码的二次错误判定
#
# v1.8.0-dev19:
#   - 四种协议节点支持自定义节点名称，直接回车使用原默认名称
#   - 节点名称保存到 /etc/ss2022/state.json，并用于 URI / Surge / Loon / Mihomo / 二维码参数
#   - 已部署旧节点可在“查看节点配置 -> 修改节点名称”中直接改名，无需重装
#   - state.json 更新改为字段合并，修改端口/地址/SNI/密钥时不会丢失自定义节点名称
#
# v1.8.0-dev18:
#   - 正式接入服务器测试管理：IP 质量 / 回程路由 / 流媒体解锁 / AI 工具
#   - IP 质量使用 IP.Check.Place
#   - 回程路由使用 Chennhaoo/AutoTrace
#   - 流媒体解锁使用 1-stream/RegionRestrictionCheck
#   - AI 工具使用 adsorgcn/vpscheck，仅运行 AI 服务检测（-r 5）
#
# v1.8.0-dev17:
#   - WARP 出口模式菜单固定提供：仅 IPv4 / 仅 IPv6 / IPv4+IPv6 双栈
#   - IPv4-only VPS 默认推荐“仅 WARP IPv6”，但仍允许用户主动选择“仅 WARP IPv4”
#   - IPv6-only VPS 默认推荐“仅 WARP IPv4”，但仍允许用户主动选择“仅 WARP IPv6”
#   - 双栈 VPS 默认推荐 WARP 双栈；三种模式底层规则、状态页与测试逻辑保持一致
#
# v1.8.0-dev16:
#   - 修正 dev15 仅“推荐”补全地址族但仍同时暴露 WARP IPv4/IPv6 的问题
#   - WARP 安装/配置时明确选择：仅 IPv6 / 仅 IPv4 / 双栈
#   - IPv4-only VPS 默认推荐“仅 WARP IPv6”；IPv6-only VPS默认推荐“仅 WARP IPv4”
#   - 单地址族模式下，分流规则强制使用所选地址族，另一地址族始终保持 DIRECT
#   - 单地址族 WARP 不允许设为全局默认出口，避免未分类流量误走 WARP
#   - 状态页和出口测试只显示/测试当前启用的 WARP 地址族
#
# v1.8.0-dev15:
#   - WARP Local Proxy 增加原生 IPv4 / IPv6 自动检测与双栈补全提示
#   - IPv4-only VPS 推荐 DIRECT 保留原生 IPv4、WARP 补 IPv6
#   - IPv6-only VPS 推荐 DIRECT 保留原生 IPv6、WARP 补 IPv4
#   - 双栈 VPS 将 WARP 作为可选额外出口，不接管系统默认路由
#   - WARP 状态页分别显示 DIRECT/WARP 的 IPv4、IPv6 可用性与出口 IP
#   - 分流规则选择 WARP 时，IP 地址族默认推荐当前缺失的协议族
#   - 若将 WARP 设为全局默认出口，在“补全模式”下增加明确警告确认
#
# v1.8.0-dev14:
# - Shadowsocks 落地导入不再由 Bash 强制校验 SS2022 Key/Base64 长度；保留解析后的原始 password。
# - SS2022 落地在 VLESS/Xray 链路中优先使用 Xray 原生 Shadowsocks outbound。
# - sing-box 本地 Bridge 仅保留给 Xray 不支持、但 sing-box 支持的标准/Legacy Shadowsocks 算法。
# - 落地节点测试与分流出口测试按实际核心能力选择 Xray 或 sing-box。
#
# v1.8.0-dev13:
#   - 修复 SS2022 EIH / 多用户落地密码被误判为 Key 长度非法
#   - 支持 iPSK:uPSK 与多级 iPSK:...:uPSK 组合密码
#   - 每段 PSK 独立校验算法要求的字节长度
#   - 兼容 Base64URL / 缺失 padding，并规范化为标准 Base64 后写入配置
#
# 版本主线:
#   v1.7.0       四协议稳定基线
#   v1.8.0-dev1  服务端分流
#   v1.8.0-dev2  Realm L4 转发
#   v1.8.0-dev3  协议/组件/卸载菜单重构
#   v1.8.0-dev4  代码审计、瘦身与结构化
#   v1.8.0-dev5  标准 Shadowsocks 落地节点
#   v1.8.0-dev6  菜单术语整理 / 协议运维边界
#   v1.8.0-dev7  服务器管理 / 测试菜单定型
#   v1.8.0-dev8  GitHub 脚本自更新
#   v1.8.0-dev9  主菜单三段式定型
#   v1.8.0-dev10 标准 Shadowsocks 扩展算法 + Xray/sing-box 按需 Bridge
#   v1.8.0-dev11 ss:// 导入自动识别标准 SS / SS2022
#   v1.8.0-dev12 落地节点 Shadowsocks 入口合并
#   v1.8.0-dev13 SS2022 EIH 多 PSK 导入兼容
#   v1.8.0-dev14 SS2022 原始密码透传 / Xray 原生直连
#   v1.8.0-dev15 WARP IPv4/IPv6 双栈补全
#   v1.8.0-dev16 WARP 单地址族出口强制（IPv6-only / IPv4-only / 双栈）
#   v1.8.0-dev17 WARP 三种出口模式固定可选 / 按 VPS 网络自动推荐
#   v1.8.0-dev18 服务器测试工具正式接入
#   v1.8.0-dev19 协议节点自定义名称 / 旧节点在线改名
#   v1.8.0-dev20 第三方测试脚本返回码误判修复
#   v1.8.0-dev21 服务器管理工具轻量化完善
#   v1.8.0-dev22 TG-BOT 流量预警 / 端口占用增强 / IP 信息增强
#   v1.8.0-dev23 工具菜单实测收口 / AI 测试替换
#   v1.8.0-dev24 系统信息展示优化
#   v1.8.0-dev25 系统信息主机名置顶
#   v1.8.0-dev26 系统信息月流量统计 / 内存单位优化
#   v1.8.0-dev27 端口占用释放工具
#   v1.8.0-dev28 端口释放交互优化
#   v1.8.0-dev29 脚本自更新版本判断修复
#   v1.8.0 正式发布
#   v1.8.1-dev1 系统信息 WARP IPv6 显示修复
#   v1.8.1-dev2 IPv6-only 落地测试修复
#   v1.8.1-dev3 WARP 接入 IPv6-only 落地修复
#   v1.8.1-dev4 IPv6-only 落地测试 SOCKS 调用修复
#   v1.8.1-dev5 落地测试多检测站容错
#   v1.8.1-dev6 落地地址族识别文案拆分
#   v1.8.1-dev7 双栈落地服务器拨号地址族修复
#   v1.8.1-dev8 sing-box local DNS prefer_go 安全迁移
#   v1.8.1-dev9 IPv4 / IPv6 全局与应用级地址族管理
#   v1.8.1-dev10 应用地址族一键出口测试 / YouTube IPv6 实例验证
#   v1.8.1 正式发布
#   v1.9.0-dev1 Alpine / OpenRC 基础兼容层 / SS2022 + ShadowTLS 首批适配
#   v1.9.0-dev2 Alpine 部署前置阶段诊断增强
#   v1.9.0-dev3 Alpine/OpenRC 时间同步策略修复
#   v1.9.0-dev4 Alpine sing-box musl 构建修复
#   v1.9.0-dev5 Alpine sing-box 原生 APK 安装
#   v1.9.0-dev6 Alpine 3.21 gcompat + 完整 release 归档兼容
#   v1.9.0-dev7 SS2022/ShadowTLS IPv4+IPv6 双栈入站 / 双节点输出
#   v1.9.0-dev8 Alpine VLESS Reality / Realm OpenRC
#   v1.9.0-dev9 Alpine/OpenRC 服务器管理完整适配
#   v1.9.0-dev10 跨发行版服务器测试组件重构
#   v1.9.0-dev11 流媒体地区选择 / IPv4+IPv6 独立检测
#   v1.9.0-dev12 流媒体/AI拆分 / 通用平台 / 通信软件检测
#   v1.9.0-dev13 通信软件出口地区识别
#   v1.9.0-dev14 流媒体出口地区识别
#   v1.9.0-dev15 修复通用流媒体白名单
#   v1.9.0-dev16 流媒体上游切换 RegionRestrictionCheck
#   v1.9.0-dev17 回程路由结构化检测
#   v1.9.0-dev18 三网逐跳回程 NextTrace
#   v1.9.0-dev19 合并平台流媒体AI通信软件解锁测试
#   v1.9.0-dev20 修复 systemd 服务状态递归
#   v1.9.0-dev21 修复 Realm OpenRC 状态残留
#   v1.9.0-dev22 修复 OpenRC 完全卸载残留
#   v1.9.0-dev23 Snell v5 Alpine/OpenRC 运行时自检适配
#   v1.9.0-dev24 Alpine/OpenRC CI smoke test
#   v1.9.0-dev25 v1.9 支持状态文案收口
#   v1.9.0-dev26 修复 TG-BOT systemd 完全卸载残留
#   v1.9.0-dev27 禁止 IPv6-only 误删用户 hosts
#   v1.9.0-dev28 IPv6-only 不再改写 APT 镜像
#   v1.9.0-dev29 修复 WARP 异常安装卸载残留
#   v1.9.0-dev30 完全卸载文件残留收口
#   v1.9.0-dev31 明确完全卸载系统设置保留边界
#   v1.9.0-dev32 服务用户/组 ownership 保护
#   v1.9.0-dev33 sing-box 安装 ownership 保护
#   v1.9.0-dev34 Realm 单独卸载 ownership 收口
#   v1.9.0-dev35 Alpine Snell 官方二进制兼容性结论收口
#   v1.9.0-dev36 Snell 安装 ownership 保护
#   v1.9.0-dev37 完全卸载临时/备份残留与 WARP 失败路径收口
#   v1.9.0-dev38 Snell 候选文件与 SSH 事务备份残留收口
#   v1.9.0-dev39 IPv6 Keepalive systemd ownership 收口
#   v1.9.0-dev40 proxy 快捷命令 ownership 收口
#   v1.9.0-dev41 APT ForceIPv6 / WARP 仓库 ownership 收口
#   v1.9.0-dev42 sing-box / Snell 配置目录 ownership 收口
#   v1.9.0-dev43 proxy 展示与安装文档 ownership 一致性收口
#
# 注意: v1.9.0 为稳定正式版；Alpine 3.21 上 Snell v5 与 Cloudflare WARP 仍受官方组件兼容性限制。
# ==============================================================================
# [01] 常量与路径
SCRIPT_VERSION="v1.10.0-dev8"
# ----------------------------- 脚本自更新 --------------------------------------
SCRIPT_UPDATE_URL="https://raw.githubusercontent.com/Jackyhuang83/vps-bootstrap/main/ss2022.sh"
SCRIPT_INSTALL_PATH="/usr/local/bin/ss2022"
SCRIPT_PROXY_LINK="/usr/local/bin/proxy"
SCRIPT_BACKUP_PATH="/usr/local/bin/ss2022.bak"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'
PLATFORM_OS=""
PLATFORM_INIT=""
PLATFORM_PKG=""
PLATFORM_NAME=""
SINGBOX_OPENRC_SERVICE="/etc/init.d/sing-box"
SINGBOX_OPENRC_PID="/run/sing-box.pid"
SINGBOX_OPENRC_LOG="/var/log/ss2022/sing-box.log"
IPV6_KEEPALIVE_SYSTEMD_SERVICE_NAME="ss2022-ipv6-keepalive"
IPV6_KEEPALIVE_SYSTEMD_SERVICE="/etc/systemd/system/${IPV6_KEEPALIVE_SYSTEMD_SERVICE_NAME}.service"
IPV6_KEEPALIVE_SYSTEMD_TIMER="/etc/systemd/system/${IPV6_KEEPALIVE_SYSTEMD_SERVICE_NAME}.timer"
IPV6_KEEPALIVE_LEGACY_SERVICE="/etc/systemd/system/ipv6-keepalive.service"
IPV6_KEEPALIVE_LEGACY_TIMER="/etc/systemd/system/ipv6-keepalive.timer"
IPV6_KEEPALIVE_OPENRC_SERVICE="/etc/init.d/ss2022-ipv6-keepalive"
IPV6_KEEPALIVE_HELPER="/usr/local/lib/ss2022/ipv6-keepalive.sh"
# ----------------------------- sing-box ---------------------------------------
SINGBOX_BIN="/usr/local/bin/sing-box"
SINGBOX_CONF_DIR="/etc/sing-box"
SINGBOX_CONF="${SINGBOX_CONF_DIR}/config.json"
SINGBOX_DIR_MARKER="/etc/ss2022-singbox-dir-managed"
SINGBOX_SERVICE="/etc/systemd/system/sing-box.service"
SINGBOX_USER="sing-box"
SINGBOX_GROUP="sing-box"
SINGBOX_USER_MARKER="/etc/ss2022-singbox-user-managed"
SINGBOX_GROUP_MARKER="/etc/ss2022-singbox-group-managed"
SINGBOX_MANAGED_MARKER="/etc/ss2022-singbox-install-managed"
SINGBOX_ALPINE_PKG_MARKER="/etc/ss2022-singbox-apk-managed"
SINGBOX_ALPINE_RUNTIME_DIR="/usr/local/lib/ss2022/sing-box-runtime"
SINGBOX_ALPINE_RUNTIME_BIN="${SINGBOX_ALPINE_RUNTIME_DIR}/sing-box"
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
XRAY_GROUP_MARKER="/etc/ss2022-xray-group-managed"
XRAY_OPENRC_SERVICE="/etc/init.d/${XRAY_SERVICE_NAME}"
XRAY_OPENRC_PID="/run/${XRAY_SERVICE_NAME}.pid"
XRAY_OPENRC_LOG="/var/log/ss2022/${XRAY_SERVICE_NAME}.log"
XRAY_SHA256_AMD64="23cd9af937744d97776ee35ecad4972cf4b2109d1e0fe6be9930467608f7c8ae"
XRAY_SHA256_ARM64="4d30283ae614e3057f730f67cd088a42be6fdf91f8639d82cb69e48cde80413c"
# ----------------------------- Snell v5 ---------------------------------------
SNELL_VERSION="5.0.1"
SNELL_BIN="/usr/local/bin/snell-server-v5"
SNELL_CONF_DIR="/etc/snell"
SNELL_CONF="${SNELL_CONF_DIR}/snell-v5.conf"
SNELL_DIR_MARKER="/etc/ss2022-snell-dir-managed"
SNELL_SERVICE="/etc/systemd/system/snell-v5.service"
SNELL_USER="snell"
SNELL_GROUP="snell"
SNELL_USER_MARKER="/etc/ss2022-snell-user-managed"
SNELL_GROUP_MARKER="/etc/ss2022-snell-group-managed"
SNELL_MANAGED_MARKER="/etc/ss2022-snell-install-managed"
SNELL_CANDIDATE_PREFIX="/usr/local/bin/.ss2022-snell-server-v5.new"
SNELL_OPENRC_SERVICE="/etc/init.d/snell-v5"
SNELL_OPENRC_PID="/run/snell-v5.pid"
SNELL_OPENRC_LOG="/var/log/ss2022/snell-v5.log"
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
REALM_GROUP_MARKER="/etc/ss2022-realm-group-managed"
REALM_OPENRC_SERVICE="/etc/init.d/${REALM_SERVICE_NAME}"
REALM_OPENRC_PID="/run/${REALM_SERVICE_NAME}.pid"
REALM_OPENRC_LOG="/var/log/ss2022/${REALM_SERVICE_NAME}.log"
FORWARDING_FILE="/etc/ss2022/forwarding.json"
REALM_MAX_RANGE_PORTS=1000
# ----------------------------- 网络环境 ----------------------------------------
BACKUP_DNS="/root/.ss2022-resolv.conf.bak"
LEGACY_BACKUP_DNS="/root/resolv.conf.orig"
DNS_MARKER="/etc/ss2022-ipv6-dns-managed"
FORCE_IPV6_CONF="/etc/apt/apt.conf.d/99ss2022-force-ipv6"
FORCE_IPV6_LEGACY_CONF="/etc/apt/apt.conf.d/99force-ipv6"
STATE_DIR="/etc/ss2022"
STATE_FILE="${STATE_DIR}/state.json"
ROUTING_FILE="${STATE_DIR}/routing.json"
WARP_DEFAULT_PORT=40000
WARP_MANAGED_MARKER="${STATE_DIR}/warp-package-managed"
WARP_REPO_MANAGED_MARKER="${STATE_DIR}/warp-repo-managed"
WARP_OWNERSHIP_V2_MARKER="${STATE_DIR}/warp-ownership-v2"
WARP_APT_SOURCE="/etc/apt/sources.list.d/cloudflare-client.list"
WARP_APT_KEYRING="/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg"
IP_FAMILY_MODE_FILE="${STATE_DIR}/ip-family-mode"
IP_FAMILY_APPLY_HELPER="/usr/local/lib/ss2022/ip-family-apply.sh"
IP_FAMILY_SERVICE_NAME="ss2022-ip-family"
IP_FAMILY_SERVICE="/etc/systemd/system/${IP_FAMILY_SERVICE_NAME}.service"
IP_FAMILY_OPENRC_SERVICE="/etc/init.d/${IP_FAMILY_SERVICE_NAME}"
# ----------------------------- TG-BOT 流量监控 ---------------------------------
TG_MONITOR_CONF="${STATE_DIR}/tg-monitor.conf"
TG_MONITOR_STATE="${STATE_DIR}/tg-monitor.state"
SYSTEM_INFO_TRAFFIC_STATE="${STATE_DIR}/system-info-traffic.state"
TG_MONITOR_WORKER="/usr/local/lib/ss2022/tg-traffic-monitor.sh"
TG_MONITOR_SERVICE="/etc/systemd/system/ss2022-tg-monitor.service"
TG_MONITOR_TIMER="/etc/systemd/system/ss2022-tg-monitor.timer"
TG_MONITOR_CRON_FILE="/etc/crontabs/root"
TG_MONITOR_CRON_TAG="# ss2022-tg-monitor"
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
SERVER_HOST_V4=""
SERVER_HOST_V6=""
NETWORK_MODE=""
LISTEN_ADDR=""
NODE_NAME=""
# ==============================================================================
# [02] 通用工具与状态面板
# ==============================================================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[错误] 必须使用 root 权限运行此脚本！${PLAIN}"
        exit 1
    fi
}

detect_platform() {
    local os_id="" os_like="" pretty=""
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        os_id="${ID:-}"
        os_like="${ID_LIKE:-}"
        pretty="${PRETTY_NAME:-${NAME:-}}"
    fi

    case "$os_id" in
        debian|ubuntu)
            PLATFORM_OS="$os_id"
            PLATFORM_PKG="apt"
            PLATFORM_NAME="$pretty"
            command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]] || {
                echo "[错误] Debian / Ubuntu 当前仅支持 systemd。"
                return 1
            }
            PLATFORM_INIT="systemd"
            ;;
        alpine)
            PLATFORM_OS="alpine"
            PLATFORM_PKG="apk"
            PLATFORM_NAME="$pretty"
            command -v rc-service >/dev/null 2>&1 && command -v rc-update >/dev/null 2>&1 || {
                echo "[错误] 检测到 Alpine，但未检测到完整 OpenRC 环境。"
                return 1
            }
            PLATFORM_INIT="openrc"
            ;;
        *)
            if [[ " $os_like " == *" debian "* ]]; then
                PLATFORM_OS="debian"
                PLATFORM_PKG="apt"
                PLATFORM_NAME="$pretty"
                command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]] || {
                    echo "[错误] Debian 系发行版当前仅支持 systemd。"
                    return 1
                }
                PLATFORM_INIT="systemd"
            else
                echo "[错误] 暂不支持当前发行版: $os_id"
                echo "当前支持: Debian / Ubuntu + systemd；Alpine + OpenRC（v1.9 开发预览）。"
                return 1
            fi
            ;;
    esac

    [[ -n "$PLATFORM_NAME" ]] || PLATFORM_NAME="$os_id"
    return 0
}

platform_is_alpine() {
    [[ "$PLATFORM_OS" == "alpine" ]]
}

platform_label() {
    case "$PLATFORM_INIT" in
        systemd) printf '%s / systemd' "$PLATFORM_NAME" ;;
        openrc) printf '%s / OpenRC' "$PLATFORM_NAME" ;;
        *) printf '%s' "$PLATFORM_NAME" ;;
    esac
}

pkg_update() {
    case "$PLATFORM_PKG" in
        apt) DEBIAN_FRONTEND=noninteractive apt-get update -y ;;
        apk) apk update ;;
        *) return 1 ;;
    esac
}

pkg_install() {
    case "$PLATFORM_PKG" in
        apt) DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
        apk) apk add --no-cache "$@" ;;
        *) return 1 ;;
    esac
}

pkg_remove() {
    case "$PLATFORM_PKG" in
        apt) DEBIAN_FRONTEND=noninteractive apt-get remove -y "$@" ;;
        apk) apk del "$@" ;;
        *) return 1 ;;
    esac
}

service_daemon_reload() {
    if [[ "$PLATFORM_INIT" == "systemd" ]]; then
        systemctl daemon-reload
    else
        return 0
    fi
}

service_is_active() {
    local svc="$1"
    case "$PLATFORM_INIT" in
        systemd) systemctl is-active --quiet "$svc" 2>/dev/null ;;
        openrc) rc-service "$svc" status >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

service_enable() {
    local svc="$1"
    case "$PLATFORM_INIT" in
        systemd) systemctl enable "$svc" >/dev/null 2>&1 ;;
        openrc) rc-update add "$svc" default >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

service_disable() {
    local svc="$1"
    case "$PLATFORM_INIT" in
        systemd) systemctl disable "$svc" >/dev/null 2>&1 ;;
        openrc) rc-update del "$svc" default >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

service_start() {
    local svc="$1"
    case "$PLATFORM_INIT" in
        systemd) systemctl start "$svc" ;;
        openrc) rc-service "$svc" start ;;
        *) return 1 ;;
    esac
}

service_stop() {
    local svc="$1"
    case "$PLATFORM_INIT" in
        systemd) systemctl stop "$svc" ;;
        openrc) rc-service "$svc" stop ;;
        *) return 1 ;;
    esac
}

service_restart() {
    local svc="$1"
    case "$PLATFORM_INIT" in
        systemd) systemctl restart "$svc" ;;
        openrc) rc-service "$svc" restart ;;
        *) return 1 ;;
    esac
}

service_reload() {
    local svc="$1"
    case "$PLATFORM_INIT" in
        systemd) systemctl reload "$svc" ;;
        openrc) rc-service "$svc" reload ;;
        *) return 1 ;;
    esac
}

service_exists() {
    local svc="$1"
    case "$PLATFORM_INIT" in
        systemd) systemctl list-unit-files 2>/dev/null | awk '{print $1}' | grep -qx "${svc}.service" ;;
        openrc) [[ -x "/etc/init.d/$svc" ]] ;;
        *) return 1 ;;
    esac
}

service_enable_now() {
    local svc="$1"
    service_enable "$svc" || return 1
    service_is_active "$svc" && return 0
    service_start "$svc"
}

service_disable_now() {
    local svc="$1"
    service_stop "$svc" >/dev/null 2>&1 || true
    service_disable "$svc" >/dev/null 2>&1 || true
}

service_main_pid() {
    local svc="$1" pidfile="" pid=""
    if [[ "$PLATFORM_INIT" == "systemd" ]]; then
        systemctl show -p MainPID --value "$svc" 2>/dev/null || true
        return
    fi
    case "$svc" in
        sing-box) pidfile="$SINGBOX_OPENRC_PID" ;;
        "$XRAY_SERVICE_NAME") pidfile="$XRAY_OPENRC_PID" ;;
        snell-v5) pidfile="$SNELL_OPENRC_PID" ;;
        "$REALM_SERVICE_NAME") pidfile="$REALM_OPENRC_PID" ;;
    esac
    if [[ -n "$pidfile" && -r "$pidfile" ]]; then
        cat "$pidfile" 2>/dev/null || true
        return
    fi
    case "$svc" in
        "$XRAY_SERVICE_NAME") pid=$(pgrep -o -f "$XRAY_BIN" 2>/dev/null || true) ;;
        "$REALM_SERVICE_NAME") pid=$(pgrep -o -f "$REALM_BIN" 2>/dev/null || true) ;;
        *) pid=$(pgrep -o -x "$svc" 2>/dev/null || true) ;;
    esac
    [[ -n "$pid" ]] && printf '%s\n' "$pid"
}
service_status_output() {
    local svc="$1"
    case "$PLATFORM_INIT" in
        systemd) systemctl --no-pager --full status "$svc" 2>/dev/null ;;
        openrc) rc-service "$svc" status 2>/dev/null ;;
        *) return 1 ;;
    esac
}

service_log_tail() {
    local svc="$1" lines="$2" log="/var/log/ss2022/$1.log"
    if [[ "$PLATFORM_INIT" == "systemd" ]]; then
        journalctl -u "$svc" -n "$lines" --no-pager 2>/dev/null
        return
    fi
    if [[ -f "$log" ]]; then
        tail -n "$lines" "$log"
    else
        rc-service "$svc" status 2>/dev/null || true
        echo "[提示] OpenRC 未发现该服务的独立日志文件。"
    fi
}

service_log_follow() {
    local svc="$1" log="/var/log/ss2022/$1.log"
    if [[ "$PLATFORM_INIT" == "systemd" ]]; then
        journalctl -u "$svc" -f -n 30
        return
    fi
    if [[ -f "$log" ]]; then
        tail -n 30 -f "$log"
    else
        rc-service "$svc" status 2>/dev/null || true
        echo "[提示] OpenRC 未发现该服务的独立日志文件。"
        return 1
    fi
}

platform_feature_unavailable() {
    local feature="$1"
    echo ""
    echo "[提示] Alpine / OpenRC 当前不提供：$feature"
    echo "v1.9.0 正式版已适配 SS2022、ShadowTLS v3、VLESS Reality、Realm、服务器工具与测试。"
    echo "Snell v5 官方 Linux 二进制依赖 glibc，已确认无法在 Alpine 3.21 + gcompat 下正常启动；本脚本不注入第三方 glibc，也不替换非官方实现。"
    echo "Cloudflare WARP 官方 Linux 客户端当前未提供 Alpine 支持，因此本脚本也不在 Alpine 上强行安装。"
    return 1
}

system_group_exists() {
    grep -q "^$1:" /etc/group 2>/dev/null
}

ensure_system_group() {
    local group="$1"
    system_group_exists "$group" && return 0
    if platform_is_alpine; then
        addgroup -S "$group"
    else
        groupadd --system "$group"
    fi
}

add_system_user_to_group() {
    local user="$1" group="$2"
    id -nG "$user" 2>/dev/null | tr ' ' '\n' | grep -qx "$group" && return 0
    if platform_is_alpine; then
        addgroup "$user" "$group"
    else
        usermod -a -G "$group" "$user"
    fi
}

create_system_user() {
    local user="$1" group="$2" nologin_shell=""
    ensure_system_group "$group" || return 1
    if id -u "$user" >/dev/null 2>&1; then
        add_system_user_to_group "$user" "$group"
        return
    fi

    nologin_shell=$(command -v nologin 2>/dev/null || true)
    if platform_is_alpine; then
        [[ -n "$nologin_shell" ]] || nologin_shell="/sbin/nologin"
        [[ -x "$nologin_shell" ]] || nologin_shell="/bin/false"
        adduser -S -D -H -h /nonexistent -s "$nologin_shell" -G "$group" "$user"
    else
        [[ -n "$nologin_shell" ]] || nologin_shell="/usr/sbin/nologin"
        useradd --system --gid "$group" --no-create-home --home-dir /nonexistent --shell "$nologin_shell" "$user"
    fi
}

ensure_managed_system_user() {
    local user="$1" group="$2" user_marker="$3" group_marker="$4"
    local user_existed=0 group_existed=0

    id -u "$user" >/dev/null 2>&1 && user_existed=1
    system_group_exists "$group" && group_existed=1

    create_system_user "$user" "$group" || return 1

    if [[ $user_existed -eq 0 ]]; then
        touch "$user_marker" || return 1
        chmod 600 "$user_marker"
    fi
    if [[ $group_existed -eq 0 ]]; then
        touch "$group_marker" || return 1
        chmod 600 "$group_marker"
    fi
    return 0
}

delete_system_user() {
    local user="$1"
    id -u "$user" >/dev/null 2>&1 || return 0
    if platform_is_alpine; then
        deluser "$user" >/dev/null 2>&1 || true
    else
        userdel "$user" >/dev/null 2>&1 || true
    fi
}

delete_system_group() {
    local group="$1"
    system_group_exists "$group" || return 0
    if platform_is_alpine; then
        delgroup "$group" >/dev/null 2>&1 || true
    else
        groupdel "$group" >/dev/null 2>&1 || true
    fi
}

keepalive_service_name() {
    if [[ "$PLATFORM_INIT" == "openrc" ]]; then
        echo "ss2022-ipv6-keepalive"
    else
        echo "${IPV6_KEEPALIVE_SYSTEMD_SERVICE_NAME}.timer"
    fi
}

legacy_ipv6_keepalive_is_project_managed() {
    [[ -f "$IPV6_KEEPALIVE_LEGACY_SERVICE" && -f "$IPV6_KEEPALIVE_LEGACY_TIMER" ]] || return 1
    grep -Fqx 'Description=IPv6 HTTPS Keepalive Probe' "$IPV6_KEEPALIVE_LEGACY_SERVICE" 2>/dev/null || return 1
    grep -Fqx 'ExecStart=/usr/bin/curl -6fsSI --max-time 5 https://www.cloudflare.com' "$IPV6_KEEPALIVE_LEGACY_SERVICE" 2>/dev/null || return 1
    grep -Fqx 'Description=Run IPv6 Keepalive Every 5 Minutes' "$IPV6_KEEPALIVE_LEGACY_TIMER" 2>/dev/null || return 1
    grep -Fqx 'Unit=ipv6-keepalive.service' "$IPV6_KEEPALIVE_LEGACY_TIMER" 2>/dev/null || return 1
    return 0
}

cleanup_legacy_ipv6_keepalive_if_managed() {
    legacy_ipv6_keepalive_is_project_managed || return 0
    if command -v systemctl >/dev/null 2>&1; then
        systemctl disable --now ipv6-keepalive.timer >/dev/null 2>&1 || true
        systemctl stop ipv6-keepalive.service >/dev/null 2>&1 || true
    fi
    rm -f "$IPV6_KEEPALIVE_LEGACY_SERVICE" "$IPV6_KEEPALIVE_LEGACY_TIMER"
    service_daemon_reload >/dev/null 2>&1 || true
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
http_time_skew_seconds() {
    local header="" remote_date="" remote_epoch="" local_epoch="" skew=""

    command -v curl >/dev/null 2>&1 || return 1
    command -v date >/dev/null 2>&1 || return 1

    header=$(curl -kfsSI --connect-timeout 4 --max-time 8 https://www.cloudflare.com 2>/dev/null | tr -d '\r' || true)
    remote_date=$(printf '%s\n' "$header" | awk 'BEGIN{IGNORECASE=1} /^date:[[:space:]]*/{sub(/^[Dd][Aa][Tt][Ee]:[[:space:]]*/, ""); print; exit}')
    [[ -n "$remote_date" ]] || return 1

    remote_epoch=$(date -u -d "$remote_date" +%s 2>/dev/null || true)
    local_epoch=$(date -u +%s 2>/dev/null || true)
    [[ "$remote_epoch" =~ ^[0-9]+$ && "$local_epoch" =~ ^[0-9]+$ ]] || return 1

    if (( local_epoch >= remote_epoch )); then
        skew=$((local_epoch - remote_epoch))
    else
        skew=$((remote_epoch - local_epoch))
    fi
    printf '%s\n' "$skew"
}

http_time_is_healthy() {
    local skew=""
    skew=$(http_time_skew_seconds 2>/dev/null || true)
    [[ "$skew" =~ ^[0-9]+$ ]] || return 1
    (( skew <= 120 ))
}

time_sync_is_healthy() {
    local ntp_sync=""

    if command -v timedatectl >/dev/null 2>&1; then
        ntp_sync=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)
        [[ "$ntp_sync" == "yes" ]] && return 0
    fi

    if command -v chronyc >/dev/null 2>&1; then
        if chronyc tracking 2>/dev/null | grep -Eq '^Leap status[[:space:]]*:[[:space:]]*Normal$'; then
            return 0
        fi
    fi

    # VPS 场景下只要当前时钟与可信公网 Date 相差不超过 120 秒，
    # 就满足 SS2022 / Reality 部署前的时间安全要求，不强制绑定某个 NTP 实现。
    if http_time_is_healthy; then
        return 0
    fi

    # Alpine / OpenRC 允许系统已有的 NTP 守护进程继续负责长期校时。
    if [[ "$PLATFORM_INIT" == "openrc" ]]; then
        rc-service chronyd status >/dev/null 2>&1 && return 0
        rc-service ntpd status >/dev/null 2>&1 && return 0
        rc-service openntpd status >/dev/null 2>&1 && return 0
    fi

    return 1
}
get_time_sync_status() {
    if time_sync_is_healthy; then
        echo -e "${GREEN}● 已同步/时钟正常${PLAIN}"
    elif command -v chronyc >/dev/null 2>&1 || command -v timedatectl >/dev/null 2>&1 || [[ "$PLATFORM_INIT" == "openrc" ]]; then
        echo -e "${YELLOW}○ 未确认同步${PLAIN}"
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
        if service_is_active "$REALM_SERVICE_NAME"; then
            realm_status="${GREEN}● 运行中${PLAIN}"
        else
            realm_status="${RED}○ 已停止${PLAIN}"
        fi
    fi
    if [[ -f "$FORWARDING_FILE" ]]; then
        forwarding_count=$(jq '.rules|length' "$FORWARDING_FILE" 2>/dev/null || echo 0)
    fi
    if service_is_active sing-box; then
        sb_status="${GREEN}● 运行中${PLAIN}"
    elif [[ -f "$SINGBOX_CONF" || -x "$SINGBOX_BIN" ]]; then
        sb_status="${RED}○ 已停止${PLAIN}"
    fi
    if service_is_active "$XRAY_SERVICE_NAME"; then
        xray_status="${GREEN}● 运行中${PLAIN}"
    elif [[ -f "$XRAY_CONF" || -x "$XRAY_BIN" ]]; then
        xray_status="${RED}○ 已停止${PLAIN}"
    fi
    if service_is_active snell-v5; then
        snell_status="${GREEN}● 运行中${PLAIN}"
    elif [[ -f "$SNELL_CONF" || -x "$SNELL_BIN" ]]; then
        snell_status="${RED}○ 已停止${PLAIN}"
    fi
    if service_is_active "$(keepalive_service_name)"; then
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
    echo -e "      SS2022 多协议管理脚本 ${SCRIPT_VERSION}"
    if proxy_shortcut_is_project_managed; then
        echo -e "      快捷命令: ${GREEN}ss2022${PLAIN} 或 ${GREEN}proxy${PLAIN}"
    else
        echo -e "      快捷命令: ${GREEN}ss2022${PLAIN}"
    fi
    echo -e "${CYAN}═════════════════════════════════════════════════════════════════${PLAIN}"
    echo -e "  系统信息: ${sys_info}"
    echo -e "  运行环境: $(platform_label)"
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
# ==============================================================================
# [03] 系统网络环境：DNS / 时间同步 / IPv4 / IPv6
# ==============================================================================
restore_ipv4_apt_and_dns_if_needed() {
    local should_restore=0 backup=""
    rm -f "$FORCE_IPV6_CONF"
    if [[ -f "$FORCE_IPV6_LEGACY_CONF" ]] &&
       grep -Fqx 'Acquire::ForceIPv6 "true";' "$FORCE_IPV6_LEGACY_CONF" 2>/dev/null; then
        echo -e "${YELLOW}[提示] 检测到历史 /etc/apt/apt.conf.d/99force-ipv6。其 ownership 无法可靠判定，dev41 起不再自动删除；如确认由旧版 vps-bootstrap 创建，可手动移除。${PLAIN}"
    fi

    if [[ -f "$DNS_MARKER" ]]; then
        should_restore=1
        if [[ -f "$BACKUP_DNS" ]]; then
            backup="$BACKUP_DNS"
        elif [[ -f "$LEGACY_BACKUP_DNS" ]]; then
            backup="$LEGACY_BACKUP_DNS"
        fi
    elif [[ -f "$BACKUP_DNS" && -f /etc/resolv.conf && ! -L /etc/resolv.conf ]] \
         && grep -q '2001:4860:4860::8888' /etc/resolv.conf \
         && grep -q '2606:4700:4700::1111' /etc/resolv.conf; then
        should_restore=1
        backup="$BACKUP_DNS"
    fi

    [[ $should_restore -eq 1 ]] || return 0

    if [[ -L /etc/resolv.conf ]]; then
        rm -f "$DNS_MARKER" "$BACKUP_DNS"
        return 0
    fi

    if [[ -z "$backup" || ! -f "$backup" ]]; then
        echo -e "${YELLOW}[警告] 未找到 IPv6-only DNS 备份，请手动检查 /etc/resolv.conf。${PLAIN}"
        return 1
    fi

    if cp -f "$backup" /etc/resolv.conf; then
        rm -f "$DNS_MARKER"
        [[ "$backup" == "$BACKUP_DNS" ]] && rm -f "$BACKUP_DNS"
        echo -e "${GREEN}✔ 已恢复 IPv4/双栈环境原 DNS 配置。${PLAIN}"
        return 0
    fi

    echo -e "${YELLOW}[警告] DNS 自动恢复失败，请手动检查 /etc/resolv.conf。备份仍保留在: ${backup}${PLAIN}"
    return 1
}
ensure_time_sync() {
    local attempt=0 chrony_svc="" skew=""

    echo -e "${YELLOW}>> 检查系统时间同步状态...${PLAIN}"
    if time_sync_is_healthy; then
        skew=$(http_time_skew_seconds 2>/dev/null || true)
        if [[ "$skew" =~ ^[0-9]+$ ]]; then
            echo -e "${GREEN}✔ 系统时钟正常，与公网时间偏差约 ${skew} 秒。当前 UTC: $(date -u '+%Y-%m-%d %H:%M:%S UTC')${PLAIN}"
        else
            echo -e "${GREEN}✔ 系统时间同步状态正常。当前 UTC: $(date -u '+%Y-%m-%d %H:%M:%S UTC')${PLAIN}"
        fi
        return 0
    fi

    if [[ "$PLATFORM_INIT" == "openrc" ]]; then
        echo -e "${YELLOW}[提示] 当前时钟尚未通过安全校验，优先复用 Alpine / OpenRC 现有时间服务。${PLAIN}"

        for chrony_svc in chronyd ntpd openntpd; do
            if [[ -x "/etc/init.d/$chrony_svc" ]] && rc-service "$chrony_svc" status >/dev/null 2>&1; then
                echo -e "${YELLOW}>> 已检测到运行中的 $chrony_svc，等待时钟稳定...${PLAIN}"
                for attempt in {1..10}; do
                    http_time_is_healthy && {
                        echo -e "${GREEN}✔ $chrony_svc 已使系统时钟进入安全范围。${PLAIN}"
                        return 0
                    }
                    sleep 1
                done
            fi
        done

        # Alpine 基础系统自带 BusyBox ntpd/OpenRC 脚本，优先使用它，避免额外引入 chrony。
        if [[ -x /etc/init.d/ntpd ]] && command -v ntpd >/dev/null 2>&1; then
            echo -e "${YELLOW}>> 尝试启用 Alpine BusyBox ntpd...${PLAIN}"
            rc-update add ntpd default >/dev/null 2>&1 || true
            if rc-service ntpd start >/dev/null 2>&1 || rc-service ntpd status >/dev/null 2>&1; then
                for attempt in {1..15}; do
                    http_time_is_healthy && {
                        echo -e "${GREEN}✔ BusyBox ntpd 已启动，系统时钟正常。${PLAIN}"
                        return 0
                    }
                    sleep 1
                done
            fi
        fi

        echo -e "${YELLOW}[提示] BusyBox ntpd 未能确认时钟，回退到 chrony。${PLAIN}"
        if ! command -v chronyc >/dev/null 2>&1; then
            pkg_install chrony || {
                echo -e "${RED}[错误] chrony 安装失败。${PLAIN}"
                return 1
            }
        fi

        chrony_svc="chronyd"
        rc-update add "$chrony_svc" default >/dev/null 2>&1 || true
        if ! rc-service "$chrony_svc" start >/dev/null 2>&1 && ! rc-service "$chrony_svc" status >/dev/null 2>&1; then
            echo -e "${RED}[错误] chronyd 无法启动，且当前系统时钟仍未通过安全校验。${PLAIN}"
            echo -e "${YELLOW}OpenRC 状态：${PLAIN}"
            rc-service -d "$chrony_svc" start 2>&1 || true
            echo -e "${YELLOW}当前时间偏差：${PLAIN}"
            skew=$(http_time_skew_seconds 2>/dev/null || true)
            [[ "$skew" =~ ^[0-9]+$ ]] && echo "${skew} 秒" || echo "无法取得公网 Date"
            return 1
        fi

        chronyc -a burst 4/4 >/dev/null 2>&1 || true
        chronyc -a makestep >/dev/null 2>&1 || true
        for attempt in {1..15}; do
            time_sync_is_healthy && {
                echo -e "${GREEN}✔ chronyd 已启动，系统时间同步完成。${PLAIN}"
                return 0
            }
            sleep 1
        done

        echo -e "${RED}[错误] 时间服务已启动，但 15 秒内仍未确认系统时钟进入安全范围。${PLAIN}"
        chronyc tracking 2>&1 || true
        return 1
    fi

    echo -e "${YELLOW}[提示] 系统时钟尚未同步，准备使用 chrony 自动校时。${PLAIN}"
    if ! command -v chronyc >/dev/null 2>&1; then
        pkg_install chrony || {
            echo -e "${RED}[错误] chrony 安装失败。SS2022 / Reality 对时间偏差敏感，停止部署。${PLAIN}"
            return 1
        }
    fi

    chrony_svc="chrony"
    service_enable_now "$chrony_svc" >/dev/null 2>&1 || {
        echo -e "${RED}[错误] chrony 服务启动失败。${PLAIN}"
        return 1
    }
    service_restart "$chrony_svc" >/dev/null 2>&1 || true
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
    echo -e "$YELLOW>> 更新软件包索引...$PLAIN"
    pkg_update || {
        echo -e "${RED}[错误] 软件包索引更新失败，请检查网络或软件源。$PLAIN"
        return 1
    }
    echo -e "$YELLOW>> 安装运行依赖...$PLAIN"
    if [[ "$PLATFORM_PKG" == "apk" ]]; then
        pkg_install curl jq openssl coreutils ca-certificates iproute2 tar unzip libcap-setcap gcompat || {
            echo -e "${RED}[错误] Alpine 基础依赖安装失败。$PLAIN"
            return 1
        }
        if ! command -v qrencode >/dev/null 2>&1; then
            pkg_install libqrencode-tools >/dev/null 2>&1 ||                 echo -e "${YELLOW}[提示] libqrencode-tools 未安装；二维码将暂不显示，不影响节点使用。$PLAIN"
        fi
    else
        pkg_install curl jq openssl coreutils qrencode ca-certificates iproute2 tar unzip || {
            echo -e "${RED}[错误] 依赖安装失败。$PLAIN"
            return 1
        }
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
    local -a hosts=(github.com cloudflare.com)
    if platform_is_alpine; then
        hosts+=(dl-cdn.alpinelinux.org)
    else
        hosts+=(deb.debian.org)
    fi
    for host in "${hosts[@]}"; do
        if command -v getent >/dev/null 2>&1 && getent ahostsv6 "$host" 2>/dev/null | grep -q ':'; then
            return 0
        fi
        if command -v ping >/dev/null 2>&1 && ping -6 -c 1 -W 2 "$host" >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}
prepare_ipv6_env() {
    local require_time_sync="$1"
    [[ -n "$require_time_sync" ]] || require_time_sync="yes"
    echo -e "$YELLOW>> 初始化 IPv6-only 部署环境...$PLAIN"
    if ! ip -6 addr show scope global 2>/dev/null | grep -q 'inet6 '; then
        echo -e "${RED}[错误] 未检测到全局 IPv6 地址，无法使用 IPv6-only 模式。$PLAIN"
        return 1
    fi
    # Do not rewrite /etc/hosts here. It may contain user-managed GitHub/proxy entries.
    # vps-bootstrap only mutates system files when it owns a clearly marked entry.
    if dns_ipv6_resolution_works; then
        echo -e "$GREEN✔ 当前 DNS 可正常解析 IPv6 地址，不修改 /etc/resolv.conf。$PLAIN"
    else
        echo -e "${YELLOW}[提示] 当前 DNS 无法完成 IPv6 解析，准备使用公共 IPv6 DNS 兜底。$PLAIN"
        if [[ -f /etc/resolv.conf && ! -L /etc/resolv.conf ]]; then
            if [[ ! -f "$BACKUP_DNS" ]]; then
                cp -a /etc/resolv.conf "$BACKUP_DNS" || return 1
            fi
            cat > /etc/resolv.conf <<'DNS'
nameserver 2001:4860:4860::8888
nameserver 2606:4700:4700::1111
options timeout:2 attempts:2
DNS
            touch "$DNS_MARKER"
            if ! dns_ipv6_resolution_works; then
                [[ -f "$BACKUP_DNS" ]] && cp -f "$BACKUP_DNS" /etc/resolv.conf 2>/dev/null || true
                rm -f "$DNS_MARKER"
                echo -e "${RED}[错误] 公共 IPv6 DNS 仍无法解析，已尝试恢复原 DNS。$PLAIN"
                return 1
            fi
        else
            echo -e "${RED}[错误] DNS 解析失败，且 /etc/resolv.conf 由系统服务管理。$PLAIN"
            return 1
        fi
    fi

    if [[ "$PLATFORM_PKG" == "apt" ]]; then
        mkdir -p /etc/apt/apt.conf.d/
        printf '%s\n' 'Acquire::ForceIPv6 "true";' > "$FORCE_IPV6_CONF" || return 1
        # Keep the administrator's configured Debian/Ubuntu mirrors unchanged.
        # Force APT to use IPv6, but never rewrite /etc/apt/mirrors/*.
    fi

    install_dependencies || return 1
    if [[ "$require_time_sync" == "yes" ]]; then
        ensure_time_sync || return 1
    fi
    return 0
}
setup_keepalive() {
    if [[ "$PLATFORM_INIT" == "systemd" ]]; then
        echo -e "$YELLOW>> 部署 IPv6 HTTPS 链路保活定时器...$PLAIN"
        cleanup_legacy_ipv6_keepalive_if_managed
        cat > "$IPV6_KEEPALIVE_SYSTEMD_SERVICE" <<'KSERVICE'
[Unit]
Description=vps-bootstrap IPv6 HTTPS Keepalive Probe
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/bin/curl -6fsSI --max-time 5 https://www.cloudflare.com
StandardOutput=null
StandardError=null
KSERVICE
        cat > "$IPV6_KEEPALIVE_SYSTEMD_TIMER" <<'KTIMER'
[Unit]
Description=Run vps-bootstrap IPv6 Keepalive Every 5 Minutes
[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
Unit=ss2022-ipv6-keepalive.service
[Install]
WantedBy=timers.target
KTIMER
        service_daemon_reload || return 1
        systemctl enable --now "${IPV6_KEEPALIVE_SYSTEMD_SERVICE_NAME}.timer" >/dev/null 2>&1 || return 1
        echo -e "$GREEN✔ IPv6 Keepalive 定时器已激活。$PLAIN"
        return 0
    fi

    echo -e "$YELLOW>> 部署 OpenRC IPv6 HTTPS 链路保活服务...$PLAIN"
    mkdir -p /usr/local/lib/ss2022 || return 1
    cat > "$IPV6_KEEPALIVE_HELPER" <<'KHELPER'
#!/bin/sh
while :; do
    /usr/bin/curl -6fsSI --max-time 5 https://www.cloudflare.com >/dev/null 2>&1 || true
    sleep 300
done
KHELPER
    chmod 755 "$IPV6_KEEPALIVE_HELPER"
    cat > "$IPV6_KEEPALIVE_OPENRC_SERVICE" <<'KOPENRC'
#!/sbin/openrc-run
description="vps-bootstrap IPv6 HTTPS Keepalive"
command="/usr/local/lib/ss2022/ipv6-keepalive.sh"
supervisor="supervise-daemon"
respawn_delay=5
respawn_max=0
depend() {
    need net
}
KOPENRC
    chmod 755 "$IPV6_KEEPALIVE_OPENRC_SERVICE"
    service_enable_now ss2022-ipv6-keepalive || return 1
    echo -e "$GREEN✔ OpenRC IPv6 Keepalive 已激活。$PLAIN"
    return 0
}
disable_keepalive_for_ipv4() {
    if ip -6 addr show scope global 2>/dev/null | grep -q 'inet6 '; then
        return 0
    fi
    if [[ "$PLATFORM_INIT" == "systemd" ]]; then
        if systemctl is-enabled --quiet "${IPV6_KEEPALIVE_SYSTEMD_SERVICE_NAME}.timer" 2>/dev/null ||
           systemctl is-active --quiet "${IPV6_KEEPALIVE_SYSTEMD_SERVICE_NAME}.timer" 2>/dev/null; then
            systemctl disable --now "${IPV6_KEEPALIVE_SYSTEMD_SERVICE_NAME}.timer" >/dev/null 2>&1 || true
        fi
        cleanup_legacy_ipv6_keepalive_if_managed
    else
        service_disable_now ss2022-ipv6-keepalive
    fi
}
prepare_dualstack_env() {
    local require_time_sync="${1:-yes}" ip4="" ip6="" bindv6only=""

    echo -e "${YELLOW}>> 初始化 IPv4 + IPv6 双栈入站环境...${PLAIN}"
    restore_ipv4_apt_and_dns_if_needed
    install_dependencies || return 1

    ip4=$(get_public_ipv4 2>/dev/null || true)
    ip6=$(get_public_ipv6 2>/dev/null || true)
    if [[ -z "$ip4" ]]; then
        echo -e "${RED}[错误] 双栈模式未检测到可用公网 IPv4。${PLAIN}"
        return 1
    fi
    if [[ -z "$ip6" ]]; then
        echo -e "${RED}[错误] 双栈模式未检测到可用公网 IPv6。${PLAIN}"
        return 1
    fi

    bindv6only=$(cat /proc/sys/net/ipv6/bindv6only 2>/dev/null || echo "unknown")
    if [[ "$bindv6only" != "0" ]]; then
        echo -e "${RED}[错误] 当前 net.ipv6.bindv6only=${bindv6only}，无法用单个 :: 监听同时承载 IPv4 和 IPv6。${PLAIN}"
        echo -e "${YELLOW}为避免修改系统级 IPv6 socket 行为，脚本不会自动改这个内核参数。${PLAIN}"
        return 1
    fi

    if [[ "$require_time_sync" == "yes" ]]; then
        ensure_time_sync || return 1
    fi

    SERVER_HOST_V4="$ip4"
    SERVER_HOST_V6="$ip6"
    echo -e "${GREEN}✔ 双栈入站环境可用：IPv4=${ip4} / IPv6=${ip6}${PLAIN}"
    return 0
}

select_network_mode() {
    local require_time_sync="${1:-yes}"
    local allow_dual="${2:-no}"
    local max_choice="2"

    [[ "$allow_dual" == "yes" ]] && max_choice="3"

    while true; do
        echo ""
        echo "请选择 VPS 入站网络模式："
        echo "  1) IPv4（监听 0.0.0.0）"
        echo "  2) IPv6-only（监听 ::，启用 IPv6 Keepalive）"
        if [[ "$allow_dual" == "yes" ]]; then
            echo "  3) IPv4 + IPv6 双栈（监听 ::，同时输出 IPv4 / IPv6 节点）"
        fi
        echo "  0) 取消"
        read -rp "请选择 [0-${max_choice}]: " n
        case "$n" in
            1)
                NETWORK_MODE="ipv4"
                LISTEN_ADDR="0.0.0.0"
                SERVER_HOST_V4=""
                SERVER_HOST_V6=""
                prepare_ipv4_env "$require_time_sync" || return 1
                disable_keepalive_for_ipv4
                return 0
                ;;
            2)
                NETWORK_MODE="ipv6"
                LISTEN_ADDR="::"
                SERVER_HOST_V4=""
                SERVER_HOST_V6=""
                prepare_ipv6_env "$require_time_sync" || return 1
                setup_keepalive || return 1
                return 0
                ;;
            3)
                if [[ "$allow_dual" != "yes" ]]; then
                    echo -e "${RED}当前协议暂未开放双栈入站。${PLAIN}"
                    continue
                fi
                NETWORK_MODE="dual"
                LISTEN_ADDR="::"
                prepare_dualstack_env "$require_time_sync" || return 1
                return 0
                ;;
            0) return 1 ;;
            *) echo -e "${RED}输入无效。${PLAIN}" ;;
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
    if ! jq --arg mode "$mode" --argjson obj "$object_json" '.[$mode] = ((.[$mode] // {}) + $obj)' "$STATE_FILE" > "$tmp"; then
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
default_node_name() {
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
    case "$name" in
        *$'\n'*|*$'\r'*|*'='*|*','*|*'"'*|*'\'*)
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
        ss) json_has_inbound_tag "$TAG_SS" ;;
        shadowtls) json_has_inbound_tag "$TAG_STLS" ;;
        vless) xray_vless_exists ;;
        snell) protocol_exists_snell ;;
        *) return 1 ;;
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
        read -rp "请选择 [0-6]: " c
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
singbox_is_project_managed() {
    [[ -f "$SINGBOX_MANAGED_MARKER" ]] && return 0
    # Legacy vps-bootstrap installations always created the service-user marker.
    [[ -f "$SINGBOX_USER_MARKER" ]] && return 0
    [[ -f "$SINGBOX_ALPINE_PKG_MARKER" ]] && return 0
    [[ -d "$SINGBOX_ALPINE_RUNTIME_DIR" ]] && return 0

    if [[ -f "$STATE_FILE" && -f "$SINGBOX_CONF" ]] && command -v jq >/dev/null 2>&1; then
        jq -e '
          any(.inbounds[]?;
            ((.tag // "") == "ss-in") or
            ((.tag // "") == "ss-shadowtls-in") or
            ((.tag // "") == "ss-shadowtls-backend") or
            ((.tag // "") == "ss-shadowtls-udp"))
        ' "$SINGBOX_CONF" >/dev/null 2>&1 && return 0
    fi
    return 1
}

singbox_assert_safe_ownership() {
    if singbox_is_project_managed; then
        touch "$SINGBOX_MANAGED_MARKER" || return 1
        chmod 600 "$SINGBOX_MANAGED_MARKER"
        return 0
    fi

    if [[ -e "$SINGBOX_BIN" || -e "$SINGBOX_CONF" || -e "$SINGBOX_SERVICE" || -e "$SINGBOX_OPENRC_SERVICE" ]]; then
        echo -e "${RED}[错误] 检测到服务器已有非 vps-bootstrap 管理的 sing-box。${PLAIN}"
        echo -e "${YELLOW}为避免覆盖现有二进制、配置或服务，本脚本停止安装 sing-box。${PLAIN}"
        echo -e "${YELLOW}请先自行迁移/移除现有 sing-box，或继续使用原服务。${PLAIN}"
        return 1
    fi
    return 0
}

mark_singbox_project_managed() {
    touch "$SINGBOX_MANAGED_MARKER" || return 1
    chmod 600 "$SINGBOX_MANAGED_MARKER"
}

ensure_project_config_dir() {
    local dir="$1" group="$2" marker="$3"
    if [[ -e "$dir" && ! -d "$dir" ]]; then
        echo -e "${RED}[错误] ${dir} 已存在但不是目录，停止操作。${PLAIN}"
        return 1
    fi
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" || return 1
        chown root:"$group" "$dir" || return 1
        chmod 750 "$dir" || return 1
        touch "$marker" || return 1
        chmod 600 "$marker"
    elif [[ -f "$marker" ]]; then
        chown root:"$group" "$dir" || return 1
        chmod 750 "$dir" || return 1
    fi
    return 0
}

ensure_singbox_user() {
    ensure_managed_system_user "$SINGBOX_USER" "$SINGBOX_GROUP" "$SINGBOX_USER_MARKER" "$SINGBOX_GROUP_MARKER"
}
ensure_singbox_config_dir() {
    ensure_project_config_dir "$SINGBOX_CONF_DIR" "$SINGBOX_GROUP" "$SINGBOX_DIR_MARKER"
}
write_singbox_service() {
    ensure_singbox_user || return 1
    if [[ "$PLATFORM_INIT" == "systemd" ]]; then
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
        service_daemon_reload || return 1
        service_enable sing-box || return 1
        return 0
    fi

    mkdir -p /var/log/ss2022 || return 1
    touch "$SINGBOX_OPENRC_LOG" || return 1
    chown "$SINGBOX_USER:$SINGBOX_GROUP" "$SINGBOX_OPENRC_LOG" || return 1
    chmod 640 "$SINGBOX_OPENRC_LOG"
    cat > "$SINGBOX_OPENRC_SERVICE" <<'SERVICE'
#!/sbin/openrc-run
description="sing-box service"
command="/usr/local/bin/sing-box"
command_args="run -c /etc/sing-box/config.json"
command_user="sing-box:sing-box"
supervisor="supervise-daemon"
pidfile="/run/sing-box.pid"
output_log="/var/log/ss2022/sing-box.log"
error_log="/var/log/ss2022/sing-box.log"
respawn_delay=10
respawn_max=0
umask=0077
depend() {
    need net
    use dns
}
SERVICE
    chmod 755 "$SINGBOX_OPENRC_SERVICE"
    if ! service_enable sing-box; then
        echo -e "${RED}[错误] OpenRC 无法把 sing-box 加入 default runlevel。${PLAIN}"
        rc-update show 2>&1 | grep -E 'sing-box|default' || true
        return 1
    fi
    return 0
}
install_singbox_core() {
    local arch s_arch="" expected_sha256="" tar_file="" target_url="" curl_family=""
    local success=0 download_url="" actual_sha256="" runtime_tmp=""

    singbox_assert_safe_ownership || return 1

    arch=$(uname -m)
    [[ "$NETWORK_MODE" == "ipv6" ]] && curl_family="-6" || curl_family="-4"

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

    if [[ -x "$SINGBOX_BIN" ]]; then
        local current=""
        current=$("$SINGBOX_BIN" version 2>/dev/null | head -n 1 | awk '{print $3}')
        echo -e "${YELLOW}>> 已检测到 sing-box ${current:-未知版本}；重新安装固定版本 ${SINGBOX_VERSION} 并校验 SHA256。${PLAIN}"
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
    rm -rf /tmp/ss2022-sb-temp "/tmp/ss2022-${tar_file}"
    for download_url in "${download_sources[@]}"; do
        echo -e "   尝试下载: ${CYAN}${download_url}${PLAIN}"
        rm -f "/tmp/ss2022-${tar_file}"
        if ! curl -fL "$curl_family" --retry 2 --retry-delay 1 --connect-timeout 8 --max-time 90             "$download_url" -o "/tmp/ss2022-${tar_file}"; then
            echo -e "${YELLOW}   下载失败，尝试下一个源。${PLAIN}"
            continue
        fi
        actual_sha256=$(sha256sum "/tmp/ss2022-${tar_file}" | awk '{print $1}')
        if [[ "$actual_sha256" != "$expected_sha256" ]]; then
            echo -e "${RED}   SHA256 校验失败，拒绝安装该文件！${PLAIN}"
            echo -e "${YELLOW}   期望: ${expected_sha256}${PLAIN}"
            echo -e "${YELLOW}   实际: ${actual_sha256}${PLAIN}"
            rm -f "/tmp/ss2022-${tar_file}"
            continue
        fi
        if ! tar -tzf "/tmp/ss2022-${tar_file}" >/dev/null 2>&1; then
            echo -e "${RED}   压缩包结构校验失败。${PLAIN}"
            rm -f "/tmp/ss2022-${tar_file}"
            continue
        fi
        success=1
        break
    done

    if [[ $success -ne 1 ]]; then
        echo -e "${RED}[错误] 所有下载源均失败或未通过 SHA256 校验。${PLAIN}"
        return 1
    fi

    mkdir -p /tmp/ss2022-sb-temp
    tar -xzf "/tmp/ss2022-${tar_file}" -C /tmp/ss2022-sb-temp --strip-components=1 || return 1
    if [[ ! -f /tmp/ss2022-sb-temp/sing-box ]]; then
        echo -e "${RED}[错误] 压缩包中未找到 sing-box 二进制。${PLAIN}"
        rm -rf /tmp/ss2022-sb-temp "/tmp/ss2022-${tar_file}"
        return 1
    fi

    if platform_is_alpine; then
        # sing-box 1.13 的官方普通 Linux amd64/arm64 release 为 purego 运行时，
        # 归档内同时携带 libcronet.so。Alpine 需要 gcompat，并必须保留完整运行时布局。
        if ! apk info -e gcompat >/dev/null 2>&1; then
            echo -e "${YELLOW}>> 安装 Alpine glibc 兼容层 gcompat...${PLAIN}"
            pkg_install gcompat || {
                echo -e "${RED}[错误] gcompat 安装失败。${PLAIN}"
                return 1
            }
        fi

        if [[ ! -f /tmp/ss2022-sb-temp/libcronet.so ]]; then
            echo -e "${RED}[错误] 官方 release 归档缺少 libcronet.so，拒绝安装不完整运行时。${PLAIN}"
            ls -la /tmp/ss2022-sb-temp 2>/dev/null || true
            return 1
        fi

        # dev5 可能留下包管理标记；只有确实由本脚本安装成功时才清理。
        if [[ -f "$SINGBOX_ALPINE_PKG_MARKER" ]]; then
            apk del sing-box >/dev/null 2>&1 || true
            rm -f "$SINGBOX_ALPINE_PKG_MARKER"
        fi

        runtime_tmp="${SINGBOX_ALPINE_RUNTIME_DIR}.new"
        rm -rf "$runtime_tmp"
        mkdir -p "$runtime_tmp" || return 1
        install -m 755 /tmp/ss2022-sb-temp/sing-box "$runtime_tmp/sing-box" || return 1
        install -m 755 /tmp/ss2022-sb-temp/libcronet.so "$runtime_tmp/libcronet.so" || return 1

        echo -e "${YELLOW}>> 验证 Alpine sing-box 完整运行时...${PLAIN}"
        if ! LD_LIBRARY_PATH="$runtime_tmp" "$runtime_tmp/sing-box" version >/dev/null 2>&1; then
            echo -e "${RED}[错误] gcompat + 官方完整 release 运行时仍无法执行。${PLAIN}"
            echo -e "${YELLOW}ldd 诊断：${PLAIN}"
            LD_LIBRARY_PATH="$runtime_tmp" ldd "$runtime_tmp/sing-box" 2>&1 || true
            echo -e "${YELLOW}gcompat 状态：${PLAIN}"
            apk info gcompat 2>&1 | head -n 20 || true
            rm -rf "$runtime_tmp"
            return 1
        fi

        rm -rf "$SINGBOX_ALPINE_RUNTIME_DIR"
        mv "$runtime_tmp" "$SINGBOX_ALPINE_RUNTIME_DIR" || return 1

        if ! command -v setcap >/dev/null 2>&1; then
            echo -e "${RED}[错误] Alpine 未找到 setcap；libcap-setcap 未正确安装。${PLAIN}"
            return 1
        fi
        setcap cap_net_bind_service=+ep "$SINGBOX_ALPINE_RUNTIME_BIN" || {
            echo -e "${RED}[错误] 无法为真实 sing-box 二进制设置低端口能力。${PLAIN}"
            return 1
        }

        if ! LD_LIBRARY_PATH="$SINGBOX_ALPINE_RUNTIME_DIR" "$SINGBOX_ALPINE_RUNTIME_BIN" version >/dev/null 2>&1; then
            echo -e "${RED}[错误] 设置 capability 后 sing-box 无法执行。${PLAIN}"
            getcap "$SINGBOX_ALPINE_RUNTIME_BIN" 2>/dev/null || true
            LD_LIBRARY_PATH="$SINGBOX_ALPINE_RUNTIME_DIR" ldd "$SINGBOX_ALPINE_RUNTIME_BIN" 2>&1 || true
            return 1
        fi

        cat > "$SINGBOX_BIN" <<'WRAPPER'
#!/bin/sh
RUNTIME_DIR="/usr/local/lib/ss2022/sing-box-runtime"
export LD_LIBRARY_PATH="$RUNTIME_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$RUNTIME_DIR/sing-box" "$@"
WRAPPER
        chmod 755 "$SINGBOX_BIN"

        if ! "$SINGBOX_BIN" version >/dev/null 2>&1; then
            echo -e "${RED}[错误] Alpine sing-box 包装入口验证失败。${PLAIN}"
            return 1
        fi

        rm -rf /tmp/ss2022-sb-temp "/tmp/ss2022-${tar_file}"
        write_singbox_service || return 1
        mark_singbox_project_managed || return 1
        echo -e "${GREEN}✔ sing-box ${SINGBOX_VERSION}（Alpine + gcompat）核心与 OpenRC 服务已就绪。${PLAIN}"
        return 0
    fi

    # Debian / Ubuntu 保持 v1.8.1 原有安装路径。
    install -m 755 /tmp/ss2022-sb-temp/sing-box "$SINGBOX_BIN" || return 1
    rm -rf /tmp/ss2022-sb-temp "/tmp/ss2022-${tar_file}"
    "$SINGBOX_BIN" version >/dev/null 2>&1 || {
        echo -e "${RED}[错误] sing-box 安装后无法执行。${PLAIN}"
        return 1
    }

    write_singbox_service || return 1
    mark_singbox_project_managed || return 1
    echo -e "${GREEN}✔ sing-box ${SINGBOX_VERSION} 核心与服务管理已就绪。${PLAIN}"
    return 0
}
ensure_base_singbox_config() {
    ensure_singbox_user || return 1
    ensure_singbox_config_dir || return 1

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

migrate_singbox_local_dns_prefer_go() {
    local candidate="" backup="" was_active=0

    singbox_is_project_managed || return 0
    [[ -f "$SINGBOX_CONF" && -x "$SINGBOX_BIN" ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    # 仅处理本项目使用的 type=local + tag=local-dns。
    jq -e '
      any(.dns.servers[]?;
        (type == "object") and
        ((.type // "") == "local") and
        ((.tag // "") == "local-dns"))
    ' "$SINGBOX_CONF" >/dev/null 2>&1 || return 0

    # 已经是 prefer_go:true 时不重复修改。
    jq -e '
      any(.dns.servers[]?;
        (type == "object") and
        ((.type // "") == "local") and
        ((.tag // "") == "local-dns") and
        ((.prefer_go // false) != true))
    ' "$SINGBOX_CONF" >/dev/null 2>&1 || return 0

    candidate=$(mktemp "/etc/sing-box/.ss2022-dns-migrate.XXXXXX.json") || {
        echo -e "${RED}[错误] 无法创建 sing-box DNS 迁移候选配置；原配置保持不变。${PLAIN}"
        return 1
    }

    if ! jq '
      (.dns.servers[]?
        | select(
            (type == "object") and
            ((.type // "") == "local") and
            ((.tag // "") == "local-dns")
          )
        | .prefer_go) = true
    ' "$SINGBOX_CONF" > "$candidate"; then
        rm -f "$candidate"
        echo -e "${RED}[错误] sing-box DNS 迁移候选配置生成失败；原配置保持不变。${PLAIN}"
        return 1
    fi

    chown root:"$SINGBOX_GROUP" "$candidate" 2>/dev/null || true
    chmod 640 "$candidate" || {
        rm -f "$candidate"
        echo -e "${RED}[错误] 无法设置候选配置权限；原配置保持不变。${PLAIN}"
        return 1
    }

    echo -e "${YELLOW}>> 检测到旧版 local-dns 缺少 prefer_go:true，正在校验候选配置...${PLAIN}"
    if ! "$SINGBOX_BIN" check -c "$candidate"; then
        rm -f "$candidate"
        echo -e "${RED}[错误] 候选配置未通过 sing-box check；原配置保持不变。${PLAIN}"
        return 1
    fi

    backup=$(mktemp "/etc/sing-box/.ss2022-dns-rollback.XXXXXX.json") || {
        rm -f "$candidate"
        echo -e "${RED}[错误] 无法创建 DNS 迁移回滚备份；原配置保持不变。${PLAIN}"
        return 1
    }
    if ! cp -a "$SINGBOX_CONF" "$backup"; then
        rm -f "$candidate" "$backup"
        echo -e "${RED}[错误] 无法备份原 sing-box 配置；原配置保持不变。${PLAIN}"
        return 1
    fi

    if service_is_active sing-box; then
        was_active=1
    fi

    if ! mv -f "$candidate" "$SINGBOX_CONF"; then
        rm -f "$candidate" "$backup"
        echo -e "${RED}[错误] DNS 迁移配置替换失败；原配置保持不变。${PLAIN}"
        return 1
    fi
    chown root:"$SINGBOX_GROUP" "$SINGBOX_CONF" 2>/dev/null || true
    chmod 640 "$SINGBOX_CONF"

    # 原服务正在运行时才重启；若用户原本停止服务，升级不会擅自启动。
    if [[ $was_active -eq 1 ]]; then
        if ! service_restart sing-box; then
            echo -e "${RED}[错误] sing-box 使用新 DNS 配置启动失败，正在自动回滚...${PLAIN}"
            if mv -f "$backup" "$SINGBOX_CONF"; then
                chown root:"$SINGBOX_GROUP" "$SINGBOX_CONF" 2>/dev/null || true
                chmod 640 "$SINGBOX_CONF" 2>/dev/null || true
                if service_restart sing-box; then
                    echo -e "${YELLOW}✔ 已恢复原配置并重新启动 sing-box。${PLAIN}"
                else
                    echo -e "${RED}[严重] 原配置已恢复，但 sing-box 仍无法重新启动，请检查日志。${PLAIN}"
                fi
            else
                echo -e "${RED}[严重] 新配置启动失败且旧配置回滚失败，请立即检查 ${SINGBOX_CONF}。${PLAIN}"
            fi
            return 1
        fi
    fi

    rm -f "$backup"
    echo -e "${GREEN}✔ local-dns 已安全迁移为 prefer_go:true。${PLAIN}"
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
        backup=$(mktemp "${conf_dir}/.ss2022-config-rollback.XXXXXX") || {
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
        service_stop sing-box >/dev/null 2>&1 || true
        rm -f "$backup"
        echo -e "${GREEN}✔ sing-box 配置已更新，当前无活动入口，服务已停止。${PLAIN}"
        return 0
    fi

    if ! service_restart sing-box; then
        echo -e "${RED}[错误] sing-box 使用新配置启动失败，正在自动回滚...${PLAIN}"
        if [[ $had_old -eq 1 && -f "$backup" ]]; then
            mv -f "$backup" "$SINGBOX_CONF"
            chown root:"$SINGBOX_GROUP" "$SINGBOX_CONF"
            chmod 640 "$SINGBOX_CONF"
            if service_restart sing-box; then
                echo -e "${YELLOW}✔ 已恢复原配置并重新启动服务。${PLAIN}"
            else
                echo -e "${RED}[严重] 原配置已恢复，但 sing-box 仍无法启动。${PLAIN}"
            fi
        else
            rm -f "$SINGBOX_CONF"
            service_stop sing-box >/dev/null 2>&1 || true
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

    tmp=$(mktemp "/etc/sing-box/.ss2022-config.XXXXXX.json") || return 1
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

    sb_pid=$(service_main_pid sing-box 2>/dev/null || true)
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

    tmp=$(mktemp /tmp/ss2022-keycheck.XXXXXX) || return 1
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

get_public_ipv6() {
    local ip=""
    ip=$(curl -6fsS --connect-timeout 5 --max-time 10 https://api6.ipify.org 2>/dev/null) || true
    [[ -z "$ip" ]] && ip=$(curl -6fsS --connect-timeout 5 --max-time 10 https://6.ident.me 2>/dev/null) || true

    if [[ "$ip" == *:* ]]; then
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

    SERVER_HOST_V4=""
    SERVER_HOST_V6=""

    case "$NETWORK_MODE" in
        ipv6)
            detected=$(get_public_ipv6 2>/dev/null || get_global_ipv6 2>/dev/null || true)
            SERVER_HOST_V6="$detected"
            ;;
        dual)
            SERVER_HOST_V4=$(get_public_ipv4 2>/dev/null || true)
            SERVER_HOST_V6=$(get_public_ipv6 2>/dev/null || get_global_ipv6 2>/dev/null || true)
            detected="$SERVER_HOST_V4"
            echo -e "${GREEN}检测到双栈公网地址：${PLAIN}"
            echo -e "  IPv4: ${CYAN}${SERVER_HOST_V4:-未检测到}${PLAIN}"
            echo -e "  IPv6: ${CYAN}${SERVER_HOST_V6:-未检测到}${PLAIN}"
            ;;
        *)
            detected=$(get_public_ipv4 2>/dev/null || true)
            SERVER_HOST_V4="$detected"
            ;;
    esac

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

# ==============================================================================
# [05] 节点参数与客户端配置输出
# ==============================================================================

show_ss_details_single() {
    local host="$1" port="$2" method="$3" pass="$4"
    local tag="${5:-$(default_node_name ss)}"
    local url_host method_enc pass_enc tag_enc ss_url

    url_host=$(format_host_for_uri "$host")
    method_enc=$(urlencode "$method")
    pass_enc=$(urlencode "$pass")
    tag_enc=$(urlencode "$tag")
    ss_url="ss://${method_enc}:${pass_enc}@${url_host}:${port}#${tag_enc}"

    echo ""
    echo -e "${CYAN}════════════════════ SS2022 节点配置 ════════════════════${PLAIN}"
    echo -e "  节点名称: ${GREEN}${tag}${PLAIN}"
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

show_ss_details() {
    local host="$1" port="$2" method="$3" pass="$4"
    local tag="${5:-$(default_node_name ss)}"
    local host_v4="${6:-}" host_v6="${7:-}"

    if [[ -n "$host_v4" && -n "$host_v6" && "$host_v4" != "$host_v6" ]]; then
        echo ""
        echo -e "${CYAN}检测到双栈入站：以下两个节点连接同一 SS2022 服务，共用端口和密钥。${PLAIN}"
        show_ss_details_single "$host_v4" "$port" "$method" "$pass" "${tag}-IPv4"
        show_ss_details_single "$host_v6" "$port" "$method" "$pass" "${tag}-IPv6"
    else
        show_ss_details_single "$host" "$port" "$method" "$pass" "$tag"
    fi
}

show_shadowtls_details_single() {
    local host="$1" port="$2" method="$3" ss_pass="$4" stls_pass="$5" sni="$6" udp_enabled="$7" udp_port="$8"
    local tag="${9:-$(default_node_name shadowtls)}"
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
    echo -e "  节点名称: ${GREEN}${tag}${PLAIN}"
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
    qr_payload=$(jq -cn --arg type "ss2022-shadowtls" --arg name "$tag" --arg server "$host" --argjson port "$port" --arg cipher "$method" --arg password "$ss_pass" --arg stls_password "$stls_pass" --arg sni "$sni" --arg udp "$udp_enabled" --arg udp_port "$udp_port" '{type:$type,name:$name,server:$server,port:$port,cipher:$cipher,password:$password,shadow_tls:{version:3,password:$stls_password,sni:$sni},udp:($udp=="true"),udp_port:(if $udp_port=="" then null else ($udp_port|tonumber) end)}')
    show_qr "$qr_payload"
    echo -e "${YELLOW}[二维码说明] SS2022+ShadowTLS 尚无统一跨客户端 URI；二维码保存完整参数，客户端仍应使用上面的对应格式。${PLAIN}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${PLAIN}"
}

show_shadowtls_details() {
    local host="$1" port="$2" method="$3" ss_pass="$4" stls_pass="$5" sni="$6" udp_enabled="$7" udp_port="$8"
    local tag="${9:-$(default_node_name shadowtls)}"
    local host_v4="${10:-}" host_v6="${11:-}"

    if [[ -n "$host_v4" && -n "$host_v6" && "$host_v4" != "$host_v6" ]]; then
        echo ""
        echo -e "${CYAN}检测到双栈入站：以下两个节点连接同一 ShadowTLS 服务，共用 TCP/UDP 端口与密钥。${PLAIN}"
        show_shadowtls_details_single "$host_v4" "$port" "$method" "$ss_pass" "$stls_pass" "$sni" "$udp_enabled" "$udp_port" "${tag}-IPv4"
        show_shadowtls_details_single "$host_v6" "$port" "$method" "$ss_pass" "$stls_pass" "$sni" "$udp_enabled" "$udp_port" "${tag}-IPv6"
    else
        show_shadowtls_details_single "$host" "$port" "$method" "$ss_pass" "$stls_pass" "$sni" "$udp_enabled" "$udp_port" "$tag"
    fi
}

show_vless_details() {
    local host="$1" port="$2" uuid="$3" sni="$4" public_key="$5" short_id="$6"
    local tag="${7:-$(default_node_name vless)}"
    local url_host
    local tag_enc vless_uri

    url_host=$(format_host_for_uri "$host")
    tag_enc=$(urlencode "$tag")
    vless_uri="vless://${uuid}@${url_host}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$(urlencode "$sni")&fp=chrome&pbk=$(urlencode "$public_key")&sid=${short_id}&type=tcp#${tag_enc}"

    echo ""
    echo -e "${CYAN}════════════════════ VLESS Reality 配置 ════════════════════${PLAIN}"
    echo -e "  节点名称: ${GREEN}${tag}${PLAIN}"
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
    local tag="${4:-$(default_node_name snell)}"
    local surge_line qr_payload
    surge_line="${tag} = snell, ${host}, ${port}, psk=\"${psk}\", version=5, reuse=true, tfo=true"

    echo ""
    echo -e "${CYAN}════════════════════ Snell v5 配置 ════════════════════${PLAIN}"
    echo -e "  节点名称: ${GREEN}${tag}${PLAIN}"
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
    qr_payload=$(jq -cn --arg type "snell" --arg name "$tag" --arg server "$host" --argjson port "$port" --arg psk "$psk" '{type:$type,name:$name,server:$server,port:$port,psk:$psk,version:5,udp:true}')
    show_qr "$qr_payload"
    echo -e "${YELLOW}[二维码说明] Snell 没有统一的跨客户端分享 URI；二维码保存完整参数。${PLAIN}"
    echo -e "${CYAN}═════════════════════════════════════════════════════════${PLAIN}"
}

select_network_mode_for_update() {
    local current_network="$1"
    local require_time_sync="${2:-yes}"
    local allow_dual="${3:-no}"
    local default_choice="1" n="" max_choice="2"

    [[ "$current_network" == "ipv6" ]] && default_choice="2"
    if [[ "$allow_dual" == "yes" ]]; then
        max_choice="3"
        [[ "$current_network" == "dual" ]] && default_choice="3"
    fi

    while true; do
        echo ""
        echo "请选择 VPS 入站网络模式："
        echo "  1) IPv4（监听 0.0.0.0）"
        echo "  2) IPv6-only（监听 ::，启用 IPv6 Keepalive）"
        if [[ "$allow_dual" == "yes" ]]; then
            echo "  3) IPv4 + IPv6 双栈（监听 ::，同时输出 IPv4 / IPv6 节点）"
        fi
        echo "  0) 取消"
        read -rp "请选择 [0-${max_choice}，默认: ${default_choice}]: " n
        n=${n:-$default_choice}

        case "$n" in
            1)
                NETWORK_MODE="ipv4"
                LISTEN_ADDR="0.0.0.0"
                SERVER_HOST_V4=""
                SERVER_HOST_V6=""
                prepare_ipv4_env "$require_time_sync" || return 1
                disable_keepalive_for_ipv4
                return 0
                ;;
            2)
                NETWORK_MODE="ipv6"
                LISTEN_ADDR="::"
                SERVER_HOST_V4=""
                SERVER_HOST_V6=""
                prepare_ipv6_env "$require_time_sync" || return 1
                setup_keepalive || return 1
                return 0
                ;;
            3)
                [[ "$allow_dual" == "yes" ]] || { echo -e "${RED}当前协议暂未开放双栈入站。${PLAIN}"; continue; }
                NETWORK_MODE="dual"
                LISTEN_ADDR="::"
                prepare_dualstack_env "$require_time_sync" || return 1
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

snell_is_project_managed() {
    [[ -f "$SNELL_MANAGED_MARKER" ]] && return 0
    [[ -f "$SNELL_USER_MARKER" ]] && return 0
    if [[ -f "$STATE_FILE" ]] && command -v jq >/dev/null 2>&1; then
        jq -e '.snell? != null' "$STATE_FILE" >/dev/null 2>&1 && return 0
    fi
    return 1
}

snell_assert_safe_ownership() {
    if snell_is_project_managed; then
        touch "$SNELL_MANAGED_MARKER" || return 1
        chmod 600 "$SNELL_MANAGED_MARKER"
        return 0
    fi

    if [[ -e "$SNELL_BIN" || -e "$SNELL_CONF" || -e "$SNELL_SERVICE" || -e "$SNELL_OPENRC_SERVICE" ]]; then
        echo -e "${RED}[错误] 检测到服务器已有非 vps-bootstrap 管理的 Snell v5。${PLAIN}"
        echo -e "${YELLOW}为避免覆盖现有二进制、配置或服务，本脚本停止安装 Snell。${PLAIN}"
        return 1
    fi
    return 0
}

mark_snell_project_managed() {
    touch "$SNELL_MANAGED_MARKER" || return 1
    chmod 600 "$SNELL_MANAGED_MARKER"
}

protocol_exists_snell() {
    [[ -f "$SNELL_CONF" ]] && snell_is_project_managed
}

# ==============================================================================
# [06] 协议更新与删除
# ==============================================================================

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
                select_network_mode_for_update "$current_network" "yes" "yes" || continue
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
            if [[ "$new_network" == "dual" ]]; then
                SERVER_HOST_V4=$(get_public_ipv4 2>/dev/null || true)
                SERVER_HOST_V6=$(get_public_ipv6 2>/dev/null || get_global_ipv6 2>/dev/null || true)
            else
                SERVER_HOST_V4=""
                SERVER_HOST_V6=""
            fi
            save_mode_state "ss" "$(jq -n --arg host "$current_host" --arg host_v4 "$SERVER_HOST_V4" --arg host_v6 "$SERVER_HOST_V6" --arg network "$new_network" '{host:$host,host_v4:$host_v4,host_v6:$host_v6,network:$network}')" || true
            apply_routing_config >/dev/null 2>&1 || echo -e "${YELLOW}[提示] 节点已更新，但现有分流配置未能自动应用。${PLAIN}"
            echo -e "${GREEN}✔ SS2022 更新成功。${PLAIN}"
        else
            service_log_tail sing-box 30 || true
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
                select_network_mode_for_update "$current_network" "yes" "yes" || continue
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
            if [[ "$new_network" == "dual" ]]; then
                SERVER_HOST_V4=$(get_public_ipv4 2>/dev/null || true)
                SERVER_HOST_V6=$(get_public_ipv6 2>/dev/null || get_global_ipv6 2>/dev/null || true)
            else
                SERVER_HOST_V4=""
                SERVER_HOST_V6=""
            fi
            save_mode_state "shadowtls" "$(jq -n --arg host "$current_host" --arg host_v4 "$SERVER_HOST_V4" --arg host_v6 "$SERVER_HOST_V6" --arg network "$new_network" '{host:$host,host_v4:$host_v4,host_v6:$host_v6,network:$network}')" || true
            apply_routing_config >/dev/null 2>&1 || echo -e "${YELLOW}[提示] 节点已更新，但现有分流配置未能自动应用。${PLAIN}"
            echo -e "${GREEN}✔ SS2022 + ShadowTLS v3 更新成功。${PLAIN}"
        else
            service_log_tail sing-box 30 || true
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
            echo -e "${YELLOW}[旧 sing-box VLESS] 当前版本不做隐式跨核心迁移。请先删除旧 VLESS，再部署 Xray 版。${PLAIN}"
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
        else service_log_tail "$XRAY_SERVICE_NAME" 30 || true; fi
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
        ensure_snell_config_dir || { pause; continue; }
        write_snell_service || { pause; continue; }
        tmp=$(mktemp "${SNELL_CONF_DIR}/.ss2022-config.XXXXXX") || continue
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
            service_log_tail snell-v5 30 || true
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
        if [[ $has_xray -eq 1 ]]; then service_disable_now "$XRAY_SERVICE_NAME"; rm -f "$XRAY_CONF"; fi
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
        service_disable_now snell-v5
        rm -f "$SNELL_CONF" "$SNELL_SERVICE" "$SNELL_OPENRC_SERVICE" "$SNELL_OPENRC_PID" "$SNELL_OPENRC_LOG"
        remove_mode_state "snell" || true
        service_daemon_reload || true
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

# ==============================================================================
# [07] 协议部署、Xray 与 Snell 基础设施
# ==============================================================================

deploy_ss2022() {
    local excluded_tags='["ss-in"]'
    local inbound add_json

    if json_has_inbound_tag "$TAG_SS"; then
        echo -e "${YELLOW}SS2022 已存在。请返回并选择“更新”或“删除”。${PLAIN}"
        pause
        return
    fi

    echo -e "${CYAN}>> [1/3] 初始化系统与网络环境...${PLAIN}"
    if ! select_network_mode "yes" "yes"; then
        echo ""
        echo -e "${RED}[部署中止] SS2022 尚未进入端口配置阶段：系统/网络环境初始化失败或被取消。${PLAIN}"
        echo -e "${YELLOW}上方最后一条错误就是本次中止原因；当前不会写入 SS2022 节点配置。${PLAIN}"
        pause
        return
    fi

    echo -e "${CYAN}>> [2/3] 安装 / 校验 sing-box 核心与服务...${PLAIN}"
    if ! install_singbox_core; then
        echo ""
        echo -e "${RED}[部署中止] sing-box 核心或服务初始化失败，因此没有进入端口配置阶段。${PLAIN}"
        if platform_is_alpine; then
            echo -e "${YELLOW}Alpine / OpenRC 快速状态：${PLAIN}"
            [[ -x "$SINGBOX_BIN" ]] && "$SINGBOX_BIN" version 2>&1 | head -n 2 || true
            [[ -f "$SINGBOX_OPENRC_SERVICE" ]] && rc-service sing-box status 2>&1 || true
        fi
        pause
        return
    fi

    echo -e "${CYAN}>> [3/3] 配置 SS2022 监听端口与节点参数...${PLAIN}"
    ask_singbox_port "请输入 SS2022 监听端口" "58588" "$excluded_tags" || return
    get_ss_cipher_and_key || { pause; return; }
    ask_server_host
    ask_node_name "ss" || return

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
        save_mode_state "ss" "$(jq -n --arg host "$SERVER_HOST" --arg host_v4 "$SERVER_HOST_V4" --arg host_v6 "$SERVER_HOST_V6" --arg network "$NETWORK_MODE" --arg name "$NODE_NAME" '{host:$host,host_v4:$host_v4,host_v6:$host_v6,network:$network,name:$name}')" || true
        show_ss_details "$SERVER_HOST" "$PORT" "$METHOD" "$SS_KEY" "$NODE_NAME" "$SERVER_HOST_V4" "$SERVER_HOST_V6"
    else
        service_log_tail sing-box 30 || true
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

    echo -e "${CYAN}>> [1/3] 初始化系统与网络环境...${PLAIN}"
    if ! select_network_mode "yes" "yes"; then
        echo ""
        echo -e "${RED}[部署中止] ShadowTLS 尚未进入端口配置阶段：系统/网络环境初始化失败或被取消。${PLAIN}"
        pause
        return
    fi

    echo -e "${CYAN}>> [2/3] 安装 / 校验 sing-box 核心与服务...${PLAIN}"
    if ! install_singbox_core; then
        echo ""
        echo -e "${RED}[部署中止] sing-box 核心或 OpenRC 服务初始化失败，因此没有进入端口配置阶段。${PLAIN}"
        if platform_is_alpine; then
            [[ -x "$SINGBOX_BIN" ]] && "$SINGBOX_BIN" version 2>&1 | head -n 2 || true
            [[ -f "$SINGBOX_OPENRC_SERVICE" ]] && rc-service sing-box status 2>&1 || true
        fi
        pause
        return
    fi

    echo -e "${CYAN}>> [3/3] 配置 ShadowTLS 端口与节点参数...${PLAIN}"
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
            sb_pid=$(service_main_pid sing-box 2>/dev/null || true)
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
    ask_node_name "shadowtls" || return

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
        save_mode_state "shadowtls" "$(jq -n --arg host "$SERVER_HOST" --arg host_v4 "$SERVER_HOST_V4" --arg host_v6 "$SERVER_HOST_V6" --arg network "$NETWORK_MODE" --arg name "$NODE_NAME" '{host:$host,host_v4:$host_v4,host_v6:$host_v6,network:$network,name:$name}')" || true
        show_shadowtls_details "$SERVER_HOST" "$tcp_port" "$METHOD" "$SS_KEY" "$stls_pass" "$sni" "$udp_enabled" "$udp_port" "$NODE_NAME" "$SERVER_HOST_V4" "$SERVER_HOST_V6"
    else
        service_log_tail sing-box 30 || true
    fi
    pause
}

deploy_vless_reality() {
    local vless_port uuid sni short_id reality_sni_choice
    local REALITY_PRIVATE_KEY="" REALITY_PUBLIC_KEY=""
    if xray_vless_exists; then
        echo -e "${YELLOW}VLESS Reality (Xray) 已存在。请返回并选择“更新”或“删除”。${PLAIN}"; pause; return
    fi
    if json_has_inbound_tag "$TAG_VLESS"; then
        echo -e "${YELLOW}[检测到旧配置] 当前 VLESS Reality 仍由 sing-box 承载。${PLAIN}"
        echo -e "${YELLOW}当前版本的 VLESS Reality 使用独立 ss2022-xray 服务。为避免与旧 sing-box VLESS 端口冲突，请先删除旧 VLESS，再重新部署。${PLAIN}"
        pause; return
    fi
    select_network_mode || return
    if [[ -x /usr/local/bin/xray ]] || { [[ "$PLATFORM_INIT" == "systemd" ]] && systemctl cat xray.service >/dev/null 2>&1; } || [[ -x /etc/init.d/xray ]] || [[ -f /usr/local/etc/xray/config.json ]]; then
        echo -e "${YELLOW}[提示] 检测到服务器已有 Xray。本脚本使用独立 ss2022-xray 服务、二进制和配置，不会覆盖或重启现有 xray.service。${PLAIN}"
    fi
    # 如果之前已经添加了 Xray 不原生支持的标准 SS 落地节点，VLESS 部署前补齐 sing-box Bridge 依赖。
    if routing_has_bridge_nodes; then
        ensure_existing_bridges_for_vless || { pause; return; }
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
    ask_node_name "vless" || return
    if write_xray_vless_config "$LISTEN_ADDR" "$vless_port" "$uuid" "$sni" "$REALITY_PRIVATE_KEY" "$short_id"; then
        save_mode_state "vless" "$(jq -n --arg host "$SERVER_HOST" --arg network "$NETWORK_MODE" --arg public_key "$REALITY_PUBLIC_KEY" --arg name "$NODE_NAME" '{host:$host,network:$network,public_key:$public_key,core:"xray",name:$name}')" || true
        apply_routing_config >/dev/null 2>&1 || echo -e "${YELLOW}[提示] VLESS 已部署，但现有分流配置未能自动应用。${PLAIN}"
        echo -e "${GREEN}✔ VLESS Reality (Xray) 部署成功。${PLAIN}"
        show_vless_details "$SERVER_HOST" "$vless_port" "$uuid" "$sni" "$REALITY_PUBLIC_KEY" "$short_id" "$NODE_NAME"
    else
        service_log_tail "$XRAY_SERVICE_NAME" 30 || true
    fi
    pause
}

ensure_xray_user() {
    ensure_managed_system_user "$XRAY_USER" "$XRAY_GROUP" "$XRAY_USER_MARKER" "$XRAY_GROUP_MARKER"
}
write_xray_service() {
    ensure_xray_user || return 1
    if [[ "$PLATFORM_INIT" == "systemd" ]]; then
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
        service_daemon_reload || return 1
        service_enable "$XRAY_SERVICE_NAME" || return 1
        return 0
    fi

    mkdir -p /var/log/ss2022 || return 1
    touch "$XRAY_OPENRC_LOG" || return 1
    chown "$XRAY_USER:$XRAY_GROUP" "$XRAY_OPENRC_LOG" || return 1
    chmod 640 "$XRAY_OPENRC_LOG"
    cat > "$XRAY_OPENRC_SERVICE" <<SERVICE
#!/sbin/openrc-run
description="vps-bootstrap Xray VLESS Reality"
command="$XRAY_BIN"
command_args="run -format json -config $XRAY_CONF"
command_user="$XRAY_USER:$XRAY_GROUP"
supervisor="supervise-daemon"
pidfile="$XRAY_OPENRC_PID"
output_log="$XRAY_OPENRC_LOG"
error_log="$XRAY_OPENRC_LOG"
respawn_delay=10
respawn_max=0
umask=0077

depend() {
    need net
    use dns
}
SERVICE
    chmod 755 "$XRAY_OPENRC_SERVICE"
    service_enable "$XRAY_SERVICE_NAME" || {
        echo -e "${RED}[错误] OpenRC 无法注册 $XRAY_SERVICE_NAME。${PLAIN}"
        return 1
    }
    return 0
}
install_xray_core() {
    local arch asset sha curl_family tmp zip url actual
    install_dependencies || return 1
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) asset="Xray-linux-64.zip"; sha="$XRAY_SHA256_AMD64" ;;
        aarch64|arm64) asset="Xray-linux-arm64-v8a.zip"; sha="$XRAY_SHA256_ARM64" ;;
        *) echo -e "${RED}[错误] Xray 暂不支持当前 CPU 架构: ${arch}${PLAIN}"; return 1 ;;
    esac
    [[ "$NETWORK_MODE" == "ipv6" ]] && curl_family="-6" || curl_family="-4"
    tmp=$(mktemp -d /tmp/ss2022-xray-install.XXXXXX) || return 1
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
    if ! "$XRAY_BIN" version >/dev/null 2>&1; then
        echo -e "${RED}[错误] Xray 安装后无法执行。${PLAIN}"
        platform_is_alpine && ldd "$XRAY_BIN" 2>&1 || true
        return 1
    fi
    if platform_is_alpine; then
        command -v setcap >/dev/null 2>&1 || { echo -e "${RED}[错误] Alpine 缺少 setcap。${PLAIN}"; return 1; }
        setcap cap_net_bind_service=+ep "$XRAY_BIN" || { echo -e "${RED}[错误] 无法为 Xray 设置低端口 capability。${PLAIN}"; return 1; }
        "$XRAY_BIN" version >/dev/null 2>&1 || { echo -e "${RED}[错误] Xray 设置 capability 后无法执行。${PLAIN}"; return 1; }
    fi
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
            echo -e "${RED}[错误] 端口 ${input} 已被现有协议配置占用。${PLAIN}"; continue
        fi
        pid=$(service_main_pid "$XRAY_SERVICE_NAME" 2>/dev/null || true)
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
    if ! service_restart "$XRAY_SERVICE_NAME"; then
        echo -e "${RED}[错误] Xray 新配置启动失败，正在回滚...${PLAIN}"
        if [[ $had_old -eq 1 && -f "$backup" ]]; then mv -f "$backup" "$XRAY_CONF"; chown root:"$XRAY_GROUP" "$XRAY_CONF"; chmod 640 "$XRAY_CONF"; service_restart "$XRAY_SERVICE_NAME" || true; else rm -f "$XRAY_CONF"; fi
        service_log_tail "$XRAY_SERVICE_NAME" 30 || true
        return 1
    fi
    rm -f "$backup"
    echo -e "${GREEN}✔ Xray 配置已校验并安全切换。${PLAIN}"
}

ensure_snell_user() {
    ensure_managed_system_user "$SNELL_USER" "$SNELL_GROUP" "$SNELL_USER_MARKER" "$SNELL_GROUP_MARKER"
}
ensure_snell_config_dir() {
    ensure_project_config_dir "$SNELL_CONF_DIR" "$SNELL_GROUP" "$SNELL_DIR_MARKER"
}

snell_port_from_config() {
    [[ -f "$SNELL_CONF" ]] || return 1
    awk -F'[: ]+' '/^[[:space:]]*listen[[:space:]]*=/{gsub(/\[/,"",$0); gsub(/\]/,"",$0); print $NF; exit}' "$SNELL_CONF" 2>/dev/null
}

port_is_available_for_snell() {
    local port="$1"
    local current_port="" snell_pid=""

    current_port=$(snell_port_from_config 2>/dev/null || true)
    snell_pid=$(service_main_pid snell-v5 2>/dev/null || true)

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
    local arch sarch expected_sha url tmp zip actual curl_family candidate

    if platform_is_alpine; then
        echo -e "${RED}[错误] Snell v5 官方 Linux 二进制无法在 Alpine 3.21 + gcompat 下正常启动。${PLAIN}"
        echo -e "${YELLOW}为保持官方实现与系统安全，本脚本不注入第三方 glibc，也不改用非官方 Snell 实现。${PLAIN}"
        return 1
    fi

    snell_assert_safe_ownership || return 1
    install_dependencies || return 1

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

    case "$NETWORK_MODE" in
        ipv6) curl_family="-6" ;;
        ipv4|dual) curl_family="-4" ;;
        *)
            if get_public_ipv4 >/dev/null 2>&1; then
                curl_family="-4"
            elif get_public_ipv6 >/dev/null 2>&1; then
                curl_family="-6"
            else
                echo -e "${RED}[错误] 未检测到可用公网 IPv4 / IPv6，无法下载 Snell。${PLAIN}"
                return 1
            fi
            ;;
    esac

    if [[ -x "$SNELL_BIN" ]]; then
        echo -e "${GREEN}✔ 已检测到 Snell v5 二进制；新文件通过完整校验与运行时自检后才会替换。${PLAIN}"
    fi

    tmp=$(mktemp -d /tmp/ss2022-snell-install.XXXXXX) || return 1
    zip="$tmp/snell.zip"
    candidate="${SNELL_CANDIDATE_PREFIX}.$"
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

    rm -f "$candidate"
    install -m 755 "$tmp/snell-server" "$candidate" || {
        rm -rf "$tmp"
        rm -f "$candidate"
        return 1
    }

    if ! snell_binary_works "$candidate"; then
        echo -e "${RED}[错误] Snell v5 官方二进制无法在当前系统正常加载/执行。${PLAIN}"
        if platform_is_alpine; then
            echo -e "${YELLOW}Surge 官方 Snell 依赖 glibc；当前 Alpine 的 gcompat 兼容层未通过运行时自检。${PLAIN}"
            echo -e "${YELLOW}为避免注入第三方 glibc 或改用非官方实现，本脚本停止部署；现有 Snell 二进制不会被覆盖。${PLAIN}"
            echo -e "${YELLOW}ldd 诊断：${PLAIN}"
            ldd "$candidate" 2>&1 || true
            apk info gcompat libstdc++ libgcc 2>&1 | head -n 30 || true
        fi
        rm -rf "$tmp"
        rm -f "$candidate"
        return 1
    fi

    mv -f "$candidate" "$SNELL_BIN" || {
        rm -rf "$tmp"
        rm -f "$candidate"
        return 1
    }
    mark_snell_project_managed || {
        rm -rf "$tmp"
        return 1
    }
    rm -rf "$tmp"

    echo -e "${GREEN}✔ Snell v${SNELL_VERSION} 官方二进制已通过 SHA256 与运行时自检。${PLAIN}"
    return 0
}

write_snell_service() {
    ensure_snell_user || return 1

    if [[ "$PLATFORM_INIT" == "systemd" ]]; then
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
        service_daemon_reload || return 1
        service_enable snell-v5 || return 1
        return 0
    fi

    mkdir -p /var/log/ss2022 || return 1
    touch "$SNELL_OPENRC_LOG" || return 1
    chown "$SNELL_USER:$SNELL_GROUP" "$SNELL_OPENRC_LOG" || return 1
    chmod 640 "$SNELL_OPENRC_LOG"

    cat > "$SNELL_OPENRC_SERVICE" <<SERVICE
#!/sbin/openrc-run
description="vps-bootstrap Snell Server v5"
command="$SNELL_BIN"
command_args="-c $SNELL_CONF"
command_user="$SNELL_USER:$SNELL_GROUP"
supervisor="supervise-daemon"
pidfile="$SNELL_OPENRC_PID"
output_log="$SNELL_OPENRC_LOG"
error_log="$SNELL_OPENRC_LOG"
capabilities="^cap_net_bind_service"
no_new_privs=true
respawn_delay=5
respawn_max=0
umask=0077

depend() {
    need net
    use dns
}
SERVICE
    chmod 755 "$SNELL_OPENRC_SERVICE"
    if ! service_enable snell-v5; then
        echo -e "${RED}[错误] OpenRC 无法把 Snell v5 加入 default runlevel。${PLAIN}"
        return 1
    fi
    return 0
}

apply_snell_config() {
    local candidate="$1"
    local backup="" had_old=0

    ensure_snell_config_dir || return 1

    if [[ -f "$SNELL_CONF" ]]; then
        had_old=1
        backup=$(mktemp "/etc/snell/.ss2022-rollback.XXXXXX") || return 1
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

    if ! service_restart snell-v5; then
        echo -e "${RED}[错误] Snell v5 启动失败，正在回滚配置...${PLAIN}"
        if [[ $had_old -eq 1 && -f "$backup" ]]; then
            mv -f "$backup" "$SNELL_CONF"
            chown root:"$SNELL_GROUP" "$SNELL_CONF"
            chmod 640 "$SNELL_CONF"
            service_restart snell-v5 >/dev/null 2>&1 || true
        else
            rm -f "$SNELL_CONF"
            service_stop snell-v5 >/dev/null 2>&1 || true
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
    ask_node_name "snell" || return

    ensure_snell_config_dir || { pause; return; }
    tmp=$(mktemp "${SNELL_CONF_DIR}/.ss2022-config.XXXXXX") || return
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
        save_mode_state "snell" "$(jq -n --arg host "$SERVER_HOST" --arg network "$NETWORK_MODE" --arg name "$NODE_NAME" '{host:$host,network:$network,name:$name}')" || true
        show_snell_details "$SERVER_HOST" "$snell_port" "$psk" "$NODE_NAME"
    else
        service_log_tail snell-v5 30 || true
    fi
    pause
}

# ==============================================================================
# [08] 节点配置查看
# ==============================================================================

view_ss2022_config() {
    local host host_v4="" host_v6="" network="" port method pass listen ip_type name
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
    network=$(get_mode_state_field "ss" "network" 2>/dev/null || true)
    if [[ "$network" == "dual" ]]; then
        host_v4=$(get_mode_state_field "ss" "host_v4" 2>/dev/null || get_public_ipv4 2>/dev/null || true)
        host_v6=$(get_mode_state_field "ss" "host_v6" 2>/dev/null || get_public_ipv6 2>/dev/null || get_global_ipv6 2>/dev/null || true)
    fi
    name=$(get_node_name "ss")
    show_ss_details "$host" "$port" "$method" "$pass" "$name" "$host_v4" "$host_v6"
}

view_shadowtls_config() {
    local host host_v4="" host_v6="" network="" port method ss_pass stls_pass sni listen udp_enabled="false" udp_port="" name

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
    network=$(get_mode_state_field "shadowtls" "network" 2>/dev/null || true)
    if [[ "$network" == "dual" ]]; then
        host_v4=$(get_mode_state_field "shadowtls" "host_v4" 2>/dev/null || get_public_ipv4 2>/dev/null || true)
        host_v6=$(get_mode_state_field "shadowtls" "host_v6" 2>/dev/null || get_public_ipv6 2>/dev/null || get_global_ipv6 2>/dev/null || true)
    fi
    name=$(get_node_name "shadowtls")
    show_shadowtls_details "$host" "$port" "$method" "$ss_pass" "$stls_pass" "$sni" "$udp_enabled" "$udp_port" "$name" "$host_v4" "$host_v6"
}

view_vless_config() {
    local host port uuid sni private public short_id listen out name
    if ! xray_vless_exists; then
        if json_has_inbound_tag "$TAG_VLESS"; then
            echo -e "${YELLOW}检测到旧 sing-box VLESS Reality。当前版本请删除后重新部署为 Xray 版。${PLAIN}"
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
    name=$(get_node_name "vless")
    show_vless_details "$host" "$port" "$uuid" "$sni" "$public" "$short_id" "$name"
}

view_snell_config() {
    local host port psk listen name

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
    name=$(get_node_name "snell")
    show_snell_details "$host" "$port" "$psk" "$name"
}

view_config_menu() {
    while true; do
        clear
        echo -e "${CYAN}════════════════════ 查看节点配置 ════════════════════${PLAIN}"
        echo "  1. SS2022"
        echo "  2. SS2022 + ShadowTLS v3"
        echo "  3. VLESS Reality"
        echo "  4. Snell v5"
        echo "  5. 修改节点名称"
        echo "  0. 返回"
        echo -e "${CYAN}═══════════════════════════════════════════════════════${PLAIN}"
        read -rp "请选择 [0-5]: " c
        case "$c" in
            1) view_ss2022_config; pause ;;
            2) view_shadowtls_config; pause ;;
            3) view_vless_config; pause ;;
            4) view_snell_config; pause ;;
            5) node_name_management ;;
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

# ==============================================================================
# [09] 服务端分流：WARP / Chain / Rules
# ==============================================================================

routing_init_state() {
    mkdir -p "$STATE_DIR" || return 1
    chmod 700 "$STATE_DIR"
    if [[ ! -f "$ROUTING_FILE" ]]; then
        cat > "$ROUTING_FILE" <<EOF
{
  "version": 1,
  "default_outbound": "direct",
  "global_ip_family": "default",
  "warp": {
    "proxy_host": "127.0.0.1",
    "proxy_port": ${WARP_DEFAULT_PORT},
    "profile": "auto",
    "egress_family": "auto",
    "direct_ipv4": null,
    "direct_ipv6": null
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
      .global_ip_family = (.global_ip_family // "default") |
      .warp = (.warp // {}) |
      .warp.proxy_host = (.warp.proxy_host // "127.0.0.1") |
      .warp.proxy_port = (.warp.proxy_port // $port) |
      .warp.profile = (.warp.profile // "auto") |
      .warp.egress_family = (.warp.egress_family // "auto") |
      .warp.direct_ipv4 = (.warp.direct_ipv4 // null) |
      .warp.direct_ipv6 = (.warp.direct_ipv6 // null) |
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

routing_resolve_outbound_ref() {
    local ref="$1" resolved
    if [[ "$ref" == "default" ]]; then
        resolved=$(jq -r '.default_outbound // "direct"' "$ROUTING_FILE" 2>/dev/null)
        [[ -n "$resolved" && "$resolved" != "default" ]] || resolved="direct"
        echo "$resolved"
    else
        echo "$ref"
    fi
}

routing_outbound_label() {
    local ref="$1" id name
    case "$ref" in
        default) echo "DEFAULT（跟随全局默认出口）" ;;
        direct) echo "DIRECT（本 VPS）" ;;
        warp) echo "WARP（$(warp_egress_label)）" ;;
        chain:*)
            id=${ref#chain:}
            name=$(jq -r --arg id "$id" '.chain_nodes[]? | select(.id==$id) | .name // empty' "$ROUTING_FILE" 2>/dev/null | head -n1)
            echo "${name:-$id}"
            ;;
        *) echo "$ref" ;;
    esac
}

routing_tag_singbox() {
    local ref
    ref=$(routing_resolve_outbound_ref "$1")
    case "$ref" in
        direct) echo "direct" ;;
        warp) echo "route-warp" ;;
        chain:*) echo "route-chain-${ref#chain:}" ;;
        *) echo "direct" ;;
    esac
}

routing_tag_xray() {
    local ref family="${2:-default}" base
    ref=$(routing_resolve_outbound_ref "$1")
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

warp_direct_ipv4_ready() {
    curl -4fsS --connect-timeout 4 --max-time 8 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep -q '^ip='
}

warp_direct_ipv6_ready() {
    curl -6fsS --connect-timeout 4 --max-time 8 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep -q '^ip='
}

warp_detect_direct_profile() {
    # 只测试系统原生网络。WARP 使用 Local Proxy，不会影响这里的 DIRECT 探测。
    WARP_DIRECT_IPV4=false
    WARP_DIRECT_IPV6=false
    WARP_PROFILE="unknown"
    WARP_RECOMMENDED_FAMILY="default"

    warp_direct_ipv4_ready && WARP_DIRECT_IPV4=true
    warp_direct_ipv6_ready && WARP_DIRECT_IPV6=true

    # 首次进入 WARP 菜单时 DNS 可能尚未初始化；此时用本机地址+默认路由作为保守兜底。
    if [[ "$WARP_DIRECT_IPV4" == false ]] && ip -4 route show default 2>/dev/null | grep -q '^default ' \
       && ip -4 addr show scope global 2>/dev/null | grep -q 'inet '; then
        WARP_DIRECT_IPV4=true
    fi
    if [[ "$WARP_DIRECT_IPV6" == false ]] && ip -6 route show default 2>/dev/null | grep -q '^default ' \
       && ip -6 addr show scope global 2>/dev/null | grep -q 'inet6 '; then
        WARP_DIRECT_IPV6=true
    fi

    if [[ "$WARP_DIRECT_IPV4" == true && "$WARP_DIRECT_IPV6" == false ]]; then
        WARP_PROFILE="supplement_ipv6"
        WARP_RECOMMENDED_FAMILY="ipv6"
    elif [[ "$WARP_DIRECT_IPV4" == false && "$WARP_DIRECT_IPV6" == true ]]; then
        WARP_PROFILE="supplement_ipv4"
        WARP_RECOMMENDED_FAMILY="ipv4"
    elif [[ "$WARP_DIRECT_IPV4" == true && "$WARP_DIRECT_IPV6" == true ]]; then
        WARP_PROFILE="dual_stack"
        WARP_RECOMMENDED_FAMILY="default"
    fi
}

warp_profile_label() {
    local profile="${1:-unknown}"
    case "$profile" in
        supplement_ipv6) echo "IPv4-only：WARP 补充 IPv6" ;;
        supplement_ipv4) echo "IPv6-only：WARP 补充 IPv4" ;;
        dual_stack) echo "原生双栈：WARP 作为可选额外出口" ;;
        *) echo "未识别 / 尚未检测" ;;
    esac
}

warp_save_detected_profile() {
    routing_init_state || return 1
    local tmp
    warp_detect_direct_profile
    tmp=$(mktemp "${STATE_DIR}/routing.json.tmp.XXXXXX") || return 1
    jq --arg profile "$WARP_PROFILE" \
       --argjson v4 "$WARP_DIRECT_IPV4" \
       --argjson v6 "$WARP_DIRECT_IPV6" \
       '.warp.profile=$profile | .warp.direct_ipv4=$v4 | .warp.direct_ipv6=$v6' \
       "$ROUTING_FILE" > "$tmp" || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$ROUTING_FILE"
    chmod 600 "$ROUTING_FILE"
}

warp_show_direct_profile() {
    warp_detect_direct_profile
    echo "VPS 原生网络："
    if [[ "$WARP_DIRECT_IPV4" == true ]]; then echo -e "  IPv4 : ${GREEN}可用${PLAIN}"; else echo -e "  IPv4 : ${YELLOW}不可用${PLAIN}"; fi
    if [[ "$WARP_DIRECT_IPV6" == true ]]; then echo -e "  IPv6 : ${GREEN}可用${PLAIN}"; else echo -e "  IPv6 : ${YELLOW}不可用${PLAIN}"; fi
    echo "推荐模式：$(warp_profile_label "$WARP_PROFILE")"
    case "$WARP_PROFILE" in
        supplement_ipv6)
            echo "  DIRECT → VPS 原生 IPv4"
            echo "  WARP   → 推荐仅 IPv6（按分流规则调用）"
            ;;
        supplement_ipv4)
            echo "  DIRECT → VPS 原生 IPv6"
            echo "  WARP   → 推荐仅 IPv4（按分流规则调用）"
            ;;
        dual_stack)
            echo "  DIRECT → VPS 原生 IPv4 / IPv6"
            echo "  WARP   → 可选 IPv4 / IPv6 额外出口"
            ;;
        *)
            echo "  无法确认原生公网协议族，请先检查 VPS 网络。"
            ;;
    esac
}

warp_test_family() {
    local family="$1" port url out
    port=$(warp_proxy_port)
    [[ "$family" == "ipv6" ]] && url="https://api6.ipify.org" || url="https://api4.ipify.org"
    out=$(curl -fsS --connect-timeout 8 --max-time 15 --socks5-hostname "127.0.0.1:${port}" "$url" 2>/dev/null) || return 1
    printf '%s' "$out"
}

warp_recommended_family() {
    warp_detect_direct_profile
    printf '%s' "$WARP_RECOMMENDED_FAMILY"
}

warp_egress_family() {
    routing_init_state || { echo "auto"; return; }
    jq -r '.warp.egress_family // "auto"' "$ROUTING_FILE" 2>/dev/null
}

warp_effective_egress_family() {
    local mode
    mode=$(warp_egress_family)
    case "$mode" in
        ipv4_only|ipv6_only|dual) echo "$mode"; return ;;
    esac
    # dev15 升级兼容：旧状态尚未选择时，按 VPS 原生网络自动取“补缺”模式。
    warp_detect_direct_profile
    case "$WARP_PROFILE" in
        supplement_ipv6) echo "ipv6_only" ;;
        supplement_ipv4) echo "ipv4_only" ;;
        dual_stack) echo "dual" ;;
        *) echo "dual" ;;
    esac
}

warp_egress_label() {
    case "${1:-$(warp_effective_egress_family)}" in
        ipv6_only) echo "仅 IPv6（IPv4 保持 DIRECT）" ;;
        ipv4_only) echo "仅 IPv4（IPv6 保持 DIRECT）" ;;
        dual) echo "IPv4 + IPv6" ;;
        *) echo "自动" ;;
    esac
}

warp_family_allowed() {
    local family="$1" mode
    mode=$(warp_effective_egress_family)
    case "$mode:$family" in
        dual:ipv4|dual:ipv6|ipv4_only:ipv4|ipv6_only:ipv6) return 0 ;;
        *) return 1 ;;
    esac
}

warp_effective_rule_family() {
    local requested="${1:-default}" mode
    mode=$(warp_effective_egress_family)
    case "$mode" in
        ipv4_only) echo "ipv4" ;;
        ipv6_only) echo "ipv6" ;;
        *) echo "$requested" ;;
    esac
}

routing_global_ip_family() {
    routing_init_state >/dev/null 2>&1 || { echo "default"; return; }
    jq -r '.global_ip_family // "default"' "$ROUTING_FILE" 2>/dev/null
}

routing_ip_family_label() {
    case "${1:-default}" in
        ipv4) echo "仅 IPv4" ;;
        ipv6) echo "仅 IPv6" ;;
        *) echo "双栈 / 默认" ;;
    esac
}

routing_effective_family() {
    local requested="${1:-default}" ref="${2:-direct}" family global actual_ref
    global=$(routing_global_ip_family)
    family="$requested"
    [[ "$family" == "default" ]] && family="$global"
    actual_ref=$(routing_resolve_outbound_ref "$ref")
    if [[ "$actual_ref" == "warp" ]]; then
        family=$(warp_effective_rule_family "$family")
    fi
    echo "$family"
}

warp_choose_egress_family() {
    warp_detect_direct_profile
    local c default_choice recommendation

    case "$WARP_PROFILE" in
        supplement_ipv6)
            default_choice=2
            recommendation="推荐：仅 WARP IPv6；VPS 原生 IPv4 继续 DIRECT"
            ;;
        supplement_ipv4)
            default_choice=1
            recommendation="推荐：仅 WARP IPv4；VPS 原生 IPv6 继续 DIRECT"
            ;;
        dual_stack)
            default_choice=3
            recommendation="推荐：WARP IPv4 + IPv6 双栈"
            ;;
        *)
            echo -e "${RED}[错误] 无法识别 VPS 原生 IPv4/IPv6，不能安全选择 WARP 出口模式。${PLAIN}"
            return 1
            ;;
    esac

    echo -e "${CYAN}请选择 WARP 实际出口模式：${PLAIN}"
    echo ""
    case "$WARP_PROFILE" in
        supplement_ipv4) echo "  1. 仅启用 WARP IPv4（推荐；VPS IPv6 继续 DIRECT）" ;;
        *)               echo "  1. 仅启用 WARP IPv4" ;;
    esac
    case "$WARP_PROFILE" in
        supplement_ipv6) echo "  2. 仅启用 WARP IPv6（推荐；VPS IPv4 继续 DIRECT）" ;;
        *)               echo "  2. 仅启用 WARP IPv6" ;;
    esac
    case "$WARP_PROFILE" in
        dual_stack) echo "  3. WARP IPv4 + IPv6 双栈（推荐）" ;;
        *)          echo "  3. WARP IPv4 + IPv6 双栈" ;;
    esac
    echo "  0. 取消"
    echo ""
    echo -e "${YELLOW}${recommendation}${PLAIN}"
    read -rp "请选择 [0-3，默认 ${default_choice}]: " c
    c=${c:-$default_choice}
    case "$c" in
        1) WARP_SELECTED_EGRESS="ipv4_only" ;;
        2) WARP_SELECTED_EGRESS="ipv6_only" ;;
        3) WARP_SELECTED_EGRESS="dual" ;;
        0) return 1 ;;
        *) echo -e "${RED}[错误] 无效选择。${PLAIN}"; return 1 ;;
    esac

    echo ""
    echo -e "已选择：${GREEN}$(warp_egress_label "$WARP_SELECTED_EGRESS")${PLAIN}"
}

warp_save_egress_family() {
    local mode="$1" tmp
    case "$mode" in ipv4_only|ipv6_only|dual) ;; *) return 1 ;; esac
    routing_init_state || return 1
    if [[ "$mode" != "dual" ]] && [[ "$(jq -r '.default_outbound' "$ROUTING_FILE")" == "warp" ]]; then
        echo -e "${RED}[错误] 当前全局默认出口仍是 WARP。请先改为 DIRECT 或落地节点，再启用单地址族 WARP。${PLAIN}"
        return 1
    fi
    tmp=$(mktemp "${STATE_DIR}/routing.json.tmp.XXXXXX") || return 1
    jq --arg mode "$mode" '.warp.egress_family=$mode' "$ROUTING_FILE" > "$tmp" || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$ROUTING_FILE"
    chmod 600 "$ROUTING_FILE"
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
    # 兼容三类常见 Shadowsocks URI:
    #   1) SIP002: ss://BASE64URL(method:password)@host:port
    #   2) 明文 userinfo: ss://method:password@host:port
    #   3) 旧格式: ss://BASE64(method:password@host:port)
    #
    # query/fragment 不参与核心解析；若 query 中含 plugin=，由调用方决定是否接受。
    local raw="$1" uri query="" userinfo hostport decoded host port method pass full
    [[ "$raw" == ss://* ]] || return 1
    uri=${raw#ss://}
    uri=${uri%%#*}
    if [[ "$uri" == *"?"* ]]; then
        query=${uri#*\?}
        uri=${uri%%\?*}
    fi

    if [[ "$uri" == *"@"* ]]; then
        userinfo=${uri%@*}
        hostport=${uri##*@}
        if [[ "$userinfo" == *:* ]]; then
            decoded=$(url_decode_simple "$userinfo")
        else
            decoded=$(base64url_decode "$userinfo") || return 1
        fi
    else
        full=$(base64url_decode "$uri") || return 1
        [[ "$full" == *"@"* ]] || return 1
        decoded=${full%@*}
        hostport=${full##*@}
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

    CHAIN_SERVER="$host"
    CHAIN_PORT="$port"
    CHAIN_METHOD="$method"
    CHAIN_PASSWORD="$pass"
    CHAIN_SS_QUERY="$query"
}

normalize_standard_ss_method() {
    case "$1" in
        chacha20-poly1305) echo "chacha20-ietf-poly1305" ;;
        xchacha20-poly1305) echo "xchacha20-ietf-poly1305" ;;
        *) echo "$1" ;;
    esac
}

# Shadowsocks 落地能力判断：
# - SS2022 与常见 AEAD 优先由 Xray 原生直连；
# - aes-192-gcm / Legacy 等 Xray 不支持的方法，才通过 sing-box 本地 Bridge。
singbox_supports_standard_ss_method() {
    case "$1" in
        aes-128-gcm|aes-192-gcm|aes-256-gcm|chacha20-ietf-poly1305|xchacha20-ietf-poly1305|\
        aes-128-ctr|aes-192-ctr|aes-256-ctr|aes-128-cfb|aes-192-cfb|aes-256-cfb|\
        rc4-md5|chacha20-ietf|xchacha20) return 0 ;;
        *) return 1 ;;
    esac
}

xray_supports_ss_method() {
    case "$1" in
        2022-blake3-aes-128-gcm|2022-blake3-aes-256-gcm|2022-blake3-chacha20-poly1305|\
        aes-128-gcm|aes-256-gcm|chacha20-ietf-poly1305|xchacha20-ietf-poly1305) return 0 ;;
        *) return 1 ;;
    esac
}

standard_ss_method_is_legacy() {
    case "$1" in
        aes-128-ctr|aes-192-ctr|aes-256-ctr|aes-128-cfb|aes-192-cfb|aes-256-cfb|rc4-md5|chacha20-ietf|xchacha20) return 0 ;;
        *) return 1 ;;
    esac
}

validate_standard_ss_outbound() {
    local method="$1" pass="$2"
    singbox_supports_standard_ss_method "$method" || return 1
    [[ -n "$pass" ]]
}

# 为需要 sing-box Bridge 的标准 SS 节点分配稳定的本地 SOCKS 端口。
# 40000 预留给 WARP；Bridge 使用 41000-41999。
allocate_ss_bridge_port() {
    local p used
    routing_init_state || return 1
    for p in $(seq 41000 41999); do
        used=$(jq -r --argjson p "$p" 'any(.chain_nodes[]?; (.bridge_port // 0) == $p)' "$ROUTING_FILE" 2>/dev/null || echo false)
        [[ "$used" == "true" ]] && continue
        if command -v ss >/dev/null 2>&1 && ss -lntH 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$p$"; then
            continue
        fi
        echo "$p"
        return 0
    done
    return 1
}

routing_has_bridge_nodes() {
    [[ -f "$ROUTING_FILE" ]] || return 1
    jq -e 'any(.chain_nodes[]?; .type=="shadowsocks" and (.bridge_required // false)==true)' "$ROUTING_FILE" >/dev/null 2>&1
}

# 当 VLESS/Xray 需要使用 Xray 不支持的标准 SS 算法时，sing-box 是必要依赖。
# 不静默安装：第一次明确告诉用户原因并确认。
ensure_singbox_for_ss_bridge() {
    [[ -x "$SINGBOX_BIN" && -f "$SINGBOX_CONF" ]] && return 0

    echo -e "${YELLOW}========================================${PLAIN}"
    echo -e "${YELLOW} 需要安装 sing-box（本地 SS Bridge）${PLAIN}"
    echo -e "${YELLOW}========================================${PLAIN}"
    echo "当前标准 Shadowsocks 落地算法无法由 Xray 原生连接。"
    echo "VLESS Reality 需要通过本机 SOCKS Bridge 交给 sing-box 转发。"
    echo ""
    echo "将安装 sing-box ${SINGBOX_VERSION}，仅作为本脚本组件使用。"
    echo "不会因此额外开放公网 SS2022 端口。"
    local ans
    read -rp "是否继续安装？[y/N]: " ans
    [[ "$ans" =~ ^[Yy]$ ]] || {
        echo -e "${YELLOW}[取消] 未安装 sing-box，标准 SS 落地节点未添加。${PLAIN}"
        return 1
    }

    install_singbox_core || return 1
    ensure_base_singbox_config || return 1
    echo -e "${GREEN}✔ sing-box 已安装，本地 Bridge 依赖就绪。${PLAIN}"
    return 0
}

chain_node_type_label() {
    case "$1" in
        ss2022|shadowsocks) echo "Shadowsocks" ;;
        socks5) echo "SOCKS5" ;;
        *) echo "$1" ;;
    esac
}

# 导入的 SS2022 落地节点不在 Bash 层重复校验/重编码 PSK。
# ss:// 解析后保留 password 原值，由 Xray / sing-box 自身配置校验负责协议合法性。

routing_choose_outbound() {
    local prompt="${1:-请选择出口}" nodes count idx choice i id name type
    routing_init_state || return 1
    nodes=$(jq -c '.chain_nodes' "$ROUTING_FILE")
    count=$(jq 'length' <<<"$nodes")
    echo "$prompt"
    echo "  1. DIRECT（当前 VPS 本身出口）"
    if warp_proxy_ready; then
        echo "  2. WARP（Cloudflare Local Proxy / $(warp_egress_label)）"
    else
        echo "  2. WARP（当前不可用，请先安装/连接）"
    fi
    i=0
    while [[ $i -lt $count ]]; do
        name=$(jq -r ".[$i].name" <<<"$nodes")
        type=$(jq -r ".[$i].type" <<<"$nodes")
        printf '  %d. %s [%s]\n' "$((i+3))" "$name" "$(chain_node_type_label "$type")"
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
    local c default_choice=1 recommended="default" mode

    if [[ "${SELECTED_OUTBOUND:-}" == "warp" ]]; then
        mode=$(warp_effective_egress_family)
        case "$mode" in
            ipv4_only)
                SELECTED_IP_FAMILY="ipv4"
                echo -e "WARP 当前模式：${GREEN}仅 IPv4${PLAIN}；该规则已固定使用 IPv4。"
                return 0
                ;;
            ipv6_only)
                SELECTED_IP_FAMILY="ipv6"
                echo -e "WARP 当前模式：${GREEN}仅 IPv6${PLAIN}；该规则已固定使用 IPv6。"
                return 0
                ;;
            dual)
                recommended=$(warp_recommended_family)
                [[ "$recommended" == "ipv4" ]] && default_choice=2
                [[ "$recommended" == "ipv6" ]] && default_choice=3
                ;;
        esac
    fi

    echo "请选择 IP 地址族："
    echo "  1. 默认（不强制）"
    [[ "$recommended" == "ipv4" ]] && echo "  2. 仅 IPv4（WARP 补全推荐）" || echo "  2. 仅 IPv4"
    [[ "$recommended" == "ipv6" ]] && echo "  3. 仅 IPv6（WARP 补全推荐）" || echo "  3. 仅 IPv6"
    read -rp "请选择 [1-3，默认 ${default_choice}]: " c
    c=${c:-$default_choice}
    case "$c" in
        1) SELECTED_IP_FAMILY="default" ;;
        2) SELECTED_IP_FAMILY="ipv4" ;;
        3) SELECTED_IP_FAMILY="ipv6" ;;
        *) return 1 ;;
    esac
}

build_singbox_routing_candidate() {
    local output="$1" outbounds='[]' rules='[{"action":"sniff","timeout":"300ms"}]' bridge_inbounds='[]' nodes count i node type tag ref default_ref default_tag port
    local rule_count r rmatch family outbound domains suffix keywords ips part action global_family global_strategy
    [[ -f "$SINGBOX_CONF" && -x "$SINGBOX_BIN" ]] || return 2
    routing_init_state || return 1
    global_family=$(routing_global_ip_family)

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
        case "$type" in
            ss2022|shadowsocks)
                if chain_node_needs_warp_underlay "$node"; then
                    outbounds=$(jq -c --arg tag "$tag" --arg server "$(jq -r '.server' <<<"$node")" --argjson port "$(jq -r '.port' <<<"$node")" --arg method "$(jq -r '.method' <<<"$node")" --arg pass "$(jq -r '.password' <<<"$node")" --arg ds "$(chain_node_singbox_domain_strategy "$node")" '. + [({type:"shadowsocks",tag:$tag,server:$server,server_port:$port,method:$method,password:$pass,detour:"route-warp"} + (if $ds!="" then {domain_strategy:$ds} else {} end))]' <<<"$outbounds")
                else
                    outbounds=$(jq -c --arg tag "$tag" --arg server "$(jq -r '.server' <<<"$node")" --argjson port "$(jq -r '.port' <<<"$node")" --arg method "$(jq -r '.method' <<<"$node")" --arg pass "$(jq -r '.password' <<<"$node")" --arg ds "$(chain_node_singbox_domain_strategy "$node")" '. + [({type:"shadowsocks",tag:$tag,server:$server,server_port:$port,method:$method,password:$pass} + (if $ds!="" then {domain_strategy:$ds} else {} end))]' <<<"$outbounds")
                fi
                if [[ "$type" == "shadowsocks" && "$(jq -r '.bridge_required // false' <<<"$node")" == "true" ]]; then
                    local bridge_port bridge_tag
                    bridge_port=$(jq -r '.bridge_port // 0' <<<"$node")
                    [[ "$bridge_port" =~ ^[0-9]+$ && "$bridge_port" -gt 0 ]] || {
                        echo -e "${RED}[错误] 标准 SS 节点缺少有效 bridge_port。${PLAIN}" >&2
                        return 1
                    }
                    bridge_tag="route-bridge-in-$(jq -r '.id' <<<"$node")"
                    bridge_inbounds=$(jq -c --arg tag "$bridge_tag" --argjson p "$bridge_port" '. + [{type:"socks",tag:$tag,listen:"127.0.0.1",listen_port:$p}]' <<<"$bridge_inbounds")
                    rules=$(jq -c --arg inbound "$bridge_tag" --arg out "$tag" '. + [{inbound:[$inbound],action:"route",outbound:$out}]' <<<"$rules")
                fi
                ;;
            socks5)
                outbounds=$(jq -c --arg tag "$tag" --arg server "$(jq -r '.server' <<<"$node")" --argjson port "$(jq -r '.port' <<<"$node")" --arg user "$(jq -r '.username // ""' <<<"$node")" --arg pass "$(jq -r '.password // ""' <<<"$node")" '. + [({type:"socks",tag:$tag,server:$server,server_port:$port} + (if $user!="" then {username:$user,password:$pass} else {} end))]' <<<"$outbounds")
                ;;
            *)
                echo -e "${RED}[错误] 未知落地节点类型: ${type}${PLAIN}" >&2
                return 1
                ;;
        esac
        i=$((i+1))
    done

    rule_count=$(jq '.rules|length' "$ROUTING_FILE")
    i=0
    while [[ $i -lt $rule_count ]]; do
        r=$(jq -c ".rules[$i]" "$ROUTING_FILE")
        rmatch=$(routing_rule_match_json "$r")
        outbound=$(jq -r '.outbound' <<<"$r")
        family=$(routing_effective_family "$(jq -r '.ip_family // "default"' <<<"$r")" "$outbound")
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

    if [[ "$global_family" == "ipv4" || "$global_family" == "ipv6" ]]; then
        [[ "$global_family" == "ipv4" ]] && global_strategy="ipv4_only" || global_strategy="ipv6_only"
        rules=$(jq -c --arg strategy "$global_strategy" '. + [{action:"resolve",strategy:$strategy}]' <<<"$rules")
    fi

    default_ref=$(jq -r '.default_outbound' "$ROUTING_FILE")
    default_tag=$(routing_tag_singbox "$default_ref")
    jq --argjson outs "$outbounds" --argjson rules "$rules" --argjson bridges "$bridge_inbounds" --arg final "$default_tag" '
      .dns = (.dns // {}) |
      .dns.servers = ((.dns.servers // []) as $servers |
        if any($servers[]?; ((.tag // "") == "local-dns"))
        then ($servers | map(
          if (type == "object") and ((.type // "") == "local") and ((.tag // "") == "local-dns")
          then . + {prefer_go:true}
          else .
          end
        ))
        else $servers + [{type:"local",tag:"local-dns",prefer_go:true}]
        end) |
      .inbounds = (((.inbounds // []) | map(select(((.tag // "") | startswith("route-bridge-in-")) | not))) + $bridges) |
      .outbounds = $outs |
      .route = (.route // {}) |
      .route.rules = $rules |
      .route.final = $final |
      .route.default_domain_resolver = (.route.default_domain_resolver // "local-dns")
    ' "$SINGBOX_CONF" > "$output"
}

xray_outbound_for_node() {
    local node="$1" tag="$2" family="${3:-default}" type strategy="AsIs" server_strategy
    type=$(jq -r '.type' <<<"$node")
    server_strategy=$(chain_node_xray_server_strategy "$node")
    [[ "$family" == "ipv4" ]] && strategy="ForceIPv4"
    [[ "$family" == "ipv6" ]] && strategy="ForceIPv6"
    case "$type" in
        ss2022)
            if chain_node_needs_warp_underlay "$node"; then
                jq -nc --arg tag "$tag" --arg address "$(jq -r '.server' <<<"$node")" --argjson port "$(jq -r '.port' <<<"$node")" --arg method "$(jq -r '.method' <<<"$node")" --arg pass "$(jq -r '.password' <<<"$node")" --arg ts "$strategy" --arg ss "$server_strategy" '{protocol:"shadowsocks",tag:$tag,targetStrategy:$ts,settings:{address:$address,port:$port,method:$method,password:$pass},streamSettings:{sockopt:{dialerProxy:"route-warp",domainStrategy:$ss}}}'
            else
                jq -nc --arg tag "$tag" --arg address "$(jq -r '.server' <<<"$node")" --argjson port "$(jq -r '.port' <<<"$node")" --arg method "$(jq -r '.method' <<<"$node")" --arg pass "$(jq -r '.password' <<<"$node")" --arg ts "$strategy" --arg ss "$server_strategy" '{protocol:"shadowsocks",tag:$tag,targetStrategy:$ts,settings:{address:$address,port:$port,method:$method,password:$pass},streamSettings:{sockopt:{domainStrategy:$ss}}}'
            fi
            ;;
        shadowsocks)
            local method bridge_required bridge_port
            method=$(jq -r '.method' <<<"$node")
            bridge_required=$(jq -r '.bridge_required // false' <<<"$node")
            if [[ "$bridge_required" == "true" ]] || ! xray_supports_ss_method "$method"; then
                bridge_port=$(jq -r '.bridge_port // 0' <<<"$node")
                [[ "$bridge_port" =~ ^[0-9]+$ && "$bridge_port" -gt 0 ]] || return 1
                jq -nc --arg tag "$tag" --argjson port "$bridge_port" --arg ts "$strategy" '{protocol:"socks",tag:$tag,targetStrategy:$ts,settings:{address:"127.0.0.1",port:$port}}'
            else
                if chain_node_needs_warp_underlay "$node"; then
                    jq -nc --arg tag "$tag" --arg address "$(jq -r '.server' <<<"$node")" --argjson port "$(jq -r '.port' <<<"$node")" --arg method "$method" --arg pass "$(jq -r '.password' <<<"$node")" --arg ts "$strategy" --arg ss "$server_strategy" '{protocol:"shadowsocks",tag:$tag,targetStrategy:$ts,settings:{address:$address,port:$port,method:$method,password:$pass},streamSettings:{sockopt:{dialerProxy:"route-warp",domainStrategy:$ss}}}'
                else
                    jq -nc --arg tag "$tag" --arg address "$(jq -r '.server' <<<"$node")" --argjson port "$(jq -r '.port' <<<"$node")" --arg method "$method" --arg pass "$(jq -r '.password' <<<"$node")" --arg ts "$strategy" --arg ss "$server_strategy" '{protocol:"shadowsocks",tag:$tag,targetStrategy:$ts,settings:{address:$address,port:$port,method:$method,password:$pass},streamSettings:{sockopt:{domainStrategy:$ss}}}'
                fi
            fi
            ;;
        socks5)
            jq -nc --arg tag "$tag" --arg address "$(jq -r '.server' <<<"$node")" --argjson port "$(jq -r '.port' <<<"$node")" --arg user "$(jq -r '.username // ""' <<<"$node")" --arg pass "$(jq -r '.password // ""' <<<"$node")" --arg ts "$strategy" '{protocol:"socks",tag:$tag,targetStrategy:$ts,settings:({address:$address,port:$port} + (if $user!="" then {user:$user,pass:$pass} else {} end))}'
            ;;
        *)
            return 1
            ;;
    esac
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

# VLESS 部署完成后，如果已有标准 SS 节点需要 Bridge，则确保 sing-box 依赖存在。
ensure_existing_bridges_for_vless() {
    routing_init_state || return 1
    routing_has_bridge_nodes || return 0
    [[ -x "$SINGBOX_BIN" && -f "$SINGBOX_CONF" ]] && return 0
    ensure_singbox_for_ss_bridge
}

build_xray_routing_candidate() {
    local output="$1" outbounds='[]' rules='[]' nodes count i node ref family base match
    local rule_count r rmatch domains suffix keywords ips xdomains tag part arr default_ref default_tag global_family default_family
    [[ -f "$XRAY_CONF" && -x "$XRAY_BIN" ]] || return 2
    routing_init_state || return 1
    global_family=$(routing_global_ip_family)

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
        ref=$(jq -r '.outbound' <<<"$r")
        family=$(routing_effective_family "$(jq -r '.ip_family // "default"' <<<"$r")" "$ref")
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
    default_family=$(routing_effective_family "$global_family" "$default_ref")
    default_tag=$(routing_tag_xray "$default_ref" "$default_family")
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
        sb_tmp=$(mktemp "/etc/sing-box/.ss2022-routing.XXXXXX.json") || return 1
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
        sb_backup=$(mktemp "/etc/sing-box/.ss2022-routing-rollback.XXXXXX.json") || { rm -f "$sb_tmp" "$xr_tmp"; return 1; }
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

    if [[ $failed -eq 0 && $sb_active -eq 1 ]] && ! service_restart sing-box; then failed=1; fi
    if [[ $failed -eq 0 && $xr_active -eq 1 ]] && ! service_restart "$XRAY_SERVICE_NAME"; then failed=1; fi

    if [[ $failed -ne 0 ]]; then
        echo -e "${RED}[错误] 分流配置应用失败，正在回滚 sing-box / Xray...${PLAIN}"
        if [[ $sb_active -eq 1 && -f "$sb_backup" ]]; then mv -f "$sb_backup" "$SINGBOX_CONF"; chown root:"$SINGBOX_GROUP" "$SINGBOX_CONF" 2>/dev/null || true; chmod 640 "$SINGBOX_CONF"; service_restart sing-box >/dev/null 2>&1 || true; fi
        if [[ $xr_active -eq 1 && -f "$xr_backup" ]]; then mv -f "$xr_backup" "$XRAY_CONF"; chown root:"$XRAY_GROUP" "$XRAY_CONF" 2>/dev/null || true; chmod 640 "$XRAY_CONF"; service_restart "$XRAY_SERVICE_NAME" >/dev/null 2>&1 || true; fi
        rm -f "$sb_tmp" "$xr_tmp" "$sb_backup" "$xr_backup"
        return 1
    fi

    rm -f "$sb_backup" "$xr_backup"
    echo -e "${GREEN}✔ 分流配置已通过双核心校验并安全应用。${PLAIN}"
}

warp_package_is_project_managed() {
    [[ -f "$WARP_MANAGED_MARKER" ]]
}

warp_repo_is_project_managed() {
    [[ -f "$WARP_REPO_MANAGED_MARKER" ]] && return 0
    # v1 legacy marker represented both the package and the repository assets.
    [[ -f "$WARP_MANAGED_MARKER" && ! -f "$WARP_OWNERSHIP_V2_MARKER" ]] && return 0
    return 1
}

warp_remove_managed_install_assets() {
    local package_managed=0 repo_managed=0
    warp_package_is_project_managed && package_managed=1 || true
    warp_repo_is_project_managed && repo_managed=1 || true

    if [[ $package_managed -eq 1 && "$PLATFORM_PKG" == "apt" ]]; then
        pkg_remove cloudflare-warp >/dev/null 2>&1 || true
    fi
    if [[ $repo_managed -eq 1 && "$PLATFORM_PKG" == "apt" ]]; then
        rm -f "$WARP_APT_SOURCE" "$WARP_APT_KEYRING"
    fi
    rm -f "$WARP_MANAGED_MARKER" "$WARP_REPO_MANAGED_MARKER" "$WARP_OWNERSHIP_V2_MARKER"
}

warp_install_client() {
    local codename port
    routing_init_state || return 1
    port=$(warp_proxy_port)

    echo -e "${CYAN}══════════════ WARP 双栈补全检测 ══════════════${PLAIN}"
    warp_show_direct_profile
    echo ""
    if [[ "$WARP_PROFILE" == "unknown" ]]; then
        echo -e "${RED}[错误] IPv4 / IPv6 原生公网连接均未检测成功，暂不安装 WARP。${PLAIN}"
        return 1
    fi
    echo -e "${YELLOW}[说明] Cloudflare Local Proxy 本身可能同时具备 IPv4/IPv6 能力；本脚本会在路由层严格限制为你选择的出口地址族。${PLAIN}"
    echo ""
    warp_choose_egress_family || { echo "已取消。"; return 0; }
    echo ""

    # 让 IPv6-only VPS 也能通过 APT 正常安装 Cloudflare 官方客户端。
    if [[ "$WARP_DIRECT_IPV4" == false && "$WARP_DIRECT_IPV6" == true ]]; then
        prepare_ipv6_env no || return 1
    else
        prepare_ipv4_env no || return 1
    fi

    if ! command -v warp-cli >/dev/null 2>&1; then
        echo -e "${YELLOW}>> 安装 Cloudflare 官方 WARP Linux 客户端...${PLAIN}"
        apt-get install -y curl ca-certificates gnupg lsb-release || return 1

        if [[ -e "$WARP_APT_SOURCE" || -e "$WARP_APT_KEYRING" ]]; then
            if [[ ! -f "$WARP_APT_SOURCE" || ! -f "$WARP_APT_KEYRING" ]] ||
               ! grep -Fq 'https://pkg.cloudflareclient.com/' "$WARP_APT_SOURCE" ||
               ! grep -Fq 'signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg' "$WARP_APT_SOURCE"; then
                echo -e "${RED}[错误] 检测到服务器已有不完整或非标准 Cloudflare APT 仓库配置。${PLAIN}"
                echo -e "${YELLOW}为避免覆盖外部软件源，脚本不会修改现有 source/keyring；请先自行检查后重试。${PLAIN}"
                return 1
            fi
            echo -e "${YELLOW}[提示] 检测到服务器已有 Cloudflare 官方 APT 仓库，当前仅复用，不接管其 ownership。${PLAIN}"
        else
            touch "$WARP_OWNERSHIP_V2_MARKER" "$WARP_REPO_MANAGED_MARKER" || return 1
            chmod 600 "$WARP_OWNERSHIP_V2_MARKER" "$WARP_REPO_MANAGED_MARKER"
            curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output "$WARP_APT_KEYRING" || return 1
            codename=$(. /etc/os-release 2>/dev/null; echo "${VERSION_CODENAME:-}")
            [[ -n "$codename" ]] || codename=$(lsb_release -cs 2>/dev/null || true)
            [[ -n "$codename" ]] || { echo -e "${RED}[错误] 无法识别 Debian/Ubuntu 发行版代号。${PLAIN}"; return 1; }
            echo "deb [signed-by=${WARP_APT_KEYRING}] https://pkg.cloudflareclient.com/ ${codename} main" > "$WARP_APT_SOURCE"
        fi

        apt-get update -y || return 1
        touch "$WARP_OWNERSHIP_V2_MARKER" "$WARP_MANAGED_MARKER" || return 1
        chmod 600 "$WARP_OWNERSHIP_V2_MARKER" "$WARP_MANAGED_MARKER"
        apt-get install -y cloudflare-warp || return 1
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
            warp_save_detected_profile || true
            if ! warp_save_egress_family "$WARP_SELECTED_EGRESS"; then
                echo -e "${RED}[错误] WARP 已连接，但出口模式保存失败。${PLAIN}"
                return 1
            fi
            echo -e "${GREEN}✔ WARP Local Proxy 已连接：127.0.0.1:${port}${PLAIN}"
            echo -e "${GREEN}✔ 已启用 WARP 出口：$(warp_egress_label)${PLAIN}"
            warp_test_exit
            return 0
        fi
        sleep 1; n=$((n+1))
    done
    echo -e "${RED}[错误] WARP 已配置，但 15 秒内未进入 Connected 状态。${PLAIN}"
    warp-cli --accept-tos status 2>/dev/null || true
    return 1
}

warp_show_status() {
    local port mode
    port=$(warp_proxy_port)
    mode=$(warp_effective_egress_family)
    echo -e "${CYAN}════════════════ WARP 状态 ════════════════${PLAIN}"
    warp_show_direct_profile
    echo ""
    if ! command -v warp-cli >/dev/null 2>&1; then
        echo "Cloudflare WARP：未安装"
        return
    fi
    warp-cli --accept-tos status 2>/dev/null || true
    echo ""
    warp-cli --accept-tos settings 2>/dev/null | grep -Ei 'mode|proxy|protocol' || true
    echo ""
    echo "Local Proxy: 127.0.0.1:${port}"
    echo "脚本出口模式: $(warp_egress_label "$mode")"
    if warp_proxy_ready; then
        echo -e "状态: ${GREEN}可用${PLAIN}"
        local v4="" v6=""
        case "$mode" in
            ipv6_only)
                v6=$(warp_test_family ipv6 2>/dev/null || true)
                echo -e "WARP IPv4: ${YELLOW}未启用（IPv4 保持 DIRECT）${PLAIN}"
                [[ -n "$v6" ]] && echo -e "WARP IPv6: ${GREEN}${v6}${PLAIN}" || echo -e "WARP IPv6: ${RED}测试失败${PLAIN}"
                ;;
            ipv4_only)
                v4=$(warp_test_family ipv4 2>/dev/null || true)
                [[ -n "$v4" ]] && echo -e "WARP IPv4: ${GREEN}${v4}${PLAIN}" || echo -e "WARP IPv4: ${RED}测试失败${PLAIN}"
                echo -e "WARP IPv6: ${YELLOW}未启用（IPv6 保持 DIRECT）${PLAIN}"
                ;;
            *)
                v4=$(warp_test_family ipv4 2>/dev/null || true)
                v6=$(warp_test_family ipv6 2>/dev/null || true)
                [[ -n "$v4" ]] && echo -e "WARP IPv4: ${GREEN}${v4}${PLAIN}" || echo -e "WARP IPv4: ${YELLOW}不可用${PLAIN}"
                [[ -n "$v6" ]] && echo -e "WARP IPv6: ${GREEN}${v6}${PLAIN}" || echo -e "WARP IPv6: ${YELLOW}不可用${PLAIN}"
                ;;
        esac
    else
        echo -e "状态: ${YELLOW}未就绪${PLAIN}"
    fi
}

warp_test_exit() {
    local v4="" v6="" mode
    warp_proxy_ready || { echo -e "${RED}[错误] WARP Local Proxy 当前不可用。${PLAIN}"; return 1; }
    mode=$(warp_effective_egress_family)
    case "$mode" in
        ipv6_only)
            echo -e "${YELLOW}>> 测试 WARP IPv6 出口（IPv4 不使用 WARP）...${PLAIN}"
            v6=$(warp_test_family ipv6 2>/dev/null || true)
            [[ -n "$v6" ]] || { echo -e "${RED}[错误] WARP IPv6 测试失败。${PLAIN}"; return 1; }
            echo -e "${GREEN}✔ WARP IPv6: ${v6}${PLAIN}"
            echo "  IPv4 保持 VPS DIRECT，不经过 WARP。"
            ;;
        ipv4_only)
            echo -e "${YELLOW}>> 测试 WARP IPv4 出口（IPv6 不使用 WARP）...${PLAIN}"
            v4=$(warp_test_family ipv4 2>/dev/null || true)
            [[ -n "$v4" ]] || { echo -e "${RED}[错误] WARP IPv4 测试失败。${PLAIN}"; return 1; }
            echo -e "${GREEN}✔ WARP IPv4: ${v4}${PLAIN}"
            echo "  IPv6 保持 VPS DIRECT，不经过 WARP。"
            ;;
        *)
            echo -e "${YELLOW}>> 分别测试 WARP IPv4 / IPv6 出口...${PLAIN}"
            v4=$(warp_test_family ipv4 2>/dev/null || true)
            v6=$(warp_test_family ipv6 2>/dev/null || true)
            [[ -n "$v4" ]] && echo -e "${GREEN}✔ WARP IPv4: ${v4}${PLAIN}" || echo -e "${YELLOW}○ WARP IPv4: 不可用${PLAIN}"
            [[ -n "$v6" ]] && echo -e "${GREEN}✔ WARP IPv6: ${v6}${PLAIN}" || echo -e "${YELLOW}○ WARP IPv6: 不可用${PLAIN}"
            [[ -n "$v4" || -n "$v6" ]] || return 1
            ;;
    esac
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
    local package_managed=0 repo_managed=0
    if warp_is_referenced; then
        echo -e "${RED}[错误] 当前默认出口或分流规则仍引用 WARP。请先修改这些规则再卸载。${PLAIN}"
        return 1
    fi

    warp_package_is_project_managed && package_managed=1 || true
    warp_repo_is_project_managed && repo_managed=1 || true

    if command -v warp-cli >/dev/null 2>&1; then
        warp-cli --accept-tos disconnect >/dev/null 2>&1 || true
        [[ $package_managed -eq 1 ]] && warp-cli --accept-tos registration delete >/dev/null 2>&1 || true
    elif [[ $package_managed -eq 0 && $repo_managed -eq 0 ]]; then
        echo -e "${YELLOW}WARP 未安装。${PLAIN}"
        return 0
    fi

    if [[ $package_managed -eq 1 || $repo_managed -eq 1 ]]; then
        warp_remove_managed_install_assets
        echo -e "${GREEN}✔ 已清理由 ss2022.sh 管理的 Cloudflare WARP 资产；外部 APT 仓库配置保持不变。${PLAIN}"
    else
        echo -e "${YELLOW}[提示] WARP 不是由本脚本安装，仅执行断开，不删除软件包或软件源。${PLAIN}"
    fi
}

warp_management() {
    if platform_is_alpine; then
        platform_feature_unavailable "Cloudflare WARP 官方客户端"
        pause
        return
    fi
    while true; do
        clear
        warp_show_status
        echo ""
        echo "  1. 安装 / 配置 WARP 出口模式（Local Proxy）"
        echo "  2. 测试当前 WARP 出口"
        echo "  3. 重新检测 VPS 原生 IPv4 / IPv6"
        echo "  4. 重连 WARP"
        echo "  5. 重新注册 WARP"
        echo "  6. 卸载 WARP"
        echo "  0. 返回"
        read -rp "请选择 [0-6]: " c
        case "$c" in
            1) warp_install_client; pause ;;
            2) warp_test_exit; pause ;;
            3) warp_save_detected_profile; echo ""; warp_show_direct_profile; pause ;;
            4) if command -v warp-cli >/dev/null; then warp-cli --accept-tos disconnect >/dev/null 2>&1 || true; warp-cli --accept-tos connect; sleep 2; warp_test_exit; else echo "WARP 未安装。"; fi; pause ;;
            5) warp_reregister; pause ;;
            6) warp_uninstall_client; pause ;;
            0) return ;;
            *) sleep 1 ;;
        esac
    done
}

chain_add_shadowsocks() {
    local name mode uri server port method pass id node tmp bridge_required=false bridge_port=0 ss_kind="standard"
    read -rp "节点名称（例如 US-SS）: " name
    [[ -n "$name" ]] || return 1
    if routing_node_name_exists "$name"; then
        echo -e "${RED}[错误] 落地节点名称 ${name} 已存在，请使用唯一名称。${PLAIN}"
        return 1
    fi

    echo "  1. 粘贴 ss:// URI（自动识别 SS2022 / 标准 Shadowsocks）"
    echo "  2. 手动输入"
    read -rp "请选择 [1-2，默认 1]: " mode
    mode=${mode:-1}

    if [[ "$mode" == "1" ]]; then
        read -rp "请粘贴 Shadowsocks ss:// URI: " uri
        if ! parse_ss_uri "$uri"; then
            echo -e "${RED}[错误] 无法解析该 ss:// URI。${PLAIN}"
            return 1
        fi
        if [[ "${CHAIN_SS_QUERY:-}" == *"plugin="* ]]; then
            echo -e "${RED}[错误] 当前 Shadowsocks 落地暂不支持 SIP003 插件（如 v2ray-plugin / obfs）。${PLAIN}"
            return 1
        fi
        server="$CHAIN_SERVER"
        port="$CHAIN_PORT"
        method="$CHAIN_METHOD"
        pass="$CHAIN_PASSWORD"
    else
        read -rp "服务器地址/域名: " server
        read -rp "端口: " port
        validate_port_number "$port" || { echo -e "${RED}[错误] 端口无效。${PLAIN}"; return 1; }
        echo "请选择 Shadowsocks 加密算法："
        echo ""
        echo "【SS2022】"
        echo "  1. 2022-blake3-aes-128-gcm"
        echo "  2. 2022-blake3-aes-256-gcm"
        echo "  3. 2022-blake3-chacha20-poly1305"
        echo ""
        echo "【标准 AEAD】"
        echo "  4. aes-128-gcm"
        echo "  5. aes-192-gcm"
        echo "  6. aes-256-gcm"
        echo "  7. chacha20-ietf-poly1305"
        echo "  8. xchacha20-ietf-poly1305"
        echo ""
        echo "【兼容旧算法】"
        echo "  9. aes-128-ctr"
        echo " 10. aes-192-ctr"
        echo " 11. aes-256-ctr"
        echo " 12. aes-128-cfb"
        echo " 13. aes-192-cfb"
        echo " 14. aes-256-cfb"
        echo " 15. rc4-md5"
        echo " 16. chacha20-ietf"
        echo " 17. xchacha20"
        read -rp "请选择 [1-17]: " mode
        case "$mode" in
            1) method="2022-blake3-aes-128-gcm" ;;
            2) method="2022-blake3-aes-256-gcm" ;;
            3) method="2022-blake3-chacha20-poly1305" ;;
            4) method="aes-128-gcm" ;;
            5) method="aes-192-gcm" ;;
            6) method="aes-256-gcm" ;;
            7) method="chacha20-ietf-poly1305" ;;
            8) method="xchacha20-ietf-poly1305" ;;
            9) method="aes-128-ctr" ;;
            10) method="aes-192-ctr" ;;
            11) method="aes-256-ctr" ;;
            12) method="aes-128-cfb" ;;
            13) method="aes-192-cfb" ;;
            14) method="aes-256-cfb" ;;
            15) method="rc4-md5" ;;
            16) method="chacha20-ietf" ;;
            17) method="xchacha20" ;;
            *) return 1 ;;
        esac
        read -rsp "Shadowsocks 密码 / Key: " pass
        echo ""
    fi

    method=$(normalize_standard_ss_method "$method")
    [[ "$method" == 2022-blake3-* ]] && ss_kind="ss2022"

    echo ""
    echo "检测到 Shadowsocks 节点："
    echo "服务器 : ${server}"
    echo "端口   : ${port}"
    echo "算法   : ${method}"
    echo "类型   : $([[ "$ss_kind" == "ss2022" ]] && echo 'SS2022' || echo '标准 Shadowsocks')"
    echo "密码   : $([[ -n "$pass" ]] && echo '已解析' || echo '解析失败')"

    if [[ "$ss_kind" == "ss2022" ]]; then
        if [[ -z "$pass" ]]; then
            echo -e "${RED}[错误] ss:// URI 密码解析失败或密码为空。${PLAIN}"
            return 1
        fi
        if ! xray_supports_ss_method "$method"; then
            echo -e "${RED}[错误] 当前 Xray 不支持该 SS2022 算法: ${method}${PLAIN}"
            return 1
        fi
        echo -e "${GREEN}✔ 已识别 SS2022；保留节点原始 password，由协议核心执行合法性校验。${PLAIN}"
        id="n$(date +%s)${RANDOM}"
        node=$(jq -nc --arg id "$id" --arg name "$name" --arg server "$server" --argjson port "$port" --arg method "$method" --arg pass "$pass" \
            '{id:$id,name:$name,type:"ss2022",server:$server,port:$port,method:$method,password:$pass}')
        tmp=$(mktemp "${STATE_DIR}/routing.json.tmp.XXXXXX") || return 1
        jq --argjson n "$node" '.chain_nodes += [$n]' "$ROUTING_FILE" > "$tmp" || { rm -f "$tmp"; return 1; }
        routing_commit_state_candidate "$tmp" || return 1
        echo -e "${GREEN}✔ Shadowsocks 落地节点 ${name} 已添加（SS2022）。${PLAIN}"
        if xray_vless_exists; then
            echo -e "${GREEN}  VLESS/Xray: Xray 原生直连${PLAIN}"
        fi
        return 0
    fi

    if ! singbox_supports_standard_ss_method "$method"; then
        echo -e "${RED}[错误] 当前 sing-box 不支持该标准 Shadowsocks 算法: ${method}${PLAIN}"
        return 1
    fi
    if [[ -z "$pass" ]]; then
        echo -e "${RED}[错误] ss:// URI 密码解析失败或密码为空。${PLAIN}"
        return 1
    fi

    if standard_ss_method_is_legacy "$method"; then
        echo -e "${YELLOW}[提示] ${method} 属于兼容旧算法；可用于既有节点，新部署建议优先使用 AEAD/SS2022。${PLAIN}"
    fi
    if [[ ${#pass} -lt 16 ]]; then
        echo -e "${YELLOW}[提示] 当前密码少于 16 个字符；节点仍可使用，但建议落地端设置更强密码。${PLAIN}"
    fi

    # Xray 不原生支持的标准 SS 算法，通过 sing-box 本地 SOCKS Bridge 兼容。
    if ! xray_supports_ss_method "$method"; then
        bridge_required=true
        bridge_port=$(allocate_ss_bridge_port) || {
            echo -e "${RED}[错误] 无法分配本地 SS Bridge 端口。${PLAIN}"
            return 1
        }
        echo -e "${YELLOW}[提示] Xray 不原生支持 ${method}；VLESS 路径将自动使用 sing-box 本地 Bridge（127.0.0.1:${bridge_port}）。${PLAIN}"
        if xray_vless_exists && [[ ! -x "$SINGBOX_BIN" || ! -f "$SINGBOX_CONF" ]]; then
            ensure_singbox_for_ss_bridge || return 1
        fi
    fi

    id="n$(date +%s)${RANDOM}"
    node=$(jq -nc --arg id "$id" --arg name "$name" --arg server "$server" --argjson port "$port" --arg method "$method" --arg pass "$pass" --argjson bridge "$bridge_required" --argjson bport "$bridge_port" \
        '{id:$id,name:$name,type:"shadowsocks",server:$server,port:$port,method:$method,password:$pass,bridge_required:$bridge,bridge_port:(if $bridge then $bport else null end)}')
    tmp=$(mktemp "${STATE_DIR}/routing.json.tmp.XXXXXX") || return 1
    jq --argjson n "$node" '.chain_nodes += [$n]' "$ROUTING_FILE" > "$tmp" || { rm -f "$tmp"; return 1; }
    routing_commit_state_candidate "$tmp" || return 1
    echo -e "${GREEN}✔ Shadowsocks 落地节点 ${name} 已添加（标准 Shadowsocks）。${PLAIN}"
    if [[ "$bridge_required" == "true" ]]; then
        echo -e "${GREEN}  VLESS/Xray: 本地 sing-box Bridge${PLAIN}"
    else
        echo -e "${GREEN}  VLESS/Xray: Xray 原生直连${PLAIN}"
    fi
}
chain_add_socks5() {
    local name server port auth user="" pass="" id node tmp
    echo -e "${YELLOW}[提示] SOCKS5 本身不加密；公网落地优先建议使用 Shadowsocks，SOCKS5 仅用于可信或已受保护的链路。${PLAIN}"
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
        printf '  %d. %s [%s] %s:%s\n' "$((i+1))" "$(jq -r '.name' <<<"$node")" "$(chain_node_type_label "$(jq -r '.type' <<<"$node")")" "$(jq -r '.server' <<<"$node")" "$(jq -r '.port' <<<"$node")"
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

chain_node_recommended_test_family() {
    local node="$1" server=""
    local has4=0 has6=0

    server=$(jq -r '.server // empty' <<<"$node")
    [[ -n "$server" ]] || {
        echo "unknown"
        return
    }

    # IPv6 字面量（ss:// 中解析后通常已去掉 []）
    if [[ "$server" == *:* ]]; then
        echo "ipv6"
        return
    fi

    # IPv4 字面量
    if [[ "$server" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo "ipv4"
        return
    fi

    # 域名：分别检查 A / AAAA。
    if command -v getent >/dev/null 2>&1; then
        getent ahostsv4 "$server" >/dev/null 2>&1 && has4=1
        getent ahostsv6 "$server" >/dev/null 2>&1 && has6=1

        if [[ $has4 -eq 1 && $has6 -eq 1 ]]; then
            echo "dual"
            return
        fi
        if [[ $has4 -eq 1 ]]; then
            echo "ipv4"
            return
        fi
        if [[ $has6 -eq 1 ]]; then
            echo "ipv6"
            return
        fi
    fi

    echo "unknown"
}

chain_node_effective_connect_family() {
    local node="$1" detected
    detected=$(chain_node_recommended_test_family "$node")

    case "$detected" in
        ipv4|ipv6)
            echo "$detected"
            ;;
        dual)
            # 双栈落地优先使用 VPS 原生地址族。
            # 原生 IPv4 优先于 WARP 补充 IPv6，避免 Go/AsIs 优先 AAAA 后超时。
            if warp_direct_ipv4_ready; then
                echo "ipv4"
            elif warp_direct_ipv6_ready; then
                echo "ipv6"
            elif warp_proxy_ready && warp_family_allowed ipv4 && warp_test_family ipv4 >/dev/null 2>&1; then
                echo "ipv4"
            elif warp_proxy_ready && warp_family_allowed ipv6 && warp_test_family ipv6 >/dev/null 2>&1; then
                echo "ipv6"
            else
                echo "default"
            fi
            ;;
        *)
            echo "default"
            ;;
    esac
}

chain_node_xray_server_strategy() {
    local family
    family=$(chain_node_effective_connect_family "$1")
    case "$family" in
        ipv4) echo "ForceIPv4" ;;
        ipv6) echo "ForceIPv6" ;;
        *) echo "AsIs" ;;
    esac
}

chain_node_singbox_domain_strategy() {
    local family
    family=$(chain_node_effective_connect_family "$1")
    case "$family" in
        ipv4) echo "ipv4_only" ;;
        ipv6) echo "ipv6_only" ;;
        *) echo "" ;;
    esac
}

chain_node_needs_warp_underlay() {
    local node="$1" family
    family=$(chain_node_effective_connect_family "$node")
    case "$family" in
        ipv6)
            warp_direct_ipv6_ready && return 1
            warp_proxy_ready && warp_family_allowed ipv6 && warp_test_family ipv6 >/dev/null 2>&1
            ;;
        ipv4)
            warp_direct_ipv4_ready && return 1
            warp_proxy_ready && warp_family_allowed ipv4 && warp_test_family ipv4 >/dev/null 2>&1
            ;;
        *) return 1 ;;
    esac
}

curl_chain_test_via_local_socks() {
    local port="$1" family="$2" primary="$3" fallback endpoint out
    case "$family" in
        ipv4) fallback="https://4.ident.me" ;;
        ipv6) fallback="https://6.ident.me" ;;
        dual|unknown|*) fallback="https://ident.me" ;;
    esac
    : > /tmp/ss2022-chain-curl.err
    for endpoint in "$primary" "$fallback"; do
        printf '[%s]\n' "$endpoint" >> /tmp/ss2022-chain-curl.err
        if out=$(curl -fsS --connect-timeout 8 --max-time 15 \
            --socks5-hostname "127.0.0.1:${port}" "$endpoint" \
            2>>/tmp/ss2022-chain-curl.err); then
            printf '%s\n' "$out"
            return 0
        fi
    done
    return 1
}

test_shadowsocks_node_with_singbox() {
    local node="$1" family="${2:-default}" port cfg pid out rc=1 n=19080 url warp_port use_warp=false sb_ds
    url=$(ip_echo_url_for_family "$family")
    sb_ds=$(chain_node_singbox_domain_strategy "$node")
    [[ -x "$SINGBOX_BIN" ]] || { echo -e "${YELLOW}[提示] 未安装 sing-box，无法执行 Shadowsocks 落地实连测试。${PLAIN}"; return 1; }
    chain_node_needs_warp_underlay "$node" && use_warp=true
    while ss -H -ltn 2>/dev/null | grep -q ":${n} "; do n=$((n+1)); [[ $n -lt 19150 ]] || return 1; done
    port=$n
    cfg=$(mktemp /tmp/ss2022-chain-test.XXXXXX.json) || return 1
    if [[ "$use_warp" == true ]]; then
        warp_port=$(warp_proxy_port)
        jq -n --arg server "$(jq -r '.server' <<<"$node")" --argjson sport "$(jq -r '.port' <<<"$node")" --arg method "$(jq -r '.method' <<<"$node")" --arg pass "$(jq -r '.password' <<<"$node")" --argjson lp "$port" --argjson wp "$warp_port" --arg ds "$sb_ds" \
          '{log:{level:"warn"},inbounds:[{type:"socks",tag:"test-in",listen:"127.0.0.1",listen_port:$lp}],outbounds:[{type:"socks",tag:"test-warp",server:"127.0.0.1",server_port:$wp},({type:"shadowsocks",tag:"test-out",server:$server,server_port:$sport,method:$method,password:$pass,detour:"test-warp"} + (if $ds!="" then {domain_strategy:$ds} else {} end))],route:{final:"test-out"}}' > "$cfg"
        echo -e "${YELLOW}节点接入链路: WARP（VPS 缺少该地址族的原生出口）${PLAIN}"
    else
        jq -n --arg server "$(jq -r '.server' <<<"$node")" --argjson sport "$(jq -r '.port' <<<"$node")" --arg method "$(jq -r '.method' <<<"$node")" --arg pass "$(jq -r '.password' <<<"$node")" --argjson lp "$port" --arg ds "$sb_ds" \
          '{log:{level:"warn"},inbounds:[{type:"socks",tag:"test-in",listen:"127.0.0.1",listen_port:$lp}],outbounds:[({type:"shadowsocks",tag:"test-out",server:$server,server_port:$sport,method:$method,password:$pass} + (if $ds!="" then {domain_strategy:$ds} else {} end))],route:{final:"test-out"}}' > "$cfg"
    fi
    "$SINGBOX_BIN" check -c "$cfg" >/dev/null 2>&1 || { rm -f "$cfg"; return 1; }
    "$SINGBOX_BIN" run -c "$cfg" >/tmp/ss2022-chain-test.log 2>&1 & pid=$!
    sleep 1
    out=$(curl_chain_test_via_local_socks "$port" "$family" "$url") && rc=0
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" 2>/dev/null || true
    rm -f "$cfg"
    if [[ $rc -eq 0 ]]; then
        echo -e "${GREEN}✔ 落地节点可用，出口 IP: ${out}${PLAIN}"
        return 0
    fi
    echo -e "${RED}[错误] Shadowsocks 落地节点测试失败。${PLAIN}"
    [[ -s /tmp/ss2022-chain-curl.err ]] && { echo "curl:"; tail -n 3 /tmp/ss2022-chain-curl.err; }
    tail -n 10 /tmp/ss2022-chain-test.log 2>/dev/null || true
    return 1
}

test_shadowsocks_node_with_xray() {
    local node="$1" family="${2:-default}" port cfg pid out rc=1 n=19180 url method strategy="AsIs" server_strategy warp_port use_warp=false
    url=$(ip_echo_url_for_family "$family")
    server_strategy=$(chain_node_xray_server_strategy "$node")
    [[ -x "$XRAY_BIN" ]] || { echo -e "${YELLOW}[提示] 未安装 Xray，无法使用 Xray 执行 Shadowsocks 落地实连测试。${PLAIN}"; return 1; }
    method=$(jq -r '.method' <<<"$node")
    xray_supports_ss_method "$method" || { echo -e "${YELLOW}[提示] Xray 不原生支持 ${method}，应改由 sing-box 测试。${PLAIN}"; return 1; }
    [[ "$family" == "ipv4" ]] && strategy="ForceIPv4"
    [[ "$family" == "ipv6" ]] && strategy="ForceIPv6"
    chain_node_needs_warp_underlay "$node" && use_warp=true
    while ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)${n}$"; do n=$((n+1)); [[ $n -lt 19250 ]] || return 1; done
    port=$n
    cfg=$(mktemp /tmp/ss2022-xray-chain-test.XXXXXX.json) || return 1
    if [[ "$use_warp" == true ]]; then
        warp_port=$(warp_proxy_port)
        jq -n --arg server "$(jq -r '.server' <<<"$node")" --argjson sport "$(jq -r '.port' <<<"$node")" --arg method "$method" --arg pass "$(jq -r '.password' <<<"$node")" --argjson lp "$port" --argjson wp "$warp_port" --arg ts "$strategy" --arg ss "$server_strategy" '{
          log:{loglevel:"warning"},
          inbounds:[{listen:"127.0.0.1",port:$lp,protocol:"socks",tag:"test-in",settings:{auth:"noauth",udp:true}}],
          outbounds:[
            {protocol:"socks",tag:"test-warp",settings:{address:"127.0.0.1",port:$wp}},
            {protocol:"shadowsocks",tag:"test-out",targetStrategy:$ts,settings:{address:$server,port:$sport,method:$method,password:$pass},streamSettings:{sockopt:{dialerProxy:"test-warp",domainStrategy:$ss}}}
          ],
          routing:{rules:[{type:"field",inboundTag:["test-in"],outboundTag:"test-out"}]}
        }' > "$cfg"
        echo -e "${YELLOW}节点接入链路: WARP（VPS 缺少该地址族的原生出口）${PLAIN}"
    else
        jq -n --arg server "$(jq -r '.server' <<<"$node")" --argjson sport "$(jq -r '.port' <<<"$node")" --arg method "$method" --arg pass "$(jq -r '.password' <<<"$node")" --argjson lp "$port" --arg ts "$strategy" --arg ss "$server_strategy" '{
          log:{loglevel:"warning"},
          inbounds:[{listen:"127.0.0.1",port:$lp,protocol:"socks",tag:"test-in",settings:{auth:"noauth",udp:true}}],
          outbounds:[{protocol:"shadowsocks",tag:"test-out",targetStrategy:$ts,settings:{address:$server,port:$sport,method:$method,password:$pass},streamSettings:{sockopt:{domainStrategy:$ss}}}],
          routing:{rules:[{type:"field",inboundTag:["test-in"],outboundTag:"test-out"}]}
        }' > "$cfg"
    fi
    "$XRAY_BIN" run -test -format json -config "$cfg" >/dev/null 2>&1 || { rm -f "$cfg"; return 1; }
    "$XRAY_BIN" run -format json -config "$cfg" >/tmp/ss2022-xray-chain-test.log 2>&1 & pid=$!
    sleep 1
    out=$(curl_chain_test_via_local_socks "$port" "$family" "$url") && rc=0
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" 2>/dev/null || true
    rm -f "$cfg"
    if [[ $rc -eq 0 ]]; then
        echo -e "${GREEN}✔ 落地节点可用，出口 IP: ${out}${PLAIN}"
        return 0
    fi
    echo -e "${RED}[错误] Shadowsocks 落地节点测试失败。${PLAIN}"
    [[ -s /tmp/ss2022-chain-curl.err ]] && { echo "curl:"; tail -n 3 /tmp/ss2022-chain-curl.err; }
    tail -n 10 /tmp/ss2022-xray-chain-test.log 2>/dev/null || true
    return 1
}

test_shadowsocks_node_auto() {
    local node="$1" family="${2:-default}" method
    method=$(jq -r '.method' <<<"$node")

    # 能由 Xray 原生处理时优先用 Xray 测试，和 VLESS 实际链式路径保持一致。
    if [[ -x "$XRAY_BIN" ]] && xray_supports_ss_method "$method"; then
        test_shadowsocks_node_with_xray "$node" "$family"
        return $?
    fi
    if [[ -x "$SINGBOX_BIN" ]]; then
        test_shadowsocks_node_with_singbox "$node" "$family"
        return $?
    fi

    echo -e "${YELLOW}[提示] 当前没有可用于 ${method} 的 Shadowsocks 核心。${PLAIN}"
    return 1
}

chain_test_node() {
    chain_select_id || return 1
    local node type server port user pass out family detected_family url
    node=$(jq -c --arg id "$SELECTED_NODE_ID" '.chain_nodes[]|select(.id==$id)' "$ROUTING_FILE")
    type=$(jq -r '.type' <<<"$node")
    detected_family=$(chain_node_recommended_test_family "$node")
    family=$(chain_node_effective_connect_family "$node")
    case "$family" in
        ipv4) url=$(ip_echo_url_for_family ipv4) ;;
        ipv6) url=$(ip_echo_url_for_family ipv6) ;;
        dual|unknown) url=$(ip_echo_url_for_family default) ;;
        *) family="unknown"; url=$(ip_echo_url_for_family default) ;;
    esac

    echo -e "${YELLOW}>> 测试 $(jq -r '.name' <<<"$node")...${PLAIN}"
    case "$detected_family" in
        ipv4) echo -e "检测地址族: ${CYAN}IPv4-only / IPv4 地址${PLAIN}，使用 IPv4 接入测试。" ;;
        ipv6) echo -e "检测地址族: ${CYAN}IPv6-only / IPv6 地址${PLAIN}，使用 IPv6 接入测试。" ;;
        dual)
            if [[ "$family" == "ipv4" ]]; then
                echo -e "检测地址族: ${CYAN}IPv4 + IPv6 双栈${PLAIN}，优先使用 IPv4 接入测试。"
            elif [[ "$family" == "ipv6" ]]; then
                echo -e "检测地址族: ${CYAN}IPv4 + IPv6 双栈${PLAIN}，优先使用 IPv6 接入测试。"
            else
                echo -e "检测地址族: ${CYAN}IPv4 + IPv6 双栈${PLAIN}，使用默认接入测试。"
            fi
            ;;
        unknown) echo -e "检测地址族: ${YELLOW}地址族无法确定${PLAIN}，使用默认接入测试。" ;;
    esac

    case "$type" in
        ss2022|shadowsocks)
            test_shadowsocks_node_auto "$node" "$family"
            ;;
        socks5)
            server=$(jq -r '.server' <<<"$node")
            port=$(jq -r '.port' <<<"$node")
            user=$(jq -r '.username // ""' <<<"$node")
            pass=$(jq -r '.password // ""' <<<"$node")
            if [[ -n "$user" ]]; then
                out=$(curl -fsS --connect-timeout 8 --max-time 15 \
                    --proxy-user "${user}:${pass}" \
                    --socks5-hostname "${server}:${port}" \
                    "$url" 2>/dev/null) || {
                        echo -e "${RED}[错误] SOCKS5 测试失败。${PLAIN}"
                        return 1
                    }
            else
                out=$(curl -fsS --connect-timeout 8 --max-time 15 \
                    --socks5-hostname "${server}:${port}" \
                    "$url" 2>/dev/null) || {
                        echo -e "${RED}[错误] SOCKS5 测试失败。${PLAIN}"
                        return 1
                    }
            fi
            echo -e "${GREEN}✔ 落地节点可用，出口 IP: ${out}${PLAIN}"
            ;;
        *)
            echo -e "${RED}[错误] 未知落地节点类型: ${type}${PLAIN}"
            return 1
            ;;
    esac
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
    local tmp label yes profile
    label=$(routing_outbound_label "$SELECTED_OUTBOUND")

    if [[ "$SELECTED_OUTBOUND" == "warp" ]]; then
        local warp_mode
        warp_mode=$(warp_effective_egress_family)
        if [[ "$warp_mode" == "ipv4_only" || "$warp_mode" == "ipv6_only" ]]; then
            echo -e "${RED}[错误] 当前 WARP 为“$(warp_egress_label "$warp_mode")”模式，不能设为全局默认出口。${PLAIN}"
            echo "请保持默认出口为 DIRECT，只在需要的分流规则中调用 WARP。"
            return 1
        fi
    fi

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
        echo -e "${CYAN}════════════════ 落地节点管理 ════════════════${PLAIN}"
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
                echo "  1. Shadowsocks（自动识别 SS2022 / 标准 SS）"
                echo "  2. SOCKS5"
                read -rp "节点类型 [1-2]: " t
                [[ "$t" == "1" ]] && chain_add_shadowsocks
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
            jq --argjson idx "$idx" --arg out "$SELECTED_OUTBOUND" '.rules[$idx].outbound=$out | .rules[$idx].family_only=false' "$ROUTING_FILE" > "$tmp" ;;
        2)
            SELECTED_OUTBOUND=$(jq -r ".rules[$idx].outbound" "$ROUTING_FILE")
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

routing_global_ip_family_management() {
    local c family tmp
    while true; do
        routing_init_state || return 1
        clear
        echo -e "${CYAN}════════════ 全局业务出口地址族 ════════════${PLAIN}"
        echo "当前模式: $(routing_ip_family_label "$(routing_global_ip_family)")"
        echo "说明: 仅控制 vps-bootstrap 承载的 SS2022 / ShadowTLS / VLESS 分流业务出口，不关闭系统网卡地址。"
        echo "应用单独指定 IPv4 / IPv6 时，应用规则优先于这里的全局模式。"
        echo ""
        echo "  1. 双栈 / 默认"
        echo "  2. 仅 IPv4"
        echo "  3. 仅 IPv6"
        echo "  0. 返回"
        read -rp "请选择 [0-3]: " c
        case "$c" in
            1) family="default" ;;
            2) family="ipv4" ;;
            3) family="ipv6" ;;
            0) return 0 ;;
            *) sleep 1; continue ;;
        esac

        if ! server_tool_ip_family_mode_allows "$family"; then
            echo -e "${RED}[冲突] 当前系统协议族关闭策略不允许使用 $(routing_ip_family_label "$family")。${PLAIN}"
            pause
            continue
        fi

        tmp=$(mktemp "${STATE_DIR}/routing.json.tmp.XXXXXX") || return 1
        jq --arg fam "$family" '.global_ip_family=$fam' "$ROUTING_FILE" > "$tmp" || { rm -f "$tmp"; return 1; }
        if routing_commit_state_candidate "$tmp"; then
            echo -e "${GREEN}✔ 全局业务出口地址族已设置为：$(routing_ip_family_label "$family")。${PLAIN}"
        else
            echo -e "${RED}[错误] 地址族配置应用失败，已恢复上一版配置。${PLAIN}"
        fi
        pause
    done
}

routing_app_family_rule_index() {
    local service="$1"
    jq -r --arg service "$service" '.rules | to_entries[]? | select(.value.service==$service) | .key' "$ROUTING_FILE" 2>/dev/null | head -n1
}

routing_app_family_list() {
    local service idx rule fam out i=1
    printf '%-4s %-22s %-28s %-12s\n' "序号" "应用 / 服务" "出口" "地址族"
    printf '%s\n' "----------------------------------------------------------------------------"
    for service in openai netflix youtube google telegram mytvsuper appletv tiktok; do
        idx=$(routing_app_family_rule_index "$service")
        if [[ -n "$idx" ]]; then
            rule=$(jq -c --argjson idx "$idx" '.rules[$idx]' "$ROUTING_FILE")
            fam=$(jq -r '.ip_family // "default"' <<<"$rule")
            out=$(jq -r '.outbound // "default"' <<<"$rule")
        else
            fam="default"
            out="default"
        fi
        printf '%-4s %-22s %-28s %-12s\n' "$i" "$(routing_service_name "$service")" "$(routing_outbound_label "$out")" "$(routing_ip_family_label "$fam")"
        i=$((i+1))
    done
}

routing_set_app_family() {
    local service="$1" family="$2" idx tmp id name rule family_only
    routing_init_state || return 1

    if ! server_tool_ip_family_mode_allows "$family"; then
        echo -e "${RED}[冲突] 当前系统协议族关闭策略不允许使用 $(routing_ip_family_label "$family")。${PLAIN}"
        return 1
    fi

    idx=$(routing_app_family_rule_index "$service")
    tmp=$(mktemp "${STATE_DIR}/routing.json.tmp.XXXXXX") || return 1

    if [[ -z "$idx" ]]; then
        if [[ "$family" == "default" ]]; then
            rm -f "$tmp"
            echo -e "${GREEN}✔ $(routing_service_name "$service") 已经跟随全局地址族。${PLAIN}"
            return 0
        fi
        id="r$(date +%s)${RANDOM}"
        name=$(routing_service_name "$service")
        rule=$(jq -nc --arg id "$id" --arg name "$name" --arg service "$service" --arg fam "$family" '{id:$id,name:$name,service:$service,custom_type:"",values:[],outbound:"default",ip_family:$fam,family_only:true}')
        jq --argjson r "$rule" '.rules += [$r]' "$ROUTING_FILE" > "$tmp" || { rm -f "$tmp"; return 1; }
    else
        family_only=$(jq -r --argjson idx "$idx" '.rules[$idx].family_only // false' "$ROUTING_FILE")
        if [[ "$family" == "default" && "$family_only" == "true" ]]; then
            jq --argjson idx "$idx" 'del(.rules[$idx])' "$ROUTING_FILE" > "$tmp" || { rm -f "$tmp"; return 1; }
        else
            jq --argjson idx "$idx" --arg fam "$family" '.rules[$idx].ip_family=$fam' "$ROUTING_FILE" > "$tmp" || { rm -f "$tmp"; return 1; }
        fi
    fi

    routing_commit_state_candidate "$tmp"
}

routing_app_family_test_one() {
    local service="$1" idx rule configured_family ref effective_family resolved_ref name rc4=1 rc6=1
    routing_init_state || return 1

    name=$(routing_service_name "$service")
    idx=$(routing_app_family_rule_index "$service")
    if [[ -n "$idx" ]]; then
        rule=$(jq -c --argjson idx "$idx" '.rules[$idx]' "$ROUTING_FILE")
        configured_family=$(jq -r '.ip_family // "default"' <<<"$rule")
        ref=$(jq -r '.outbound // "default"' <<<"$rule")
    else
        configured_family="default"
        ref="default"
    fi

    effective_family=$(routing_effective_family "$configured_family" "$ref")
    resolved_ref=$(routing_resolve_outbound_ref "$ref")

    echo ""
    echo -e "${CYAN}════════════ ${name} 地址族出口测试 ════════════${PLAIN}"
    echo "规则设置     : $(routing_ip_family_label "$configured_family")"
    echo "全局地址族   : $(routing_ip_family_label "$(routing_global_ip_family)")"
    echo "实际生效     : $(routing_ip_family_label "$effective_family")"
    echo "规则出口     : $(routing_outbound_label "$ref")"
    if [[ "$ref" == "default" ]]; then
        echo "实际出口     : $(routing_outbound_label "$resolved_ref")"
    fi
    echo ""

    if ! server_tool_ip_family_mode_allows "$effective_family"; then
        echo -e "${RED}[冲突] 当前系统协议族状态不允许使用 $(routing_ip_family_label "$effective_family")。${PLAIN}"
        return 1
    fi

    case "$effective_family" in
        ipv4)
            echo -e "${YELLOW}>> 正在通过该应用实际出口验证 IPv4...${PLAIN}"
            if routing_test_exit_ref "$ref" ipv4; then
                echo -e "${GREEN}✔ ${name}: IPv4 出口验证通过。${PLAIN}"
                return 0
            fi
            echo -e "${RED}✘ ${name}: 规则要求 IPv4，但 IPv4 出口验证失败。${PLAIN}"
            return 1
            ;;
        ipv6)
            echo -e "${YELLOW}>> 正在通过该应用实际出口验证 IPv6...${PLAIN}"
            if routing_test_exit_ref "$ref" ipv6; then
                echo -e "${GREEN}✔ ${name}: IPv6 出口验证通过。${PLAIN}"
                return 0
            fi
            echo -e "${RED}✘ ${name}: 规则要求 IPv6，但 IPv6 出口验证失败。${PLAIN}"
            return 1
            ;;
        *)
            echo -e "${YELLOW}当前未强制单一地址族，分别探测该出口的 IPv4 / IPv6。${PLAIN}"
            routing_test_exit_ref "$ref" ipv4 && rc4=0
            routing_test_exit_ref "$ref" ipv6 && rc6=0
            echo ""
            if [[ $rc4 -eq 0 && $rc6 -eq 0 ]]; then
                echo -e "${GREEN}✔ ${name}: 当前出口 IPv4 / IPv6 均可用。${PLAIN}"
                return 0
            elif [[ $rc4 -eq 0 ]]; then
                echo -e "${YELLOW}○ ${name}: 当前出口仅检测到 IPv4 可用；规则本身未强制地址族。${PLAIN}"
                return 0
            elif [[ $rc6 -eq 0 ]]; then
                echo -e "${YELLOW}○ ${name}: 当前出口仅检测到 IPv6 可用；规则本身未强制地址族。${PLAIN}"
                return 0
            fi
            echo -e "${RED}✘ ${name}: IPv4 / IPv6 出口均验证失败。${PLAIN}"
            return 1
            ;;
    esac
}

routing_app_family_management() {
    local c service family fc
    while true; do
        routing_init_state || return 1
        clear
        echo -e "${CYAN}════════════ 应用 IPv4 / IPv6 分流 ════════════${PLAIN}"
        echo "未单独指定的应用跟随全局业务出口地址族。"
        echo "已有分流规则会保留原出口，只修改其 IP 地址族；新建的地址族规则默认跟随全局默认出口。"
        echo ""
        routing_app_family_list
        echo ""
        echo "  9. 自定义域名 / IP（进入现有分流规则管理）"
        echo "  0. 返回"
        read -rp "请选择应用 [0-9]: " c
        case "$c" in
            1) service=openai ;; 2) service=netflix ;; 3) service=youtube ;; 4) service=google ;;
            5) service=telegram ;; 6) service=mytvsuper ;; 7) service=appletv ;; 8) service=tiktok ;;
            9) routing_rule_management; continue ;;
            0) return 0 ;;
            *) sleep 1; continue ;;
        esac

        echo ""
        echo "$(routing_service_name "$service") 地址族："
        echo "  1. 默认（跟随全局）"
        echo "  2. 仅 IPv4"
        echo "  3. 仅 IPv6"
        echo "  4. 测试当前地址族出口"
        echo "  0. 取消"
        read -rp "请选择 [0-4]: " fc
        case "$fc" in
            1) family=default ;;
            2) family=ipv4 ;;
            3) family=ipv6 ;;
            4)
                routing_app_family_test_one "$service" || true
                pause
                continue
                ;;
            0) continue ;;
            *) continue ;;
        esac
        if routing_set_app_family "$service" "$family"; then
            echo -e "${GREEN}✔ $(routing_service_name "$service") 地址族已设置为：$(routing_ip_family_label "$family")。${PLAIN}"
        fi
        pause
    done
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
    echo "  地址族: $(routing_ip_family_label "$(routing_global_ip_family)")"
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
    local ref="$1" family="${2:-default}" label out="" rc=1 url requested_ref
    requested_ref="$ref"
    ref=$(routing_resolve_outbound_ref "$ref")
    if [[ "$requested_ref" == "default" ]]; then
        label="DEFAULT → $(routing_outbound_label "$ref")"
    else
        label=$(routing_outbound_label "$ref")
    fi
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
        case "$type" in
            socks5)
                server=$(jq -r '.server' <<<"$node"); sport=$(jq -r '.port' <<<"$node"); user=$(jq -r '.username // ""' <<<"$node"); pass=$(jq -r '.password // ""' <<<"$node")
                if [[ -n "$user" ]]; then out=$(curl -fsS --connect-timeout 8 --max-time 15 --proxy-user "${user}:${pass}" --socks5-hostname "${server}:${sport}" "$url" 2>/dev/null) && rc=0
                else out=$(curl -fsS --connect-timeout 8 --max-time 15 --socks5-hostname "${server}:${sport}" "$url" 2>/dev/null) && rc=0; fi
                ;;
            ss2022|shadowsocks)
                test_shadowsocks_node_auto "$node" "$family" && return 0 || return 1
                ;;
            *)
                return 1
                ;;
        esac
    fi
    if [[ $rc -eq 0 ]]; then echo -e "${GREEN}✔ ${label} / ${family}: ${out}${PLAIN}"; return 0; fi
    echo -e "${RED}✘ ${label} / ${family}: 测试失败${PLAIN}"; return 1
}

routing_test_effect() {
    routing_init_state || return 1
    echo -e "${CYAN}════════════════ 基础出口测试 ════════════════${PLAIN}"
    routing_test_exit_ref direct ipv4 || true
    if ip -6 route show default 2>/dev/null | grep -q default; then routing_test_exit_ref direct ipv6 || true; fi
    if warp_proxy_ready; then
        routing_test_exit_ref warp ipv4 || true
        routing_test_exit_ref warp ipv6 || true
    fi
    local count i id rule_count r ref fam key tested='|' node
    count=$(jq '.chain_nodes|length' "$ROUTING_FILE")
    i=0
    while [[ $i -lt $count ]]; do
        id=$(jq -r ".chain_nodes[$i].id" "$ROUTING_FILE")
        node=$(jq -c ".chain_nodes[$i]" "$ROUTING_FILE")
        fam=$(chain_node_effective_connect_family "$node")
        routing_test_exit_ref "chain:${id}" "$fam" || true
        i=$((i+1))
    done

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
            fam=$(routing_effective_family "$(jq -r '.ip_family // "default"' <<<"$r")" "$ref")
            key="${ref}@${fam}"
            echo "$(jq -r '.name' <<<"$r") → $(routing_outbound_label "$ref") / $(routing_ip_family_label "$fam")"
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
    echo -e "${YELLOW}WARP Local Proxy 为应用层代理；当前实现不保证 QUIC/UDP 经 WARP 分流。${PLAIN}"
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
        echo "地址族   : $(routing_ip_family_label "$(routing_global_ip_family)")"
        if [[ "$warp_state" == "Running" ]]; then
            warp_detect_direct_profile
            echo "WARP     : ${warp_state} / $(warp_profile_label "$WARP_PROFILE")"
        else
            echo "WARP     : ${warp_state}"
        fi
        echo "落地节点 : ${count} 个"
        echo "规则     : ${rules} 条"
        echo ""
        echo "  1. WARP 出口管理"
        echo "  2. 落地节点管理"
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
# [10] Realm L4 端口转发
# ==============================================================================

ensure_realm_user() {
    ensure_managed_system_user "$REALM_USER" "$REALM_GROUP" "$REALM_USER_MARKER" "$REALM_GROUP_MARKER"
}
write_realm_service() {
    ensure_realm_user || return 1
    mkdir -p "$(dirname "$REALM_CONF")" "$(dirname "$REALM_BIN")" || return 1
    if [[ "$PLATFORM_INIT" == "systemd" ]]; then
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
        service_daemon_reload || return 1
        return 0
    fi
    mkdir -p /var/log/ss2022 || return 1
    touch "$REALM_OPENRC_LOG" || return 1
    chown "$REALM_USER:$REALM_GROUP" "$REALM_OPENRC_LOG" || return 1
    chmod 640 "$REALM_OPENRC_LOG"
    cat > "$REALM_OPENRC_SERVICE" <<SERVICE
#!/sbin/openrc-run
description="vps-bootstrap Realm L4 forwarding"
command="$REALM_BIN"
command_args="-c $REALM_CONF"
command_user="$REALM_USER:$REALM_GROUP"
supervisor="supervise-daemon"
pidfile="$REALM_OPENRC_PID"
output_log="$REALM_OPENRC_LOG"
error_log="$REALM_OPENRC_LOG"
respawn_delay=3
respawn_max=0
umask=0077

depend() {
    need net
    use dns
}
SERVICE
    chmod 755 "$REALM_OPENRC_SERVICE"
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
    tmp=$(mktemp /tmp/ss2022-realm-meta.XXXXXX) || return 1

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

    archive="/tmp/ss2022-${asset}"
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

    tmpdir=$(mktemp -d /tmp/ss2022-realm-install.XXXXXX) || { rm -f "$archive"; return 1; }
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

    if platform_is_alpine; then
        command -v setcap >/dev/null 2>&1 || { echo -e "${RED}[错误] Alpine 缺少 setcap。${PLAIN}"; return 1; }
        setcap cap_net_bind_service=+ep "$REALM_BIN" || { echo -e "${RED}[错误] 无法为 Realm 设置低端口 capability。${PLAIN}"; return 1; }
        "$REALM_BIN" --version >/dev/null 2>&1 || { echo -e "${RED}[错误] Realm 设置 capability 后无法执行。${PLAIN}"; return 1; }
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
    allowed_pid=$(service_main_pid "$REALM_SERVICE_NAME" 2>/dev/null || true)
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
    chown root:"$REALM_GROUP" "$REALM_CONF"
    chmod 640 "$REALM_CONF"

    if [[ "$new_count" -eq 0 ]]; then
        service_disable_now "$REALM_SERVICE_NAME"
        rm -f "$state_backup" "$cfg_backup"
        echo -e "${GREEN}✔ Realm 转发规则已清空，服务已停止。${PLAIN}"
        return 0
    fi

    service_daemon_reload || true
    service_enable "$REALM_SERVICE_NAME" >/dev/null 2>&1 || true
    if service_restart "$REALM_SERVICE_NAME" && sleep 1 && service_is_active "$REALM_SERVICE_NAME"; then
        rm -f "$state_backup" "$cfg_backup"
        echo -e "${GREEN}✔ Realm 转发配置已应用。${PLAIN}"
        return 0
    fi

    echo -e "${RED}[错误] Realm 新配置启动失败，正在恢复旧配置和旧规则...${PLAIN}"
    mv -f "$state_backup" "$FORWARDING_FILE"
    if [[ -n "$cfg_backup" && -f "$cfg_backup" ]]; then
        mv -f "$cfg_backup" "$REALM_CONF"
        chown root:"$REALM_GROUP" "$REALM_CONF" 2>/dev/null || true
        chmod 640 "$REALM_CONF"
    else
        rm -f "$REALM_CONF"
    fi
    if [[ "$old_count" -gt 0 ]]; then
        service_restart "$REALM_SERVICE_NAME" >/dev/null 2>&1 || true
    else
        service_disable_now "$REALM_SERVICE_NAME"
    fi
    service_log_tail "$REALM_SERVICE_NAME" 30 || true
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
    if service_is_active "$REALM_SERVICE_NAME"; then
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
    case "$PLATFORM_INIT" in
        systemd) echo "服务管理     : systemd (${REALM_SERVICE_NAME}.service)" ;;
        openrc) echo "服务管理     : OpenRC (${REALM_OPENRC_SERVICE})" ;;
        *) echo "服务管理     : 未知" ;;
    esac
}

uninstall_realm_forwarding() {
    local yes=""
    echo -e "${YELLOW}此操作只删除 ss2022.sh 管理的 Realm 转发组件和 forwarding.json；不会删除服务器已有 realm.service 或 /usr/local/bin/realm。${PLAIN}"
    read -rp "确认卸载 Realm 转发组件？[y/N]: " yes
    [[ "$yes" =~ ^[Yy]$ ]] || return
    service_disable_now "$REALM_SERVICE_NAME"
    rm -f "$REALM_SERVICE" "$REALM_OPENRC_SERVICE" "$REALM_BIN" "$FORWARDING_FILE" "$REALM_OPENRC_PID" "$REALM_OPENRC_LOG"
    rm -rf /etc/ss2022-realm
    if [[ -f "$REALM_USER_MARKER" ]]; then
        delete_system_user "$REALM_USER"
        rm -f "$REALM_USER_MARKER"
    fi
    if [[ -f "$REALM_GROUP_MARKER" ]]; then
        delete_system_group "$REALM_GROUP"
        rm -f "$REALM_GROUP_MARKER"
    fi
    service_daemon_reload || true
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
        read -rp "请选择 [0-8]: " c
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
            2) service_status_output "$REALM_SERVICE_NAME" || echo "未运行"; pause ;;
            3) service_log_follow "$REALM_SERVICE_NAME" ;;
            4) service_restart "$REALM_SERVICE_NAME" && echo "已重启" || service_log_tail "$REALM_SERVICE_NAME" 30; pause ;;
            5) service_stop "$REALM_SERVICE_NAME" && echo "已停止"; pause ;;
            6) service_start "$REALM_SERVICE_NAME" && echo "已启动" || service_log_tail "$REALM_SERVICE_NAME" 30; pause ;;
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
            if service_is_active "$REALM_SERVICE_NAME"; then state="Running"; else state="Stopped"; fi
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
        read -rp "请选择 [0-10]: " c
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

# ==============================================================================
# [11] 服务运维与彻底卸载
# ==============================================================================

show_service_status() {
    echo ""
    echo -e "$YELLOW【sing-box】$PLAIN"
    service_status_output sing-box | head -n 15 || echo "未安装/未加载"
    echo ""
    echo -e "$YELLOW【ss2022-xray / VLESS Reality】$PLAIN"
    service_status_output "$XRAY_SERVICE_NAME" | head -n 15 || echo "未安装/未加载"
    echo ""
    echo -e "$YELLOW【Snell v5】$PLAIN"
    service_status_output snell-v5 | head -n 15 || echo "未安装/未加载"
    echo ""
    echo -e "$YELLOW【Realm 端口转发】$PLAIN"
    service_status_output "$REALM_SERVICE_NAME" | head -n 15 || echo "未安装/未加载"
    echo ""
    echo -e "$YELLOW【监听端口】$PLAIN"
    ss -lntup 2>/dev/null | grep -E 'sing-box|xray|snell-server|ss2022-realm|realm' || echo "未检测到相关监听"
}
full_uninstall() {
    local yes="" singbox_managed=0 snell_managed=0 proxy_link_managed=0
    local warp_package_managed=0 warp_repo_managed=0
    singbox_is_project_managed && singbox_managed=1 || true
    snell_is_project_managed && snell_managed=1 || true
    proxy_shortcut_is_project_managed && proxy_link_managed=1 || true
    warp_package_is_project_managed && warp_package_managed=1 || true
    warp_repo_is_project_managed && warp_repo_managed=1 || true
    echo -e "${RED}========== 完全卸载 ss2022.sh ==========${PLAIN}"
    echo ""
    echo -e "${RED}此操作会删除本脚本管理的协议核心、节点/分流/端口转发配置与服务。不会删除服务器原有 xray.service 或 realm.service。${PLAIN}"
    echo -e "${YELLOW}[保留] 服务器工具中由你主动设置的 BBR、DNS、SSH 端口和 IPv4/IPv6 地址优先级不会自动回滚。${PLAIN}"
    echo -e "${YELLOW}[说明] 这些属于服务器系统设置；自动恢复可能改变网络或 SSH 可达性，需要时请在卸载前通过对应菜单手动恢复。${PLAIN}"
    echo ""
    read -rp "确认彻底卸载？请输入 DELETE: " yes
    [[ "$yes" == "DELETE" ]] || { echo "已取消。"; sleep 1; return; }

    if [[ "$PLATFORM_INIT" == "systemd" ]]; then
        [[ $singbox_managed -eq 1 ]] && systemctl disable --now sing-box >/dev/null 2>&1 || true
        [[ $snell_managed -eq 1 ]] && systemctl disable --now snell-v5 >/dev/null 2>&1 || true
        systemctl disable --now "$XRAY_SERVICE_NAME" "$REALM_SERVICE_NAME" "${IPV6_KEEPALIVE_SYSTEMD_SERVICE_NAME}.timer" >/dev/null 2>&1 || true
        systemctl disable --now "$IP_FAMILY_SERVICE_NAME" ss2022-tg-monitor.timer >/dev/null 2>&1 || true
        systemctl stop "${IPV6_KEEPALIVE_SYSTEMD_SERVICE_NAME}.service" ss2022-tg-monitor.service >/dev/null 2>&1 || true
        cleanup_legacy_ipv6_keepalive_if_managed
    else
        [[ $singbox_managed -eq 1 ]] && service_disable_now sing-box
        service_disable_now "$XRAY_SERVICE_NAME"
        [[ $snell_managed -eq 1 ]] && service_disable_now snell-v5
        service_disable_now "$REALM_SERVICE_NAME"
        service_disable_now "$IP_FAMILY_SERVICE_NAME"
        service_disable_now ss2022-ipv6-keepalive
    fi

    command -v nft >/dev/null 2>&1 && nft delete table inet ss2022_ip_family >/dev/null 2>&1 || true

    if [[ $singbox_managed -eq 1 ]] && platform_is_alpine && [[ -f "$SINGBOX_ALPINE_PKG_MARKER" ]]; then
        apk del sing-box >/dev/null 2>&1 || true
        rm -f "$SINGBOX_ALPINE_PKG_MARKER"
    fi

    if [[ $warp_package_managed -eq 1 || $warp_repo_managed -eq 1 ]]; then
        if command -v warp-cli >/dev/null 2>&1; then
            warp-cli --accept-tos disconnect >/dev/null 2>&1 || true
            [[ $warp_package_managed -eq 1 ]] && warp-cli --accept-tos registration delete >/dev/null 2>&1 || true
        fi
        warp_remove_managed_install_assets
    fi

    if [[ $singbox_managed -eq 1 ]]; then
        rm -f "$SINGBOX_CONF" "${SINGBOX_CONF_DIR}"/.ss2022-*
        rm -f "$SINGBOX_BIN" "$SINGBOX_SERVICE" "$SINGBOX_OPENRC_SERVICE" "$SINGBOX_MANAGED_MARKER"
        if [[ -f "$SINGBOX_DIR_MARKER" ]]; then
            rmdir "$SINGBOX_CONF_DIR" 2>/dev/null || true
            rm -f "$SINGBOX_DIR_MARKER"
        fi
    fi
    if [[ $snell_managed -eq 1 ]]; then
        rm -f "$SNELL_CONF" "${SNELL_CONF_DIR}"/.ss2022-*
        rm -f "$SNELL_BIN" "$SNELL_SERVICE" "$SNELL_OPENRC_SERVICE" "$SNELL_MANAGED_MARKER"
        if [[ -f "$SNELL_DIR_MARKER" ]]; then
            rmdir "$SNELL_CONF_DIR" 2>/dev/null || true
            rm -f "$SNELL_DIR_MARKER"
        fi
    fi
    rm -rf /etc/ss2022-xray /etc/ss2022-realm "$STATE_DIR" /usr/local/lib/ss2022 /var/log/ss2022

    [[ $proxy_link_managed -eq 1 ]] && rm -f "$SCRIPT_PROXY_LINK"
    rm -f \
        "$SCRIPT_INSTALL_PATH" \
        "$SCRIPT_BACKUP_PATH" \
        "${SNELL_CANDIDATE_PREFIX}".* \
        "$XRAY_BIN" \
        "$XRAY_SERVICE" \
        "$REALM_SERVICE" \
        "$IP_FAMILY_SERVICE" \
        "$XRAY_OPENRC_SERVICE" \
        "$REALM_OPENRC_SERVICE" \
        "$IP_FAMILY_OPENRC_SERVICE" \
        "$IPV6_KEEPALIVE_OPENRC_SERVICE" \
        "$IPV6_KEEPALIVE_SYSTEMD_SERVICE" \
        "$IPV6_KEEPALIVE_SYSTEMD_TIMER" \
        "$TG_MONITOR_SERVICE" \
        "$TG_MONITOR_TIMER" \
        "$FORCE_IPV6_CONF"

    if [[ -f "$DNS_MARKER" || -f "$BACKUP_DNS" ]]; then
        if ! restore_ipv4_apt_and_dns_if_needed; then
            echo -e "${YELLOW}[提示] IPv6-only 临时 DNS 未能自动恢复；脚本专属备份会保留供手动恢复。${PLAIN}"
        fi
    fi
    rm -f "$DNS_MARKER"

    if [[ -f "$SINGBOX_USER_MARKER" ]]; then delete_system_user "$SINGBOX_USER"; rm -f "$SINGBOX_USER_MARKER"; fi
    if [[ -f "$SINGBOX_GROUP_MARKER" ]]; then delete_system_group "$SINGBOX_GROUP"; rm -f "$SINGBOX_GROUP_MARKER"; fi

    if [[ -f "$XRAY_USER_MARKER" ]]; then delete_system_user "$XRAY_USER"; rm -f "$XRAY_USER_MARKER"; fi
    if [[ -f "$XRAY_GROUP_MARKER" ]]; then delete_system_group "$XRAY_GROUP"; rm -f "$XRAY_GROUP_MARKER"; fi

    if [[ -f "$REALM_USER_MARKER" ]]; then delete_system_user "$REALM_USER"; rm -f "$REALM_USER_MARKER"; fi
    if [[ -f "$REALM_GROUP_MARKER" ]]; then delete_system_group "$REALM_GROUP"; rm -f "$REALM_GROUP_MARKER"; fi

    if [[ -f "$SNELL_USER_MARKER" ]]; then delete_system_user "$SNELL_USER"; rm -f "$SNELL_USER_MARKER"; fi
    if [[ -f "$SNELL_GROUP_MARKER" ]]; then delete_system_group "$SNELL_GROUP"; rm -f "$SNELL_GROUP_MARKER"; fi

    [[ -f "$TG_MONITOR_CRON_FILE" ]] && sed -i "/ss2022-tg-monitor/d" "$TG_MONITOR_CRON_FILE" 2>/dev/null || true
    rm -f "$SINGBOX_OPENRC_PID" "$XRAY_OPENRC_PID" "$SNELL_OPENRC_PID" "$REALM_OPENRC_PID"
    rm -rf /run/ss2022-tg-monitor.lockdir
    rm -rf /tmp/ss2022-* 2>/dev/null || true
    service_daemon_reload || true
    echo -e "${GREEN}✔ vps-bootstrap 协议核心、服务与运行文件已清理完成。${PLAIN}"
    echo -e "${YELLOW}[保留] BBR / DNS / SSH 端口 / IPv4-IPv6 地址优先级等用户主动系统设置保持当前状态。${PLAIN}"
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
    service_is_active "$svc" && old_active=1 || true

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
        service_daemon_reload >/dev/null 2>&1 || true
        if ! service_restart "$svc" >/dev/null 2>&1; then
            echo -e "${RED}[错误] ${label} 新版本启动失败，开始回滚。${PLAIN}"
            ok=0
        else
            sleep 1
            service_is_active "$svc" || ok=0
        fi
    fi

    if [[ $ok -ne 1 ]]; then
        if [[ $had_bin -eq 1 && -f "$tmp/old.bin" ]]; then
            install -m 755 "$tmp/old.bin" "$bin" || true
        elif [[ $had_bin -eq 0 ]]; then
            rm -f "$bin"
        fi
        service_daemon_reload >/dev/null 2>&1 || true
        [[ $old_active -eq 1 ]] && service_restart "$svc" >/dev/null 2>&1 || true
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
    echo "【协议核心】"
    printf '  sing-box      已安装: %-12s 推荐: %s\n' "$sb" "$SINGBOX_VERSION"
    printf '  Xray-core     已安装: %-12s 推荐: %s\n' "$xr" "$XRAY_VERSION"
    if platform_is_alpine; then
        printf '  Snell Server  已安装: %-12s 推荐: %s  [Alpine 暂不支持]\n' "$sn" "$SNELL_VERSION"
    else
        printf '  Snell Server  已安装: %-12s 推荐: %s\n' "$sn" "$SNELL_VERSION"
    fi
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
    if platform_is_alpine && [[ "$c" == "snell" ]]; then
        platform_feature_unavailable "Snell v5（Surge 官方 snell-server）"
        pause
        return
    fi
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
        if platform_is_alpine && [[ "$c" == "snell" ]]; then
            echo -e "${YELLOW}○ Snell Server：Alpine 3.21 暂不支持官方 snell-server，跳过。${PLAIN}"
            continue
        fi
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
        if platform_is_alpine; then
            echo "  3. Snell Server            [Alpine 暂不支持]"
        else
            echo "  3. Snell Server"
        fi
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

# ==============================================================================
# [13] 脚本自更新
# ==============================================================================

extract_script_version() {
    local file="$1"
    sed -n 's/^SCRIPT_VERSION="\([^"]*\)".*/\1/p' "$file" 2>/dev/null | head -n1
}

script_source_path() {
    local src="${BASH_SOURCE[0]}"
    readlink -f "$src" 2>/dev/null || printf '%s\n' "$src"
}

proxy_shortcut_is_project_managed() {
    local target=""
    [[ -L "$SCRIPT_PROXY_LINK" ]] || return 1
    target=$(readlink "$SCRIPT_PROXY_LINK" 2>/dev/null || true)
    [[ "$target" == "$SCRIPT_INSTALL_PATH" || "$target" == "${SCRIPT_INSTALL_PATH##*/}" ]]
}

ensure_proxy_shortcut() {
    if [[ -e "$SCRIPT_PROXY_LINK" || -L "$SCRIPT_PROXY_LINK" ]]; then
        if ! proxy_shortcut_is_project_managed; then
            echo -e "${YELLOW}[提示] ${SCRIPT_PROXY_LINK} 已被其它文件或链接占用，保留原内容；仍可使用 ${SCRIPT_INSTALL_PATH}。${PLAIN}"
            return 0
        fi
        rm -f "$SCRIPT_PROXY_LINK" || return 1
    fi
    ln -s "$SCRIPT_INSTALL_PATH" "$SCRIPT_PROXY_LINK"
}

compare_script_versions() {
    # 输出：
    #   equal         两版本相同
    #   remote_newer  第二个版本更新
    #   remote_older  第二个版本更旧
    #   unknown       无法按 vX.Y.Z[-devN] 规则比较
    local current="$1"
    local remote="$2"
    local c_major c_minor c_patch c_dev r_major r_minor r_patch r_dev
    local c_is_dev=0 r_is_dev=0

    if [[ "$current" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)(-dev([0-9]+))?$ ]]; then
        c_major="${BASH_REMATCH[1]}"
        c_minor="${BASH_REMATCH[2]}"
        c_patch="${BASH_REMATCH[3]}"
        if [[ -n "${BASH_REMATCH[4]:-}" ]]; then
            c_is_dev=1
            c_dev="${BASH_REMATCH[5]}"
        else
            c_dev=0
        fi
    else
        echo "unknown"
        return
    fi

    if [[ "$remote" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)(-dev([0-9]+))?$ ]]; then
        r_major="${BASH_REMATCH[1]}"
        r_minor="${BASH_REMATCH[2]}"
        r_patch="${BASH_REMATCH[3]}"
        if [[ -n "${BASH_REMATCH[4]:-}" ]]; then
            r_is_dev=1
            r_dev="${BASH_REMATCH[5]}"
        else
            r_dev=0
        fi
    else
        echo "unknown"
        return
    fi

    local c r
    for c_r in major minor patch; do
        case "$c_r" in
            major) c="$c_major"; r="$r_major" ;;
            minor) c="$c_minor"; r="$r_minor" ;;
            patch) c="$c_patch"; r="$r_patch" ;;
        esac
        if (( 10#$r > 10#$c )); then
            echo "remote_newer"
            return
        elif (( 10#$r < 10#$c )); then
            echo "remote_older"
            return
        fi
    done

    # 同一正式版本号下：正式版 > dev 版。
    if (( c_is_dev == 1 && r_is_dev == 0 )); then
        echo "remote_newer"
        return
    elif (( c_is_dev == 0 && r_is_dev == 1 )); then
        echo "remote_older"
        return
    elif (( c_is_dev == 0 && r_is_dev == 0 )); then
        echo "equal"
        return
    fi

    if (( 10#$r_dev > 10#$c_dev )); then
        echo "remote_newer"
    elif (( 10#$r_dev < 10#$c_dev )); then
        echo "remote_older"
    else
        echo "equal"
    fi
}

check_script_update() {
    clear
    echo -e "${CYAN}════════════════════ 检查脚本更新 ════════════════════${PLAIN}"
    echo "更新源 : ${SCRIPT_UPDATE_URL}"
    echo ""

    command -v curl >/dev/null 2>&1 || {
        echo -e "${RED}[错误] 未检测到 curl，无法检查更新。${PLAIN}"
        pause
        return
    }

    local tmp remote_version running_file running_version installed_version
    local running_hash installed_hash remote_hash cache_bust relation
    local install_reason=""
    local ans

    running_file=$(script_source_path)
    running_version=$(extract_script_version "$running_file")
    [[ -n "$running_version" ]] || running_version="$SCRIPT_VERSION"

    if [[ -f "$SCRIPT_INSTALL_PATH" ]]; then
        installed_version=$(extract_script_version "$SCRIPT_INSTALL_PATH")
        installed_hash=$(sha256sum "$SCRIPT_INSTALL_PATH" 2>/dev/null | awk '{print $1}')
    else
        installed_version="未安装"
        installed_hash=""
    fi

    running_hash=$(sha256sum "$running_file" 2>/dev/null | awk '{print $1}')

    tmp=$(mktemp /tmp/ss2022-update.XXXXXX.sh) || {
        echo -e "${RED}[错误] 无法创建临时文件。${PLAIN}"
        pause
        return
    }
    cache_bust=$(date +%s)

    echo -e "${YELLOW}>> 正在从 GitHub main 获取最新脚本...${PLAIN}"
    if ! curl -fsSL --retry 2 --retry-delay 1 --connect-timeout 8 --max-time 60 \
        -H 'Cache-Control: no-cache' \
        "${SCRIPT_UPDATE_URL}?t=${cache_bust}" -o "$tmp"; then
        rm -f "$tmp"
        echo -e "${RED}[错误] 下载 GitHub 最新脚本失败。${PLAIN}"
        pause
        return
    fi

    # 只接受本项目脚本，避免 URL / CDN 异常返回 HTML 或其它内容后被直接执行。
    if ! grep -q '^# 项目名称: vps-bootstrap / ss2022.sh$' "$tmp"; then
        rm -f "$tmp"
        echo -e "${RED}[错误] 下载内容不是有效的 vps-bootstrap/ss2022.sh，已拒绝更新。${PLAIN}"
        pause
        return
    fi
    if ! bash -n "$tmp"; then
        rm -f "$tmp"
        echo -e "${RED}[错误] GitHub 脚本未通过 Bash 语法检查，已拒绝更新。${PLAIN}"
        pause
        return
    fi

    remote_version=$(extract_script_version "$tmp")
    if [[ -z "$remote_version" ]]; then
        rm -f "$tmp"
        echo -e "${RED}[错误] 无法读取远程 SCRIPT_VERSION，已拒绝更新。${PLAIN}"
        pause
        return
    fi

    remote_hash=$(sha256sum "$tmp" | awk '{print $1}')
    relation=$(compare_script_versions "$running_version" "$remote_version")

    echo "当前运行 : ${running_version}"
    echo "系统安装 : ${installed_version}"
    echo "GitHub main: ${remote_version}"
    echo ""
    echo "运行 SHA : ${running_hash:-无法读取}"
    echo "安装 SHA : ${installed_hash:-未安装}"
    echo "远程 SHA : ${remote_hash}"
    echo ""

    # 情况 1：当前正在运行的文件与 GitHub main 完全一致。
    if [[ -n "$running_hash" && "$running_hash" == "$remote_hash" ]]; then
        if [[ -n "$installed_hash" && "$installed_hash" == "$remote_hash" ]]; then
            rm -f "$tmp"
            echo -e "${GREEN}✔ 当前运行脚本、系统安装脚本与 GitHub main 完全一致。${PLAIN}"
            pause
            return
        fi

        echo -e "${YELLOW}当前运行脚本已与 GitHub main 一致，但系统安装版本仍不一致。${PLAIN}"
        echo "可以把当前 GitHub main 版本同步安装到：${SCRIPT_INSTALL_PATH}"
        install_reason="sync_install"
    else
        case "$relation" in
            remote_newer)
                echo -e "${GREEN}检测到脚本更新：${running_version} → ${remote_version}${PLAIN}"
                install_reason="remote_newer"
                ;;
            remote_older)
                rm -f "$tmp"
                echo -e "${YELLOW}GitHub main 版本比当前运行版本更旧：${remote_version} < ${running_version}${PLAIN}"
                echo "为避免误降级，本工具不会自动覆盖当前版本。"
                echo ""
                echo "如果你刚从测试文件运行了新版，请先把新版 ss2022.sh 提交到 GitHub main，"
                echo "之后再使用“检查脚本更新”。"
                pause
                return
                ;;
            equal)
                echo -e "${YELLOW}检测到同版本号内容变化：${running_version}${PLAIN}"
                echo "版本号相同，但当前运行文件与 GitHub main 的 SHA256 不同。"
                install_reason="same_version_changed"
                ;;
            *)
                echo -e "${YELLOW}检测到脚本内容不同，但无法可靠判断版本新旧。${PLAIN}"
                echo "当前运行：${running_version}"
                echo "GitHub main：${remote_version}"
                echo "为避免误降级，默认不自动覆盖。"
                rm -f "$tmp"
                pause
                return
                ;;
        esac
    fi

    echo ""
    echo "更新将："
    echo "  1. 备份当前系统安装脚本到 ${SCRIPT_BACKUP_PATH}"
    echo "  2. 安装 GitHub main 脚本到 ${SCRIPT_INSTALL_PATH}"
    echo "  3. 若 ${SCRIPT_PROXY_LINK} 未被其它程序占用，则保持该快捷命令"
    echo "  4. 自动重新进入安装后的管理面板"
    echo ""

    read -rp "确认安装 / 更新？[y/N]: " ans
    if [[ ! "$ans" =~ ^[Yy]$ ]]; then
        rm -f "$tmp"
        echo "已取消更新。"
        pause
        return
    fi

    # 覆盖前保存最近一个系统安装版本。安装失败时立即恢复。
    if [[ -f "$SCRIPT_INSTALL_PATH" ]]; then
        cp -a "$SCRIPT_INSTALL_PATH" "$SCRIPT_BACKUP_PATH" || {
            rm -f "$tmp"
            echo -e "${RED}[错误] 无法备份当前脚本，已取消更新。${PLAIN}"
            pause
            return
        }
    fi

    if ! install -m 0755 "$tmp" "$SCRIPT_INSTALL_PATH"; then
        [[ -f "$SCRIPT_BACKUP_PATH" ]] && install -m 0755 "$SCRIPT_BACKUP_PATH" "$SCRIPT_INSTALL_PATH" 2>/dev/null || true
        rm -f "$tmp"
        echo -e "${RED}[错误] 新脚本安装失败，已尝试恢复旧版本。${PLAIN}"
        pause
        return
    fi
    rm -f "$tmp"

    if ! bash -n "$SCRIPT_INSTALL_PATH"; then
        echo -e "${RED}[错误] 安装后的脚本语法校验失败，正在恢复旧版本。${PLAIN}"
        [[ -f "$SCRIPT_BACKUP_PATH" ]] && install -m 0755 "$SCRIPT_BACKUP_PATH" "$SCRIPT_INSTALL_PATH" 2>/dev/null || true
        pause
        return
    fi

    ensure_proxy_shortcut || echo -e "${YELLOW}[提示] proxy 快捷命令创建失败，不影响 ss2022 主命令。${PLAIN}"
    echo -e "${GREEN}✔ 脚本安装 / 更新完成：$(extract_script_version "$SCRIPT_INSTALL_PATH")${PLAIN}"
    echo "正在重新进入安装后的管理面板..."
    sleep 1
    exec "$SCRIPT_INSTALL_PATH"
}

# ==============================================================================
# [14] 菜单与程序入口
# ==============================================================================

protocol_management() {
    while true; do
        clear
        echo -e "$CYAN════════════════════ 协议管理 ════════════════════$PLAIN"
        echo "  1. SS2022"
        echo "  2. SS2022 + ShadowTLS v3（增强伪装）"
        echo "  3. VLESS Reality"
        if platform_is_alpine; then
            echo "  4. Snell v5                [Alpine 暂不支持]"
        else
            echo "  4. Snell v5"
        fi
        echo "  0. 返回"
        echo -e "$CYAN═══════════════════════════════════════════════════$PLAIN"
        read -rp "请选择 [0-4]: " c
        case "$c" in
            1) protocol_action_menu "SS2022" deploy_ss2022 update_ss2022 delete_ss2022 ;;
            2) protocol_action_menu "SS2022 + ShadowTLS v3" deploy_shadowtls update_shadowtls delete_shadowtls ;;
            3) protocol_action_menu "VLESS Reality" deploy_vless_reality update_vless_reality delete_vless_reality ;;
            4)
                if platform_is_alpine; then
                    platform_feature_unavailable "Snell v5（Surge 官方 snell-server）"
                    pause
                else
                    protocol_action_menu "Snell v5" deploy_snell_v5 update_snell_v5 delete_snell_v5
                fi
                ;;
            0) return ;;
            *) sleep 1 ;;
        esac
    done
}
follow_service_log() {
    local service="$1"
    service_log_follow "$service"
}
restart_service_safe() {
    local service="$1" label="$2"
    if service_restart "$service"; then
        echo -e "$GREEN✔ $label 已重启。$PLAIN"
    else
        service_log_tail "$service" 30 || true
        return 1
    fi
}
server_tool_pkg_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v apk >/dev/null 2>&1; then
        echo "apk"
    else
        echo "unknown"
    fi
}

server_tool_get_ip_profile() {
    local ipv4="$1" ipv6="$2" target meta hosting proxy mobile org asn isp country region city location
    local scam_html score risk_label

    SERVER_INFO_IPV4="$ipv4"
    SERVER_INFO_IPV6="$ipv6"
    SERVER_INFO_IP_TYPE="未知"
    SERVER_INFO_IP_RISK="未获取"
    SERVER_INFO_ISP="未知"
    SERVER_INFO_ASN="未知"
    SERVER_INFO_LOCATION="未知"

    target="$ipv4"
    [[ -n "$target" ]] || target="$ipv6"
    [[ -n "$target" ]] || return 0

    # ip-api 免费接口用于轻量判定 hosting / proxy / mobile；查询失败时保持“未知”。
    meta=$(curl -fsS --connect-timeout 3 --max-time 5 \
        "http://ip-api.com/json/${target}?fields=status,message,country,regionName,city,isp,org,as,hosting,proxy,mobile,query" \
        2>/dev/null || true)

    if [[ -n "$meta" ]] && jq -e '.status=="success"' >/dev/null 2>&1 <<<"$meta"; then
        hosting=$(jq -r '.hosting // false' <<<"$meta")
        proxy=$(jq -r '.proxy // false' <<<"$meta")
        mobile=$(jq -r '.mobile // false' <<<"$meta")
        org=$(jq -r '.org // empty' <<<"$meta")
        isp=$(jq -r '.isp // empty' <<<"$meta")
        asn=$(jq -r '.as // empty' <<<"$meta")
        country=$(jq -r '.country // empty' <<<"$meta")
        region=$(jq -r '.regionName // empty' <<<"$meta")
        city=$(jq -r '.city // empty' <<<"$meta")

        SERVER_INFO_ISP="${isp:-${org:-未知}}"
        SERVER_INFO_ASN="${asn:-未知}"

        location=""
        [[ -n "$country" ]] && location="$country"
        [[ -n "$region" ]] && location="${location:+${location} / }${region}"
        [[ -n "$city" ]] && location="${location:+${location} / }${city}"
        SERVER_INFO_LOCATION="${location:-未知}"

        if [[ "$hosting" == "true" ]]; then
            SERVER_INFO_IP_TYPE="数据中心"
        elif [[ "$mobile" == "true" ]]; then
            SERVER_INFO_IP_TYPE="移动网络"
        elif [[ "$proxy" == "true" ]]; then
            SERVER_INFO_IP_TYPE="代理/VPN"
        else
            SERVER_INFO_IP_TYPE="宽带/其他"
        fi
    fi

    # Scamalytics 网页公开查询结果中包含 Fraud Score；失败时不影响系统信息展示。
    scam_html=$(curl -A "Mozilla/5.0" -fsSL --connect-timeout 3 --max-time 6 \
        "https://scamalytics.com/ip/${target}" 2>/dev/null || true)

    if [[ -n "$scam_html" ]]; then
        score=$(printf '%s' "$scam_html" \
            | tr '\n' ' ' \
            | grep -oE '"score"[[:space:]]*:[[:space:]]*"?[0-9]{1,3}"?' \
            | head -n1 \
            | grep -oE '[0-9]{1,3}' || true)

        if [[ -z "$score" ]]; then
            score=$(printf '%s' "$scam_html" \
                | tr '\n' ' ' \
                | sed -nE 's/.*Fraud Score:[[:space:]]*([0-9]{1,3}).*/\1/p' \
                | head -n1 || true)
        fi

        if [[ "$score" =~ ^[0-9]+$ ]] && [[ "$score" -le 100 ]]; then
            if [[ "$score" -le 19 ]]; then
                risk_label="低风险"
            elif [[ "$score" -le 59 ]]; then
                risk_label="中等风险"
            elif [[ "$score" -le 89 ]]; then
                risk_label="高风险"
            else
                risk_label="极高风险"
            fi
            SERVER_INFO_IP_RISK="${score}/100（${risk_label}）"
        fi
    fi
}

server_tool_format_bytes() {
    local bytes="${1:-0}"
    awk -v b="$bytes" 'BEGIN {
        if (b >= 1099511627776) printf "%.2f TB", b/1099511627776;
        else if (b >= 1073741824) printf "%.2f GB", b/1073741824;
        else if (b >= 1048576) printf "%.2f MB", b/1048576;
        else if (b >= 1024) printf "%.2f KB", b/1024;
        else printf "%.0f B", b;
    }'
}

server_tool_public_traffic_bytes() {
    local iface4 iface6 iface path rx tx
    local total_rx=0 total_tx=0
    local -A seen=()

    iface4=$(ip -4 route show default 2>/dev/null | awk '
        {
            for (i=1;i<=NF;i++) if ($i=="dev" && (i+1)<=NF) {print $(i+1); exit}
        }')
    iface6=$(ip -6 route show default 2>/dev/null | awk '
        {
            for (i=1;i<=NF;i++) if ($i=="dev" && (i+1)<=NF) {print $(i+1); exit}
        }')

    for iface in "$iface4" "$iface6"; do
        [[ -n "$iface" ]] || continue
        [[ -n "${seen[$iface]:-}" ]] && continue
        seen[$iface]=1
        path="/sys/class/net/${iface}/statistics"
        [[ -r "${path}/rx_bytes" && -r "${path}/tx_bytes" ]] || continue
        rx=$(cat "${path}/rx_bytes" 2>/dev/null || echo 0)
        tx=$(cat "${path}/tx_bytes" 2>/dev/null || echo 0)
        [[ "$rx" =~ ^[0-9]+$ ]] || rx=0
        [[ "$tx" =~ ^[0-9]+$ ]] || tx=0
        total_rx=$((total_rx + rx))
        total_tx=$((total_tx + tx))
    done

    # 极少数环境没有默认路由设备时，回退到常见公网接口。
    if [[ ${#seen[@]} -eq 0 ]]; then
        for path in /sys/class/net/*; do
            [[ -d "$path/statistics" ]] || continue
            iface=${path##*/}
            case "$iface" in
                lo|docker*|br-*|veth*|tun*|tap*|wg*|warp*|tailscale*) continue ;;
            esac
            [[ "$iface" =~ ^(eth|ens|enp|eno|venet|bond) ]] || continue
            rx=$(cat "$path/statistics/rx_bytes" 2>/dev/null || echo 0)
            tx=$(cat "$path/statistics/tx_bytes" 2>/dev/null || echo 0)
            [[ "$rx" =~ ^[0-9]+$ ]] || rx=0
            [[ "$tx" =~ ^[0-9]+$ ]] || tx=0
            total_rx=$((total_rx + rx))
            total_tx=$((total_tx + tx))
        done
    fi

    printf '%s %s\n' "$total_rx" "$total_tx"
}

server_tool_monthly_traffic_bytes() {
    local raw current_rx current_tx month
    local state_month="" last_rx=0 last_tx=0 total_rx=0 total_tx=0
    local tmp

    mkdir -p "$STATE_DIR" || {
        echo "0 0"
        return
    }
    chmod 700 "$STATE_DIR"

    raw=$(server_tool_public_traffic_bytes)
    current_rx=$(awk '{print $1}' <<<"$raw")
    current_tx=$(awk '{print $2}' <<<"$raw")
    [[ "$current_rx" =~ ^[0-9]+$ ]] || current_rx=0
    [[ "$current_tx" =~ ^[0-9]+$ ]] || current_tx=0

    month=$(date +%Y-%m)

    if [[ -f "$SYSTEM_INFO_TRAFFIC_STATE" ]]; then
        state_month=$(awk -F= '$1=="MONTH" {gsub(/\047/,"",$2); print $2}' "$SYSTEM_INFO_TRAFFIC_STATE" 2>/dev/null)
        last_rx=$(awk -F= '$1=="LAST_RX" {print $2}' "$SYSTEM_INFO_TRAFFIC_STATE" 2>/dev/null)
        last_tx=$(awk -F= '$1=="LAST_TX" {print $2}' "$SYSTEM_INFO_TRAFFIC_STATE" 2>/dev/null)
        total_rx=$(awk -F= '$1=="TOTAL_RX" {print $2}' "$SYSTEM_INFO_TRAFFIC_STATE" 2>/dev/null)
        total_tx=$(awk -F= '$1=="TOTAL_TX" {print $2}' "$SYSTEM_INFO_TRAFFIC_STATE" 2>/dev/null)
    fi

    [[ "$last_rx" =~ ^[0-9]+$ ]] || last_rx=0
    [[ "$last_tx" =~ ^[0-9]+$ ]] || last_tx=0
    [[ "$total_rx" =~ ^[0-9]+$ ]] || total_rx=0
    [[ "$total_tx" =~ ^[0-9]+$ ]] || total_tx=0

    if [[ "$state_month" != "$month" ]]; then
        # 新月份从当前时刻重新开始累计。
        state_month="$month"
        last_rx="$current_rx"
        last_tx="$current_tx"
        total_rx=0
        total_tx=0
    else
        if [[ "$current_rx" -ge "$last_rx" ]]; then
            total_rx=$((total_rx + current_rx - last_rx))
        else
            # VPS 重启或网卡计数归零：保留当月累计，并把当前值作为重启后的新增量。
            total_rx=$((total_rx + current_rx))
        fi

        if [[ "$current_tx" -ge "$last_tx" ]]; then
            total_tx=$((total_tx + current_tx - last_tx))
        else
            total_tx=$((total_tx + current_tx))
        fi

        last_rx="$current_rx"
        last_tx="$current_tx"
    fi

    tmp="${SYSTEM_INFO_TRAFFIC_STATE}.tmp.$$"
    umask 077
    cat > "$tmp" <<EOF
MONTH='${state_month}'
LAST_RX=${last_rx}
LAST_TX=${last_tx}
TOTAL_RX=${total_rx}
TOTAL_TX=${total_tx}
EOF
    mv -f "$tmp" "$SYSTEM_INFO_TRAFFIC_STATE"
    chmod 600 "$SYSTEM_INFO_TRAFFIC_STATE"

    printf '%s %s\n' "$total_rx" "$total_tx"
}

server_tool_system_info() {
    local cpu cores mem_total mem_used swap_total swap_used disk_used disk_total
    local uptime_days timezone dns congestion qdisc os_info ipv4 ipv6 hostname_text
    local cpu_mhz cpu_ghz traffic_rx traffic_tx traffic_pair
    local warp_ipv6="" ipv6_display=""

    clear
    os_info=$(get_sys_info)
    cpu=$(awk -F: '/model name|Hardware|Processor/ {gsub(/^[ \t]+/,"",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null)
    cpu=${cpu:-$(uname -m)}
    cores=$(nproc 2>/dev/null || echo "?")

    cpu_mhz=$(awk -F: '/cpu MHz/ {gsub(/^[ \t]+/,"",$2); sum+=$2; n++} END {if (n>0) printf "%.0f", sum/n}' /proc/cpuinfo 2>/dev/null)
    if [[ "$cpu_mhz" =~ ^[0-9]+$ ]] && [[ "$cpu_mhz" -gt 0 ]]; then
        cpu_ghz=$(awk -v mhz="$cpu_mhz" 'BEGIN {printf "%.2f", mhz/1000}')
    else
        cpu_ghz=""
    fi

    mem_total=$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}')
    mem_used=$(free -h 2>/dev/null | awk '/^Mem:/ {print $3}')
    swap_total=$(free -h 2>/dev/null | awk '/^Swap:/ {print $2}')
    swap_used=$(free -h 2>/dev/null | awk '/^Swap:/ {print $3}')
    mem_total=${mem_total//Gi/G}
    mem_total=${mem_total//Mi/M}
    mem_total=${mem_total//Ki/K}
    mem_total=${mem_total//Ti/T}
    mem_used=${mem_used//Gi/G}
    mem_used=${mem_used//Mi/M}
    mem_used=${mem_used//Ki/K}
    mem_used=${mem_used//Ti/T}
    swap_total=${swap_total//Gi/G}
    swap_total=${swap_total//Mi/M}
    swap_total=${swap_total//Ki/K}
    swap_total=${swap_total//Ti/T}
    swap_used=${swap_used//Gi/G}
    swap_used=${swap_used//Mi/M}
    swap_used=${swap_used//Ki/K}
    swap_used=${swap_used//Ti/T}
    disk_used=$(df -h / 2>/dev/null | awk 'NR==2 {print $3}')
    disk_total=$(df -h / 2>/dev/null | awk 'NR==2 {print $2}')

    uptime_days=$(awk '{printf "%d", $1/86400}' /proc/uptime 2>/dev/null)
    [[ "$uptime_days" =~ ^[0-9]+$ ]] || uptime_days=0

    timezone=$(timedatectl show -p Timezone --value 2>/dev/null || date +%Z)
    dns=$(awk '/^[[:space:]]*nameserver[[:space:]]+/ {print $2}' /etc/resolv.conf 2>/dev/null | paste -sd ',' -)
    congestion=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "未知")
    hostname_text=$(hostname 2>/dev/null || echo "未知")

    traffic_pair=$(server_tool_monthly_traffic_bytes)
    traffic_rx=$(awk '{print $1}' <<<"$traffic_pair")
    traffic_tx=$(awk '{print $2}' <<<"$traffic_pair")

    ipv4=$(curl -4fsS --connect-timeout 2 --max-time 4 https://api4.ipify.org 2>/dev/null || true)
    ipv6=$(curl -6fsS --connect-timeout 2 --max-time 4 https://api6.ipify.org 2>/dev/null || true)

    # WARP 使用 Local Proxy，不会把 Cloudflare IPv6 写入 VPS 本机网络栈。
    # 因此原生 IPv6 不存在时，需要通过 WARP SOCKS 出口单独查询。
    if [[ -n "$ipv6" ]]; then
        ipv6_display="$ipv6"
    elif warp_proxy_ready 2>/dev/null && warp_family_allowed ipv6 2>/dev/null; then
        warp_ipv6=$(warp_test_family ipv6 2>/dev/null || true)
        if [[ -n "$warp_ipv6" ]]; then
            ipv6_display="${warp_ipv6}（WARP）"
        else
            ipv6_display="无 IPv6"
        fi
    else
        ipv6_display="无 IPv6"
    fi

    # IP 属性继续以 VPS 原生公网地址为准，不使用 WARP 出口覆盖机房/IP 属性。
    server_tool_get_ip_profile "$ipv4" "$ipv6"

    echo -e "${CYAN}════════════════════ 系统信息 ════════════════════${PLAIN}"
    echo "  主机名     : ${hostname_text}"
    echo "  系统       : ${os_info}"
    echo "  CPU        : ${cpu}"
    echo "  CPU 核心   : ${cores}$([[ -n "$cpu_ghz" ]] && printf " 核 @ %s GHz" "$cpu_ghz" || printf " 核")"
    echo "  内存       : ${mem_used:-?} / ${mem_total:-?}"
    echo "  虚拟内存   : ${swap_used:-?} / ${swap_total:-?}"
    echo "  硬盘占用   : ${disk_used:-?} / ${disk_total:-?}"
    echo "  运行时间   : ${uptime_days} 天"
    echo "  入站流量   : $(server_tool_format_bytes "${traffic_rx:-0}")（本月）"
    echo "  出站流量   : $(server_tool_format_bytes "${traffic_tx:-0}")（本月）"
    echo "  时区       : ${timezone:-未知}"
    echo "  IPv4 地址  : ${ipv4:-无 IPv4}"
    echo "  IPv6 地址  : ${ipv6_display}"
    echo "  地理位置   : ${SERVER_INFO_LOCATION}"
    echo "  ISP / ASN  : ${SERVER_INFO_ISP} / ${SERVER_INFO_ASN}"
    echo "  IP 性质    : ${SERVER_INFO_IP_TYPE}"
    echo "  IP 危险性  : ${SERVER_INFO_IP_RISK}"
    echo "  DNS        : ${dns:-未检测到}"
    echo "  网络算法   : ${congestion} ${qdisc}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${PLAIN}"
}

server_tool_system_update() {
    local pm action
    pm=$(server_tool_pkg_manager)

    clear
    echo -e "${CYAN}════════════════ 系统更新 / 清理 ════════════════${PLAIN}"
    echo "  1. 更新系统软件包"
    echo "  2. 清理无用软件包与缓存"
    echo "  3. 更新 + 清理"
    echo "  0. 返回"
    read -rp "请选择 [0-3]: " action

    [[ "$action" == "0" ]] && return

    if [[ "$pm" == "unknown" ]]; then
        echo -e "${RED}[错误] 未识别当前系统包管理器。${PLAIN}"
        pause
        return
    fi

    if [[ "$action" == "1" || "$action" == "3" ]]; then
        echo -e "${YELLOW}>> 正在更新系统软件包...${PLAIN}"
        case "$pm" in
            apt)
                DEBIAN_FRONTEND=noninteractive apt-get update -y &&
                DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y
                ;;
            dnf) dnf upgrade -y ;;
            yum) yum update -y ;;
            apk) apk update && apk upgrade ;;
        esac
    fi

    if [[ "$action" == "2" || "$action" == "3" ]]; then
        echo -e "${YELLOW}>> 正在清理无用软件包与包管理器缓存...${PLAIN}"
        case "$pm" in
            apt)
                DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y
                apt-get clean
                apt-get autoclean
                ;;
            dnf)
                dnf autoremove -y || true
                dnf clean all
                ;;
            yum)
                yum autoremove -y || true
                yum clean all
                ;;
            apk)
                apk cache clean
                ;;
        esac
    fi

    echo -e "${GREEN}✔ 操作完成。${PLAIN}"
    pause
}

server_tool_swap_status() {
    echo -e "${YELLOW}当前内存 / Swap:${PLAIN}"
    free -h 2>/dev/null || true
    echo ""
    swapon --show 2>/dev/null || true
}

server_tool_swap_create() {
    local size_mb="$1"

    if ! [[ "$size_mb" =~ ^[0-9]+$ ]] || [[ "$size_mb" -lt 256 ]] || [[ "$size_mb" -gt 32768 ]]; then
        echo -e "${RED}[错误] Swap 大小必须在 256-32768 MB。${PLAIN}"
        return 1
    fi

    if platform_is_alpine; then
        ensure_test_dependency mkswap util-linux-misc || {
            echo -e "${RED}[错误] Alpine 无法安装 util-linux-misc，不能安全管理 Swap。${PLAIN}"
            return 1
        }
    fi
    for cmd in mkswap swapon swapoff; do
        command -v "$cmd" >/dev/null 2>&1 || {
            echo -e "${RED}[错误] 缺少 $cmd，无法管理 Swap。${PLAIN}"
            return 1
        }
    done

    if swapon --show=NAME --noheadings 2>/dev/null | grep -qx '/swapfile'; then
        swapoff /swapfile || return 1
    fi
    rm -f /swapfile
    echo -e "${YELLOW}>> 创建 ${size_mb} MB /swapfile...${PLAIN}"
    if command -v fallocate >/dev/null 2>&1; then
        fallocate -l "${size_mb}M" /swapfile || return 1
    else
        dd if=/dev/zero of=/swapfile bs=1M count="$size_mb" status=progress || return 1
    fi
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null || { rm -f /swapfile; return 1; }
    swapon /swapfile || { rm -f /swapfile; return 1; }
    sed -i '\|^/swapfile[[:space:]]|d' /etc/fstab
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo -e "${GREEN}✔ /swapfile 已启用。${PLAIN}"
}
server_tool_swap_remove() {
    local ans=""
    if [[ ! -f /swapfile ]] && ! grep -qE '^/swapfile[[:space:]]' /etc/fstab 2>/dev/null; then
        echo -e "${YELLOW}未检测到由本工具管理的 /swapfile。${PLAIN}"
        return 0
    fi

    read -rp "确认删除 /swapfile？不会影响其他 Swap。[y/N]: " ans
    [[ "$ans" =~ ^[Yy]$ ]] || return 0

    swapoff /swapfile >/dev/null 2>&1 || true
    sed -i '\|^/swapfile[[:space:]]|d' /etc/fstab
    rm -f /swapfile
    echo -e "${GREEN}✔ /swapfile 已删除。${PLAIN}"
}

server_tool_swap_management() {
    local c custom
    while true; do
        clear
        echo -e "${CYAN}════════════════════ Swap 管理 ════════════════════${PLAIN}"
        server_tool_swap_status
        echo ""
        echo "  1. 设置 512 MB"
        echo "  2. 设置 1 GB"
        echo "  3. 设置 2 GB"
        echo "  4. 设置 4 GB"
        echo "  5. 自定义大小"
        echo "  6. 删除 /swapfile"
        echo "  0. 返回"
        read -rp "请选择 [0-6]: " c
        case "$c" in
            1) server_tool_swap_create 512; pause ;;
            2) server_tool_swap_create 1024; pause ;;
            3) server_tool_swap_create 2048; pause ;;
            4) server_tool_swap_create 4096; pause ;;
            5)
                read -rp "请输入 Swap 大小（MB，256-32768）: " custom
                server_tool_swap_create "$custom"
                pause
                ;;
            6) server_tool_swap_remove; pause ;;
            0) return ;;
            *) sleep 1 ;;
        esac
    done
}

# ==============================================================================
# [12A] 网络调优 v1.10.0-dev1：只读诊断 / 初始快照 / BBR 最小事务
# ==============================================================================
# 禁止把网络调优状态存进 STATE_DIR：完全卸载默认保留用户主动网络设置，
# 必须同时保留恢复所需的 baseline，避免留下无法回滚的 sysctl 配置。
NET_TUNE_DIR="/var/lib/ss2022-network-tuning"
NET_TUNE_SNAPSHOT="${NET_TUNE_DIR}/original.json"
NET_TUNE_CONF="/etc/sysctl.d/99-ss2022-network-tuning.conf"
NET_TUNE_LEGACY_CONF="/etc/sysctl.d/99-ss2022-bbr.conf"
NET_TUNE_SYSCTL_DIR="/etc/sysctl.d"
NET_TUNE_SYSTEM_SYSCTL_CONF="/etc/sysctl.conf"

network_tuning_legacy_status() {
    if [[ ! -e "$NET_TUNE_LEGACY_CONF" && ! -L "$NET_TUNE_LEGACY_CONF" ]]; then
        printf 'absent'
    elif [[ -f "$NET_TUNE_LEGACY_CONF" && ! -L "$NET_TUNE_LEGACY_CONF" ]] &&
         [[ "$(cat "$NET_TUNE_LEGACY_CONF")" == $'net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr' ]]; then
        printf 'owned'
    else
        printf 'modified'
    fi
}

network_tuning_conf_is_owned() {
    [[ -f "$NET_TUNE_CONF" && ! -L "$NET_TUNE_CONF" ]] || return 1
    [[ "$(cat "$NET_TUNE_CONF")" == $'# vps-bootstrap network tuning: BBR/fq (managed by ss2022.sh)\nnet.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr' ]]
}

network_tuning_conflict_file() {
    local f
    # 操作系统原生 /usr/lib/sysctl.d 属发行版默认值；本模块仅拒绝覆盖管理员
    # 在 /etc/sysctl.conf、/etc/sysctl.d 手工维护的相同键。
    for f in "$NET_TUNE_SYSTEM_SYSCTL_CONF" "$NET_TUNE_SYSCTL_DIR"/*.conf; do
        [[ -f "$f" ]] || continue
        [[ "$f" == "$NET_TUNE_CONF" || "$f" == "$NET_TUNE_LEGACY_CONF" ]] && continue
        if awk '/^[[:space:]]*(net\.core\.default_qdisc|net\.ipv4\.tcp_congestion_control)[[:space:]]*=/{found=1} END{exit !found}' "$f"; then
            printf '%s\n' "$f"
            return 0
        fi
    done
    return 1
}

network_tuning_assert_safe() {
    local legacy conflict
    legacy=$(network_tuning_legacy_status)
    if [[ "$legacy" == modified ]]; then
        echo "[保护] 检测到非官方内容的旧 BBR 文件，拒绝接管：$NET_TUNE_LEGACY_CONF"
        return 1
    fi
    if [[ -e "$NET_TUNE_CONF" || -L "$NET_TUNE_CONF" ]] && ! network_tuning_conf_is_owned; then
        echo "[保护] 新版网络调优文件内容已被修改，拒绝覆盖：$NET_TUNE_CONF"
        return 1
    fi
    conflict=$(network_tuning_conflict_file) && {
        echo "[保护] 管理员已有相同 sysctl 键配置，拒绝覆盖：$conflict"
        return 1
    }
    return 0
}

network_tuning_get_iface() {
    local family="$1" target="$2" route line prev="" field
    command -v ip >/dev/null 2>&1 || return 1
    route=$(ip "-${family}" route get "$target" 2>/dev/null) || return 1
    # 不使用 ip | grep -q；在 pipefail + 单核/多网卡环境中会误判 SIGPIPE。
    line=${route%%$'\n'*}
    for field in $line; do
        if [[ "$prev" == dev ]]; then printf '%s\n' "$field"; return 0; fi
        prev="$field"
    done
    return 1
}

network_tuning_status() {
    local cc available qdisc v4 v6 iface active legacy snapshot_note conflict
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)
    available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || true)
    v4=$(network_tuning_get_iface 4 1.1.1.1 || true)
    v6=$(network_tuning_get_iface 6 2606:4700:4700::1111 || true)
    iface=${v4:-$v6}
    active="未检测"
    if [[ -n "$iface" ]] && command -v tc >/dev/null 2>&1; then
        active=$(tc qdisc show dev "$iface" 2>/dev/null | awk '$1=="qdisc" && $0 ~ / root / {print $2; exit}')
        [[ -n "$active" ]] || active="系统默认/未显示根队列"
    fi
    legacy=$(network_tuning_legacy_status)
    snapshot_note="未建立"
    [[ -f "$NET_TUNE_SNAPSHOT" ]] && snapshot_note="已保存"
    echo -e "${CYAN}══════════════════ 网络状态 ══════════════════${PLAIN}"
    echo "拥塞算法       : ${cc:-未知}"
    echo "内核可用算法   : ${available:-未知}"
    echo "默认 qdisc     : ${qdisc:-未知}"
    echo "当前出口 qdisc : $active"
    echo "IPv4 出口设备  : ${v4:-不可用/未识别}"
    echo "IPv6 出口设备  : ${v6:-不可用/未识别}"
    echo "旧版 BBR 配置  : $legacy"
    echo "初始快照       : $snapshot_note"
    if [[ -e "$NET_TUNE_CONF" || -L "$NET_TUNE_CONF" ]]; then
        if network_tuning_conf_is_owned; then
            echo "BBR 持久化     : v1.10.0 管理"
        else
            echo "BBR 持久化     : 文件已修改，拒绝接管"
        fi
    elif [[ "$legacy" == owned ]]; then
        echo "BBR 持久化     : v1.9.0 管理（尚未迁移）"
    else
        echo "BBR 持久化     : 无本模块配置"
    fi
    conflict=$(network_tuning_conflict_file) && echo "外部 sysctl    : $conflict"
    echo ""
    echo "说明：网卡识别仅使用路由查询，不主动发包；"
    echo "      iperf3 测速/临时 HTB 均须显式授权；initcwnd 不修改。"
}

network_tuning_snapshot() (
    local cc qdisc legacy tmp key value
    command -v jq >/dev/null 2>&1 || { echo "[错误] 缺少 jq，无法创建可信快照。"; return 1; }
    network_tuning_assert_safe || return 1
    if [[ -f "$NET_TUNE_SNAPSHOT" ]]; then
        jq -e '.schema == 1 and (.baseline.congestion|type=="string") and (.baseline.qdisc|type=="string")' \
            "$NET_TUNE_SNAPSHOT" >/dev/null 2>&1 || {
            echo "[保护] 已有快照格式异常，拒绝覆盖。"
            return 1
        }
        echo "原始快照已存在，保留首次记录：$NET_TUNE_SNAPSHOT"
        return 0
    fi
    if [[ -e "$NET_TUNE_CONF" || -L "$NET_TUNE_CONF" ]]; then
        echo "[保护] 已有新模块配置但没有初始快照，不得把调优后的状态冒充基线。"
        return 1
    fi
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null) || return 1
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null) || return 1
    [[ "$cc" =~ ^[a-zA-Z0-9_]+$ && "$qdisc" =~ ^[a-zA-Z0-9_]+$ ]] || return 1
    legacy=$(network_tuning_legacy_status)
    # 未来 BDP 调优也需要最初的四项 buffer 值，首版就完整保存，避免以后无法回滚。
    local rmem_max wmem_max tcp_rmem tcp_wmem
    rmem_max=$(sysctl -n net.core.rmem_max 2>/dev/null) || return 1
    wmem_max=$(sysctl -n net.core.wmem_max 2>/dev/null) || return 1
    tcp_rmem=$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null) || return 1
    tcp_wmem=$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null) || return 1
    umask 077
    mkdir -p "$NET_TUNE_DIR" || return 1
    chmod 700 "$NET_TUNE_DIR" || return 1
    tmp=$(mktemp "$NET_TUNE_DIR/.original.XXXXXXXX") || return 1
    if ! jq -n \
        --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg cc "$cc" --arg q "$qdisc" --arg legacy "$legacy" \
        --arg rmax "$rmem_max" --arg wmax "$wmem_max" \
        --arg tr "$tcp_rmem" --arg tw "$tcp_wmem" \
        '{schema:1,created_at:$at,legacy_bbr:$legacy,baseline:{
           congestion:$cc,qdisc:$q,rmem_max:$rmax,wmem_max:$wmax,tcp_rmem:$tr,tcp_wmem:$tw
         }}' > "$tmp" ||
       ! jq -e '.schema == 1 and .baseline.congestion != "" and .baseline.qdisc != "" and
                .baseline.rmem_max != "" and .baseline.wmem_max != "" and
                .baseline.tcp_rmem != "" and .baseline.tcp_wmem != ""' "$tmp" >/dev/null; then
        rm -f "$tmp"
        echo "[错误] 快照写入或校验失败，未修改网络。"
        return 1
    fi
    if [[ -e "$NET_TUNE_SNAPSHOT" ]]; then
        rm -f "$tmp"
        echo "[保护] 快照由另一会话创建，保留现有版本。"
        return 1
    fi
    chmod 600 "$tmp" && ln "$tmp" "$NET_TUNE_SNAPSHOT" && rm -f "$tmp" || {
        rm -f "$tmp"
        echo "[错误] 无法原子保存快照，未修改网络。"
        return 1
    }
    echo -e "${GREEN}✔ 原始快照已保存：$NET_TUNE_SNAPSHOT${PLAIN}"
    echo "  旧版 BBR 的当前值如已生效，将被视为这次迁移的基线。"
)

network_tuning_enable_bbr() (
    local cc qdisc available tmp="" legacy
    network_tuning_assert_safe || exit 1
    network_tuning_snapshot || exit 1
    modprobe tcp_bbr >/dev/null 2>&1 || true
    available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)
    if [[ " $available " != *" bbr "* ]]; then
        echo "[错误] 当前内核不提供 BBR；不会自动更换内核。"
        exit 1
    fi
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null) || exit 1
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null) || exit 1
    legacy=$(network_tuning_legacy_status)
    umask 077
    mkdir -p "$NET_TUNE_SYSCTL_DIR" || exit 1
    tmp=$(mktemp "$NET_TUNE_SYSCTL_DIR/.ss2022-network-tuning.XXXXXXXX") || exit 1
    trap 'rm -f "$tmp"' EXIT
    printf '%s\n' \
        '# vps-bootstrap network tuning: BBR/fq (managed by ss2022.sh)' \
        'net.core.default_qdisc=fq' \
        'net.ipv4.tcp_congestion_control=bbr' > "$tmp" || exit 1
    if ! sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1 ||
       ! sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1 ||
       [[ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" != bbr ]]; then
        sysctl -w "net.ipv4.tcp_congestion_control=$cc" >/dev/null 2>&1 || true
        sysctl -w "net.core.default_qdisc=$qdisc" >/dev/null 2>&1 || true
        echo "[错误] BBR/fq 未能完全生效，已尝试恢复操作前的运行参数。"
        exit 1
    fi
    chmod 644 "$tmp" && mv -f "$tmp" "$NET_TUNE_CONF" || {
        sysctl -w "net.ipv4.tcp_congestion_control=$cc" >/dev/null 2>&1 || true
        sysctl -w "net.core.default_qdisc=$qdisc" >/dev/null 2>&1 || true
        echo "[错误] BBR 持久化失败；已尝试恢复运行参数。"
        exit 1
    }
    if [[ "$legacy" == owned ]]; then
        rm -f "$NET_TUNE_LEGACY_CONF" || {
            echo "[错误] 无法清理旧版 BBR 文件，新版已生效但迁移未完成。"
            exit 1
        }
    fi
    echo -e "${GREEN}✔ 已启用原生 BBR + fq；持久化归新版网络调优模块管理。${PLAIN}"
)

network_tuning_restore() (
    local cc qdisc legacy old_cc old_qdisc tmp=""
    [[ -f "$NET_TUNE_SNAPSHOT" ]] || { echo "[提示] 没有可恢复的初始快照。"; exit 1; }
    command -v jq >/dev/null 2>&1 || exit 1
    network_tuning_assert_safe || exit 1
    jq -e '.schema==1 and (.baseline.congestion|type=="string") and
           (.baseline.qdisc|type=="string") and
           (.legacy_bbr=="absent" or .legacy_bbr=="owned")' \
        "$NET_TUNE_SNAPSHOT" >/dev/null 2>&1 || {
        echo "[保护] 快照内容无效，拒绝恢复。"
        exit 1
    }
    cc=$(jq -r '.baseline.congestion' "$NET_TUNE_SNAPSHOT")
    qdisc=$(jq -r '.baseline.qdisc' "$NET_TUNE_SNAPSHOT")
    legacy=$(jq -r '.legacy_bbr' "$NET_TUNE_SNAPSHOT")
    [[ "$cc" =~ ^[a-zA-Z0-9_]+$ && "$qdisc" =~ ^[a-zA-Z0-9_]+$ ]] || exit 1
    if [[ "$legacy" == absent && "$(network_tuning_legacy_status)" != absent ]]; then
        echo "[保护] 恢复目标原来不存在旧 BBR 文件，但现在出现了新的同名文件。"
        exit 1
    fi
    old_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null) || exit 1
    old_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null) || exit 1
    if [[ "$legacy" == owned && ! -e "$NET_TUNE_LEGACY_CONF" ]]; then
        umask 077
        tmp=$(mktemp "$NET_TUNE_SYSCTL_DIR/.ss2022-bbr-restore.XXXXXXXX") || exit 1
        trap 'rm -f "$tmp"' EXIT
        printf '%s\n' 'net.core.default_qdisc=fq' \
            'net.ipv4.tcp_congestion_control=bbr' > "$tmp" || exit 1
    fi
    if ! sysctl -w "net.ipv4.tcp_congestion_control=$cc" >/dev/null 2>&1 ||
       ! sysctl -w "net.core.default_qdisc=$qdisc" >/dev/null 2>&1; then
        sysctl -w "net.ipv4.tcp_congestion_control=$old_cc" >/dev/null 2>&1 || true
        sysctl -w "net.core.default_qdisc=$old_qdisc" >/dev/null 2>&1 || true
        echo "[错误] 恢复运行参数失败，保留原配置文件和快照。"
        exit 1
    fi
    if [[ -n "$tmp" ]]; then
        chmod 644 "$tmp" && mv "$tmp" "$NET_TUNE_LEGACY_CONF" || {
            sysctl -w "net.ipv4.tcp_congestion_control=$old_cc" >/dev/null 2>&1 || true
            sysctl -w "net.core.default_qdisc=$old_qdisc" >/dev/null 2>&1 || true
            echo "[错误] 恢复旧版 BBR 持久化文件失败。"
            exit 1
        }
    fi
    if [[ -e "$NET_TUNE_CONF" ]] && ! rm -f "$NET_TUNE_CONF"; then
        echo "[错误] 无法移除新版 BBR 配置，保留初始快照供修复。"
        exit 1
    fi
    echo -e "${GREEN}✔ 已恢复首次调优前的 BBR/fq 运行参数及旧版配置状态。${PLAIN}"
    echo "原始快照仍保留，便于核对；没有修改路由、网卡根 qdisc 或 SSH。"
)

# ==============================================================================
# [12B] v1.10.0-dev2：低流量非侵入式 iperf3 诊断
# ==============================================================================
# dev2 不调用 tc qdisc / sysctl -w / ip route replace。高带宽扫描另行实现。
# 用户线路机的正式支持范围：只允许这些实际套餐档位参与未来的自动检测。
# 1Gbps 及以上不进行自动整形；不能根据 NIC 1000/10000Mbps 链路速度猜套餐。
NET_TUNE_SUPPORTED_MAX_MBPS=500
NET_TUNE_SUPPORTED_TIERS="10 20 30 100 200 300 500"

network_tuning_profile() {
    # 返回：套餐Mbps 初筛Mbps 粗扫步长Kbps 细扫步长Kbps 单次秒数
    # 只描述未来 dev3 自动扫描的策略，不执行测速、写 sysctl 或安装 HTB。
    local tier="${1:-}"
    case "$tier" in
        10)  printf '10 5 1000 100 6\n' ;;
        20)  printf '20 8 2000 200 6\n' ;;
        30)  printf '30 10 2000 250 6\n' ;;
        100) printf '100 20 5000 500 6\n' ;;
        200) printf '200 30 10000 1000 6\n' ;;
        300) printf '300 40 15000 1000 6\n' ;;
        500) printf '500 50 20000 2000 6\n' ;;
        *)
            echo "[保护] 不支持的线路套餐：${tier:-未指定}Mbps；仅支持 $NET_TUNE_SUPPORTED_TIERS Mbps。" >&2
            return 1 ;;
    esac
}

network_tuning_profile_upper_kbps() {
    # 最大允许的扫描档位：1.2 x 套餐速率与 500 Mbps 中较小者。
    # 这是扫描计划的绝对上界，不是最终整形速率，任何结果都不得超过 500Mbps。
    local tier="${1:-}" cap
    network_tuning_profile "$tier" >/dev/null || return 1
    cap=$((tier * 1200))
    (( cap <= NET_TUNE_SUPPORTED_MAX_MBPS * 1000 )) || cap=$((NET_TUNE_SUPPORTED_MAX_MBPS * 1000))
    printf '%s\n' "$cap"
}

network_tuning_profile_print() {
    local tier="$1" info upper
    info=$(network_tuning_profile "$tier") || return 1
    upper=$(network_tuning_profile_upper_kbps "$tier") || return 1
    local plan first coarse fine duration
    read -r plan first coarse fine duration <<< "$info"
    echo "套餐：${plan}Mbps；初筛上限：${first}Mbps；单次测速：${duration}秒"
    echo "粗扫步长：${coarse}Kbps；细扫步长：${fine}Kbps；扫描上限：${upper}Kbps"
    echo "这是策略预览，不代表已测速或建议实际出口整形。"
}

NET_TUNE_PROBE_SYSFS="/sys/class/net"
NET_TUNE_PROBE_MAX_MBPS=100
NET_TUNE_PROBE_MAX_SECS=20
NET_TUNE_PROBE_MAX_BUDGET_MIB=256

network_tuning_probe_resolve() {
    local family="$1" host="$2" line="" address rest
    [[ "$host" =~ ^[A-Za-z0-9_.:-]{1,253}$ && "$host" != -* ]] || return 1
    if [[ "$host" == *:* ]]; then
        [[ "$family" == 6 && "$host" != ::ffff:* && "$host" != ::FFFF:* ]] || return 1
        printf '%s\n' "$host"
        return 0
    fi
    if [[ "$host" =~ ^[0-9.]+$ ]]; then
        [[ "$family" == 4 ]] || return 1
        printf '%s\n' "$host"
        return 0
    fi
    command -v getent >/dev/null 2>&1 || return 1
    if [[ "$family" == 4 ]]; then
        line=$(getent ahostsv4 "$host" 2>/dev/null || true)
    else
        line=$(getent ahostsv6 "$host" 2>/dev/null || true)
    fi
    [[ -n "$line" ]] || line=$(getent hosts "$host" 2>/dev/null || true)
    while read -r address rest; do
        if [[ "$family" == 4 && "$address" =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then
            printf '%s\n' "$address"
            return 0
        fi
        if [[ "$family" == 6 && "$address" == *:* && "$address" != ::ffff:* &&
              "$address" != ::FFFF:* && "$address" != *%* ]]; then
            printf '%s\n' "$address"
            return 0
        fi
    done <<< "$line"
    return 1
}

network_tuning_probe_iface_guard() {
    local iface="$1" route="$2"
    [[ "$iface" =~ ^[a-zA-Z0-9_.:-]+$ ]] || return 1
    case "$iface" in
        lo|wg*|tun*|tap*|tailscale*|zt*|docker*|br-*|veth*|virbr*|ifb*)
            return 1 ;;
    esac
    case " $route " in
        *" blackhole "*|*" unreachable "*|*" prohibit "*) return 1 ;;
    esac
    [[ -r "$NET_TUNE_PROBE_SYSFS/$iface/statistics/tx_bytes" ]]
}

network_tuning_probe_check() {
    # family peer rate Mbps duration seconds budget MiB
    local family="$1" peer="$2" rate="$3" duration="$4" budget="$5"
    local target route iface estimated allowance
    [[ "$family" == 4 || "$family" == 6 ]] || { echo "[错误] IPv4/IPv6 参数不正确。"; return 1; }
    [[ "$rate" =~ ^[1-9][0-9]*$ && "$duration" =~ ^[1-9][0-9]*$ && "$budget" =~ ^[1-9][0-9]*$ ]] || {
        echo "[错误] 速率、时长和流量预算必须是整数。"; return 1;
    }
    (( rate >= 1 && rate <= NET_TUNE_PROBE_MAX_MBPS &&
       duration >= 3 && duration <= NET_TUNE_PROBE_MAX_SECS &&
       budget >= 1 && budget <= NET_TUNE_PROBE_MAX_BUDGET_MIB )) || {
        echo "[保护] dev2 限额：1-100Mbps、3-20秒、1-256MiB。"; return 1;
    }
    target=$(network_tuning_probe_resolve "$family" "$peer") || {
        echo "[错误] 测试对端无法解析到指定 IPv${family}。"; return 1;
    }
    # 将单流 TCP 预估载荷限制在预算的 70%，留出协议开销/监控余量。
    estimated=$((rate * 1000000 * duration / 8))
    allowance=$((budget * 1048576 * 70 / 100))
    (( estimated <= allowance )) || {
        echo "[保护] 预计发送量超过预算的 70%，请调整速率/时长/预算。"; return 1;
    }
    route=$(ip "-${family}" route get "$target" 2>/dev/null) || {
        echo "[错误] 无法获取 IPv${family} 真实出口路由。"; return 1;
    }
    iface=$(network_tuning_get_iface "$family" "$target") || {
        echo "[错误] 无法解析测速出口设备。"; return 1;
    }
    network_tuning_probe_iface_guard "$iface" "$route" || {
        echo "[保护] $iface 为隧道/容器/不可计量设备，不进行自动测速。"; return 1;
    }
    printf '%s|%s|%s\n' "$target" "$iface" "$estimated"
}

network_tuning_probe_result_json() {
    jq -e -c '
      if (.error // "") != "" or
         (.end.sum_sent.bits_per_second | type) != "number" or
         (.end.sum_received.bits_per_second | type) != "number" or
         (.end.sum_sent.bytes | type) != "number" or
         (.end.sum_received.bytes | type) != "number"
      then empty
      else
        {sender_mbps:(.end.sum_sent.bits_per_second / 1000000 * 100 | round / 100),
         received_mbps:(.end.sum_received.bits_per_second / 1000000 * 100 | round / 100),
         sender_bytes:.end.sum_sent.bytes,
         received_bytes:.end.sum_received.bytes,
         retransmits:(.end.sum_sent.retransmits // 0)}
      end
    ' "$1" 2>/dev/null
}

network_tuning_probe_watchdog() {
    # 监控进程独立于主脚本运行；就算主脚本被 SIGKILL，也继续监控 iperf3。
    local pid="$1" txfile="$2" before="$3" budget_bytes="$4" deadline="$5" reasonfile="$6"
    local now start="$SECONDS"
    while kill -0 "$pid" 2>/dev/null; do
        now=$(cat "$txfile" 2>/dev/null || true)
        if [[ ! "$now" =~ ^[0-9]+$ ]] || (( now < before )); then
            printf 'counter_unavailable\n' > "$reasonfile"
        elif (( now - before >= budget_bytes )); then
            printf 'budget_exceeded\n' > "$reasonfile"
        elif (( SECONDS - start >= deadline )); then
            printf 'timeout\n' > "$reasonfile"
        else
            sleep 0.25
            continue
        fi
        kill -TERM "$pid" 2>/dev/null || true
        sleep 2
        kill -KILL "$pid" 2>/dev/null || true
        return 1
    done
}

network_tuning_probe_run() (
    local family="$1" peer="$2" port="$3" rate="$4" duration="$5" budget="$6" result_path="${7:-}"
    local checked target iface estimated txfile before after usage limit answer result reason code=1
    local tmp="" pid=0 watcher=0
    [[ "$port" =~ ^[1-9][0-9]*$ ]] && ((port >= 1 && port <= 65535)) || {
        echo "[错误] 端口必须为 1-65535。"; exit 1;
    }
    command -v iperf3 >/dev/null 2>&1 || {
        echo "[错误] 缺少 iperf3，请先安装系统包 iperf3。"; exit 1;
    }
    command -v jq >/dev/null 2>&1 || { echo "[错误] 缺少 jq。"; exit 1; }
    checked=$(network_tuning_probe_check "$family" "$peer" "$rate" "$duration" "$budget") || {
        echo "$checked"; exit 1;
    }
    IFS='|' read -r target iface estimated <<< "$checked"
    txfile="$NET_TUNE_PROBE_SYSFS/$iface/statistics/tx_bytes"
    before=$(cat "$txfile" 2>/dev/null) || exit 1
    [[ "$before" =~ ^[0-9]+$ ]] || exit 1
    limit=$((budget * 1048576))
    echo "对端：$target:$port；IPv${family} 出口：$iface"
    echo "单流发送：${rate}Mbps × ${duration}s；预估载荷约 $(((estimated+1048575)/1048576))MiB"
    echo "网卡发送预算：${budget}MiB（包含其他业务流量，超过预算会终止测试）"
    echo "不更改 qdisc、路由或 sysctl；不自动执行整形。"
    read -rp "确认开始？请输入 RUN: " answer
    [[ "$answer" == RUN ]] || { echo "已取消。"; exit 0; }
    umask 077
    tmp=$(mktemp -d /tmp/ss2022-netprobe.XXXXXXXX) || exit 1
    network_tuning_probe_cleanup() {
        (( pid > 0 )) && kill -TERM "$pid" 2>/dev/null || true
        (( watcher > 0 )) && kill -TERM "$watcher" 2>/dev/null || true
        [[ -d "$tmp" ]] && rm -rf "$tmp"
    }
    trap 'exit 130' INT TERM HUP
    trap network_tuning_probe_cleanup EXIT
    iperf3 "-${family}" -c "$target" -p "$port" -t "$duration" -P 1 -b "${rate}M" -J \
        > "$tmp/out.json" 2>"$tmp/err.log" </dev/null &
    pid=$!
    network_tuning_probe_watchdog "$pid" "$txfile" "$before" "$limit" "$((duration+8))" "$tmp/reason" &
    watcher=$!
    wait "$pid" && code=0 || code=$?
    kill -TERM "$watcher" 2>/dev/null || true
    wait "$watcher" 2>/dev/null || true
    watcher=0
    pid=0
    reason=$(cat "$tmp/reason" 2>/dev/null || true)
    after=$(cat "$txfile" 2>/dev/null || true)
    [[ "$after" =~ ^[0-9]+$ ]] && ((after >= before)) || {
        echo "[错误] 网卡计数异常，结果无效。"; exit 1;
    }
    usage=$((after-before))
    echo "网卡总发送增量：$(((usage+1048575)/1048576))MiB"
    if [[ -n "$reason" || "$code" -ne 0 ]] || (( usage >= limit )); then
        echo "[保护] 测速失败/超时/超流量预算，结果不可信。${reason:+ 原因：$reason}"
        exit 1
    fi
    result=$(network_tuning_probe_result_json "$tmp/out.json") || {
        echo "[错误] iperf3 JSON 无有效 TCP sender/receiver 信息。"; exit 1;
    }
    jq -r '"发送吞吐：\(.sender_mbps)Mbps；有效接收：\(.received_mbps)Mbps；重传：\(.retransmits)次"' <<< "$result"
    if ! jq -e --argjson r "$rate" '
        .sender_mbps > 0 and .received_mbps > 0 and
        .sender_mbps <= ($r * 1.5) and
        .received_mbps >= (.sender_mbps * 0.7) and .retransmits >= 0
    ' <<< "$result" >/dev/null; then
        echo "[提示] 单次样本异常/链路波动/对端性能不足，结果不确定，不用于整形。"
        exit 1
    fi
    if [[ -n "$result_path" ]]; then
        # 仅供 dev3 私有临时目录使用；不得从失败的 iperf3 测试输出任何数据。
        [[ "$result_path" == /* ]] || { echo "[错误] 输出路径必须为绝对路径。"; exit 1; }
        ( umask 077; printf '%s\n' "$result" > "$result_path" ) || exit 1
    fi
    echo -e "${GREEN}✔ 安全测速完成；仅供诊断，不修改服务器网络设置。${PLAIN}"
)

network_tuning_probe_menu() {
    local family peer port rate duration budget
    echo "需要可信的 iperf3 服务端；dev2 不自动选择公共节点，也不执行大带宽拐点扫描。"
    read -rp "地址族 4/6 [4]: " family
    read -rp "对端域名或 IP（端口另填）: " peer
    [[ -n "$peer" ]] || return 0
    read -rp "服务端端口 [5201]: " port
    read -rp "单流速率 Mbps [5]: " rate
    read -rp "测试秒数 [8]: " duration
    read -rp "流量预算 MiB [32]: " budget
    network_tuning_probe_run "${family:-4}" "$peer" "${port:-5201}" "${rate:-5}" "${duration:-8}" "${budget:-32}"
}

# ==============================================================================
# [12C] v1.10.0-dev3：视频、网页、聊天 QoE 双轮诊断（只读）
# ==============================================================================
NET_TUNE_QOE_IDLE_COUNT=6
NET_TUNE_QOE_LOADED_COUNT=12
NET_TUNE_QOE_SECONDS=8
NET_TUNE_QOE_BUDGET_MIB=96

network_tuning_qoe_ping() {
    # IPv4/IPv6 per-target ICMP on the same route as the iperf peer.
    ping "-$1" -n -c "$3" -i "${4:-0.5}" -W 1 "$2"
}

network_tuning_qoe_samples() {
    # Extract valid received ICMP RTT in ms, one JSON number per line.
    # Ignore vendor-specific ping summary output.
    awk '
      /time[=<][[:space:]]*[0-9]+([.][0-9]+)?/ {
        if (match($0, /time[=<][[:space:]]*[0-9]+([.][0-9]+)?/)) {
          value=substr($0,RSTART,RLENGTH)
          sub(/^time[=<][[:space:]]*/, "", value)
          if (value+0>=0 && value+0<100000) printf "%.3f\n", value+0
        }
      }
    ' "$1"
}

network_tuning_qoe_evaluate() {
    # Files: idle JSONL, loaded JSONL, validated iperf3 summary JSON.
    jq -n -c --slurpfile idle "$1" --slurpfile loaded "$2" --slurpfile throughput "$3" '
      def perc($arr;$fraction):
        ($arr|sort) as $sorted |
        if ($sorted|length)==0 then 0
        else $sorted[((($sorted|length)-1)*$fraction|ceil)] end;
      def jitter($arr):
        if ($arr|length)<2 then 0
        else ([range(1;($arr|length)) as $i | (($arr[$i]-$arr[$i-1])|abs)]|add)/(($arr|length)-1) end;
      def round2: .*100 | round / 100;
      ($idle|map(select(type=="number" and .>=0 and .<100000))) as $i |
      ($loaded|map(select(type=="number" and .>=0 and .<100000))) as $l |
      ($throughput[0] // {}) as $t |
      (perc($i;0.95)) as $ip95 |
      (perc($l;0.95)) as $lp95 |
      ($lp95 - $ip95) as $delta |
      ((12-($l|length))*100/12) as $loss |
      (if ($i|length)<5 or ($l|length)<9 or
          ($t.sender_mbps // 0)<=0 or ($t.received_mbps // 0)<=0 or
          $t.received_mbps < $t.sender_mbps*0.7 then "inconclusive"
        elif $loss>=15 then "possible_loss"
        elif $delta>=100 and $lp95 >= $ip95*1.8 then "possible_queueing"
        else "no_clear_issue_at_sampled_rate" end) as $verdict |
      {verdict:$verdict,idle_samples:($i|length),loaded_samples:($l|length),
       idle_p95_ms:($ip95|round2),loaded_p95_ms:($lp95|round2),
       idle_p50_ms:(perc($i;0.5)|round2),loaded_p50_ms:(perc($l;0.5)|round2),
       loaded_jitter_ms:(jitter($l)|round2),loss_percent:($loss|round2),
       p95_increase_ms:($delta|round2),received_mbps:($t.received_mbps // 0),
       tcp_retransmits:($t.retransmits // 0)}
    '
}

network_tuning_qoe_combine() {
    jq -s -c '
      if length != 2 then {status:"inconclusive",reason:"missing_round"}
      elif .[0].verdict=="inconclusive" or .[1].verdict=="inconclusive" then
        {status:"inconclusive",reason:"insufficient_samples",rounds:.}
      elif .[0].verdict != .[1].verdict then
        {status:"inconclusive",reason:"inconsistent_rounds",rounds:.}
      elif .[0].verdict=="possible_queueing" then
        {status:"repeatable_queueing_signal",reason:"not_confirmed_policer",rounds:.}
      elif .[0].verdict=="possible_loss" then
        {status:"repeatable_loss_signal",reason:"icmp_loss_origin_unknown",rounds:.}
      else
        {status:"no_clear_issue_at_sampled_rate",reason:"sampled_load_only",rounds:.}
      end
    ' "$1" "$2"
}

network_tuning_qoe_run() (
    local tier="$1" family="$2" peer="$3" port="$4" profile rate checked target
    local answer dir="" ping_pid=0 round report status
    profile=$(network_tuning_profile "$tier") || exit 1
    [[ "$family" == 4 || "$family" == 6 ]] || { echo "[错误] 仅支持 IPv4/IPv6。"; exit 1; }
    [[ "$port" =~ ^[1-9][0-9]*$ ]] && ((port >= 1 && port <= 65535)) || exit 1
    for tool in ping jq iperf3; do
        command -v "$tool" >/dev/null 2>&1 || { echo "[错误] 缺少 $tool。"; exit 1; }
    done
    read -r _ rate _ _ _ <<< "$profile"
    checked=$(network_tuning_probe_check "$family" "$peer" "$rate" \
      "$NET_TUNE_QOE_SECONDS" "$NET_TUNE_QOE_BUDGET_MIB") || {
        echo "$checked"; exit 1;
    }
    target=${checked%%|*}
    echo "套餐：${tier}Mbps；IPv${family}；iperf3 / ICMP 对端：$target:$port"
    echo "自动执行两轮：空闲 RTT + 8s 有界 TCP 负载 + 带载 RTT。"
    echo "每轮最大 96MiB 网卡发送预算，约 2×8s；不改变服务器网络参数。"
    echo "ping 与 iperf3 的对端不等于真实播放 CDN 或客户端路径。"
    read -rp "确认开始双轮体验诊断？请输入 RUN: " answer
    [[ "$answer" == RUN ]] || { echo "已取消。"; exit 0; }
    umask 077
    dir=$(mktemp -d /tmp/ss2022-qoe.XXXXXXXX) || exit 1
    network_tuning_qoe_cleanup() {
        ((ping_pid > 0)) && kill -TERM "$ping_pid" 2>/dev/null || true
        [[ -d "$dir" ]] && rm -rf "$dir"
    }
    trap 'exit 130' INT TERM HUP
    trap network_tuning_qoe_cleanup EXIT
    for round in 1 2; do
        echo "=== 第 $round/2 轮 ==="
        network_tuning_qoe_ping "$family" "$target" "$NET_TUNE_QOE_IDLE_COUNT" \
          > "$dir/idle_$round.log" 2>&1 || true
        network_tuning_qoe_samples "$dir/idle_$round.log" > "$dir/idle_$round.jsonl"
        ( sleep 0.5; network_tuning_qoe_ping "$family" "$target" "$NET_TUNE_QOE_LOADED_COUNT" ) \
          > "$dir/loaded_$round.log" 2>&1 &
        ping_pid=$!
        if ! network_tuning_probe_run "$family" "$target" "$port" "$rate" \
          "$NET_TUNE_QOE_SECONDS" "$NET_TUNE_QOE_BUDGET_MIB" "$dir/probe_$round.json" <<< "RUN"; then
            echo "[保护] 测试中断、超额或吞吐异常：拒绝生成 QoE 建议。"
            exit 1
        fi
        wait "$ping_pid" 2>/dev/null || true
        ping_pid=0
        network_tuning_qoe_samples "$dir/loaded_$round.log" > "$dir/loaded_$round.jsonl"
        network_tuning_qoe_evaluate "$dir/idle_$round.jsonl" \
          "$dir/loaded_$round.jsonl" "$dir/probe_$round.json" > "$dir/eval_$round.json" || exit 1
        jq -r --arg round "$round" \
          '"第 \($round) 轮：空闲 P95 \(.idle_p95_ms)ms → 带载 P95 \(.loaded_p95_ms)ms；抖动 \(.loaded_jitter_ms)ms；收到 \(.received_mbps)Mbps；\(.verdict)"' \
          "$dir/eval_$round.json"
    done
    report=$(network_tuning_qoe_combine "$dir/eval_1.json" "$dir/eval_2.json") || exit 1
    status=$(jq -r '.status' <<< "$report") || exit 1
    case "$status" in
        repeatable_queueing_signal)
            echo "[诊断] 两轮均有显著带载排队延迟，尚不能断定服务商限速器。" ;;
        repeatable_loss_signal)
            echo "[诊断] 两轮均有明显 ICMP 响应缺失，可能是 ICMP 限速/对端问题。" ;;
        no_clear_issue_at_sampled_rate)
            echo "[诊断] 本次采样速率未发现明显异常，不代表线路全速无问题。" ;;
        *) echo "[诊断] 样本不足或两轮结论不一致，无法判断。" ;;
    esac
    echo "结果：$status（仅诊断，不提供 HTB 整形建议或更改网卡配置）。"
)

network_tuning_qoe_menu() {
    local tier family peer port
    echo "线路机支持档位：$NET_TUNE_SUPPORTED_TIERS Mbps；不含 1Gbps。"
    read -rp "套餐 Mbps [30]: " tier
    tier=${tier:-30}
    network_tuning_profile "$tier" >/dev/null || return 1
    read -rp "地址族 4/6 [4]: " family
    read -rp "可信 iperf3 测速服务端的域名或 IP: " peer
    [[ -n "$peer" ]] || { echo "已取消。"; return 0; }
    read -rp "端口 [5201]: " port
    network_tuning_qoe_run "$tier" "${family:-4}" "$peer" "${port:-5201}"
}

# ==============================================================================
# [12D] v1.10.0-dev4: candidate calculation + existing tc ownership preflight
# ==============================================================================
# The candidate is NEVER auto-applied. No tc add/replace/delete calls here.
network_tuning_candidate_assess() {
    local tier="$1" path="$2" size max_kbps
    network_tuning_profile "$tier" >/dev/null || return 1
    [[ -f "$path" && ! -L "$path" && -r "$path" ]] || {
        echo "[保护] 证据必须是可读的普通 JSON 文件。" >&2; return 1;
    }
    size=$(wc -c < "$path") || return 1
    ((size >= 16 && size <= 262144)) || {
        echo "[保护] 证据文件大小不可信。" >&2; return 1;
    }
    max_kbps=$(network_tuning_profile_upper_kbps "$tier") || return 1
    jq -nc --slurpfile data "$path" --argjson tier "$tier" --argjson maximum "$max_kbps" '
      def refuse($why): {status:"inconclusive", reason:$why,
                          candidate_kbps:null,auto_apply:false};
      def absent($why): {status:"no_confirmed_knee",reason:$why,
                          candidate_kbps:null,auto_apply:false};
      ($data[0] // {}) as $d |
      if $d.schema != 1 or $d.tier_mbps != $tier or
        ($d.samples|type)!="array" or ($d.samples|length)!=6 then
        refuse("invalid_schema_or_tier")
      elif ([ $d.samples[] | (type=="object" and
        (.rate_mbps|type)=="number" and (.round|type)=="number" and
        (.sender_mbps|type)=="number" and (.received_mbps|type)=="number" and
        (.idle_p95_ms|type)=="number" and (.loaded_p95_ms|type)=="number" and
        (.retransmits|type)=="number") ] | all | not) then
        refuse("missing_or_invalid_metrics")
      else
        ($d.samples|sort_by(.rate_mbps,.round)) as $s |
        ([$s[].rate_mbps]|unique) as $rates |
        if ($rates|length)!=3 or
           $rates[0] < $tier*0.25 or $rates[2] < $tier*0.80 or
           $rates[2]*1000 > $maximum or
           ($rates[1]-$rates[0]) < $tier*0.08 or
           ($rates[2]-$rates[1]) < $tier*0.08 then
          refuse("insufficient_rate_coverage")
        elif ([ $rates[] as $r |
          ([$s[]|select(.rate_mbps==$r)|.round]|sort)==[1,2]
          ] | all | not) then
          refuse("missing_repeat_at_rate")
        elif ([ $s[] |
          (.rate_mbps>0 and .sender_mbps>=.rate_mbps*0.80 and
           .sender_mbps<=.rate_mbps*1.15 and .received_mbps>0 and
           .received_mbps<=.sender_mbps*1.03 and
           .idle_p95_ms>=0 and .loaded_p95_ms>=0 and
           .idle_p95_ms<=10000 and .loaded_p95_ms<=10000 and
           .retransmits>=0 and .retransmits<=100000)
          ] | all | not) then
          refuse("invalid_sample_range")
        else
          ([ $rates[] as $r |
            ([$s[]|select(.rate_mbps==$r)]|sort_by(.round)) as $p |
            {rate:$r,
             rx:(($p[0].received_mbps+$p[1].received_mbps)/2),
             stable:((($p[0].received_mbps-$p[1].received_mbps)|abs)
                      <= ($p[0].received_mbps+$p[1].received_mbps)*0.09),
             clean:([$p[]|
               (.received_mbps>=.sender_mbps*0.91 and
                .loaded_p95_ms<=.idle_p95_ms+85 and
                .retransmits<=4)]|all),
             stressed:([$p[]|
               (.received_mbps<=.sender_mbps*0.90 and
                .loaded_p95_ms>=.idle_p95_ms+100)]|all)}
          ]) as $g |
          if ([$g[].stable]|all|not) then refuse("inconsistent_repeats")
          elif ($g[0].clean|not) or ($g[1].clean|not) then
            absent("lower_rates_not_clean")
          elif ($g[2].stressed|not) or
               ($g[2].rx-$g[1].rx > ($g[2].rate-$g[1].rate)*0.30) then
            absent("no_repeatable_plateau_and_queueing")
          else
            ($g[1].rate*950|floor) as $candidate |
            if $candidate < $tier*500 or $candidate >= $tier*1000 then
              absent("candidate_outside_safe_range")
            else
              {status:"candidate_for_validation",candidate_kbps:$candidate,
               auto_apply:false,
               reason:"independent_peer_and_a_b_qoe_testing_required",
               evidence:{rates_mbps:$rates,mid_rx:$g[1].rx,high_rx:$g[2].rx}}
            end
          end
        end
      end
    '
}

network_tuning_qdisc_audit() {
    local iface="$1" qdisc classes filters root
    command -v tc >/dev/null 2>&1 || {
        echo "blocked|tc_unavailable"; return 1;
    }
    [[ "$iface" =~ ^[a-zA-Z0-9_.:-]+$ ]] || {
        echo "blocked|invalid_interface"; return 1;
    }
    qdisc=$(tc qdisc show dev "$iface" 2>/dev/null) || {
        echo "blocked|qdisc_unavailable"; return 1;
    }
    classes=$(tc class show dev "$iface" 2>/dev/null) || {
        echo "blocked|class_unavailable"; return 1;
    }
    filters=$(tc filter show dev "$iface" 2>/dev/null) || {
        echo "blocked|filter_unavailable"; return 1;
    }
    if [[ -n "$classes" || -n "$filters" ]]; then
        echo "blocked|external_classes_or_filters"; return 1
    fi
    if [[ "$qdisc" == *" mq "* || "$qdisc" == *" clsact "* ||
          "$qdisc" == *" ingress "* ]]; then
        echo "blocked|mq_clsact_ingress"; return 1
    fi
    root=$(awk '$1=="qdisc" && $0 ~ / root / {print $2; exit}' <<< "$qdisc")
    case "$root" in
        fq|fq_codel|pfifo_fast) echo "inspect_only|known_root_but_restore_unverified" ;;
        *) echo "blocked|unknown_root_qdisc"; return 1 ;;
    esac
}

network_tuning_candidate_menu() {
    local tier file payload iface family audit
    echo "开发测试功能：离线分析 3 档×2 轮的完整数据，不执行 HTB。"
    read -rp "套餐 Mbps [30]: " tier
    tier="${tier:-30}"
    network_tuning_profile "$tier" >/dev/null || return 1
    read -rp "可信六样本 JSON 文件绝对路径（留空取消）: " file
    [[ -n "$file" ]] || return 0
    payload=$(network_tuning_candidate_assess "$tier" "$file") || return 1
    jq -r 'if .candidate_kbps != null then
        "仅供后续验证的候选：\(.candidate_kbps) Kbps（未应用）"
        else "暂不建议整形：" + .reason end' <<< "$payload"
    read -rp "出口地址族 4/6 [4]: " family
    family="${family:-4}"
    [[ "$family" == 4 || "$family" == 6 ]] || return 1
    if [[ "$family" == 4 ]]; then
        iface=$(network_tuning_get_iface 4 1.1.1.1) || return 1
    else
        iface=$(network_tuning_get_iface 6 2606:4700:4700::1111) || return 1
    fi
    audit=$(network_tuning_qdisc_audit "$iface") || true
    echo "网卡 $iface 安全检查：$audit"
    echo "dev4 仅给候选及风险提示，不修改 qdisc、路由或 sysctl。"
}


# ==============================================================================
# [12E] v1.10.0-dev5: bounded 3-rate x 2-round evidence collection
# ==============================================================================
# An explicit RUN and a trusted iperf3 peer are mandatory. NO network writes.
NET_TUNE_SCAN_DURATION=6
NET_TUNE_SCAN_TOTAL_MAX_MIB=2560
NET_TUNE_SCAN_PER_PROBE_MAX_MIB=768

network_tuning_scan_plan() {
    local tier="$1" low mid high rate estimate budget total=0
    local -a budgets=()
    network_tuning_profile "$tier" >/dev/null || return 1
    command -v jq >/dev/null 2>&1 || return 1
    low=$((tier * 40 / 100))
    mid=$((tier * 80 / 100))
    high="$tier"
    for rate in "$low" "$mid" "$high"; do
        estimate=$((rate * 1000000 * NET_TUNE_SCAN_DURATION / 8))
        # Each probe needs a 30% headroom above its computed TCP payload.
        budget=$(((estimate * 10 + 7 * 1048576 - 1) / (7 * 1048576)))
        (( budget >= 1 && budget <= NET_TUNE_SCAN_PER_PROBE_MAX_MIB )) || return 1
        budgets+=("$budget")
        total=$((total + 2 * budget))
    done
    (( total <= NET_TUNE_SCAN_TOTAL_MAX_MIB )) || return 1
    jq -nc --argjson tier "$tier" --argjson duration "$NET_TUNE_SCAN_DURATION" \
        --argjson total "$total" --argjson cap "$NET_TUNE_SCAN_TOTAL_MAX_MIB" \
        --argjson low "$low" --argjson mid "$mid" --argjson high "$high" \
        --argjson lb "${budgets[0]}" --argjson mb "${budgets[1]}" \
        --argjson hb "${budgets[2]}" \
        '{schema:1,tier_mbps:$tier,duration_sec:$duration,rounds:2,
          rate_mbps:[$low,$mid,$high],budget_mib:[$lb,$mb,$hb],
          aggregate_budget_mib:$total,aggregate_cap_mib:$cap,auto_apply:false}'
}

network_tuning_scan_run() (
    local tier="$1" family="$2" peer="$3" port="$4"
    local plan target iface baseline checked audit answer rate budget round i
    local ping_pid=0 work="" report="" now summary tool counter
    local -a rates budgets
    network_tuning_profile "$tier" >/dev/null || exit 1
    [[ "$family" == 4 || "$family" == 6 ]] || exit 1
    [[ "$port" =~ ^[1-9][0-9]*$ ]] && ((port >= 1 && port <= 65535)) || exit 1
    for tool in ip iperf3 jq ping tc flock; do
        command -v "$tool" >/dev/null 2>&1 || { echo "[错误] 缺少：$tool"; exit 1; }
    done
    plan=$(network_tuning_scan_plan "$tier") || exit 1
    mapfile -t rates < <(jq -r '.rate_mbps[]' <<< "$plan")
    mapfile -t budgets < <(jq -r '.budget_mib[]' <<< "$plan")
    # Scoped to this subshell; existing dev2 100Mbps/256MiB caps are unchanged.
    NET_TUNE_PROBE_MAX_MBPS=500
    NET_TUNE_PROBE_MAX_BUDGET_MIB="$NET_TUNE_SCAN_PER_PROBE_MAX_MIB"
    target=$(network_tuning_probe_resolve "$family" "$peer") || exit 1
    checked=$(network_tuning_probe_check "$family" "$target" "${rates[0]}" \
        "$NET_TUNE_SCAN_DURATION" "${budgets[0]}") || {
        echo "$checked"; exit 1;
    }
    IFS='|' read -r _ iface _ <<< "$checked"
    counter="$NET_TUNE_PROBE_SYSFS/$iface/statistics/tx_bytes"
    baseline=$(cat "$counter" 2>/dev/null) || exit 1
    [[ "$baseline" =~ ^[0-9]+$ ]] || exit 1
    audit=$(network_tuning_qdisc_audit "$iface") || true
    echo "套餐：${tier}Mbps；对端：$target:$port；IPv${family} 出口：$iface"
    echo "每档两轮、每轮 ${NET_TUNE_SCAN_DURATION}s；速率：${rates[*]} Mbps"
    echo "累计网卡发送预算：$(jq -r .aggregate_budget_mib <<< "$plan")MiB（≤${NET_TUNE_SCAN_TOTAL_MAX_MIB}MiB）"
    echo "qdisc 预检：$audit（只读，不授予更改权限）"
    echo "警告：本测试可能占满线路，影响视频和聊天；仅建议低峰期手动执行。"
    echo "永不应用 tc 整形或修改 sysctl。"
    read -rp "确认六次网络采样？请输入 RUN: " answer
    [[ "$answer" == RUN ]] || { echo "已取消。"; exit 0; }

    [[ ! -L "$NET_TUNE_DIR" ]] || { echo "[保护] 工作目录为链接。"; exit 1; }
    if [[ ! -e "$NET_TUNE_DIR" ]]; then
        ( umask 077; mkdir -m 700 -p "$NET_TUNE_DIR" ) || exit 1
    fi
    [[ -d "$NET_TUNE_DIR" && ! -L "$NET_TUNE_DIR" ]] || exit 1
    [[ "$(stat -c %u "$NET_TUNE_DIR")" == "$(id -u)" ]] || {
        echo "[保护] 工作目录不属于当前用户。"; exit 1;
    }
    [[ ! -L "$NET_TUNE_DIR/.scan.lock" ]] || exit 1
    umask 077
    exec 9>>"$NET_TUNE_DIR/.scan.lock" || exit 1
    flock -n 9 || { echo "[保护] 已有扫描正在进行。"; exit 1; }
    work=$(mktemp -d "$NET_TUNE_DIR/.scan.XXXXXXXX") || exit 1
    network_tuning_scan_cleanup() {
        (( ping_pid > 0 )) && kill -TERM "$ping_pid" 2>/dev/null || true
        [[ -n "$work" && -d "$work" ]] && rm -rf "$work"
        [[ -n "$report" ]] && rm -f "$report"
        return 0
    }
    trap 'exit 130' INT TERM HUP
    trap network_tuning_scan_cleanup EXIT
    : > "$work/samples.jsonl"
    for round in 1 2; do
        for i in 0 1 2; do
            rate="${rates[i]}"; budget="${budgets[i]}"
            checked=$(network_tuning_probe_check "$family" "$target" "$rate" \
                "$NET_TUNE_SCAN_DURATION" "$budget") || exit 1
            [[ "$checked" == "$target|$iface|"* ]] || {
                echo "[保护] 扫描期间出口路由变化，停止。"; exit 1;
            }
            now=$(cat "$counter" 2>/dev/null) || exit 1
            [[ "$now" =~ ^[0-9]+$ ]] && ((now >= baseline)) || exit 1
            ((now - baseline < NET_TUNE_SCAN_TOTAL_MAX_MIB * 1048576)) || exit 1
            echo "=== 第 $round/2 轮，${rate}Mbps ==="
            network_tuning_qoe_ping "$family" "$target" "$NET_TUNE_QOE_IDLE_COUNT" \
                > "$work/idle.log" 2>&1 || true
            network_tuning_qoe_samples "$work/idle.log" > "$work/idle.jsonl"
            ( sleep 0.2; network_tuning_qoe_ping "$family" "$target" \
                "$NET_TUNE_QOE_LOADED_COUNT" 0.4 ) > "$work/loaded.log" 2>&1 &
            ping_pid=$!
            if ! network_tuning_probe_run "$family" "$target" "$port" "$rate" \
                "$NET_TUNE_SCAN_DURATION" "$budget" "$work/probe.json" <<< "RUN"; then
                echo "[保护] 测速失败或超预算，不生成完整证据。"; exit 1
            fi
            wait "$ping_pid" 2>/dev/null || true
            ping_pid=0
            network_tuning_qoe_samples "$work/loaded.log" > "$work/loaded.jsonl"
            network_tuning_qoe_evaluate "$work/idle.jsonl" "$work/loaded.jsonl" \
                "$work/probe.json" > "$work/eval.json" || exit 1
            if ! jq -e --argjson idle "$NET_TUNE_QOE_IDLE_COUNT" \
                --argjson loaded "$NET_TUNE_QOE_LOADED_COUNT" \
                '.verdict!="inconclusive" and .idle_samples==$idle and
                  .loaded_samples==$loaded and .loss_percent==0' \
                "$work/eval.json" >/dev/null; then
                echo "[保护] RTT/ICMP 样本不完整；停止扫描。"; exit 1
            fi
            jq -nc --argjson rate "$rate" --argjson round "$round" \
                --slurpfile p "$work/probe.json" --slurpfile q "$work/eval.json" \
                '{rate_mbps:$rate,round:$round,sender_mbps:$p[0].sender_mbps,
                  received_mbps:$p[0].received_mbps,
                  idle_p95_ms:$q[0].idle_p95_ms,
                  loaded_p95_ms:$q[0].loaded_p95_ms,
                  retransmits:$p[0].retransmits}' >> "$work/samples.jsonl" || exit 1
            now=$(cat "$counter" 2>/dev/null) || exit 1
            [[ "$now" =~ ^[0-9]+$ ]] && ((now >= baseline)) || exit 1
            ((now - baseline < NET_TUNE_SCAN_TOTAL_MAX_MIB * 1048576)) || exit 1
            sleep 2
        done
    done
    report=$(mktemp "$NET_TUNE_DIR/scan-XXXXXXXX.json") || exit 1
    jq -n --argjson tier "$tier" --slurpfile samples "$work/samples.jsonl" \
        '{schema:1,tier_mbps:$tier,samples:$samples}' > "$report" || exit 1
    [[ "$(jq -r '.samples|length' "$report")" == 6 ]] || exit 1
    summary=$(network_tuning_candidate_assess "$tier" "$report") || exit 1
    echo "只读判定：$(jq -r '.status + " / " + .reason' <<< "$summary")"
    echo "候选结果：$(jq -r 'if .candidate_kbps then
        (.candidate_kbps|tostring)+"Kbps（需 A/B 复验，未应用）"
        else "无可靠候选，保持原配置" end' <<< "$summary")"
    echo "本机六样本证据：$report（600 权限）"
    report=""
)

network_tuning_scan_menu() {
    local tier family peer port plan
    echo "开发预览：六轮实时测速可能占满线路。"
    read -rp "真实线路套餐 Mbps [30]: " tier
    tier="${tier:-30}"
    plan=$(network_tuning_scan_plan "$tier") || return 1
    echo "自动三档：$(jq -r '.rate_mbps|join(" / ")' <<< "$plan") Mbps；"
    echo "总发送预算：$(jq -r .aggregate_budget_mib <<< "$plan") MiB。"
    read -rp "地址族 4/6 [4]: " family
    read -rp "可信 iperf3 服务端域名或 IP: " peer
    [[ -n "$peer" ]] || { echo "已取消。"; return 0; }
    read -rp "服务端端口 [5201]: " port
    network_tuning_scan_run "$tier" "${family:-4}" "$peer" "${port:-5201}"
}


# ==============================================================================
# [12F] v1.10.0-dev6: independently running rollback watchdog (file-only demo)
# ==============================================================================
# WARNING: no production qdisc/HTB changes or recovery are enabled here.
NET_TUNE_ROLLBACK_TRIALS_DIR="$NET_TUNE_DIR/rollback-rehearsals"

network_tuning_rollback_dir_safe() {
    [[ -d "$1" && ! -L "$1" ]] &&
    [[ "$(stat -c %u "$1" 2>/dev/null)" == "$(id -u)" ]] &&
    [[ "$(stat -c %a "$1" 2>/dev/null)" == 700 ]]
}

network_tuning_rollback_rehearsal() (
    local ttl="$1" confirm="$2" root="$NET_TUNE_ROLLBACK_TRIALS_DIR"
    local trial="" started=0 pid i
    [[ "$ttl" =~ ^[1-9][0-9]*$ ]] && ((ttl>=3 && ttl<=30)) || {
        echo "[保护] 仅允许 3-30 秒的模拟回滚。" >&2; exit 1;
    }
    for i in setsid nohup stat mktemp; do
        command -v "$i" >/dev/null 2>&1 || { echo "[保护] 缺少 $i。"; exit 1; }
    done
    if [[ "$confirm" != RUN ]]; then
        read -rp "仅演练回滚文件标记，不动网卡。输入 RUN 确认: " confirm
        [[ "$confirm" == RUN ]] || { echo "已取消。"; exit 0; }
    fi
    umask 077
    [[ ! -L "$NET_TUNE_DIR" && ! -L "$root" ]] || exit 1
    if [[ ! -e "$NET_TUNE_DIR" ]]; then mkdir -m 700 "$NET_TUNE_DIR" || exit 1; fi
    network_tuning_rollback_dir_safe "$NET_TUNE_DIR" || {
        echo "[保护] 数据目录不是本用户拥有的 700 私有目录。" >&2; exit 1;
    }
    if [[ ! -e "$root" ]]; then mkdir -m 700 "$root" || exit 1; fi
    network_tuning_rollback_dir_safe "$root" || exit 1
    trial=$(mktemp -d "$root/trial-XXXXXXXX") || exit 1
    printf '%s\n' '{"schema":1,"mode":"dry_run","auto_apply":false}' > "$trial/plan.json"
    printf '%s\n' ARMED > "$trial/armed"
    cat > "$trial/watchdog.sh" <<'WATCHDOG_EOF'
#!/usr/bin/env bash
# Standalone watchdog: private test-marker cleanup ONLY.
set -euo pipefail
umask 077
trial="$1"
ttl="$2"
[[ "$ttl" =~ ^[1-9][0-9]*$ ]] && ((ttl>=3 && ttl<=30)) || exit 1
[[ -d "$trial" && ! -L "$trial" ]] || exit 1
[[ "$(stat -c %u "$trial")" == "$(id -u)" ]] || exit 1
[[ "$(stat -c %a "$trial")" == 700 ]] || exit 1
[[ "$(cat "$trial/plan.json")" == '{"schema":1,"mode":"dry_run","auto_apply":false}' ]] || exit 1
[[ "$(cat "$trial/armed")" == ARMED ]] || exit 1
printf '%s\n' READY > "$trial/ready"
deadline=$((SECONDS+ttl))
while ((SECONDS<deadline)); do sleep 1; done
[[ ! -L "$trial/canary.active" ]] || {
    echo blocked_symlink > "$trial/result"; exit 1;
}
rm -f -- "$trial/canary.active"
echo rolled_back_simulated > "$trial/result"
WATCHDOG_EOF
    chmod 700 "$trial/watchdog.sh" || exit 1
    nohup setsid bash "$trial/watchdog.sh" "$trial" "$ttl" \
        </dev/null >"$trial/worker.log" 2>&1 &
    pid=$!
    for ((i=0;i<40;i++)); do
        if [[ "$(cat "$trial/ready" 2>/dev/null || true)" == READY ]]; then
            started=1; break
        fi
        sleep 0.1
    done
    if ((started!=1)); then
        kill -TERM "$pid" 2>/dev/null || true
        echo "[保护] 看门狗未就绪，拒绝开始模拟变更。" >&2
        exit 1
    fi
    printf '%s\n' DRY_RUN_ONLY > "$trial/canary.active" || exit 1
    echo "Dev6 看门狗已脱离当前 Shell；不修改真实网络。"
    echo "演练事务：$trial"
    echo "结果文件：$trial/result"
)

network_tuning_rollback_rehearsal_status() {
    local root="$NET_TUNE_ROLLBACK_TRIALS_DIR" d result shown=0
    network_tuning_rollback_dir_safe "$root" || { echo "暂无演练记录。"; return 0; }
    for d in "$root"/trial-*; do
        [[ -d "$d" && ! -L "$d" ]] || continue
        result=$(cat "$d/result" 2>/dev/null || true)
        [[ -n "$result" ]] || result=pending
        echo "$(basename "$d"): $result"
        shown=$((shown+1))
        ((shown<20)) || break
    done
    ((shown>0)) || echo "暂无演练记录。"
}

network_tuning_rollback_rehearsal_menu() {
    local ttl
    echo "Dev6 仅演练独立超时清理模拟状态，不支持生产 HTB/qdisc 恢复。"
    read -rp "模拟回滚秒数 [5]: " ttl
    [[ -n "$ttl" ]] || ttl=5
    network_tuning_rollback_rehearsal "$ttl" ""
}


# ==============================================================================
# [12G] v1.10.0-dev7: transient HTB trial and detached timed rollback
# ==============================================================================
# Never persistent. Enabled only on isolated fq_codel roots with verified
# restore options. This path has not yet been tested on a real VPS.
NET_TUNE_HTB_TRIAL_SECONDS=60

network_tuning_htb_baseline() {
    local iface="$1" root classes filters index i key value argjson
    local -a tokens args
    [[ "$iface" =~ ^[a-zA-Z0-9_.:-]+$ ]] || return 1
    network_tuning_probe_iface_guard "$iface" "dev $iface" || return 1
    [[ ! -L "$NET_TUNE_PROBE_SYSFS/$iface/master" ]] || return 1
    index=$(cat "$NET_TUNE_PROBE_SYSFS/$iface/ifindex" 2>/dev/null) || return 1
    [[ "$index" =~ ^[1-9][0-9]*$ ]] || return 1
    root=$(tc qdisc show dev "$iface" 2>/dev/null) || return 1
    [[ -n "$root" && "$root" != *$'\n'* ]] || return 1
    classes=$(tc class show dev "$iface" 2>/dev/null) || return 1
    filters=$(tc filter show dev "$iface" 2>/dev/null) || return 1
    [[ -z "$classes" && -z "$filters" ]] || return 1
    read -r -a tokens <<< "$root"
    [[ "${tokens[0]:-}" == qdisc && "${tokens[1]:-}" == fq_codel &&
       "${tokens[2]:-}" =~ ^[0-9a-fA-F]+:$ && "${tokens[3]:-}" == root ]] || return 1
    i=4
    if [[ "${tokens[i]:-}" == refcnt ]]; then
        [[ "${tokens[i+1]:-}" =~ ^[1-9][0-9]*$ ]] || return 1
        i=$((i+2))
    fi
    args=()
    while ((i < ${#tokens[@]})); do
        key="${tokens[i]}"
        case "$key" in
            ecn|noecn) args+=("$key"); i=$((i+1)) ;;
            limit|flows|quantum|target|interval|memory_limit|drop_batch)
                value="${tokens[i+1]:-}"
                case "$key" in
                    limit) [[ "$value" =~ ^[1-9][0-9]*p$ ]] || return 1 ;;
                    flows|quantum|drop_batch) [[ "$value" =~ ^[1-9][0-9]*$ ]] || return 1 ;;
                    target|interval) [[ "$value" =~ ^[1-9][0-9]*(us|ms|s)$ ]] || return 1 ;;
                    memory_limit) [[ "$value" =~ ^[1-9][0-9]*(b|Kb|Mb|Gb)$ ]] || return 1 ;;
                esac
                if [[ "$key" == limit ]]; then value="${value%p}"; fi
                args+=("$key" "$value"); i=$((i+2)) ;;
            *) return 1 ;;
        esac
    done
    argjson=$(printf '%s\n' "${args[@]}" |
        jq -Rsc 'split("\n")|map(select(length>0))') || return 1
    jq -nc --arg iface "$iface" --arg idx "$index" --arg root "$root" \
        --argjson args "$argjson" \
        '{schema:1,mode:"htb_ephemeral_trial",iface:$iface,ifindex:$idx,
          original_root:$root,restore_kind:"fq_codel",restore_args:$args,permanent:false}'
}

network_tuning_htb_trial() (
    local tier="$1" family="$2" report="$3" confirm="$4"
    local iface peer baseline second status rate active trial unit cmd
    [[ "$(id -u)" == 0 ]] || { echo "[保护] 仅支持 root 临时测试。" >&2; exit 1; }
    [[ "$NET_TUNE_DIR" == /var/lib/ss2022-network-tuning &&
       "$NET_TUNE_PROBE_SYSFS" == /sys/class/net ]] || exit 1
    [[ "$family" == 4 || "$family" == 6 ]] || exit 1
    network_tuning_profile "$tier" >/dev/null || exit 1
    for cmd in ip tc jq stat flock systemd-run systemctl; do
        command -v "$cmd" >/dev/null 2>&1 || return 1
    done
    case "$report" in "$NET_TUNE_DIR"/scan-*.json) ;; *) return 1 ;; esac
    [[ -f "$report" && ! -L "$report" && -r "$report" ]] || exit 1
    [[ "$(stat -c %u "$report")" == 0 &&
       "$(stat -c %a "$report")" == 600 ]] || exit 1
    status=$(network_tuning_candidate_assess "$tier" "$report") || exit 1
    [[ "$(jq -r .status <<< "$status")" == candidate_for_validation ]] || exit 1
    rate=$(jq -r .candidate_kbps <<< "$status")
    [[ "$rate" =~ ^[1-9][0-9]*$ ]] || exit 1
    ((rate >= tier * 500 && rate < tier * 1000 && rate <= 500000)) || exit 1
    if [[ "$family" == 4 ]]; then peer=1.1.1.1; else peer=2606:4700:4700::1111; fi
    iface=$(network_tuning_get_iface "$family" "$peer") || exit 1
    baseline=$(network_tuning_htb_baseline "$iface") || {
        echo "[保护] 根 qdisc 不是可完整重建的独占 fq_codel；拒绝操作。" >&2
        exit 1
    }
    echo "实验：临时在 $iface 应用 $rate Kbps HTB，60 秒后尝试恢复原配置。"
    echo "风险：可能短暂断流；没有真实 VPS A/B 验证；不会永久启用。"
    if [[ "$confirm" != TRIAL ]]; then
        read -rp "同意风险请输入 TRIAL: " confirm
        [[ "$confirm" == TRIAL ]] || { echo "已取消。"; exit 0; }
    fi
    network_tuning_rollback_dir_safe "$NET_TUNE_DIR" || exit 1
    [[ ! -L "$NET_TUNE_DIR/.htb.lock" ]] || exit 1
    umask 077
    exec 9>>"$NET_TUNE_DIR/.htb.lock" || exit 1
    flock -n 9 || exit 1
    active="$NET_TUNE_DIR/.htb-active"
    [[ ! -e "$active" && ! -L "$active" ]] || {
        echo "[保护] 已有活动试验或未处理的回滚失败。" >&2; exit 1;
    }
    trial=$(mktemp -d "$NET_TUNE_DIR/htb-XXXXXXXX") || exit 1
    # Shared phase lock: a fired watchdog waits until all HTB writes end.
    # A killed shell releases this lock, allowing independent recovery.
    exec 8>"$trial/phase.lock" || exit 1
    flock -x 8 || exit 1
    jq --argjson rate "$rate" '. + {candidate_kbps:$rate}' \
        <<< "$baseline" > "$trial/snapshot.json" || exit 1
    cat > "$trial/restore.sh" <<'RESTORE_HTB_EOF'
#!/usr/bin/env bash
# Runs as an independent systemd timer service (no SSH dependency).
set -euo pipefail
umask 077
trial="$1"
[[ -d "$trial" && ! -L "$trial" && "$(stat -c %u "$trial")" == "$(id -u)" ]] || exit 1
snapshot="$trial/snapshot.json"
jq -e '.schema==1 and .mode=="htb_ephemeral_trial" and
       (.restore_args|type)=="array"' "$snapshot" >/dev/null || exit 1
iface=$(jq -r .iface "$snapshot")
index=$(jq -r .ifindex "$snapshot")
[[ "$iface" =~ ^[a-zA-Z0-9_.:-]+$ && "$index" =~ ^[1-9][0-9]*$ ]] || exit 1
[[ "$(cat "/sys/class/net/$iface/ifindex" 2>/dev/null)" == "$index" ]] || {
    echo interface_changed > "$trial/result"; exit 1;
}
active="$(dirname "$trial")/.htb-active"
[[ -f "$active" && ! -L "$active" && "$(cat "$active")" == "$trial" ]] || exit 1
exec 8>>"$trial/phase.lock"
flock -x 8 || exit 1
root=$(tc qdisc show dev "$iface") || exit 1
if grep -Eq '^qdisc htb 1: root' <<< "$root"; then
    while IFS= read -r qline; do
        [[ -z "$qline" || "$qline" == "qdisc htb 1: root"* ||
           "$qline" == "qdisc fq_codel 10: parent 1:10 "* ]] || {
            echo external_qdisc_conflict > "$trial/result"; exit 1;
        }
    done <<< "$root"
    [[ -z "$(tc filter show dev "$iface")" ]] || {
        echo filter_conflict > "$trial/result"; exit 1;
    }
    classes=$(tc class show dev "$iface") || exit 1
    while IFS= read -r class; do
        [[ -z "$class" || "$class" == "class htb 1:10 "* ||
           "$class" =~ ^class[[:space:]]fq_codel[[:space:]]10:[[:xdigit:]]+[[:space:]]parent[[:space:]]10:[[:space:]]*$ ]] || {
            echo class_conflict > "$trial/result"; exit 1;
        }
    done <<< "$classes"
    mapfile -t args < <(jq -r '.restore_args[]' "$snapshot")
    restored=0
    for attempt in 1 2 3; do
        if tc qdisc replace dev "$iface" root fq_codel "${args[@]}"; then
            check=$(tc qdisc show dev "$iface" 2>/dev/null || true)
            if grep -Eq '^qdisc fq_codel [^ ]+ root' <<< "$check"; then
                restored=1; break
            fi
        fi
        sleep 1
    done
    ((restored == 1)) || { echo restore_failed > "$trial/result"; exit 1; }
    echo rolled_back_live > "$trial/result"
elif grep -Eq '^qdisc fq_codel [^ ]+ root' <<< "$root"; then
    expected=$(jq -r .original_root "$snapshot")
    if [[ "$root" == "$expected" ]]; then
        echo baseline_unchanged > "$trial/result"
    else
        echo external_root_conflict > "$trial/result"; exit 1
    fi
else
    echo external_root_conflict > "$trial/result"; exit 1
fi
[[ "$(cat "$active")" == "$trial" ]] && rm -f -- "$active"
RESTORE_HTB_EOF
    chmod 700 "$trial/restore.sh" || exit 1
    ( set -C; printf '%s\n' "$trial" > "$active" ) || exit 1
    unit="ss2022-htb-restore-$(basename "$trial")"
    if ! systemd-run --unit="$unit" --on-active=60s \
        --timer-property=AccuracySec=1s /usr/bin/bash \
        "$trial/restore.sh" "$trial" >/dev/null; then
        rm -f -- "$active"
        echo "[保护] 独立 systemd 定时器不可用，未更改网络。" >&2; exit 1
    fi
    systemctl is-active --quiet "$unit.timer" || {
        echo "[保护] 定时器未就绪，不触碰网络。" >&2; exit 1;
    }
    second=$(network_tuning_htb_baseline "$iface") || exit 1
    [[ "$second" == "$baseline" ]] || {
        echo "[保护] 配置准备期间发生变化，不触碰网络。" >&2; exit 1;
    }
    [[ -f "$active" && ! -L "$active" &&
       "$(cat "$active")" == "$trial" ]] || {
        echo "[保护] 活动事务标记变化，未执行 HTB。" >&2
        exit 1
    }
    tc qdisc replace dev "$iface" root handle 1: htb default 10 || exit 1
    if ! tc class add dev "$iface" parent 1: classid 1:10 htb \
        rate "$rate"kbit ceil "$rate"kbit burst 32k cburst 32k ||
       ! tc qdisc add dev "$iface" parent 1:10 handle 10: fq_codel; then
        echo "[保护] 子队列失败，尝试立即恢复；定时器依然保留。" >&2
        flock -u 8
        flock -u 9
        /usr/bin/bash "$trial/restore.sh" "$trial" || true
        exit 1
    fi
    flock -u 8
    echo "✔ 临时整形已启用，60 秒后自动恢复。"
    echo "事务目录：$trial"
    echo "回滚定时器：$unit.timer"
)

network_tuning_htb_trial_menu() {
    local tier family report
    echo "dev7 仅支持 systemd + 独占 fq_codel，且必须有 dev5 的完整证据。"
    read -rp "套餐 Mbps [30]: " tier
    read -rp "IPv4/IPv6 [4]: " family
    read -rp "scan-*.json 文件绝对路径（空取消）: " report
    [[ -n "$report" ]] || return 0
    [[ -n "$tier" ]] || tier=30
    [[ -n "$family" ]] || family=4
    network_tuning_htb_trial "$tier" "$family" "$report" ""
}

network_tuning_htb_trial_status() {
    local active="$NET_TUNE_DIR/.htb-active" trial
    [[ -f "$active" && ! -L "$active" ]] || {
        echo "当前没有活动 HTB 试验。"; return 0;
    }
    trial=$(cat "$active")
    echo "活动试验：$trial"
    echo "回滚状态：$(cat "$trial/result" 2>/dev/null || echo pending)"
}

network_tuning_htb_restore_now() {
    local active="$NET_TUNE_DIR/.htb-active" trial
    [[ -f "$active" && ! -L "$active" ]] || return 1
    trial=$(cat "$active")
    [[ "$trial" == "$NET_TUNE_DIR"/htb-* && -f "$trial/restore.sh" ]] || return 1
    /usr/bin/bash "$trial/restore.sh" "$trial"
}


# ==============================================================================
# [12H] Dev8: video-first client A/B evidence (read-only, not field-verified)
# ==============================================================================
network_tuning_ab_assess() {
    local tier="$1" path="$2" size
    network_tuning_profile "$tier" >/dev/null || return 1
    [[ -f "$path" && ! -L "$path" && -r "$path" ]] || return 1
    size=$(wc -c < "$path") || return 1
    ((size >= 16 && size <= 32768)) || return 1
    jq -nc --slurpfile evidence "$path" --argjson tier "$tier" '
      def invalid($why): {verdict:"inconclusive",reason:$why,
                          auto_apply:false,field_verified:false};
      def original($why): {verdict:"keep_baseline",reason:$why,
                           auto_apply:false,field_verified:false};
      ($evidence[0] // {}) as $d |
      if $d.schema != 1 or $d.tier_mbps != $tier or
         ($d.video_source|type)!="string" or
         ($d.video_source|length)<5 or ($d.video_source|length)>120 or
         ($d.video_resolution|type)!="string" or
         ($d.video_resolution|length)<2 or ($d.video_resolution|length)>40 or
         ($d.samples|type)!="array" or ($d.samples|length)!=4 then
        invalid("invalid_schema_tier_video_or_sample_count")
      elif ([ $d.samples[] |
        (type=="object" and
         (.phase=="baseline" or .phase=="trial") and
         (.round==1 or .round==2) and
         (.duration_s|type)=="number" and .duration_s>=300 and .duration_s<=1800 and
         (.video_stalls|type)=="number" and .video_stalls>=0 and
          (.video_stalls|floor)==.video_stalls and .video_stalls<=120 and
         (.video_buffer_s|type)=="number" and .video_buffer_s>=0 and .video_buffer_s<=1800 and
         (.video_dropped_frames|type)=="number" and .video_dropped_frames>=0 and
          (.video_dropped_frames|floor)==.video_dropped_frames and .video_dropped_frames<=100000 and
         (.web_p95_ms|type)=="number" and .web_p95_ms>0 and .web_p95_ms<=10000 and
         (.chat_p95_ms|type)=="number" and .chat_p95_ms>0 and .chat_p95_ms<=10000 and
         (.ping_p95_ms|type)=="number" and .ping_p95_ms>0 and .ping_p95_ms<=10000 and
         (.loss_pct|type)=="number" and .loss_pct>=0 and .loss_pct<=100)
        ] | all | not) then
        invalid("incomplete_or_implausible_manual_measurements")
      elif ([ $d.samples[] | select(.phase=="baseline") | .round ] | sort)!=[1,2] or
           ([ $d.samples[] | select(.phase=="trial") | .round ] | sort)!=[1,2] then
        invalid("missing_duplicate_or_mismatched_ab_rounds")
      else
        ([ range(1;3) as $r |
          {b:([$d.samples[]|select(.phase=="baseline" and .round==$r)][0]),
           t:([$d.samples[]|select(.phase=="trial" and .round==$r)][0])}
        ]) as $pairs |
        ([ $pairs[] |
          (.t.video_stalls<=.b.video_stalls and
           .t.video_buffer_s<=.b.video_buffer_s+0.5 and
           .t.video_dropped_frames<=.b.video_dropped_frames+2)
        ]|all) as $video_safe |
        ([ $pairs[] |
          (.t.chat_p95_ms<=.b.chat_p95_ms*1.10+15 and
           .t.loss_pct<=.b.loss_pct+0.3 and .t.loss_pct<=1 and
           .t.ping_p95_ms<=.b.ping_p95_ms*1.15+20)
        ]|all) as $chat_safe |
        ([ $pairs[] | .t.web_p95_ms<=.b.web_p95_ms*1.10+15 ]|all) as $web_safe |
        ([ $pairs[] |
          ((.b.video_stalls>=1 and .t.video_stalls<.b.video_stalls) or
           (.b.video_buffer_s>=5 and .t.video_buffer_s<=.b.video_buffer_s*0.65))
        ]|all) as $video_gain |
        ([ $pairs[] | .t.web_p95_ms<=.b.web_p95_ms*0.85 ]|all) as $web_gain |
        if ($video_safe|not) then original("video_regressed")
        elif ($chat_safe|not) then original("chat_or_packet_loss_regressed")
        elif ($web_safe|not) then original("web_regressed")
        elif $video_gain or $web_gain then
          {verdict:"candidate_for_further_field_validation",
           reason:(if $video_gain then "repeatable_video_improvement"
                   else "video_preserved_and_repeatable_web_improvement" end),
           auto_apply:false,field_verified:false,
           note:"manual_client_observations_not_independent_proof"}
        else original("no_repeatable_useful_improvement")
        end
      end
    '
}

network_tuning_ab_menu() {
    local tier path result
    echo "Dev8：只读比对视频、网页、聊天 A/B 体验，任何结果均不自动整形。"
    echo "同一视频、清晰度、终端；基线/临时试验各两轮，每轮 >=5 分钟。"
    read -rp "线路套餐 Mbps [30]: " tier
    read -rp "A/B JSON 完整路径（空取消）: " path
    [[ -n "$path" ]] || return 0
    [[ -n "$tier" ]] || tier=30
    result=$(network_tuning_ab_assess "$tier" "$path") || return 1
    jq . <<< "$result"
    echo "注：人工采样结果不代表已经通过真实 VPS 验收。"
}

network_tuning_management() {
    local c answer
    while true; do
        clear
        network_tuning_status
        echo ""
        echo "  1. 刷新网络状态（只读）"
        echo "  2. 保存首次网络状态快照"
        echo "  3. 启用当前内核 BBR + fq"
        echo "  4. 恢复首次调优前的 BBR/fq 配置"
        echo "  5. 安全测速（iperf3 / IPv4 / IPv6）"
        echo "  6. 视频 / 网页 / 聊天体验诊断（dev3）"
        echo "  7. 只读候选整形值与 tc 安全预检（dev4）"
        echo "  8. 六样本自动诊断（dev5，开发预览）"
        echo "  9. 独立回滚演练（dev6，仅模拟）"
        echo "  10. 查看回滚演练记录（dev6）"
        echo "  11. 临时 HTB 60 秒试验（dev7，实验）"
        echo "  12. 查看 HTB 试验状态"
        echo "  13. 立即恢复 HTB 试验"
        echo "  14. A/B 视频网页聊天体验审核（dev8，只读）"
        echo "  0. 返回"
        read -rp "请选择 [0-14]: " c
        case "$c" in
            1) pause ;;
            2) network_tuning_snapshot; pause ;;
            3) network_tuning_enable_bbr; pause ;;
            4)
                echo "说明：将恢复首次快照中的拥塞算法和默认 qdisc。"
                read -rp "确认恢复？[y/N]: " answer
                if [[ "$answer" =~ ^[Yy]$ ]]; then network_tuning_restore; fi
                pause ;;
            5) network_tuning_probe_menu; pause ;;
            6) network_tuning_qoe_menu; pause ;;
            7) network_tuning_candidate_menu; pause ;;
            8) network_tuning_scan_menu; pause ;;
            9) network_tuning_rollback_rehearsal_menu; pause ;;
            10) network_tuning_rollback_rehearsal_status; pause ;;
            11) network_tuning_htb_trial_menu; pause ;;
            12) network_tuning_htb_trial_status; pause ;;
            13) network_tuning_htb_restore_now; pause ;;
            14) network_tuning_ab_menu; pause ;;
            0) return ;;
            *) sleep 1 ;;
        esac
    done
}

server_tool_dns_show() {
    echo -e "${YELLOW}当前 /etc/resolv.conf:${PLAIN}"
    cat /etc/resolv.conf 2>/dev/null || true
}

server_tool_dns_apply() {
    local dns_list="$1"
    local resolved_dropin="/etc/systemd/resolved.conf.d/99-ss2022-dns.conf"
    local backup="${STATE_DIR}/resolv.conf.server-tools.bak"
    local dns="" valid_list=""

    for dns in $dns_list; do
        dns=${dns//,/}
        [[ -n "$dns" ]] || continue

        if [[ "$dns" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            local IFS=.
            read -r a b c d <<<"$dns"
            if (( a <= 255 && b <= 255 && c <= 255 && d <= 255 )); then
                valid_list+="${dns} "
            else
                echo -e "${RED}[错误] 无效 IPv4 DNS: ${dns}${PLAIN}"
                return 1
            fi
        elif [[ "$dns" =~ ^[0-9A-Fa-f:]+$ && "$dns" == *:* ]]; then
            valid_list+="${dns} "
        else
            echo -e "${RED}[错误] 无效 DNS 地址: ${dns}${PLAIN}"
            return 1
        fi
    done

    valid_list=${valid_list% }
    [[ -n "$valid_list" ]] || {
        echo -e "${RED}[错误] 未提供有效 DNS 地址。${PLAIN}"
        return 1
    }

    mkdir -p "$STATE_DIR"
    chmod 700 "$STATE_DIR"

    if [[ -L /etc/resolv.conf ]] && systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        mkdir -p /etc/systemd/resolved.conf.d
        cat > "$resolved_dropin" <<EOF
[Resolve]
DNS=${valid_list}
FallbackDNS=
EOF
        if ! systemctl restart systemd-resolved; then
            rm -f "$resolved_dropin"
            systemctl restart systemd-resolved >/dev/null 2>&1 || true
            return 1
        fi
        echo -e "${GREEN}✔ DNS 已通过 systemd-resolved 更新：${valid_list}${PLAIN}"
        return 0
    fi

    if [[ -L /etc/resolv.conf ]]; then
        echo -e "${RED}[错误] /etc/resolv.conf 是符号链接，但未检测到可管理的 systemd-resolved。${PLAIN}"
        echo -e "${YELLOW}为避免破坏 NetworkManager 或其他网络管理器，本工具不会强制覆盖。${PLAIN}"
        return 1
    fi

    if [[ ! -f "$backup" && -f /etc/resolv.conf ]]; then
        cp -a /etc/resolv.conf "$backup" || return 1
        chmod 600 "$backup"
    fi

    : > /etc/resolv.conf
    for dns in $valid_list; do
        printf 'nameserver %s\n' "$dns" >> /etc/resolv.conf
    done
    printf '%s\n' 'options timeout:2 attempts:2' >> /etc/resolv.conf

    echo -e "${GREEN}✔ DNS 已更新：${valid_list}${PLAIN}"
}

server_tool_dns_restore() {
    local resolved_dropin="/etc/systemd/resolved.conf.d/99-ss2022-dns.conf"
    local backup="${STATE_DIR}/resolv.conf.server-tools.bak"

    if [[ -f "$resolved_dropin" ]]; then
        rm -f "$resolved_dropin"
        systemctl restart systemd-resolved >/dev/null 2>&1 || true
        echo -e "${GREEN}✔ 已移除本脚本的 systemd-resolved DNS 配置。${PLAIN}"
        return 0
    fi

    if [[ -f "$backup" && ! -L /etc/resolv.conf ]]; then
        cp -af "$backup" /etc/resolv.conf
        rm -f "$backup"
        echo -e "${GREEN}✔ 已恢复修改前的 DNS 配置。${PLAIN}"
        return 0
    fi

    echo -e "${YELLOW}没有找到本工具可恢复的 DNS 备份。${PLAIN}"
}

server_tool_dns_management() {
    local c custom_dns
    while true; do
        clear
        echo -e "${CYAN}════════════════════ DNS 管理 ════════════════════${PLAIN}"
        server_tool_dns_show
        echo ""
        echo "  1. Cloudflare + Google"
        echo "     1.1.1.1 / 8.8.8.8 / 2606:4700:4700::1111 / 2001:4860:4860::8888"
        echo "  2. Quad9 + Cloudflare"
        echo "     9.9.9.9 / 1.1.1.1 / 2620:fe::fe / 2606:4700:4700::1111"
        echo "  3. 阿里 DNS + DNSPod"
        echo "     223.5.5.5 / 119.29.29.29 / 2400:3200::1 / 2402:4e00::"
        echo "  4. 自定义 DNS（支持解锁 DNS）"
        echo "  5. 恢复修改前 DNS"
        echo "  0. 返回"
        read -rp "请选择 [0-5]: " c
        case "$c" in
            1)
                server_tool_dns_apply "1.1.1.1 8.8.8.8 2606:4700:4700::1111 2001:4860:4860::8888"
                pause
                ;;
            2)
                server_tool_dns_apply "9.9.9.9 1.1.1.1 2620:fe::fe 2606:4700:4700::1111"
                pause
                ;;
            3)
                server_tool_dns_apply "223.5.5.5 119.29.29.29 2400:3200::1 2402:4e00::"
                pause
                ;;
            4)
                echo ""
                echo "请输入厂商提供的 DNS IP。"
                echo "支持 IPv4 / IPv6；多个地址使用空格分隔。"
                echo "示例: 1.2.3.4 5.6.7.8"
                read -rp "自定义 DNS: " custom_dns
                [[ -n "$custom_dns" ]] && server_tool_dns_apply "$custom_dns"
                pause
                ;;
            5)
                server_tool_dns_restore
                pause
                ;;
            0) return ;;
            *) sleep 1 ;;
        esac
    done
}

server_tool_ip_priority_status() {
    if platform_is_alpine; then
        echo "Alpine/musl：不使用 gai.conf"
        return
    fi
    if grep -q '^precedence ::ffff:0:0/96[[:space:]]\+100[[:space:]]*# ss2022-prefer-ipv4$' /etc/gai.conf 2>/dev/null; then
        echo "IPv4 优先"
    else
        echo "系统默认（通常 IPv6 优先）"
    fi
}
server_tool_ip_priority_management() {
    local c
    if platform_is_alpine; then
        clear
        echo -e "${CYAN}════════════ IPv4 / IPv6 地址优先级 ════════════${PLAIN}"
        echo -e "${YELLOW}Alpine 使用 musl libc，/etc/gai.conf 的 glibc precedence 规则不会生效。${PLAIN}"
        echo "因此这里不写入无效配置。"
        echo "vps-bootstrap 业务流量请使用“全局业务出口地址族 / 应用地址族分流”；"
        echo "需要彻底关闭某地址族时使用下方 IPv4 / IPv6 协议族管理。"
        pause
        return
    fi
    while true; do
        clear
        echo -e "${CYAN}════════════ IPv4 / IPv6 优先级 ════════════${PLAIN}"
        echo "当前模式: $(server_tool_ip_priority_status)"
        echo ""
        echo "  1. 设置 IPv4 优先"
        echo "  2. 恢复系统默认优先级"
        echo "  0. 返回"
        read -rp "请选择 [0-2]: " c
        case "$c" in
            1)
                touch /etc/gai.conf
                sed -i '/# ss2022-prefer-ipv4$/d' /etc/gai.conf
                echo 'precedence ::ffff:0:0/96  100 # ss2022-prefer-ipv4' >> /etc/gai.conf
                echo -e "${GREEN}✔ 已设置 IPv4 优先。${PLAIN}"; pause ;;
            2)
                [[ -f /etc/gai.conf ]] && sed -i '/# ss2022-prefer-ipv4$/d' /etc/gai.conf
                echo -e "${GREEN}✔ 已恢复系统默认地址优先级。${PLAIN}"; pause ;;
            0) return ;;
            *) sleep 1 ;;
        esac
    done
}
server_tool_ip_family_mode() {
    local mode="dual"
    if [[ -f "$IP_FAMILY_MODE_FILE" ]]; then
        mode=$(tr -d '[:space:]' < "$IP_FAMILY_MODE_FILE" 2>/dev/null)
    fi
    case "$mode" in
        dual|ipv4-only|ipv6-only) echo "$mode" ;;
        *) echo "dual" ;;
    esac
}

server_tool_ip_family_mode_label() {
    case "${1:-dual}" in
        ipv4-only) echo "仅 IPv4（IPv6 已关闭）" ;;
        ipv6-only) echo "仅 IPv6（IPv4 已关闭）" ;;
        *) echo "IPv4 + IPv6 双栈" ;;
    esac
}

server_tool_ip_family_mode_allows() {
    local family="${1:-default}" mode
    [[ "$family" == "default" ]] && return 0
    mode=$(server_tool_ip_family_mode)
    case "$mode:$family" in
        dual:ipv4|dual:ipv6|ipv4-only:ipv4|ipv6-only:ipv6) return 0 ;;
        *) return 1 ;;
    esac
}

server_tool_current_ssh_family() {
    local peer=""
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        peer=${SSH_CONNECTION%% *}
    elif [[ -n "${SSH_CLIENT:-}" ]]; then
        peer=${SSH_CLIENT%% *}
    fi
    [[ -n "$peer" ]] || { echo "unknown"; return; }
    if [[ "$peer" == *:* ]]; then echo "ipv6"; else echo "ipv4"; fi
}

server_tool_native_family_ready() {
    local family="$1"
    case "$family" in
        ipv4)
            ip -4 addr show scope global 2>/dev/null | grep -q 'inet ' || return 1
            ip -4 route show default 2>/dev/null | grep -q '^default ' || return 1
            curl -4fsS --connect-timeout 4 --max-time 8 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep -q '^ip='
            ;;
        ipv6)
            ip -6 addr show scope global 2>/dev/null | grep -q 'inet6 ' || return 1
            ip -6 route show default 2>/dev/null | grep -q '^default ' || return 1
            curl -6fsS --connect-timeout 4 --max-time 8 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep -q '^ip='
            ;;
        *) return 1 ;;
    esac
}

server_tool_ip_family_policy_conflict() {
    local mode="$1" blocked="" global default_ref effective count i r ref fam name found=0
    [[ "$mode" == "ipv4-only" ]] && blocked="ipv6"
    [[ "$mode" == "ipv6-only" ]] && blocked="ipv4"
    [[ -n "$blocked" ]] || return 1

    routing_init_state || return 1
    global=$(routing_global_ip_family)
    default_ref=$(jq -r '.default_outbound // "direct"' "$ROUTING_FILE")
    effective=$(routing_effective_family "$global" "$default_ref")
    if [[ "$effective" == "$blocked" ]]; then
        echo -e "${RED}[冲突] 全局默认出口当前固定为 $(routing_ip_family_label "$blocked")。${PLAIN}"
        found=1
    fi

    count=$(jq '.rules|length' "$ROUTING_FILE")
    i=0
    while [[ $i -lt $count ]]; do
        r=$(jq -c ".rules[$i]" "$ROUTING_FILE")
        ref=$(jq -r '.outbound // "default"' <<<"$r")
        fam=$(routing_effective_family "$(jq -r '.ip_family // "default"' <<<"$r")" "$ref")
        if [[ "$fam" == "$blocked" ]]; then
            name=$(jq -r '.name // "未命名规则"' <<<"$r")
            echo -e "${RED}[冲突] 规则 ${name} 当前固定为 $(routing_ip_family_label "$blocked")。${PLAIN}"
            found=1
        fi
        i=$((i+1))
    done

    [[ $found -eq 1 ]]
}

server_tool_install_ip_family_guard() {
    ensure_test_dependency nft nftables || {
        echo -e "${RED}[错误] nftables 不可用，无法安全管理 IPv4 / IPv6 关闭状态。${PLAIN}"
        return 1
    }
    mkdir -p "$STATE_DIR" /usr/local/lib/ss2022 || return 1
    chmod 700 "$STATE_DIR"
    cat > "$IP_FAMILY_APPLY_HELPER" <<'EOF'
#!/bin/bash
set -u
STATE_FILE="/etc/ss2022/ip-family-mode"
TABLE="ss2022_ip_family"
mode="dual"
[[ -f "$STATE_FILE" ]] && mode=$(tr -d '[:space:]' < "$STATE_FILE" 2>/dev/null)
command -v nft >/dev/null 2>&1 || exit 1
nft delete table inet "$TABLE" >/dev/null 2>&1 || true
case "$mode" in
  dual) exit 0 ;;
  ipv4-only|ipv6-only) ;;
  *) exit 1 ;;
esac
nft add table inet "$TABLE"
nft 'add chain inet ss2022_ip_family input { type filter hook input priority -20; policy accept; }'
nft 'add chain inet ss2022_ip_family output { type filter hook output priority -20; policy accept; }'
if [[ "$mode" == "ipv4-only" ]]; then
    nft 'add rule inet ss2022_ip_family input meta nfproto ipv6 iifname != "lo" drop'
    nft 'add rule inet ss2022_ip_family output meta nfproto ipv6 oifname != "lo" drop'
else
    nft 'add rule inet ss2022_ip_family input meta nfproto ipv4 iifname != "lo" drop'
    nft 'add rule inet ss2022_ip_family output meta nfproto ipv4 oifname != "lo" drop'
fi
EOF
    chmod 700 "$IP_FAMILY_APPLY_HELPER"

    if [[ "$PLATFORM_INIT" == "systemd" ]]; then
        cat > "$IP_FAMILY_SERVICE" <<EOF
[Unit]
Description=vps-bootstrap IPv4/IPv6 family guard
After=network-online.target
Wants=network-online.target
Before=sing-box.service ${XRAY_SERVICE_NAME}.service ${REALM_SERVICE_NAME}.service

[Service]
Type=oneshot
ExecStart=${IP_FAMILY_APPLY_HELPER}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        chmod 644 "$IP_FAMILY_SERVICE"
        service_daemon_reload || return 1
    else
        cat > "$IP_FAMILY_OPENRC_SERVICE" <<EOF
#!/sbin/openrc-run
description="vps-bootstrap IPv4/IPv6 family guard"
depend() {
    need net
    before sing-box ${XRAY_SERVICE_NAME} ${REALM_SERVICE_NAME}
}
start() {
    ebegin "Applying vps-bootstrap IP family guard"
    ${IP_FAMILY_APPLY_HELPER}
    eend $?
}
stop() {
    return 0
}
EOF
        chmod 755 "$IP_FAMILY_OPENRC_SERVICE"
    fi
    service_enable "$IP_FAMILY_SERVICE_NAME" || return 1
}
server_tool_set_ip_family_mode() {
    local new_mode="$1" old_mode ssh_family keep_family label
    old_mode=$(server_tool_ip_family_mode)
    [[ "$new_mode" != "$old_mode" ]] || {
        echo -e "${GREEN}当前已经是：$(server_tool_ip_family_mode_label "$new_mode")。${PLAIN}"
        return 0
    }

    if [[ "$old_mode" != "dual" && "$new_mode" != "dual" ]]; then
        echo -e "${YELLOW}[提示] 请先恢复 IPv4 + IPv6 双栈，再切换到另一单地址族模式。${PLAIN}"
        return 1
    fi

    case "$new_mode" in
        ipv4-only) keep_family="ipv4" ;;
        ipv6-only) keep_family="ipv6" ;;
        dual) keep_family="" ;;
        *) return 1 ;;
    esac

    if [[ -n "$keep_family" ]]; then
        ssh_family=$(server_tool_current_ssh_family)
        if [[ "$ssh_family" != "unknown" && "$ssh_family" != "$keep_family" ]]; then
            echo -e "${RED}[拒绝] 当前 SSH 会话正在使用 ${ssh_family^^}，不能关闭该地址族。${PLAIN}"
            echo "请先用 ${keep_family^^} 地址重新建立 SSH 会话后再操作。"
            return 1
        fi

        if ! server_tool_native_family_ready "$keep_family"; then
            echo -e "${RED}[拒绝] 未确认 ${keep_family^^} 原生公网连接可用，不能关闭另一地址族。${PLAIN}"
            return 1
        fi

        if server_tool_ip_family_policy_conflict "$new_mode"; then
            echo -e "${RED}[拒绝] 请先调整上面的全局/应用地址族规则，再关闭协议族。${PLAIN}"
            return 1
        fi
    fi

    server_tool_install_ip_family_guard || return 1
    printf '%s
' "$new_mode" > "$IP_FAMILY_MODE_FILE" || return 1
    chmod 600 "$IP_FAMILY_MODE_FILE"

    if ! service_restart "$IP_FAMILY_SERVICE_NAME"; then
        echo -e "${RED}[错误] 新协议族策略应用失败，正在恢复。${PLAIN}"
        printf '%s
' "$old_mode" > "$IP_FAMILY_MODE_FILE"
        service_restart "$IP_FAMILY_SERVICE_NAME" >/dev/null 2>&1 || true
        return 1
    fi

    label=$(server_tool_ip_family_mode_label "$new_mode")
    echo -e "${GREEN}✔ 已切换为：${label}。${PLAIN}"
    if [[ "$new_mode" != "dual" ]]; then
        echo -e "${YELLOW}说明: IP 地址本身不会被删除；本脚本通过独立 nftables 表阻断已关闭地址族的公网收发，因此可以安全恢复。${PLAIN}"
    fi
}

server_tool_ip_family_status() {
    local v4="无" v6="无" mode global
    v4=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | head -n1)
    v6=$(ip -6 -o addr show scope global 2>/dev/null | awk '{print $4}' | head -n1)
    v4=${v4:-无}
    v6=${v6:-无}
    mode=$(server_tool_ip_family_mode)
    global=$(routing_global_ip_family)
    echo "  IPv4 地址     : $v4"
    echo "  IPv6 地址     : $v6"
    echo "  系统协议族状态 : $(server_tool_ip_family_mode_label "$mode")"
    echo "  业务出口地址族 : $(routing_ip_family_label "$global")"
    echo "  地址优先级     : $(server_tool_ip_priority_status)"
}

server_tool_ip_family_management() {
    local c
    while true; do
        clear
        routing_init_state >/dev/null 2>&1 || true
        echo -e "${CYAN}════════════ IPv4 / IPv6 管理 ════════════${PLAIN}"
        server_tool_ip_family_status
        echo ""
        echo "  1. IPv4 / IPv6 地址优先级"
        echo "  2. 全局业务出口地址族（双栈 / 仅 IPv4 / 仅 IPv6）"
        echo "  3. 应用地址族分流（YouTube / ChatGPT / MyTVSuper 等）"
        echo "  ------------------------------------------"
        echo "  4. 关闭 IPv4（仅保留 IPv6 公网通信）"
        echo "  5. 关闭 IPv6（仅保留 IPv4 公网通信）"
        echo "  6. 恢复 IPv4 + IPv6 双栈公网通信"
        echo "  0. 返回"
        read -rp "请选择 [0-6]: " c
        case "$c" in
            1) server_tool_ip_priority_management ;;
            2) routing_global_ip_family_management ;;
            3) routing_app_family_management ;;
            4) server_tool_set_ip_family_mode ipv6-only; pause ;;
            5) server_tool_set_ip_family_mode ipv4-only; pause ;;
            6) server_tool_set_ip_family_mode dual; pause ;;
            0) return ;;
            *) sleep 1 ;;
        esac
    done
}

server_tool_port_usage_show_all() {
    echo -e "${YELLOW}当前 TCP / UDP 监听端口:${PLAIN}"
    if command -v ss >/dev/null 2>&1; then
        ss -H -lntup 2>/dev/null | awk '
        {
            proto=$1
            local_addr=$5
            proc=""
            for (i=6;i<=NF;i++) proc=proc $i " "
            printf "  %-5s %-30s %s\n", proto, local_addr, proc
        }'
    else
        echo "  未找到 ss 命令。"
    fi

    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        echo ""
        echo -e "${YELLOW}Docker 容器端口映射:${PLAIN}"
        docker ps --format '  {{.Names}}\t{{.Ports}}' 2>/dev/null || true
    fi
}

server_tool_port_usage_detail() {
    local port="$1" found=0

    echo -e "${CYAN}══════════════ 端口 ${port} 占用详情 ══════════════${PLAIN}"

    if command -v ss >/dev/null 2>&1; then
        local lines
        lines=$(ss -H -lntup 2>/dev/null | awk -v p="$port" '
        {
            addr=$5
            n=split(addr,a,":")
            if (a[n] == p) print
        }')
        if [[ -n "$lines" ]]; then
            found=1
            printf '%s\n' "$lines"
        fi
    fi

    if command -v lsof >/dev/null 2>&1; then
        local lsof_out
        lsof_out=$(lsof -nP -i ":${port}" 2>/dev/null || true)
        if [[ -n "$lsof_out" ]]; then
            found=1
            echo ""
            echo -e "${YELLOW}进程详情:${PLAIN}"
            printf '%s\n' "$lsof_out"
        fi
    fi

    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        local docker_out
        docker_out=$(docker ps --format '{{.Names}}\t{{.Ports}}' 2>/dev/null \
            | awk -F'\t' -v p="$port" '$2 ~ ("[:]" p "->") || $2 ~ ("0\\.0\\.0\\.0:" p "->") || $2 ~ ("\\[::\\]:" p "->") {print}')
        if [[ -n "$docker_out" ]]; then
            found=1
            echo ""
            echo -e "${YELLOW}Docker 容器:${PLAIN}"
            printf '  %s\n' "$docker_out"
        fi
    fi

    if [[ $found -eq 0 ]]; then
        echo -e "${GREEN}未发现端口 ${port} 被监听占用。${PLAIN}"
    fi
}

server_tool_port_listener_lines() {
    local port="$1"

    command -v ss >/dev/null 2>&1 || return 1
    ss -H -lntup 2>/dev/null | awk -v p="$port" '
    {
        addr=$5
        n=split(addr,a,":")
        if (a[n] == p) print
    }'
}

server_tool_port_listener_pids() {
    local port="$1"
    local lines

    lines=$(server_tool_port_listener_lines "$port" 2>/dev/null || true)
    [[ -n "$lines" ]] || return 0

    printf '%s\n' "$lines" \
        | grep -oE 'pid=[0-9]+' 2>/dev/null \
        | cut -d= -f2 \
        | sort -nu
}

server_tool_pid_systemd_unit() {
    local pid="$1" unit="" pf="" pf_pid="" svc=""
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1

    if [[ "$PLATFORM_INIT" == "systemd" ]]; then
        if [[ -r "/proc/${pid}/cgroup" ]]; then
            unit=$(sed -nE 's#.*[/]([^/]+\.service)(/.*)?$#\1#p' "/proc/${pid}/cgroup" 2>/dev/null | head -n1)
        fi
        if [[ -z "$unit" ]]; then
            unit=$(systemctl status "$pid" --no-pager 2>/dev/null | sed -nE 's/^[[:space:]]*●[[:space:]]+([^[:space:]]+\.service).*/\1/p' | head -n1)
        fi
        [[ -n "$unit" ]] && printf '%s\n' "$unit"
        return
    fi

    # OpenRC 没有 systemd cgroup unit 映射；优先从常见 pidfile 反查 init.d 服务。
    for pf in /run/*.pid /run/*/*.pid /var/run/*.pid /var/run/*/*.pid; do
        [[ -r "$pf" ]] || continue
        pf_pid=$(head -n1 "$pf" 2>/dev/null | tr -dc '0-9')
        [[ "$pf_pid" == "$pid" ]] || continue
        svc=${pf##*/}; svc=${svc%.pid}
        [[ -x "/etc/init.d/$svc" ]] || continue
        printf '%s\n' "$svc"
        return 0
    done

    for svc in sing-box "$XRAY_SERVICE_NAME" "$REALM_SERVICE_NAME" sshd chronyd ntpd crond; do
        [[ -x "/etc/init.d/$svc" ]] || continue
        [[ "$(service_main_pid "$svc" 2>/dev/null || true)" == "$pid" ]] || continue
        printf '%s\n' "$svc"
        return 0
    done
    return 1
}
server_tool_port_docker_containers() {
    local port="$1"

    command -v docker >/dev/null 2>&1 || return 0
    docker info >/dev/null 2>&1 || return 0

    docker ps --format '{{.ID}}\t{{.Names}}\t{{.Ports}}' 2>/dev/null \
        | awk -F'\t' -v p="$port" '
          $3 ~ ("0\\.0\\.0\\.0:" p "->") ||
          $3 ~ ("\\[::\\]:" p "->") ||
          $3 ~ ("127\\.0\\.0\\.1:" p "->") {
              print
          }'
}

server_tool_port_is_current_ssh() {
    local port="$1"
    local ssh_port=""

    [[ -n "${SSH_CONNECTION:-}" ]] || return 1
    ssh_port=$(awk '{print $4}' <<<"$SSH_CONNECTION")
    [[ "$ssh_port" == "$port" ]]
}

server_tool_port_release_show_targets() {
    local port="$1"
    local pids pid comm args unit docker_lines lines

    echo -e "${CYAN}══════════════ 端口 ${port} 当前占用 ══════════════${PLAIN}"

    lines=$(server_tool_port_listener_lines "$port" 2>/dev/null || true)
    if [[ -z "$lines" ]]; then
        echo -e "${GREEN}当前没有发现监听进程，端口 ${port} 已经空闲。${PLAIN}"
        return 1
    fi

    printf '%s\n' "$lines"
    echo ""

    pids=$(server_tool_port_listener_pids "$port" 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
        echo -e "${YELLOW}监听进程:${PLAIN}"
        while read -r pid; do
            [[ -n "$pid" ]] || continue
            comm=$(ps -p "$pid" -o comm= 2>/dev/null | xargs || true)
            args=$(ps -p "$pid" -o args= 2>/dev/null | xargs || true)
            unit=$(server_tool_pid_systemd_unit "$pid" 2>/dev/null || true)

            echo "  PID     : ${pid}"
            echo "  进程    : ${comm:-未知}"
            [[ -n "$unit" ]] && echo "  服务    : ${unit}"
            echo "  命令    : ${args:-未知}"
            echo ""
        done <<<"$pids"
    else
        echo -e "${YELLOW}[提示] ss 没有返回可识别 PID，可能是权限、内核或容器网络限制。${PLAIN}"
        echo ""
    fi

    docker_lines=$(server_tool_port_docker_containers "$port" 2>/dev/null || true)
    if [[ -n "$docker_lines" ]]; then
        echo -e "${YELLOW}Docker 容器端口映射:${PLAIN}"
        while IFS=$'\t' read -r cid cname cports; do
            echo "  容器    : ${cname} (${cid})"
            echo "  映射    : ${cports}"
        done <<<"$docker_lines"
        echo ""
    fi

    return 0
}

server_tool_port_stop_systemd_units() {
    local port="$1" disable="${2:-no}" pids pid unit svc
    local -A seen_units=()
    local found=0 failed=0

    pids=$(server_tool_port_listener_pids "$port" 2>/dev/null || true)
    [[ -n "$pids" ]] || { echo -e "${YELLOW}没有发现可识别的监听 PID。${PLAIN}"; return 1; }

    while read -r pid; do
        [[ -n "$pid" ]] || continue
        unit=$(server_tool_pid_systemd_unit "$pid" 2>/dev/null || true)
        [[ -n "$unit" ]] || continue
        [[ -n "${seen_units[$unit]:-}" ]] && continue
        seen_units["$unit"]=1
        found=1
        svc=${unit%.service}
        case "$svc" in
            ssh|sshd)
                echo -e "${RED}[拒绝] 不允许通过端口释放工具停止 SSH 服务：${svc}${PLAIN}"
                failed=1; continue ;;
        esac
        echo -e "${YELLOW}>> 处理服务 ${svc}...${PLAIN}"
        if [[ "$disable" == "yes" ]]; then
            service_disable_now "$svc"
            if service_is_active "$svc"; then
                echo -e "${RED}[错误] ${svc} 停止/禁用失败。${PLAIN}"; failed=1
            else
                echo -e "${GREEN}✔ ${svc} 已停止并移除开机自启。${PLAIN}"
            fi
        else
            if service_stop "$svc"; then
                echo -e "${GREEN}✔ ${svc} 已停止。${PLAIN}"
            else
                echo -e "${RED}[错误] ${svc} 停止失败。${PLAIN}"; failed=1
            fi
        fi
    done <<<"$pids"

    [[ $found -eq 1 ]] || { echo -e "${YELLOW}没有检测到对应的系统服务。${PLAIN}"; return 1; }
    sleep 1
    [[ -z "$(server_tool_port_listener_lines "$port" 2>/dev/null || true)" ]] || {
        echo -e "${YELLOW}[提示] 端口 ${port} 仍有监听进程，请重新查看占用详情。${PLAIN}"
        return 1
    }
    [[ $failed -eq 0 ]]
}
server_tool_port_stop_docker() {
    local port="$1"
    local docker_lines cid cname cports
    local found=0 failed=0

    docker_lines=$(server_tool_port_docker_containers "$port" 2>/dev/null || true)
    [[ -n "$docker_lines" ]] || {
        echo -e "${YELLOW}没有发现映射端口 ${port} 的 Docker 容器。${PLAIN}"
        return 1
    }

    while IFS=$'\t' read -r cid cname cports; do
        [[ -n "$cid" ]] || continue
        found=1
        echo -e "${YELLOW}>> 停止 Docker 容器 ${cname} (${cid})...${PLAIN}"
        if docker stop "$cid"; then
            echo -e "${GREEN}✔ 容器 ${cname} 已停止。${PLAIN}"
        else
            echo -e "${RED}[错误] 容器 ${cname} 停止失败。${PLAIN}"
            failed=1
        fi
    done <<<"$docker_lines"

    sleep 1
    if [[ -n "$(server_tool_port_listener_lines "$port" 2>/dev/null || true)" ]]; then
        echo -e "${YELLOW}[提示] 端口 ${port} 仍有监听进程。${PLAIN}"
        return 1
    fi

    [[ $found -eq 1 && $failed -eq 0 ]]
}

server_tool_port_terminate_processes() {
    local port="$1"
    local pids pid comm confirm
    local -a targets=()
    local -a remaining=()

    pids=$(server_tool_port_listener_pids "$port" 2>/dev/null || true)
    [[ -n "$pids" ]] || {
        echo -e "${YELLOW}没有发现可结束的监听 PID。${PLAIN}"
        return 1
    }

    while read -r pid; do
        [[ -n "$pid" ]] || continue

        if [[ "$pid" == "1" || "$pid" == "$$" || "$pid" == "$PPID" ]]; then
            echo -e "${RED}[拒绝] PID ${pid} 属于关键/当前进程，不允许结束。${PLAIN}"
            continue
        fi

        comm=$(ps -p "$pid" -o comm= 2>/dev/null | xargs || true)
        case "$comm" in
            sshd|systemd|init)
                echo -e "${RED}[拒绝] 不允许直接结束关键进程 ${comm} (PID ${pid})。${PLAIN}"
                continue
                ;;
        esac

        targets+=("$pid")
    done <<<"$pids"

    [[ ${#targets[@]} -gt 0 ]] || {
        echo -e "${RED}[错误] 没有安全可结束的监听进程。${PLAIN}"
        return 1
    }

    echo ""
    echo -e "${YELLOW}[警告] 将直接结束以下 PID：${targets[*]}${PLAIN}"
    echo "优先发送 SIGTERM。"
    read -rp "确认直接结束进程？请输入 RELEASE: " confirm
    [[ "$confirm" == "RELEASE" ]] || {
        echo "已取消。"
        return 0
    }

    for pid in "${targets[@]}"; do
        kill "$pid" 2>/dev/null || true
    done

    sleep 2

    for pid in "${targets[@]}"; do
        kill -0 "$pid" 2>/dev/null && remaining+=("$pid")
    done

    if [[ ${#remaining[@]} -gt 0 ]]; then
        echo -e "${YELLOW}[提示] PID ${remaining[*]} 在 SIGTERM 后仍未退出。${PLAIN}"
        read -rp "如确认强制结束，请输入 KILL: " confirm
        if [[ "$confirm" == "KILL" ]]; then
            for pid in "${remaining[@]}"; do
                kill -9 "$pid" 2>/dev/null || true
            done
            sleep 1
        else
            echo "已取消强制结束。"
        fi
    fi

    if [[ -z "$(server_tool_port_listener_lines "$port" 2>/dev/null || true)" ]]; then
        echo -e "${GREEN}✔ 端口 ${port} 已释放。${PLAIN}"
        return 0
    fi

    echo -e "${YELLOW}[提示] 端口 ${port} 仍被占用。若进程自动重启，通常说明背后还有 systemd / OpenRC / Docker / Supervisor 等守护机制。${PLAIN}"
    return 1
}

server_tool_port_release() {
    local port c
    local docker_lines pids pid unit has_unit=0

    clear
    echo -e "${CYAN}════════════════ 当前全部监听端口 ════════════════${PLAIN}"
    server_tool_port_usage_show_all
    echo ""
    echo -e "${YELLOW}请输入需要释放的端口号；输入 0 返回。${PLAIN}"
    read -rp "端口号 [0=返回]: " port

    [[ "$port" == "0" ]] && return

    if ! validate_port_number "$port"; then
        echo -e "${RED}端口无效。${PLAIN}"
        pause
        return
    fi

    if server_tool_port_is_current_ssh "$port"; then
        echo -e "${RED}════════════════ 安全保护 ════════════════${PLAIN}"
        echo -e "${RED}[拒绝] 端口 ${port} 正是当前 SSH 会话使用的服务器端口。${PLAIN}"
        echo -e "${YELLOW}为了避免把当前远程连接直接断开，本工具不会释放该端口。${PLAIN}"
        pause
        return
    fi

    clear
    if ! server_tool_port_release_show_targets "$port"; then
        pause
        return
    fi

    pids=$(server_tool_port_listener_pids "$port" 2>/dev/null || true)
    while read -r pid; do
        [[ -n "$pid" ]] || continue
        unit=$(server_tool_pid_systemd_unit "$pid" 2>/dev/null || true)
        if [[ -n "$unit" && "$unit" != "ssh.service" && "$unit" != "sshd.service" ]]; then
            has_unit=1
            break
        fi
    done <<<"$pids"

    docker_lines=$(server_tool_port_docker_containers "$port" 2>/dev/null || true)

    echo "请选择释放方式："
    if [[ $has_unit -eq 1 ]]; then
        echo "  1. 停止对应系统服务"
        echo "  2. 停止并禁用对应系统服务"
    else
        echo "  1. 停止对应系统服务（未检测到）"
        echo "  2. 停止并禁用对应系统服务（未检测到）"
    fi

    if [[ -n "$docker_lines" ]]; then
        echo "  3. 停止对应 Docker 容器"
    else
        echo "  3. 停止对应 Docker 容器（未检测到）"
    fi

    echo "  4. 直接结束监听进程"
    echo "  0. 取消"
    read -rp "请选择 [0-4]: " c

    case "$c" in
        1)
            server_tool_port_stop_systemd_units "$port" "no"
            ;;
        2)
            echo -e "${YELLOW}[注意] 该操作会同时取消对应服务的开机自启。${PLAIN}"
            read -rp "确认继续？请输入 DISABLE: " c
            [[ "$c" == "DISABLE" ]] && server_tool_port_stop_systemd_units "$port" "yes"
            ;;
        3)
            server_tool_port_stop_docker "$port"
            ;;
        4)
            server_tool_port_terminate_processes "$port"
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}输入无效。${PLAIN}"
            ;;
    esac

    echo ""
    if [[ -n "$(server_tool_port_listener_lines "$port" 2>/dev/null || true)" ]]; then
        echo -e "${YELLOW}端口 ${port} 当前仍有监听：${PLAIN}"
        server_tool_port_listener_lines "$port"
    else
        echo -e "${GREEN}✔ 端口 ${port} 当前已空闲。${PLAIN}"
    fi
    pause
}

server_tool_port_usage() {
    local c port
    while true; do
        clear
        echo -e "${CYAN}════════════════════ 端口占用 ════════════════════${PLAIN}"
        echo "  1. 查看全部监听端口"
        echo "  2. 查询指定端口"
        echo "  3. 释放指定端口"
        echo "  0. 返回"
        echo -e "${CYAN}═══════════════════════════════════════════════════${PLAIN}"
        read -rp "请选择 [0-3]: " c
        case "$c" in
            1)
                clear
                server_tool_port_usage_show_all
                pause
                ;;
            2)
                read -rp "请输入端口号: " port
                if ! validate_port_number "$port"; then
                    echo -e "${RED}端口无效。${PLAIN}"
                    pause
                    continue
                fi
                clear
                server_tool_port_usage_detail "$port"
                pause
                ;;
            3)
                server_tool_port_release
                ;;
            0) return ;;
            *) sleep 1 ;;
        esac
    done
}

server_tool_timezone_management() {
    local c zone
    if platform_is_alpine && [[ ! -e /usr/share/zoneinfo/UTC ]]; then
        pkg_install tzdata || { echo -e "${RED}[错误] tzdata 安装失败。${PLAIN}"; pause; return; }
    fi
    while true; do
        clear
        echo -e "${CYAN}════════════════════ 时区管理 ════════════════════${PLAIN}"
        echo "当前时区: $(timedatectl show -p Timezone --value 2>/dev/null || date +%Z)"
        echo ""
        echo "  1. UTC"
        echo "  2. Asia/Shanghai"
        echo "  3. Asia/Tokyo"
        echo "  4. America/Los_Angeles"
        echo "  5. Europe/London"
        echo "  6. 自定义 IANA 时区"
        echo "  0. 返回"
        read -rp "请选择 [0-6]: " c
        case "$c" in
            1) zone="UTC" ;;
            2) zone="Asia/Shanghai" ;;
            3) zone="Asia/Tokyo" ;;
            4) zone="America/Los_Angeles" ;;
            5) zone="Europe/London" ;;
            6)
                read -rp "请输入时区，例如 Asia/Singapore: " zone
                ;;
            0) return ;;
            *) sleep 1; continue ;;
        esac

        if command -v timedatectl >/dev/null 2>&1 && timedatectl list-timezones 2>/dev/null | grep -Fxq "$zone"; then
            timedatectl set-timezone "$zone" &&
                echo -e "${GREEN}✔ 时区已设置为 ${zone}。${PLAIN}"
        elif [[ -e "/usr/share/zoneinfo/${zone}" ]]; then
            ln -sf "/usr/share/zoneinfo/${zone}" /etc/localtime
            echo "$zone" > /etc/timezone 2>/dev/null || true
            echo -e "${GREEN}✔ 时区已设置为 ${zone}。${PLAIN}"
        else
            echo -e "${RED}[错误] 无效时区: ${zone}${PLAIN}"
        fi
        pause
    done
}

server_tool_ssh_ports() {
    if command -v sshd >/dev/null 2>&1; then
        sshd -T 2>/dev/null | awk '$1=="port" {print $2}' | sort -nu
    fi
}

server_tool_ssh_add_port() {
    local new_port old_ports target_conf service_name backup ans tmp_main use_dropin="no"
    local include_dir="/etc/ssh/sshd_config.d"
    local dropin="${include_dir}/99-ss2022-port.conf"
    local main_conf="/etc/ssh/sshd_config"

    command -v sshd >/dev/null 2>&1 || { echo -e "${RED}[错误] 未找到 sshd。${PLAIN}"; return 1; }
    old_ports=$(server_tool_ssh_ports)
    echo "当前 SSH 端口: $(tr '\n' ' ' <<<"$old_ports")"
    read -rp "请输入要新增的 SSH 端口: " new_port
    validate_port_number "$new_port" || { echo -e "${RED}[错误] 端口无效。${PLAIN}"; return 1; }
    if grep -qx "$new_port" <<<"$old_ports"; then
        echo -e "${YELLOW}该端口已经是 SSH 监听端口。${PLAIN}"; return 0
    fi
    if port_in_use_by_other_process "$new_port" "" >/tmp/ss2022-ssh-port.$$ 2>/dev/null; then
        echo -e "${RED}[错误] 端口 ${new_port} 已被其他进程占用。${PLAIN}"
        cat /tmp/ss2022-ssh-port.$$ 2>/dev/null || true; rm -f /tmp/ss2022-ssh-port.$$; return 1
    fi
    rm -f /tmp/ss2022-ssh-port.$$ 2>/dev/null || true
    echo -e "${YELLOW}[安全策略] 新端口会与现有 SSH 端口同时保留，不会删除旧端口。${PLAIN}"
    echo -e "${YELLOW}还需确认云厂商安全组/防火墙已放行 ${new_port}/TCP。${PLAIN}"
    read -rp "确认新增？[y/N]: " ans
    [[ "$ans" =~ ^[Yy]$ ]] || return 0

    if grep -Eiq '^[[:space:]]*Include[[:space:]]+.*sshd_config\.d' "$main_conf" 2>/dev/null; then
        use_dropin="yes"
        mkdir -p "$include_dir"
        target_conf="$dropin"
        backup="${dropin}.bak.$(date +%Y%m%d-%H%M%S)"
        [[ -f "$dropin" ]] && cp -a "$dropin" "$backup"
        {
            echo "# Managed by ss2022.sh - preserve existing SSH ports"
            while read -r p; do [[ -n "$p" ]] && echo "Port $p"; done <<<"$old_ports"
            echo "Port $new_port"
        } > "$dropin"
    else
        target_conf="$main_conf"
        backup="${STATE_DIR}/sshd_config.bak.$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"
        cp -a "$main_conf" "$backup" || return 1
        tmp_main=$(mktemp /tmp/ss2022-sshd.XXXXXX) || return 1
        awk '
          $0=="# BEGIN ss2022 managed ports" {skip=1; next}
          $0=="# END ss2022 managed ports" {skip=0; next}
          !skip {print}
        ' "$main_conf" > "$tmp_main"
        {
            cat "$tmp_main"
            echo "# BEGIN ss2022 managed ports"
            while read -r p; do [[ -n "$p" ]] && echo "Port $p"; done <<<"$old_ports"
            echo "Port $new_port"
            echo "# END ss2022 managed ports"
        } > "$main_conf"
        rm -f "$tmp_main"
    fi

    if ! sshd -t; then
        echo -e "${RED}[错误] sshd 配置校验失败，正在回滚。${PLAIN}"
        if [[ "$use_dropin" == "yes" ]]; then
            [[ -f "$backup" ]] && mv -f "$backup" "$dropin" || rm -f "$dropin"
        else
            cp -af "$backup" "$main_conf"
        fi
        sshd -t >/dev/null 2>&1 || true
        return 1
    fi

    if service_exists ssh; then service_name="ssh"; else service_name="sshd"; fi
    if ! service_reload "$service_name" 2>/dev/null; then
        echo -e "${RED}[错误] SSH reload 失败，正在回滚。${PLAIN}"
        if [[ "$use_dropin" == "yes" ]]; then
            [[ -f "$backup" ]] && mv -f "$backup" "$dropin" || rm -f "$dropin"
        else
            cp -af "$backup" "$main_conf"
        fi
        service_reload "$service_name" >/dev/null 2>&1 || true
        return 1
    fi
    sleep 1
    if ss -H -lnt 2>/dev/null | awk -v p="$new_port" '{addr=$4; n=split(addr,a,":"); if (a[n]==p) found=1} END {exit !found}'; then
        rm -f "$backup"
        echo -e "${GREEN}✔ SSH 已新增端口 ${new_port}，旧端口继续保留。${PLAIN}"
        echo -e "${YELLOW}请先新开一个 SSH 会话验证 ${new_port} 可登录，再考虑手工移除旧端口。${PLAIN}"
        return 0
    fi
    echo -e "${YELLOW}[警告] sshd 配置已通过，但暂未检测到 ${new_port} 正在监听。请不要关闭当前 SSH 会话。${PLAIN}"
    return 1
}
server_tool_ssh_management() {
    local c
    while true; do
        clear
        echo -e "${CYAN}════════════════════ SSH 端口 ════════════════════${PLAIN}"
        echo "当前端口:"
        server_tool_ssh_ports | sed 's/^/  - /'
        echo ""
        echo "  1. 安全新增 SSH 端口（保留旧端口）"
        echo "  0. 返回"
        read -rp "请选择 [0-1]: " c
        case "$c" in
            1) server_tool_ssh_add_port; pause ;;
            0) return ;;
            *) sleep 1 ;;
        esac
    done
}

server_tool_tg_monitor_ensure_worker() {
    install -d -m 755 /usr/local/lib/ss2022 || return 1
    mkdir -p "$STATE_DIR" || return 1
    chmod 700 "$STATE_DIR"
    cat > "$TG_MONITOR_WORKER" <<'TGWORKER'
#!/bin/bash
set -u
CONF="/etc/ss2022/tg-monitor.conf"
STATE="/etc/ss2022/tg-monitor.state"
LOCKDIR="/run/ss2022-tg-monitor.lockdir"
[[ -f "$CONF" ]] || exit 0
# shellcheck disable=SC1090
source "$CONF"
if ! mkdir "$LOCKDIR" 2>/dev/null; then exit 0; fi
trap 'rmdir "$LOCKDIR" >/dev/null 2>&1 || true' EXIT INT TERM

send_tg() {
    local msg="$1"
    [[ -n "${TG_BOT_TOKEN:-}" && -n "${TG_CHAT_ID:-}" ]] || return 0
    curl -fsS --connect-timeout 5 --max-time 10 -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" --data-urlencode "chat_id=${TG_CHAT_ID}" --data-urlencode "text=${msg}" >/dev/null 2>&1 || true
}
traffic_bytes() {
    awk 'BEGIN {rx=0;tx=0} {iface=$1;gsub(":","",iface); if (iface ~ /^(eth|ens|enp|eno|venet|bond)[A-Za-z0-9_.-]*$/) {rx+=$2;tx+=$10}} END {printf "%.0f %.0f\n",rx,tx}' /proc/net/dev
}
period_key() {
    local day now_day year month prev_year prev_month
    day="${RESET_DAY:-1}"; now_day=$(date +%d | sed 's/^0//'); year=$(date +%Y); month=$(date +%m | sed 's/^0//')
    if [[ "$now_day" -ge "$day" ]]; then printf "%04d-%02d" "$year" "$month"; return; fi
    if [[ "$month" -eq 1 ]]; then prev_year=$((year-1)); prev_month=12; else prev_year=$year; prev_month=$((month-1)); fi
    printf "%04d-%02d" "$prev_year" "$prev_month"
}
human_gb() { awk -v b="$1" 'BEGIN {printf "%.2f",b/1073741824}'; }
percent_of() { local bytes="$1" limit_gb="$2"; if [[ ! "$limit_gb" =~ ^[0-9]+$ || "$limit_gb" -le 0 ]]; then echo 0; else awk -v b="$bytes" -v g="$limit_gb" 'BEGIN {printf "%.0f",(b/(g*1073741824))*100}'; fi; }
CURRENT_RX=0; CURRENT_TX=0; read -r CURRENT_RX CURRENT_TX < <(traffic_bytes)
PERIOD="$(period_key)"
LAST_RX=0; LAST_TX=0; TOTAL_RX=0; TOTAL_TX=0; STATE_PERIOD=""
RX_WARN1=0; RX_WARN2=0; RX_CRITICAL=0; TX_WARN1=0; TX_WARN2=0; TX_CRITICAL=0
if [[ -f "$STATE" ]]; then
    # shellcheck disable=SC1090
    source "$STATE"
fi
if [[ "$STATE_PERIOD" != "$PERIOD" ]]; then
    STATE_PERIOD="$PERIOD"; LAST_RX="$CURRENT_RX"; LAST_TX="$CURRENT_TX"; TOTAL_RX=0; TOTAL_TX=0
    RX_WARN1=0; RX_WARN2=0; RX_CRITICAL=0; TX_WARN1=0; TX_WARN2=0; TX_CRITICAL=0
else
    if [[ "$CURRENT_RX" -ge "$LAST_RX" ]]; then TOTAL_RX=$((TOTAL_RX+CURRENT_RX-LAST_RX)); else TOTAL_RX=$((TOTAL_RX+CURRENT_RX)); fi
    if [[ "$CURRENT_TX" -ge "$LAST_TX" ]]; then TOTAL_TX=$((TOTAL_TX+CURRENT_TX-LAST_TX)); else TOTAL_TX=$((TOTAL_TX+CURRENT_TX)); fi
    LAST_RX="$CURRENT_RX"; LAST_TX="$CURRENT_TX"
fi
HOST_LABEL="${HOST_LABEL:-$(hostname)}"; WARN1_PERCENT="${WARN1_PERCENT:-80}"; WARN2_PERCENT="${WARN2_PERCENT:-90}"; AUTO_SHUTDOWN="${AUTO_SHUTDOWN:-no}"; SHUTDOWN_PERCENT="${SHUTDOWN_PERCENT:-95}"
rx_percent=$(percent_of "$TOTAL_RX" "${RX_LIMIT_GB:-0}"); tx_percent=$(percent_of "$TOTAL_TX" "${TX_LIMIT_GB:-0}")
rx_gb=$(human_gb "$TOTAL_RX"); tx_gb=$(human_gb "$TOTAL_TX")
notify_threshold() {
    local direction="$1" percent="$2" used_gb="$3" limit="$4" warn1_var warn2_var critical_var
    if [[ "$direction" == "入站" ]]; then warn1_var="RX_WARN1"; warn2_var="RX_WARN2"; critical_var="RX_CRITICAL"; else warn1_var="TX_WARN1"; warn2_var="TX_WARN2"; critical_var="TX_CRITICAL"; fi
    [[ "$limit" =~ ^[0-9]+$ && "$limit" -gt 0 ]] || return 0
    if [[ "$percent" -ge 100 && "${!critical_var}" -eq 0 ]]; then
        printf -v "$critical_var" 1
        send_tg "🚨 ${HOST_LABEL}\n${direction}流量已达到 ${used_gb} GB / ${limit} GB（${percent}%）\n已达到流量上限。"
    elif [[ "$percent" -ge "$WARN2_PERCENT" && "${!warn2_var}" -eq 0 ]]; then
        printf -v "$warn2_var" 1
        send_tg "⚠️ ${HOST_LABEL}\n${direction}流量已达到 ${used_gb} GB / ${limit} GB（${percent}%）\n已达到第二预警线 ${WARN2_PERCENT}%。"
    elif [[ "$percent" -ge "$WARN1_PERCENT" && "${!warn1_var}" -eq 0 ]]; then
        printf -v "$warn1_var" 1
        send_tg "⚠️ ${HOST_LABEL}\n${direction}流量已达到 ${used_gb} GB / ${limit} GB（${percent}%）\n已达到第一预警线 ${WARN1_PERCENT}%。"
    fi
}
notify_threshold "入站" "$rx_percent" "$rx_gb" "${RX_LIMIT_GB:-0}"
notify_threshold "出站" "$tx_percent" "$tx_gb" "${TX_LIMIT_GB:-0}"
tmp="${STATE}.tmp.$$"; umask 077
cat > "$tmp" <<EOF
STATE_PERIOD='${STATE_PERIOD}'
LAST_RX=${LAST_RX}
LAST_TX=${LAST_TX}
TOTAL_RX=${TOTAL_RX}
TOTAL_TX=${TOTAL_TX}
RX_WARN1=${RX_WARN1}
RX_WARN2=${RX_WARN2}
RX_CRITICAL=${RX_CRITICAL}
TX_WARN1=${TX_WARN1}
TX_WARN2=${TX_WARN2}
TX_CRITICAL=${TX_CRITICAL}
EOF
mv -f "$tmp" "$STATE"; chmod 600 "$STATE"
shutdown_needed=0
if [[ "${RX_LIMIT_GB:-0}" =~ ^[0-9]+$ && "${RX_LIMIT_GB:-0}" -gt 0 && "$rx_percent" -ge "$SHUTDOWN_PERCENT" ]]; then shutdown_needed=1; fi
if [[ "${TX_LIMIT_GB:-0}" =~ ^[0-9]+$ && "${TX_LIMIT_GB:-0}" -gt 0 && "$tx_percent" -ge "$SHUTDOWN_PERCENT" ]]; then shutdown_needed=1; fi
if [[ "$shutdown_needed" -eq 1 && "$AUTO_SHUTDOWN" == "yes" ]]; then
    send_tg "⛔ ${HOST_LABEL}\n流量达到自动关机阈值 ${SHUTDOWN_PERCENT}%，服务器即将自动关机。"
    sync
    shutdown -h now
fi
TGWORKER
    chmod 700 "$TG_MONITOR_WORKER"

    if [[ "$PLATFORM_INIT" == "systemd" ]]; then
        cat > "$TG_MONITOR_SERVICE" <<EOF
[Unit]
Description=ss2022 TG-BOT Traffic Monitor
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${TG_MONITOR_WORKER}
EOF
        cat > "$TG_MONITOR_TIMER" <<'EOF'
[Unit]
Description=Run ss2022 TG-BOT Traffic Monitor Every Minute

[Timer]
OnBootSec=2min
OnUnitActiveSec=60s
AccuracySec=5s
Persistent=true
Unit=ss2022-tg-monitor.service

[Install]
WantedBy=timers.target
EOF
        service_daemon_reload || return 1
    else
        mkdir -p "$(dirname "$TG_MONITOR_CRON_FILE")"
        touch "$TG_MONITOR_CRON_FILE"
        sed -i "/ss2022-tg-monitor/d" "$TG_MONITOR_CRON_FILE"
        echo "* * * * * $TG_MONITOR_WORKER >/dev/null 2>&1 $TG_MONITOR_CRON_TAG" >> "$TG_MONITOR_CRON_FILE"
        service_enable_now crond >/dev/null 2>&1 || {
            echo -e "${RED}[错误] OpenRC crond 启动失败。${PLAIN}"
            return 1
        }
    fi
}

server_tool_tg_monitor_send_test() {
    local token chat_id host
    [[ -f "$TG_MONITOR_CONF" ]] || {
        echo -e "${YELLOW}尚未配置 TG-BOT 流量监控。${PLAIN}"
        return 1
    }

    # shellcheck disable=SC1090
    source "$TG_MONITOR_CONF"
    token="${TG_BOT_TOKEN:-}"
    chat_id="${TG_CHAT_ID:-}"
    host="${HOST_LABEL:-$(hostname)}"

    if curl -fsS --connect-timeout 5 --max-time 10 \
        -X POST "https://api.telegram.org/bot${token}/sendMessage" \
        --data-urlencode "chat_id=${chat_id}" \
        --data-urlencode "text=✅ ${host}：ss2022 TG-BOT 流量监控测试消息发送成功。" \
        >/dev/null 2>&1; then
        echo -e "${GREEN}✔ Telegram 测试消息已发送。${PLAIN}"
        return 0
    fi

    echo -e "${RED}[错误] Telegram 消息发送失败，请检查 Bot Token、Chat ID 和服务器网络。${PLAIN}"
    return 1
}

server_tool_tg_monitor_configure() {
    local token chat_id rx_limit tx_limit reset_day warn1 warn2 shutdown_percent auto_shutdown host_label
    local current_token="" current_chat="" ans

    if [[ -f "$TG_MONITOR_CONF" ]]; then
        # shellcheck disable=SC1090
        source "$TG_MONITOR_CONF"
        current_token="${TG_BOT_TOKEN:-}"
        current_chat="${TG_CHAT_ID:-}"
    fi

    clear
    echo -e "${CYAN}════════════ TG-BOT 流量监控配置 ════════════${PLAIN}"
    echo "说明："
    echo "  - 每分钟累计公网网卡收发流量；累计状态写入磁盘，重启 VPS 后不会清零。"
    echo "  - 默认在 80% / 90% / 100% 三个阶段发送 Telegram 预警。"
    echo "  - 自动关机阈值独立配置，默认 95%。"
    echo "  - 新启用时从当前流量计数作为起点，只统计启用后的流量。"
    echo ""

    if [[ -n "$current_token" ]]; then
        read -rp "Telegram Bot Token [回车保持现有 Token]: " token
        token=${token:-$current_token}
    else
        read -rp "Telegram Bot Token: " token
    fi

    if [[ ! "$token" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
        echo -e "${RED}[错误] Bot Token 格式不正确。${PLAIN}"
        pause
        return
    fi

    if [[ -n "$current_chat" ]]; then
        read -rp "Telegram Chat ID [回车保持: ${current_chat}]: " chat_id
        chat_id=${chat_id:-$current_chat}
    else
        read -rp "Telegram Chat ID: " chat_id
    fi

    if [[ ! "$chat_id" =~ ^-?[0-9]+$ ]]; then
        echo -e "${RED}[错误] Chat ID 应为数字，可为负数（群组）。${PLAIN}"
        pause
        return
    fi

    read -rp "每月入站流量上限 GB [默认 1000，0=不限制]: " rx_limit
    rx_limit=${rx_limit:-1000}
    read -rp "每月出站流量上限 GB [默认 1000，0=不限制]: " tx_limit
    tx_limit=${tx_limit:-1000}
    read -rp "每月流量重置日 [默认 1，范围 1-28]: " reset_day
    reset_day=${reset_day:-1}
    read -rp "第一预警百分比 [默认 80]: " warn1
    warn1=${warn1:-80}
    read -rp "第二预警百分比 [默认 90]: " warn2
    warn2=${warn2:-90}
    read -rp "自动关机阈值百分比 [默认 95]: " shutdown_percent
    shutdown_percent=${shutdown_percent:-95}

    for n in "$rx_limit" "$tx_limit" "$reset_day" "$warn1" "$warn2" "$shutdown_percent"; do
        [[ "$n" =~ ^[0-9]+$ ]] || {
            echo -e "${RED}[错误] 阈值必须为整数。${PLAIN}"
            pause
            return
        }
    done

    if [[ "$reset_day" -lt 1 || "$reset_day" -gt 28 ]]; then
        echo -e "${RED}[错误] 重置日必须为 1-28。${PLAIN}"
        pause
        return
    fi

    if [[ "$warn1" -lt 1 || "$warn1" -ge "$warn2" || "$warn2" -ge 100 ]]; then
        echo -e "${RED}[错误] 预警比例必须满足 1 <= 第一预警 < 第二预警 < 100。${PLAIN}"
        pause
        return
    fi

    if [[ "$shutdown_percent" -lt 1 || "$shutdown_percent" -gt 100 ]]; then
        echo -e "${RED}[错误] 自动关机阈值必须在 1-100%。${PLAIN}"
        pause
        return
    fi

    read -rp "达到 ${shutdown_percent}% 后自动关机？[y/N]: " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        auto_shutdown="yes"
        echo -e "${YELLOW}[警告] 自动关机启用后，任一启用方向达到 ${shutdown_percent}% 会执行 shutdown -h now。${PLAIN}"
        read -rp "再次确认启用自动关机？[y/N]: " ans
        [[ "$ans" =~ ^[Yy]$ ]] || auto_shutdown="no"
    else
        auto_shutdown="no"
    fi

    host_label=$(hostname 2>/dev/null || echo "VPS")

    mkdir -p "$STATE_DIR"
    chmod 700 "$STATE_DIR"
    umask 077
    cat > "$TG_MONITOR_CONF" <<EOF
TG_BOT_TOKEN='${token}'
TG_CHAT_ID='${chat_id}'
HOST_LABEL='${host_label}'
RX_LIMIT_GB=${rx_limit}
TX_LIMIT_GB=${tx_limit}
RESET_DAY=${reset_day}
WARN1_PERCENT=${warn1}
WARN2_PERCENT=${warn2}
SHUTDOWN_PERCENT=${shutdown_percent}
AUTO_SHUTDOWN='${auto_shutdown}'
EOF
    chmod 600 "$TG_MONITOR_CONF"

    server_tool_tg_monitor_ensure_worker || {
        echo -e "${RED}[错误] TG-BOT 监控服务生成失败。${PLAIN}"
        pause
        return
    }

    if [[ "$PLATFORM_INIT" == "systemd" ]]; then
        systemctl enable --now ss2022-tg-monitor.timer >/dev/null 2>&1 || {
            echo -e "${RED}[错误] TG-BOT 监控 timer 启动失败。${PLAIN}"; pause; return
        }
    fi
    # 立即运行一次，建立初始状态。OpenRC 后续由 crond 每分钟执行。
    "$TG_MONITOR_WORKER" >/dev/null 2>&1 || true

    echo -e "${GREEN}✔ TG-BOT 流量监控已启用。${PLAIN}"
    server_tool_tg_monitor_send_test
    pause
}

server_tool_tg_monitor_status() {
    local enabled="未启用" rx_limit="-" tx_limit="-" reset_day="-" warn1="-" warn2="-" shutdown_percent="95" auto="-"
    local total_rx=0 total_tx=0 period="-" rx_gb tx_gb token_masked="-"
    [[ -f "$TG_MONITOR_CONF" ]] && {
        # shellcheck disable=SC1090
        source "$TG_MONITOR_CONF"
        rx_limit="${RX_LIMIT_GB:-0}"; tx_limit="${TX_LIMIT_GB:-0}"; reset_day="${RESET_DAY:-1}"
        warn1="${WARN1_PERCENT:-80}"; warn2="${WARN2_PERCENT:-90}"; shutdown_percent="${SHUTDOWN_PERCENT:-95}"; auto="${AUTO_SHUTDOWN:-no}"
        [[ -n "${TG_BOT_TOKEN:-}" ]] && token_masked="${TG_BOT_TOKEN:0:6}******"
    }
    [[ -f "$TG_MONITOR_STATE" ]] && {
        # shellcheck disable=SC1090
        source "$TG_MONITOR_STATE"
        total_rx="${TOTAL_RX:-0}"; total_tx="${TOTAL_TX:-0}"; period="${STATE_PERIOD:--}"
    }
    if [[ "$PLATFORM_INIT" == "systemd" ]]; then
        if systemctl is-active --quiet ss2022-tg-monitor.timer 2>/dev/null; then enabled="运行中"; elif systemctl is-enabled --quiet ss2022-tg-monitor.timer 2>/dev/null; then enabled="已启用但未运行"; fi
    else
        if grep -q "ss2022-tg-monitor" "$TG_MONITOR_CRON_FILE" 2>/dev/null && service_is_active crond; then enabled="运行中（OpenRC crond）"; elif grep -q "ss2022-tg-monitor" "$TG_MONITOR_CRON_FILE" 2>/dev/null; then enabled="已配置但 crond 未运行"; fi
    fi
    rx_gb=$(awk -v b="$total_rx" 'BEGIN {printf "%.2f",b/1073741824}'); tx_gb=$(awk -v b="$total_tx" 'BEGIN {printf "%.2f",b/1073741824}')
    clear
    echo -e "${CYAN}════════════ TG-BOT 流量监控状态 ════════════${PLAIN}"
    echo "  状态         : ${enabled}"
    echo "  统计周期     : ${period} / 每月 ${reset_day} 日重置"
    echo "  当前入站累计 : ${rx_gb} GB / ${rx_limit} GB"
    echo "  当前出站累计 : ${tx_gb} GB / ${tx_limit} GB"
    echo "  TG Token     : ${token_masked}"
    echo "  Chat ID      : ${TG_CHAT_ID:--}"
    echo "  预警线       : ${warn1}% / ${warn2}% / 100%"
    echo "  关机阈值     : ${shutdown_percent}%"
    echo "  自动关机     : $([[ "$auto" == "yes" ]] && echo "开启" || echo "关闭")"
    echo -e "${CYAN}═══════════════════════════════════════════════${PLAIN}"
}
server_tool_tg_monitor_disable() {
    local ans
    read -rp "确认停用 TG-BOT 流量监控？配置和累计数据会保留。[y/N]: " ans
    [[ "$ans" =~ ^[Yy]$ ]] || return 0
    if [[ "$PLATFORM_INIT" == "systemd" ]]; then
        systemctl disable --now ss2022-tg-monitor.timer >/dev/null 2>&1 || true
    else
        [[ -f "$TG_MONITOR_CRON_FILE" ]] && sed -i "/ss2022-tg-monitor/d" "$TG_MONITOR_CRON_FILE"
    fi
    echo -e "${GREEN}✔ TG-BOT 流量监控已停用。${PLAIN}"
}
server_tool_tg_monitor_reset() {
    local ans
    read -rp "确认清零当前累计流量和预警状态？[y/N]: " ans
    [[ "$ans" =~ ^[Yy]$ ]] || return 0
    rm -f "$TG_MONITOR_STATE"
    [[ -x "$TG_MONITOR_WORKER" ]] && "$TG_MONITOR_WORKER" >/dev/null 2>&1 || true
    echo -e "${GREEN}✔ 流量累计已重新从当前时刻开始统计。${PLAIN}"
}
server_tool_tg_monitor_remove() {
    local ans
    read -rp "确认彻底删除 TG-BOT 流量监控配置、Token 和累计数据？[y/N]: " ans
    [[ "$ans" =~ ^[Yy]$ ]] || return 0
    if [[ "$PLATFORM_INIT" == "systemd" ]]; then
        systemctl disable --now ss2022-tg-monitor.timer >/dev/null 2>&1 || true
    else
        [[ -f "$TG_MONITOR_CRON_FILE" ]] && sed -i "/ss2022-tg-monitor/d" "$TG_MONITOR_CRON_FILE"
    fi
    rm -f "$TG_MONITOR_TIMER" "$TG_MONITOR_SERVICE" "$TG_MONITOR_WORKER" "$TG_MONITOR_CONF" "$TG_MONITOR_STATE"
    service_daemon_reload >/dev/null 2>&1 || true
    echo -e "${GREEN}✔ TG-BOT 流量监控已彻底删除。${PLAIN}"
}
server_tool_tg_monitor_management() {
    local c
    while true; do
        server_tool_tg_monitor_status
        echo ""
        echo "  1. 配置 / 启用监控"
        echo "  2. 发送 TG 测试消息"
        echo "  3. 清零流量累计"
        echo "  4. 停用监控（保留配置）"
        echo "  5. 删除监控配置"
        echo "  0. 返回"
        read -rp "请选择 [0-5]: " c
        case "$c" in
            1) server_tool_tg_monitor_configure ;;
            2) server_tool_tg_monitor_send_test; pause ;;
            3) server_tool_tg_monitor_reset; pause ;;
            4) server_tool_tg_monitor_disable; pause ;;
            5) server_tool_tg_monitor_remove; pause ;;
            0) return ;;
            *) sleep 1 ;;
        esac
    done
}

server_tool_reboot() {
    local ans
    clear
    echo -e "${RED}════════════════════ 重启服务器 ════════════════════${PLAIN}"
    echo -e "${YELLOW}[警告] 重启会立即中断当前 SSH 会话和正在运行的任务。${PLAIN}"
    echo ""
    echo "为避免误触，请完整输入：REBOOT"
    read -rp "确认字符: " ans
    [[ "$ans" == "REBOOT" ]] || {
        echo "已取消重启。"
        pause
        return
    }
    sync
    reboot
}

server_management_tools() {
    while true; do
        clear
        echo -e "${CYAN}════════════════════ 服务器管理工具 ════════════════════${PLAIN}"
        echo "  1. 系统信息"
        echo "  2. 查看端口占用"
        echo "  3. TG-BOT 流量监控 / 预警 / 自动关机"
        echo "  4. 系统更新 / 清理"
        echo "  5. Swap 虚拟内存"
        echo "  6. 网络调优（v1.10.0-dev4）"
        echo "  7. DNS 管理"
        echo "  8. IPv4 / IPv6 管理"
        echo "  9. 系统时区"
        echo " 10. SSH 端口管理"
        echo " 11. 重启服务器"
        echo "  0. 返回"
        echo -e "${CYAN}═══════════════════════════════════════════════════════${PLAIN}"
        read -rp "请选择 [0-11]: " c
        case "$c" in
            1) server_tool_system_info; pause ;;
            2) server_tool_port_usage ;;
            3) server_tool_tg_monitor_management ;;
            4) server_tool_system_update ;;
            5) server_tool_swap_management ;;
            6) network_tuning_management ;;
            7) server_tool_dns_management ;;
            8) server_tool_ip_family_management ;;
            9) server_tool_timezone_management ;;
            10) server_tool_ssh_management ;;
            11) server_tool_reboot ;;
            0) return ;;
            *) sleep 1 ;;
        esac
    done
}

ensure_test_dependency() {
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
    echo -e "${YELLOW}说明: 测试组件仅用于检测；临时下载到 /tmp，校验来源完整性后执行，用完删除，不修改协议或分流配置。${PLAIN}"
    echo ""
}
server_test_download_release_asset() {
    local repo="$1" tag="$2" asset="$3" out="$4"
    local api meta url digest expected actual source ok=0

    ensure_test_dependency curl curl || return 1
    ensure_test_dependency jq jq || return 1
    command -v sha256sum >/dev/null 2>&1 || ensure_test_dependency sha256sum coreutils || return 1

    if [[ "$tag" == "latest" ]]; then
        api="https://api.github.com/repos/${repo}/releases/latest"
    else
        api="https://api.github.com/repos/${repo}/releases/tags/${tag}"
    fi
    meta=$(mktemp /tmp/ss2022-test-release.XXXXXX.json) || return 1
    if ! curl -fsSL --retry 2 --retry-delay 1 --connect-timeout 10 --max-time 30 -H "Accept: application/vnd.github+json" "$api" -o "$meta"; then
        rm -f "$meta"
        echo -e "${RED}[错误] 无法获取 ${repo} Release 元数据。${PLAIN}"
        return 1
    fi
    url=$(jq -r --arg a "$asset" '.assets[]? | select(.name==$a) | .browser_download_url // empty' "$meta" | head -n1)
    digest=$(jq -r --arg a "$asset" '.assets[]? | select(.name==$a) | .digest // empty' "$meta" | head -n1)
    rm -f "$meta"
    expected=${digest#sha256:}
    if [[ -z "$url" || ! "$expected" =~ ^[0-9a-fA-F]{64}$ ]]; then
        echo -e "${RED}[错误] Release 中未找到 ${asset} 或缺少官方 SHA256 digest。${PLAIN}"
        return 1
    fi

    local sources=("$url" "https://ghproxy.net/${url}" "https://gh-proxy.com/${url}")
    for source in "${sources[@]}"; do
        rm -f "$out"
        echo -e "${YELLOW}>> 下载并校验 ${asset}...${PLAIN}"
        if ! curl -fL --retry 2 --retry-delay 1 --connect-timeout 10 --max-time 120 "$source" -o "$out"; then
            continue
        fi
        actual=$(sha256sum "$out" | awk '{print $1}')
        if [[ "${actual,,}" == "${expected,,}" ]]; then
            ok=1
            break
        fi
        echo -e "${RED}[警告] SHA256 不匹配，拒绝执行当前下载结果。${PLAIN}"
    done
    [[ $ok -eq 1 ]] || { rm -f "$out"; echo -e "${RED}[错误] ${asset} 下载失败或 SHA256 校验失败。${PLAIN}"; return 1; }
    chmod 700 "$out"
    return 0
}

server_test_arch_asset() {
    local prefix="$1"
    case "$(uname -m)" in
        x86_64|amd64) printf "%s-linux-amd64" "$prefix" ;;
        aarch64|arm64) printf "%s-linux-arm64" "$prefix" ;;
        i386|i686) printf "%s-linux-386" "$prefix" ;;
        armv7l|armv7*) printf "%s-linux-arm" "$prefix" ;;
        *) return 1 ;;
    esac
}

server_test_detect_family_mode() {
    local has4=0 has6=0
    get_public_ipv4 >/dev/null 2>&1 && has4=1 || true
    get_public_ipv6 >/dev/null 2>&1 && has6=1 || true
    if [[ $has4 -eq 1 && $has6 -eq 1 ]]; then echo "both"
    elif [[ $has4 -eq 1 ]]; then echo "ipv4"
    elif [[ $has6 -eq 1 ]]; then echo "ipv6"
    else echo "none"; fi
}

run_external_curl_test() {
    local label="$1"
    local url="$2"
    shift 2

    local tmp=""
    tmp=$(mktemp /tmp/ss2022-external-test.XXXXXX.sh) || {
        echo -e "${RED}[错误] 无法创建临时测试文件。${PLAIN}"
        return 1
    }

    if ! curl -fLsS --retry 2 --retry-delay 1 \
        --connect-timeout 10 --max-time 60 \
        "$url" -o "$tmp"; then
        rm -f "$tmp"
        echo -e "${RED}[错误] ${label}脚本下载失败。${PLAIN}"
        return 1
    fi

    if [[ ! -s "$tmp" ]]; then
        rm -f "$tmp"
        echo -e "${RED}[错误] ${label}脚本下载结果为空。${PLAIN}"
        return 1
    fi

    chmod 700 "$tmp"

    # 第三方检测脚本可能用非 0 返回码表达内部检测状态。
    # 这里不把它二次解释成“脚本执行失败”；实际检测结果以第三方输出为准。
    bash "$tmp" "$@" || true

    rm -f "$tmp"
    return 0
}

test_ip_quality() {
    local asset tmp family check_mode
    clear
    show_external_test_source "IP 质量测试" "oneclickvirt/securityCheck"
    asset=$(server_test_arch_asset "securityCheck") || {
        echo -e "${RED}[错误] 当前 CPU 架构暂无 securityCheck 测试资产。${PLAIN}"; pause; return
    }
    family=$(server_test_detect_family_mode)
    case "$family" in
        both) check_mode="both" ;;
        ipv4) check_mode="ipv4" ;;
        ipv6) check_mode="ipv6" ;;
        *) echo -e "${RED}[错误] 未检测到可用公网 IPv4 / IPv6。${PLAIN}"; pause; return ;;
    esac
    tmp=$(mktemp /tmp/ss2022-securitycheck.XXXXXX) || { pause; return; }
    if server_test_download_release_asset "oneclickvirt/securityCheck" "output" "$asset" "$tmp"; then
        echo -e "${CYAN}检测地址族: ${check_mode}${PLAIN}"
        "$tmp" -l zh -c "$check_mode" -e yes || true
    fi
    rm -f "$tmp"
    echo ""
    pause
}
server_test_nexttrace_asset() {
    case "$(uname -m)" in
        x86_64|amd64) echo "nexttrace-tiny_linux_amd64" ;;
        aarch64|arm64) echo "nexttrace-tiny_linux_arm64" ;;
        i386|i686) echo "nexttrace-tiny_linux_386" ;;
        armv7l|armv7*) echo "nexttrace-tiny_linux_armv7" ;;
        *) return 1 ;;
    esac
}

server_test_write_return_targets() {
    local family="$1" out="$2"
    case "$family" in
        4)
            cat >"$out" <<'EOF'
ipv4.pek-4134.endpoint.nxtrace.org 北京电信
ipv4.pek-4837.endpoint.nxtrace.org 北京联通
ipv4.pek-9808.endpoint.nxtrace.org 北京移动
ipv4.sha-4134.endpoint.nxtrace.org 上海电信
ipv4.sha-4837.endpoint.nxtrace.org 上海联通
ipv4.sha-9808.endpoint.nxtrace.org 上海移动
ipv4.can-4134.endpoint.nxtrace.org 广州电信
ipv4.can-4837.endpoint.nxtrace.org 广州联通
ipv4.can-9808.endpoint.nxtrace.org 广州移动
EOF
            ;;
        6)
            cat >"$out" <<'EOF'
ipv6.pek-4134.endpoint.nxtrace.org 北京电信
ipv6.pek-4837.endpoint.nxtrace.org 北京联通
ipv6.pek-9808.endpoint.nxtrace.org 北京移动
ipv6.sha-4134.endpoint.nxtrace.org 上海电信
ipv6.sha-4837.endpoint.nxtrace.org 上海联通
ipv6.sha-9808.endpoint.nxtrace.org 上海移动
ipv6.can-4134.endpoint.nxtrace.org 广州电信
ipv6.can-4837.endpoint.nxtrace.org 广州联通
ipv6.can-9808.endpoint.nxtrace.org 广州移动
EOF
            ;;
        *) return 1 ;;
    esac
}

server_test_run_nexttrace_family() {
    local bin="$1" family="$2" targets title
    targets=$(mktemp /tmp/ss2022-nexttrace-targets.XXXXXX) || return 1
    server_test_write_return_targets "$family" "$targets" || {
        rm -f "$targets"
        return 1
    }

    [[ "$family" == "6" ]] && title="IPv6" || title="IPv4"
    echo ""
    echo -e "${CYAN}════════ ${title} 三网逐跳回程 ════════${PLAIN}"
    echo -e "${YELLOW}目标: 北京 / 上海 / 广州 × 电信 / 联通 / 移动；TCP 80；每一跳显示 IP / ASN / 地区 / 延迟。${PLAIN}"
    echo ""

    "$bin" --traceroute --file "$targets"         --tcp --port 80         --queries 1 --max-hops 30 --timeout 2000         --language cn --no-color -M || true

    rm -f "$targets"
}

test_return_route() {
    local asset tmp family
    clear
    show_external_test_source "IPv4 / IPv6 三网逐跳回程" "nxtrace/NTrace-core"
    echo -e "${YELLOW}本项显示完整 traceroute，每个目标会逐跳列出经过的 IP、ASN、地区与延迟。${PLAIN}"
    echo -e "${CYAN}检测目标: 北京 / 上海 / 广州 × 电信 / 联通 / 移动，共 9 条/地址族。${PLAIN}"

    server_test_select_ip_mode || return
    family=$(server_test_detect_family_mode)

    asset=$(server_test_nexttrace_asset) || {
        echo -e "${RED}[错误] 当前 CPU 架构暂无 NextTrace 测试资产。${PLAIN}"
        pause
        return
    }

    tmp=$(mktemp /tmp/ss2022-nexttrace.XXXXXX) || { pause; return; }
    if ! server_test_download_release_asset "nxtrace/NTrace-core" "latest" "$asset" "$tmp"; then
        rm -f "$tmp"
        pause
        return
    fi

    case "$SERVER_TEST_IP_MODE:$family" in
        4:both|4:ipv4)
            server_test_run_nexttrace_family "$tmp" 4
            ;;
        4:*)
            echo -e "${YELLOW}当前 VPS 未检测到可用公网 IPv4。${PLAIN}"
            ;;
        6:both|6:ipv6)
            server_test_run_nexttrace_family "$tmp" 6
            ;;
        6:*)
            echo -e "${YELLOW}当前 VPS 未检测到可用公网 IPv6。${PLAIN}"
            ;;
        0:both)
            server_test_run_nexttrace_family "$tmp" 4
            server_test_run_nexttrace_family "$tmp" 6
            ;;
        0:ipv4)
            server_test_run_nexttrace_family "$tmp" 4
            ;;
        0:ipv6)
            server_test_run_nexttrace_family "$tmp" 6
            ;;
        *)
            echo -e "${RED}[错误] 未检测到可用公网 IPv4 / IPv6。${PLAIN}"
            ;;
    esac

    rm -f "$tmp"
    echo ""
    pause
}

server_test_run_unlocktests() {
    local selection="$1" label="$2" mode="${3:-0}" selector="${4:-f}" asset tmp
    asset=$(server_test_arch_asset "ut") || {
        echo -e "${RED}[错误] 当前 CPU 架构暂无 UnlockTests 测试资产。${PLAIN}"
        return 1
    }
    tmp=$(mktemp /tmp/ss2022-unlocktests.XXXXXX) || return 1
    if ! server_test_download_release_asset "oneclickvirt/UnlockTests" "output" "$asset" "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    echo -e "${CYAN}${label}${PLAIN}"
    case "$selector" in
        region) "$tmp" -L zh -m "$mode" -region "$selection" -b=false -cache || true ;;
        test) "$tmp" -L zh -m "$mode" -test "$selection" -b=false -cache || true ;;
        *) "$tmp" -L zh -m "$mode" -f "$selection" -b=false -cache || true ;;
    esac
    rm -f "$tmp"
}
server_test_select_ip_mode() {
    local c
    SERVER_TEST_IP_MODE="0"
    while true; do
        echo ""
        echo "请选择测试地址族："
        echo "  1. IPv4 + IPv6（按 VPS 实际可用性）"
        echo "  2. 仅 IPv4"
        echo "  3. 仅 IPv6"
        echo "  0. 返回"
        read -rp "请选择 [0-3，默认 1]: " c
        c=${c:-1}
        case "$c" in
            1) SERVER_TEST_IP_MODE="0"; return 0 ;;
            2) SERVER_TEST_IP_MODE="4"; return 0 ;;
            3) SERVER_TEST_IP_MODE="6"; return 0 ;;
            0) return 1 ;;
            *) echo -e "${RED}输入无效。${PLAIN}" ;;
        esac
    done
}

server_test_region_map_local_choice() {
    case "$1" in
        2) echo "TW_UnlockTest" ;;
        3) echo "HK_UnlockTest" ;;
        4) echo "JP_UnlockTest" ;;
        5) echo "KR_UnlockTest" ;;
        6) echo "NA_UnlockTest" ;;
        7) echo "SA_UnlockTest" ;;
        8) echo "EU_UnlockTest" ;;
        9) echo "AF_UnlockTest" ;;
        10) echo "SEA_UnlockTest" ;;
        11) echo "OA_UnlockTest" ;;
        12) echo "Sport_UnlockTest" ;;
        *) return 1 ;;
    esac
}

server_test_select_streaming_region() {
    local c raw token mapped result="" label=""
    SERVER_TEST_REGION_SELECTION=""
    SERVER_TEST_REGION_LABEL="通用流媒体"
    while true; do
        echo ""
        echo "请选择流媒体 / 区域检测范围："
        echo "  1. 通用流媒体（Netflix / YouTube Premium / Disney+ / Prime Video / Google 等）"
        echo "  2. 台湾"
        echo "  3. 香港"
        echo "  4. 日本"
        echo "  5. 韩国"
        echo "  6. 北美"
        echo "  7. 南美"
        echo "  8. 欧洲"
        echo "  9. 非洲"
        echo " 10. 东南亚"
        echo " 11. 大洋洲"
        echo " 12. 体育平台"
        echo " 13. 全部流媒体平台（不含 AI）"
        echo " 14. 自定义多地区组合"
        echo "  0. 返回"
        read -rp "请选择 [0-14，默认 1]: " c
        c=${c:-1}
        case "$c" in
            1) SERVER_TEST_REGION_SELECTION=""; SERVER_TEST_REGION_LABEL="通用流媒体"; return 0 ;;
            2) SERVER_TEST_REGION_SELECTION="TW_UnlockTest"; SERVER_TEST_REGION_LABEL="台湾平台"; return 0 ;;
            3) SERVER_TEST_REGION_SELECTION="HK_UnlockTest"; SERVER_TEST_REGION_LABEL="香港平台"; return 0 ;;
            4) SERVER_TEST_REGION_SELECTION="JP_UnlockTest"; SERVER_TEST_REGION_LABEL="日本平台"; return 0 ;;
            5) SERVER_TEST_REGION_SELECTION="KR_UnlockTest"; SERVER_TEST_REGION_LABEL="韩国平台"; return 0 ;;
            6) SERVER_TEST_REGION_SELECTION="NA_UnlockTest"; SERVER_TEST_REGION_LABEL="北美平台"; return 0 ;;
            7) SERVER_TEST_REGION_SELECTION="SA_UnlockTest"; SERVER_TEST_REGION_LABEL="南美平台"; return 0 ;;
            8) SERVER_TEST_REGION_SELECTION="EU_UnlockTest"; SERVER_TEST_REGION_LABEL="欧洲平台"; return 0 ;;
            9) SERVER_TEST_REGION_SELECTION="AF_UnlockTest"; SERVER_TEST_REGION_LABEL="非洲平台"; return 0 ;;
            10) SERVER_TEST_REGION_SELECTION="SEA_UnlockTest"; SERVER_TEST_REGION_LABEL="东南亚平台"; return 0 ;;
            11) SERVER_TEST_REGION_SELECTION="OA_UnlockTest"; SERVER_TEST_REGION_LABEL="大洋洲平台"; return 0 ;;
            12) SERVER_TEST_REGION_SELECTION="Sport_UnlockTest"; SERVER_TEST_REGION_LABEL="体育平台"; return 0 ;;
            13)
                SERVER_TEST_REGION_SELECTION="TW_UnlockTest,HK_UnlockTest,JP_UnlockTest,KR_UnlockTest,NA_UnlockTest,SA_UnlockTest,EU_UnlockTest,AF_UnlockTest,SEA_UnlockTest,OA_UnlockTest,Sport_UnlockTest"
                SERVER_TEST_REGION_LABEL="全部地区平台"
                return 0
                ;;
            14)
                echo ""
                echo "输入上面地区编号，可选多个，以空格分隔。"
                echo "示例：3 4 10 = 香港 + 日本 + 东南亚"
                echo "可组合 2-12；通用流媒体固定只检测一次。"
                read -rp "地区编号: " raw
                result=""; label=""
                for token in $raw; do
                    [[ "$token" =~ ^([2-9]|1[0-2])$ ]] || {
                        echo -e "${RED}[错误] 无效地区编号: ${token}${PLAIN}"; result=""; break
                    }
                    mapped=$(server_test_region_map_local_choice "$token") || { result=""; break; }
                    if [[ ",${result}," != *",${mapped},"* ]]; then
                        result="${result:+${result},}${mapped}"
                        case "$token" in
                            2) label="${label:+${label} + }台湾" ;;
                            3) label="${label:+${label} + }香港" ;;
                            4) label="${label:+${label} + }日本" ;;
                            5) label="${label:+${label} + }韩国" ;;
                            6) label="${label:+${label} + }北美" ;;
                            7) label="${label:+${label} + }南美" ;;
                            8) label="${label:+${label} + }欧洲" ;;
                            9) label="${label:+${label} + }非洲" ;;
                            10) label="${label:+${label} + }东南亚" ;;
                            11) label="${label:+${label} + }大洋洲" ;;
                            12) label="${label:+${label} + }体育" ;;
                        esac
                    fi
                done
                [[ -n "$result" ]] || { echo -e "${RED}[错误] 未选择有效地区。${PLAIN}"; continue; }
                SERVER_TEST_REGION_SELECTION="$result"
                SERVER_TEST_REGION_LABEL="$label"
                return 0
                ;;
            0) return 1 ;;
            *) echo -e "${RED}输入无效。${PLAIN}" ;;
        esac
    done
}

server_test_show_exit_info_for_mode() {
    local mode="${1:-0}" family
    family=$(server_test_detect_family_mode)
    case "$mode" in
        4)
            case "$family" in
                both|ipv4)
                    echo "===========[ IPV4 流媒体出口 ]============"
                    server_test_exit_info "ipv4"
                    ;;
                *) echo -e "${YELLOW}当前 VPS 未检测到可用公网 IPv4。${PLAIN}" ;;
            esac
            ;;
        6)
            case "$family" in
                both|ipv6)
                    echo "===========[ IPV6 流媒体出口 ]============"
                    server_test_exit_info "ipv6"
                    ;;
                *) echo -e "${YELLOW}当前 VPS 未检测到可用公网 IPv6。${PLAIN}" ;;
            esac
            ;;
        *)
            case "$family" in
                both)
                    echo "===========[ IPV4 流媒体出口 ]============"
                    server_test_exit_info "ipv4"
                    echo ""
                    echo "===========[ IPV6 流媒体出口 ]============"
                    server_test_exit_info "ipv6"
                    ;;
                ipv4)
                    echo "===========[ IPV4 流媒体出口 ]============"
                    server_test_exit_info "ipv4"
                    ;;
                ipv6)
                    echo "===========[ IPV6 流媒体出口 ]============"
                    server_test_exit_info "ipv6"
                    ;;
                *) echo -e "${RED}[错误] 未检测到可用公网 IPv4 / IPv6。${PLAIN}" ;;
            esac
            ;;
    esac
}

server_test_download_rrc_source() {
    local out="$1"
    local commit="ab6829eb07c4c592c1f8f3dac736d675667d1a08"
    local blob="9cd4e7fd81f49acfa4336ee48322114f8d88a6ad"
    local raw="https://raw.githubusercontent.com/1-stream/RegionRestrictionCheck/${commit}/check.sh"
    local source size actual ok=0

    ensure_test_dependency curl curl || return 1
    command -v sha1sum >/dev/null 2>&1 || ensure_test_dependency sha1sum coreutils || return 1

    for source in "$raw" "https://ghproxy.net/$raw" "https://gh-proxy.com/$raw"; do
        rm -f "$out"
        echo -e "${YELLOW}>> 下载并校验 RegionRestrictionCheck...${PLAIN}"
        if ! curl -fL --retry 2 --retry-delay 1 --connect-timeout 10 --max-time 90 "$source" -o "$out"; then
            continue
        fi
        size=$(wc -c <"$out" | tr -d '[:space:]')
        actual=$(
            {
                printf 'blob %s\0' "$size"
                cat "$out"
            } | sha1sum | awk '{print $1}'
        )
        if [[ "${actual,,}" == "${blob,,}" ]]; then
            ok=1
            break
        fi
        echo -e "${RED}[警告] Git blob 校验失败，拒绝执行当前下载结果。${PLAIN}"
    done

    [[ $ok -eq 1 ]] || {
        rm -f "$out"
        echo -e "${RED}[错误] RegionRestrictionCheck 下载失败或来源完整性校验失败。${PLAIN}"
        return 1
    }
    chmod 700 "$out"
    return 0
}

server_test_run_region_restriction_check() {
    local selection="$1" mode="${2:-0}"
    local source runner family run_mode
    source=$(mktemp /tmp/ss2022-rrc-source.XXXXXX.sh) || return 1
    runner=$(mktemp /tmp/ss2022-rrc-runner.XXXXXX.sh) || { rm -f "$source"; return 1; }

    ensure_test_dependency jq jq || { rm -f "$source" "$runner"; return 1; }
    ensure_test_dependency python3 python3 || { rm -f "$source" "$runner"; return 1; }
    ensure_test_dependency grep grep || { rm -f "$source" "$runner"; return 1; }
    ensure_test_dependency openssl openssl || { rm -f "$source" "$runner"; return 1; }

    if ! server_test_download_rrc_source "$source"; then
        rm -f "$source" "$runner"
        return 1
    fi

    if ! grep -q '^function ScriptTitle()' "$source" ||
       ! grep -q '^function Global_UnlockTest()' "$source"; then
        echo -e "${RED}[错误] 上游脚本结构发生变化，已停止执行以避免误调用。${PLAIN}"
        rm -f "$source" "$runner"
        return 1
    fi

    sed '/^function ScriptTitle()/,$d' "$source" >"$runner"
    cat >>"$runner" <<'RRC_RUNNER'

ss2022_rrc_run_family() {
    local fam="$1" fn
    echo ""
    echo "===========[ IPV$fam 通用流媒体 ]============"
    Global_UnlockTest "$fam"

    if [[ -n "$SS2022_RRC_REGIONS" ]]; then
        IFS=',' read -r -a ss2022_rrc_funcs <<<"$SS2022_RRC_REGIONS"
        for fn in "${ss2022_rrc_funcs[@]}"; do
            case "$fn" in
                TW_UnlockTest|HK_UnlockTest|JP_UnlockTest|KR_UnlockTest|NA_UnlockTest|SA_UnlockTest|EU_UnlockTest|AF_UnlockTest|SEA_UnlockTest|OA_UnlockTest|Sport_UnlockTest)
                    "$fn" "$fam"
                    ;;
            esac
        done
    fi
}

case "$SS2022_RRC_MODE" in
    4) ss2022_rrc_run_family 4 ;;
    6) ss2022_rrc_run_family 6 ;;
    *)
        ss2022_rrc_run_family 4
        ss2022_rrc_run_family 6
        ;;
esac
RRC_RUNNER
    chmod 700 "$runner"

    family=$(server_test_detect_family_mode)
    run_mode="$mode"
    case "$mode:$family" in
        4:both|4:ipv4) run_mode=4 ;;
        4:*) echo -e "${YELLOW}当前 VPS 未检测到可用公网 IPv4，跳过流媒体 IPv4 检测。${PLAIN}"; rm -f "$source" "$runner"; return 0 ;;
        6:both|6:ipv6) run_mode=6 ;;
        6:*) echo -e "${YELLOW}当前 VPS 未检测到可用公网 IPv6，跳过流媒体 IPv6 检测。${PLAIN}"; rm -f "$source" "$runner"; return 0 ;;
        0:both) run_mode=0 ;;
        0:ipv4) run_mode=4 ;;
        0:ipv6) run_mode=6 ;;
        0:*) echo -e "${RED}[错误] 未检测到可用公网 IPv4 / IPv6。${PLAIN}"; rm -f "$source" "$runner"; return 1 ;;
    esac

    SS2022_RRC_REGIONS="$selection" SS2022_RRC_MODE="$run_mode" bash "$runner" || true
    rm -f "$source" "$runner"
    return 0
}

test_streaming_unlock() {
    clear
    show_external_test_source "流媒体 / 区域解锁测试" "1-stream/RegionRestrictionCheck"
    echo -e "${YELLOW}通用流媒体固定检测；地区平台按选择追加。AI 平台不会在本项执行。${PLAIN}"
    echo -e "${CYAN}通用项目包含 Netflix / YouTube Premium / Disney+ / Prime Video / Spotify / Google 等。${PLAIN}"
    server_test_select_streaming_region || return
    server_test_select_ip_mode || return
    echo ""
    echo -e "${CYAN}检测范围: 通用流媒体${SERVER_TEST_REGION_SELECTION:+ + ${SERVER_TEST_REGION_LABEL}}${PLAIN}"
    case "$SERVER_TEST_IP_MODE" in
        4) echo -e "${CYAN}地址族: 仅 IPv4${PLAIN}" ;;
        6) echo -e "${CYAN}地址族: 仅 IPv6${PLAIN}" ;;
        *) echo -e "${CYAN}地址族: IPv4 + IPv6${PLAIN}" ;;
    esac
    echo ""
    server_test_show_exit_info_for_mode "$SERVER_TEST_IP_MODE"
    echo ""
    server_test_run_region_restriction_check "$SERVER_TEST_REGION_SELECTION" "$SERVER_TEST_IP_MODE" || true
    echo ""
    pause
}

test_ai_unlock() {
    clear
    show_external_test_source "AI 工具测试" "oneclickvirt/UnlockTests"
    echo -e "${CYAN}检测模式: AI-only（ChatGPT / Gemini / Claude / Copilot / Grok / Perplexity / Poe 等）${PLAIN}"
    echo -e "${YELLOW}结果区分 YES / NO / Restricted / Banned / TIMEOUT / DNS失败等状态。${PLAIN}"
    server_test_select_ip_mode || return
    echo ""
    case "$SERVER_TEST_IP_MODE" in
        4) echo -e "${CYAN}地址族: 仅 IPv4${PLAIN}" ;;
        6) echo -e "${CYAN}地址族: 仅 IPv6${PLAIN}" ;;
        *) echo -e "${CYAN}地址族: IPv4 + IPv6${PLAIN}" ;;
    esac
    echo ""
    server_test_run_unlocktests "21" "AI 平台检测" "$SERVER_TEST_IP_MODE" "region" || true
    echo ""
    pause
}

server_test_communication_probe() {
    local family="$1" name="$2" url="$3" family_flag errfile http_code rc status
    [[ "$family" == "ipv6" ]] && family_flag="-6" || family_flag="-4"
    errfile=$(mktemp /tmp/ss2022-comm.XXXXXX) || return 1
    http_code=$(curl "$family_flag" -sS -o /dev/null -w '%{http_code}' \
        --connect-timeout 6 --max-time 12 "$url" 2>"$errfile")
    rc=$?
    rm -f "$errfile"
    case "$rc" in
        0) status="YES${http_code:+ (HTTP ${http_code})}" ;;
        6) status="N/A (DNS Resolve Failed)" ;;
        7) status="NO (Connect Failed)" ;;
        28) status="TIMEOUT" ;;
        35|60) status="NO (TLS Failed)" ;;
        *) status="NO (curl ${rc})" ;;
    esac
    printf " %-25s %s\n" "$name" "$status"
}

server_test_exit_info() {
    local family="$1" family_flag ip trace country
    [[ "$family" == "ipv6" ]] && family_flag="-6" || family_flag="-4"

    if [[ "$family" == "ipv6" ]]; then
        ip=$(get_public_ipv6 2>/dev/null || true)
    else
        ip=$(get_public_ipv4 2>/dev/null || true)
    fi

    trace=$(curl "$family_flag" -fsS --connect-timeout 5 --max-time 8 \
        "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null || true)
    country=$(awk -F= '$1=="loc" {print $2; exit}' <<<"$trace")
    [[ "$country" =~ ^[A-Z]{2}$ ]] || country="未知"

    printf " %-25s %s\n" "出口 IP" "${ip:-未知}"
    printf " %-25s %s\n" "出口地区" "$country"
}

server_test_run_communication_family() {
    local family="$1" title
    [[ "$family" == "ipv6" ]] && title="IPV6" || title="IPV4"
    echo "===========[ ${title} 通信软件 ]============"
    server_test_exit_info "$family"
    server_test_communication_probe "$family" "Telegram" "https://web.telegram.org/"
    server_test_communication_probe "$family" "WhatsApp" "https://web.whatsapp.com/"
    server_test_communication_probe "$family" "Signal" "https://signal.org/"
    server_test_communication_probe "$family" "Discord" "https://discord.com/api/v10/gateway"
}

test_communication_access() {
    local family
    clear
    echo -e "${CYAN}════════════════════ 通信软件网络可达性测试 ════════════════════${PLAIN}"
    echo -e "${YELLOW}检测 DNS / TCP / TLS / HTTPS 可达性，不登录账号，也不代表消息发送功能。${PLAIN}"
    server_test_select_ip_mode || return
    family=$(server_test_detect_family_mode)
    echo ""
    case "$SERVER_TEST_IP_MODE" in
        4)
            case "$family" in
                both|ipv4) server_test_run_communication_family "ipv4" ;;
                *) echo -e "${YELLOW}当前 VPS 未检测到可用公网 IPv4。${PLAIN}" ;;
            esac
            ;;
        6)
            case "$family" in
                both|ipv6) server_test_run_communication_family "ipv6" ;;
                *) echo -e "${YELLOW}当前 VPS 未检测到可用公网 IPv6。${PLAIN}" ;;
            esac
            ;;
        *)
            case "$family" in
                both)
                    server_test_run_communication_family "ipv4"
                    echo ""
                    server_test_run_communication_family "ipv6"
                    ;;
                ipv4) server_test_run_communication_family "ipv4" ;;
                ipv6) server_test_run_communication_family "ipv6" ;;
                *) echo -e "${RED}[错误] 未检测到可用公网 IPv4 / IPv6。${PLAIN}" ;;
            esac
            ;;
    esac
    echo ""
    pause
}

test_platform_media_ai_communication_unlock() {
    local family
    clear
    echo -e "${CYAN}════════════ 平台流媒体AI通信软件解锁测试 ════════════${PLAIN}"
    echo -e "${YELLOW}一次选择地址族后，依次执行流媒体、AI、通信软件检测。${PLAIN}"
    echo -e "${YELLOW}通信软件部分检测网络可达性，不登录账号，也不代表消息发送功能。${PLAIN}"

    server_test_select_streaming_region || return
    server_test_select_ip_mode || return
    family=$(server_test_detect_family_mode)

    echo ""
    echo -e "${CYAN}════════════ 1/3 流媒体解锁 ════════════${PLAIN}"
    show_external_test_source "流媒体 / 区域解锁测试" "1-stream/RegionRestrictionCheck"
    echo -e "${CYAN}检测范围: 通用流媒体${SERVER_TEST_REGION_SELECTION:+ + ${SERVER_TEST_REGION_LABEL}}${PLAIN}"
    case "$SERVER_TEST_IP_MODE" in
        4) echo -e "${CYAN}地址族: 仅 IPv4${PLAIN}" ;;
        6) echo -e "${CYAN}地址族: 仅 IPv6${PLAIN}" ;;
        *) echo -e "${CYAN}地址族: IPv4 + IPv6${PLAIN}" ;;
    esac
    echo ""
    server_test_show_exit_info_for_mode "$SERVER_TEST_IP_MODE"
    echo ""
    server_test_run_region_restriction_check "$SERVER_TEST_REGION_SELECTION" "$SERVER_TEST_IP_MODE" || true

    echo ""
    echo -e "${CYAN}════════════ 2/3 AI 工具解锁 ════════════${PLAIN}"
    show_external_test_source "AI 工具测试" "oneclickvirt/UnlockTests"
    server_test_run_unlocktests "21" "AI 平台检测" "$SERVER_TEST_IP_MODE" "region" || true

    echo ""
    echo -e "${CYAN}════════════ 3/3 通信软件解锁 ════════════${PLAIN}"
    echo -e "${YELLOW}此处“解锁”表示网络可达性检测，不代表账号区服或消息发送能力。${PLAIN}"
    case "$SERVER_TEST_IP_MODE" in
        4)
            case "$family" in
                both|ipv4) server_test_run_communication_family "ipv4" ;;
                *) echo -e "${YELLOW}当前 VPS 未检测到可用公网 IPv4。${PLAIN}" ;;
            esac
            ;;
        6)
            case "$family" in
                both|ipv6) server_test_run_communication_family "ipv6" ;;
                *) echo -e "${YELLOW}当前 VPS 未检测到可用公网 IPv6。${PLAIN}" ;;
            esac
            ;;
        *)
            case "$family" in
                both)
                    server_test_run_communication_family "ipv4"
                    echo ""
                    server_test_run_communication_family "ipv6"
                    ;;
                ipv4) server_test_run_communication_family "ipv4" ;;
                ipv6) server_test_run_communication_family "ipv6" ;;
                *) echo -e "${RED}[错误] 未检测到可用公网 IPv4 / IPv6。${PLAIN}" ;;
            esac
            ;;
    esac

    echo ""
    pause
}

server_test_management() {
    while true; do
        clear
        echo -e "${CYAN}════════════════════ 服务器测试管理 ════════════════════${PLAIN}"
        echo "  1. IP 质量 / 风险测试"
        echo "  2. IPv4 / IPv6 三网逐跳回程"
        echo "  3. 平台流媒体AI通信软件解锁测试"
        echo "  0. 返回"
        echo -e "${CYAN}═══════════════════════════════════════════════════════${PLAIN}"
        read -rp "请选择 [0-3]: " c
        case "$c" in
            1) test_ip_quality ;;
            2) test_return_route ;;
            3) test_platform_media_ai_communication_unlock ;;
            0) return ;;
            *) sleep 1 ;;
        esac
    done
}

protocol_operations_management() {
    while true; do
        clear
        echo -e "${CYAN}════════════════════ 协议运维管理 ════════════════════${PLAIN}"
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
            2) follow_service_log sing-box ;;
            3) follow_service_log "$XRAY_SERVICE_NAME" ;;
            4) follow_service_log snell-v5 ;;
            5) follow_service_log "$REALM_SERVICE_NAME" ;;
            6) restart_service_safe sing-box "sing-box"; pause ;;
            7) restart_service_safe "$XRAY_SERVICE_NAME" "ss2022-xray"; pause ;;
            8) restart_service_safe snell-v5 "Snell v5"; pause ;;
            9) restart_service_safe "$REALM_SERVICE_NAME" "Realm 转发"; pause ;;
            10)
                if service_is_active "$(keepalive_service_name)"; then
                    echo "IPv6 Keepalive: Running"
                    service_status_output "$(keepalive_service_name)" 2>/dev/null || true
                else
                    echo "IPv6 Keepalive: 未运行"
                fi
                pause
                ;;
            0) return ;;
            *) sleep 1 ;;
        esac
    done
}

main() {
    check_root
    detect_platform || exit 1
    if platform_is_alpine; then
        echo "[v1.9.0] 已检测到 Alpine / OpenRC；核心协议、服务管理、服务器工具与测试已接入稳定支持范围。"
        echo "[提示] Snell v5 官方二进制与 Cloudflare WARP 官方客户端暂不在 Alpine 开放。"
    fi

    # 兼容旧安装：已有 local-dns 缺少 prefer_go:true 时执行一次安全迁移。
    # 失败不会覆盖旧配置，也不会阻断管理面板。
    migrate_singbox_local_dns_prefer_go || true

    while true; do
        show_dashboard
        echo "  1. 协议管理"
        echo "  2. 分流管理"
        echo "  3. 端口转发（Realm）"
        echo "  4. 查看当前节点参数与客户端配置"
        echo "  5. 协议运维管理"
        echo "  6. 组件版本管理"
        echo "  - - - - - - - - - - - - - - - -"
        echo "  7. 服务器管理工具"
        echo "  8. 服务器测试管理"
        echo "  - - - - - - - - - - - - - - - -"
        echo "  9. 检查脚本更新"
        echo -e "${RED} 10. 完全卸载脚本${PLAIN}"
        echo "  0. 退出管理面板"
        echo -e "${CYAN}═════════════════════════════════════════════════════════════════${PLAIN}"
        read -rp "请输入选项编号 [0-10]: " choice

        case "$choice" in
            1) protocol_management ;;
            2) routing_management ;;
            3) forwarding_management ;;
            4) view_config_menu ;;
            5) protocol_operations_management ;;
            6) component_version_management ;;
            7) server_management_tools ;;
            8) server_test_management ;;
            9) check_script_update ;;
            10) full_uninstall ;;
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

# CI / smoke test can load the function library without entering the interactive UI.
# Normal users never need to set this variable.
if [[ "${SS2022_LIB_ONLY:-0}" != "1" ]]; then
    main
fi
