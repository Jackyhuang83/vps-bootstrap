# SS2022 原生 IPv6 优先 + WARP IPv4 补全（实机稳定基线）

适用于 vps-bootstrap 管理的 sing-box SS2022 / SS2022 + ShadowTLS **direct** 出站。  
**实机验证：2026-11-10，日本 IPv6-only VPS JP-sososo-v6。**

## 已确认的行为

| 目标 | 预期出口 |
| --- | --- |
| IPv6-only | VPS 原生 IPv6 |
| 双栈域名（由代理服务器解析） | 优先 VPS 原生 IPv6 |
| IPv4-only | 通过操作系统现有的 WARP IPv4 路由 |

日本 VPS 上使用 sing-box 1.13.x 的 `direct.domain_strategy=prefer_ipv6` 经独立 A/B 测试和 Surge 实机验证通过。原先尝试的 `route.resolve + dns.strategy` 未能实现目标，不能视为可复用稳定方案。

## 使用菜单

自 v1.9.1-dev17 起，**WARP 系统 IPv4 安装也在同一菜单内**，不需要另外访问 GitLab 查找命令。


在 VPS SSH 中执行 `ss2022`，进入：

**2. 分流管理 → 6. SS2022 IPv6 优先 / WARP IPv4 补全（稳定基线）**

菜单包含：
1. 查看策略状态（只读）。
2. 原生 IPv6、系统 WARP IPv4 和候选 sing-box 独立实例测试（不改运行服务）。
3. **直接运行 fscarmen 上游脚本的 `4` 模式安装系统 WARP IPv4**，安装前执行冲突检查、下载校验和二次确认。
4. **进入已安装的 fscarmen 官方 WARP 管理菜单**，保留作者自带的升级、检查与关闭功能。
5. 一键启用 SS2022 IPv6 优先，必须在检查通过后备份配置、重启 sing-box，失败自动回滚。
6. 恢复菜单启用前配置（拒绝覆盖后续发生变化的配置）。

## 安全边界

- `3` 明确授权后调用 **fscarmen 官方上游脚本**安装 WARP IPv4；`5` 仅负责 sing-box 策略，不自行创建/修改 WARP。
- 本工具的 SS2022 策略部分不改 SSH、防火墙、系统路由、系统 DNS、节点密钥、监听端口和入站；**fscarmen 上游安装器本身会管理系统路由和 DNS**，安装前必须有 VPS 厂商控制台备用。
- 不更改其他分流、链式落地与显式指定的 IPv4 / IPv6 规则；仅影响使用 `direct` 的域名拨号。
- 核心版本和配置结构必须通过当前设备 `sing-box check`，再用仅监听 `127.0.0.1` 的临时 SOCKS5 实例验证双栈地址族与 IPv4-only 回退。
- 若未来 sing-box 版本移除了 `direct.domain_strategy`，候选校验会报错并停止，**不得自动替换成未经实测的新参数**。
- 如果当前已是 `prefer_ipv6`，菜单“启用”不修改配置，不重启服务。
- 回滚只针对菜单创建的备份；若配置被其他更新修改则拒绝自动覆盖，以免破坏新的节点/分流。
- 配置通过和进程启动不等于每个客户端实机出口已验收。Surge 中仍需选择正确的日本节点检查实际目标地址族。
- `ss2022.sh` 生成路由配置时会保留已经显式启用的 `direct.domain_strategy=prefer_ipv6`，不影响尚未选择此功能的 VPS。

## 实机回执

2026-11-10：独立 A/B `CANDIDATE_PASS`，正式 sing-box `APPLY_SUCCESS`；用户通过 Surge → 香港中转 → 日本 SS2022，访问 `https://api64.ipify.org` 返回原生 IPv6。系统 `curl -4` WARP 与 `curl -6` 原生 IPv6 均正常。

此基线不代表将 WARP IPv4 用作 SS2022 本身的代理入口；WARP 仅承担服务器出站的 IPv4-only 目标。
