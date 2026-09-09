# VPS Bootstrap Management Suite

轻量化 VPS 自动部署与网络服务运维脚本，基于 **sing-box** 构建，主要用于快速部署和管理 **Shadowsocks 2022** 节点。

针对 **IPv4-only、IPv6-only 及 IPv4 + IPv6 双栈 VPS** 场景进行适配，集成服务部署、IPv6 链路保活、节点配置生成及日常运维功能。

当前版本：**v1.6.1**

---

## 系统与架构支持

| 维度 | 支持范围 |
|---|---|
| **操作系统** | Debian 11 / 12（推荐）、Ubuntu 22.04 / 24.04 LTS 等 Debian 系发行版 |
| **处理器架构** | x86_64 (amd64)、aarch64 (arm64) |
| **网络环境** | IPv4-only、IPv6-only、IPv4 + IPv6 双栈 |
| **代理核心** | sing-box 1.13.20 |
| **服务协议** | Shadowsocks 2022 |
| **前置依赖** | 自动按需安装 `curl`、`jq`、`openssl`、`coreutils`、`qrencode` 等 |

---

## ⚡ 一键部署与管理

在目标 VPS 中使用 **root** 权限执行：

```bash
curl -fsSL https://你的域名/assets/scripts/ss2022.sh -o /usr/local/bin/ss2022 && chmod +x /usr/local/bin/ss2022 && ln -sf /usr/local/bin/ss2022 /usr/local/bin/proxy && ss2022
```

```bash
curl -fsSL https://raw.githubusercontent.com/Jackyhuang83/vps-bootstrap/main/ss2022.sh -o /usr/local/bin/ss2022 && chmod +x /usr/local/bin/ss2022 && ln -sf /usr/local/bin/ss2022 /usr/local/bin/proxy && ss2022
```

安装完成后，可在终端任意位置执行：

```bash
ss2022
```

或：

```bash
proxy
```

进入交互式管理面板。

主要功能：

- Shadowsocks 2022 一键部署与管理
- IPv4 / IPv6 节点配置
- SS2022 密钥自动生成与格式校验
- 系统时间/NTP 状态检测，未同步时自动通过 chrony 校时
- TCP / UDP 服务配置
- IPv6 链路定时保活
- Surge / Loon / Clash(Mihomo) 配置生成
- SIP002 节点链接及二维码生成
- sing-box 服务状态、日志、重启及卸载管理
- sing-box 下载 SHA256 完整性校验
- 配置变更前校验及失败自动回滚
- 非 root 用户运行 sing-box 服务

---

## 管理控制台概览

```text
═════════════════════════════════════════════════════════════════
 网络连接管理运维脚本 v1.6.1
 快捷命令: ss2022 或 proxy
═════════════════════════════════════════════════════════════════
 系统信息: Debian / Ubuntu
 核心状态: sing-box 已就绪
 服务状态: ● 运行中
 链路保活: ● 已激活
 活跃通道: 已部署

 1. 部署 / 管理 Shadowsocks 2022
 2. 查看当前节点参数与客户端配置
 3. 服务运维管理
 4. 退出管理面板
═════════════════════════════════════════════════════════════════
```

---

## 常用运维命令

| 操作 | 命令 |
|---|---|
| 调出管理面板 | `ss2022` 或 `proxy` |
| 查看服务状态 | `systemctl status sing-box` |
| 查看实时日志 | `journalctl -u sing-box -f -n 20` |
| 重启服务 | `systemctl restart sing-box` |
| 查看监听端口 | `ss -tulpn \| grep sing-box` |
| 查看 IPv6 保活 | `systemctl list-timers \| grep keepalive` |

---

## Roadmap

- [ ] 自动识别并推荐 IPv4-only / IPv6-only / Dual Stack 部署模式
- [x] IPv4 环境不再强制执行 IPv6 初始化
- [ ] sing-box 版本检查与安全升级
- [x] sing-box SHA256 完整性校验
- [x] 安装失败自动回退下载源
- [x] 自动检测端口占用
- [ ] nftables / UFW 防火墙辅助配置
- [ ] 自定义节点名称
- [ ] 多节点 / 多端口支持
- [x] DNS 配置自动恢复
- [x] APT IPv6 配置卸载恢复
- [ ] 脚本在线升级
- [x] 配置变更失败自动回滚
- [ ] 配置历史备份与手动恢复

---

## 安全说明

- SS2022 密钥在 VPS 本机生成，请勿公开真实节点密钥或完整连接信息。
- sing-box Release 下载完成后会进行固定 SHA256 校验。
- sing-box 服务使用专用非 root 用户运行。
- 安全问题请参考 [`SECURITY.md`](SECURITY.md)。

---

## License

本项目基于 [MIT License](LICENSE) 开源。

仅用于网络工程技术研究、个人服务器运维及合规测试。使用者应遵守所在地法律法规及相关服务提供商条款，并自行承担使用风险。
