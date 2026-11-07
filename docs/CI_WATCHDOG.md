# 全项目 CI 看门狗（GitHub Actions）

状态：**PR 待验证，未在 VPS 上安装，也未启用实时通知**。

统一看门狗运行在单独 VPS 上；无需改变任何被监控仓库的工作流：
自动发现 Jackyhuang83 账号名下全部当前和以后新建的 GitHub 仓库（含私有仓库，只要只读令牌具有权限）。
目前已知：vps-bootstrap、MiniProbe、HomeSphere、NodeShell、F50-Proxy。

## 行为

- VPS systemd 定时器 **每分钟执行一次**轻量 GitHub REST 查询（实际调度存在数秒误差）；
- 启动后不足 5 分钟，安静等待；
- 构建进行至第 5 分钟：报告运行状态、当前 job/step、链接及耗时；
- 此后每 5 分钟继续报告，直到结束；成功、失败、取消、超时立即在下一次查询时报告一次；
- 对构建超时 **不自动停止、不自动重新执行**，以免误杀 Android / Go / Gradle 首次编译；
- 无 GitHub 工作流的设备修改权限，不读设备凭据，不执行 ADB；
- 只读取近 24 小时内的 workflow runs，并将已报告的运行 ID 写入本地持久状态，防止重复报告；
- GitHub API 故障单独通知，最多 5 分钟一次；无法查询时不会伪报构建成功；
- 不尝试抓取并推送完整工作流日志（可能包含项目敏感信息），只推送 GitHub 识别的步骤名称。

**无法自动把消息推送到正在进行的 ChatGPT 聊天。** 请使用 Telegram（建议）或 GitHub Issue 评论。GitHub Issue 使用本人 PAT 发评论时，未必触发所有人预期的客户端推送；Telegram 更适合主动消息。

## 安全要求

- 不使用 Actions Runner 用户 f50-runner 执行该服务：Runner 会运行来自仓库 PR 的代码，不能读取 GitHub 跨仓库令牌。
- 单独采用 systemd DynamicUser，令牌仅存在 root 0600 配置文件，状态保存到 systemd StateDirectory。
- 严禁将真正的 PAT、Telegram Bot Token、chat ID 或密码提交到 GitHub。
- GitHub Read PAT 必须给被监控私有仓库授予 **Actions: Read**、**Metadata: Read**；发现新仓库需要确保令牌仍具有权限。
- 若用 GitHub Issue 评论，使用**另一枚**仅具报告仓库 Issues: Write 的令牌，避免监控服务拥有跨仓库写权限。
- 默认用户指定通知模式；如果未配置通知，程序会报错而不是假称已发送。

## 安装（仅在用户授权后实施）

将经审查的脚本放在 /opt/ci-watchdog/watchdog.py。
以 root 创建 /etc/ci-watchdog/ 目录，配置 /etc/ci-watchdog/watchdog.env，root:root 所有，权限 0600。
参考 ci-watchdog/watchdog.env.example 填入凭据，建议使用 Telegram 频道：

    CI_WATCHDOG_OWNER=Jackyhuang83
    CI_WATCHDOG_REPO_MODE=discover
    CI_WATCHDOG_READ_TOKEN=<secret>
    CI_WATCHDOG_NOTIFY=telegram
    CI_WATCHDOG_TELEGRAM_BOT_TOKEN=<secret>
    CI_WATCHDOG_TELEGRAM_CHAT_ID=<numeric_id>

将 ci-watchdog/systemd/ci-watchdog.service 与 ci-watchdog.timer 复制到 /etc/systemd/system。
配置完成后由用户或管理员执行以下系统命令：

    sudo systemctl daemon-reload
    sudo systemctl enable --now ci-watchdog.timer
    sudo systemctl list-timers ci-watchdog.timer

验证（只读，测试时不发送通知也不写状态）：

    sudo systemctl start ci-watchdog.service
    sudo journalctl -u ci-watchdog.service -n 40 --no-pager

也可以直接在无令牌环境做离线测试：

    python3 -m unittest discover -s tests -p test_ci_watchdog.py -v

注意：service 的手动启动会执行真实一次检查/通知（如果有符合阈值的构建），需在凭据已配置后使用。

停止方法：

    sudo systemctl disable --now ci-watchdog.timer

这是**独立于本项目协议管理**的监控工具；不会安装到 sing-box、系统分流服务或 F50 本体。建议部署在已经运行 GitHub self-hosted runner 的 VPS，但保持分离的 Unix 身份与 systemd 服务。
