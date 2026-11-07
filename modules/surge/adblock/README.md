# Surge 去广告 Lite（独立可选模块）

本模块仅使用 Surge 内置的 **[Rule] 域名拦截**功能，对已识别的独立广告服务域名执行 REJECT。目标是降低侵入性，而不是追求规则数量。

**与现有节点体检完全独立：** 不安装、不启用本模块时，Surge 现有策略组、节点切换、广州三网、流媒体检测和其他功能保持不变。

## 单独安装（测试分支）

在 iPhone 的 **Surge → 模块 → 从 URL 安装**，粘贴：

```text
https://raw.githubusercontent.com/Jackyhuang83/vps-bootstrap/feat/surge-adblock-lite/modules/surge/adblock/adblock.sgmodule
```

安装后，Surge 模块列表中会出现 **VPS Bootstrap · 去广告 Lite**。这是单独模块，不要替换已经安装的「节点体检」。

当前处于开发分支，未合并正式版；先确认 GitHub CI 通过，再进行手机验收。成功安装并启用后，可在 Surge 的请求记录中检查 REJECT 命中情况；无需导入证书或修改节点设置。

## 覆盖范围

- 常见独立广告平台：Pangle、DoubleClick、Google Syndication、1RTB、部分广告交易和聚合 SDK。
- 国内部分 App 的专用广告域名：QQ 音乐、百度广告网络、字节、快手、淘宝广告统计、彩云天气、Keep 等。
- 优先使用完整域名；只对明确的广告服务使用域名后缀规则。

当前共 **50 条本地规则**，无远程规则订阅，不会自动扩张拦截范围。

**不会保证移除所有广告。** 与正文或视频共用第一方域名的广告、开屏广告、本地缓存广告、YouTube 视频内广告和需要响应改写的 App 广告，可能仍然存在。仅拦截广告域名，不提供会员破解、不修改 App 数据或付费权益。

## 为什么不直接合并上游 Blockads

参考来源：[thNylHx/Tools/Surge/Module/Blockads.sgmodule](https://github.com/thNylHx/Tools/blob/main/Surge/Module/Blockads.sgmodule)。

上游综合模块包含 [Rule]、[URL Rewrite]、[Body Rewrite]、[Map Local]、[Script] 和 [MITM]，涉及较多第三方远程脚本、响应修改、TLS 解密，以及可能影响推送/支付/小程序的宽泛域名、IP 与端口规则。其 README 也明确对 Fork 和转载提出限制，没有提供可直接复用的许可证。因此本模块仅参考公开广告服务线索，**自行筛选、独立整理规则，不复制上游完整模块及外部脚本**。

本版刻意排除推送服务、微信小程序资源、共享 CDN、第一方 API、ASN/IP-CIDR、整站 DOMAIN-KEYWORD、预匹配、DIRECT/PROXY 规则，避免干扰本来正常的节点路由。没有 MITM、HTTP 请求/响应脚本、远程 JavaScript 或证书安装步骤。

## 验证与关闭

先在 Surge 启用本模块，查看常用 App 的功能是否正常。可以重点查看广告是否减少，同时验证正常登录、消息通知、音乐/视频播放、支付、App 内跳转和小程序。某条广告域名规则无法覆盖的情况不要追加宽泛规则硬拦截；应先确认专属广告域名、误拦风险，再独立评估。

**遇到加载异常时**，在 Surge → 模块中关闭「VPS Bootstrap · 去广告 Lite」，重新打开对应 App 检查是否恢复。关闭模块即可回退其规则，无需修改代理节点；如仍异常，可删除该模块。其他已安装模块仍按原配置工作。

本模块不提供自动统计或额外的测速面板，不会上报浏览记录。Surge 自身的规则匹配日志仍以你的 Surge 设置为准。

## 开发者验证

```bash
node --test modules/surge/adblock/tests/adblock.test.cjs
```

回归检查包括规则语法、域名唯一性、关键服务白名单对照、脚本/MITM/改写禁入、模块独立性以及安装与回退文档。测试为静态及模拟匹配验证，不能替代不同 Surge 版本与实际 App 广告场景的手机验收。
