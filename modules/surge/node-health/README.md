# Surge 节点体检 · v0.1.0-beta.1

一个模块，三个手动刷新面板：IP 纯净度、平台解锁初检、三网站点 HTTP 耗时。面向 Surge iOS，建议使用当前版本；依赖脚本 `$httpAPI`、`$surge.selectGroupDetails()` 和 `$httpClient`。macOS 尚未实机验证。

**当前是测试版：本地自动化验证通过，尚未在真实 Surge / 用户节点上完成接口和界面验收。**

## 安装

在 Surge 的模块管理中选择从 URL 安装，粘贴：

```text
https://raw.githubusercontent.com/Jackyhuang83/vps-bootstrap/feat/surge-node-health/modules/surge/node-health/node-health.sgmodule
```

启用时填写参数：

| 参数 | 填写方法 |
| --- | --- |
| `POLICY` | 已有的具体节点名，或手动选择策略组的完整名称。包括空格和表情符号，必须一致。 |
| `SHOW_IP` | 默认 `false`，遮住部分出口 IP；填 `true` 显示完整 IP。 |

例如：已有节点叫 `日本 Snell`，则 `POLICY` 填 `日本 Snell`。已有手动选择组叫 `节点选择`，也可以填写 `节点选择`，再在该组中选好节点。

返回策略选择页，找到三个面板，点击对应面板刷新。若不显示，请先核对 Surge 的面板功能是否可用、模块是否启用、脚本是否已下载。模块本身不要求开启 MITM、安装证书、开放 HTTP API 监听端口或登录任何平台。

每次刷新先读取本机节点列表，把嵌套的手动选择组解析到具体节点。所有该次检测请求指定同一节点；节点名错误、选择 DIRECT/REJECT 或无法固定节点时会停止，显示错误。自动测速、故障转移、负载均衡等自动组请改填具体节点或外层最终选到具体节点的手动组。

外部订阅节点需要 Surge 能返回 `external-policies` 标识（官方文档标注 iOS 5.24.0+ / Mac 6.11.0+）。旧版无法识别外部节点时会提示找不到节点，请升级后再试。普通本地节点不依赖此扩展。

## 三个面板怎么看

### IP 纯净度

- 显示本次访问 IPPure 接口的出口 IP、国家/地区、ASN/组织和接口明确提供的类型。
- IPPure 风险分为 0–100，越低越好。为方便阅读，同时显示 `100 − 风险分`，标为“纯净度参考”，不是安全概率或账号保证。
- 没有分数、返回 HTML、限流、字段异常都显示未知。接口返回 `false` 或不含类型时，不反推“机房”或“原生”。
- IPPure 官方说明不评估 IPv6，因此 IPv6 即使伴随风险字段也不生成纯净度分。
- 本面板只显示这一次连接选中的地址族，不代表已同时检测 IPv4 和 IPv6。

### 平台解锁初检

| 平台 | 检测内容 | 不能据此确认 |
| --- | --- | --- |
| Netflix | 两部样本的片库页标识；能取得时显示地区 | 完整片库、DRM、账号、实际视频 CDN 能否播放 |
| Disney+ | 匿名设备会话返回的 `inSupportedLocation` 和地区 | 账号权益、DRM、实际播放 |
| YouTube Premium | Premium 页面中的地区与内容标识 | 账号可购买、所有视频可播或实际 CDN 质量 |
| ChatGPT | 网页返回、明确的地区拒绝提示，以及其边缘 trace 地区 | 登录、发送消息、App 或 API 可用性；trace 地区不等于服务授权 |
| Gemini | 网页返回及明确的地区拒绝提示 | 登录后的账号可用性、对话、API |

HTTP 200 本身不算完整解锁。人机验证、认证失败、限流、跨站登录跳转、接口字段变化均单独显示。无法取到地区就不猜测 US，不把 IPPure 的地区套给其他平台。

网页检测最多跟随两次同源跳转，每次仍指定相同节点。跨域登录/同意页面交给用户确认。Disney 的浏览器应用标识来自公开的浏览器检测实现，不是用户 Token；接口或应用标识失效会显示未知或认证错误。

### 三网站点 HTTP 耗时

测量范围：**手机 → 指定节点 → 国内运营商站点**。首版固定三个可识别的运营商站点：

| 标签 | 地址 |
| --- | --- |
| 电信 | `https://www.189.cn/favicon.ico` |
| 联通 | `https://iservice.10010.com/favicon.ico` |
| 移动 | `https://www.10086.cn/favicon.ico` |

每站串行发出 3 次 HTTPS HEAD 请求；三站并行。显示有响应样本的中位数、最小/最大耗时、响应次数和原始 HTTP 状态。每个请求超时 4 秒，整次脚本有 20 秒保护时限。

这不是 ICMP Ping，也不是 VPS 回程、三网骨干测评或运营商固定机房探针。耗时可能包括 DNS、节点连接、TLS 与站点处理；连接可能复用。运营商网站也可能使用 CDN 或调度到不同位置，因此不能据此判定 CN2、CMIN2、CUII 或三网跨境线路等级。

`HTTP 403/405/412` 表示站点有响应但拒绝当前请求；耗时仍保留，同时展示状态码。`响应 2/3` 只是这三次 HTTP 请求中两次收到响应，不能换算为网络丢包率。测试不自动跟随跳转，避免更换测量目标。

## 安装后的验收步骤

1. `POLICY` 先填一个你确认能上网的具体节点。刷新 IP 面板，核对节点名和出口 IP 是否合理；截图前建议保留 `SHOW_IP=false`。
2. 切换为另一个出口不同的节点并刷新，确认节点名和 IP 同步变化。策略组名称不需要修改；如果填写的是具体节点名，则要改 `POLICY`。
3. 刷新三网面板，核对三个域名、响应 `x/3`、HTTP 状态和毫秒数。超时或拒绝请保留原样反馈，不直接视为节点断网。
4. 刷新平台面板，再用同一节点手动打开你有账号的平台，播放视频或发送一条消息，对照实际结果。初检不等于实际播放/对话通过。
5. 故意把 `POLICY` 改成不存在的名字：应只提示找不到节点；不应显示本地直连 IP。

切换节点后，各面板保留的是其上次刷新结果。需要分别点击刷新，并核对每张面板的节点名和时间；面板缓存不代表持续实时监测。

不后台定时运行，不修改分流规则或当前全局节点，不读取账号 Cookie/Token，不向自建服务器上传检测结果。检测站会正常看到发起请求的出口 IP。脚本不输出响应正文、完整出口 IP或凭据到日志。

## 开发验证

无需第三方 npm 包：

```bash
node --check modules/surge/node-health/node-health.js
node --test modules/surge/node-health/tests/node-health.test.cjs
```

测试以模拟 Surge 运行时覆盖缺失/异常风险分、IPv6、节点解析、策略组循环、外部节点标识、认证/人机验证/限流、保守解锁判定、同源跳转、三网抽样及超时。它们不替代真实 Surge 对模块语法、面板布局、站点可达性和节点路由的验收。

## 参考

- [Surge 脚本 API](https://manual.nssurge.com/scripting/api.html)
- [Surge 信息面板](https://manual.nssurge.com/tools/panel.html)
- [Surge 模块参数](https://manual.nssurge.com/profile/module.html)
- [Surge HTTP API / 外部节点标识](https://manual.nssurge.com/tools/http-api.html)
- [IPPure 官方接口说明](https://ippure.com/en/MyIP-Info-API)
- [IPPure 评分与 IPv6 说明](https://ippure.com/faq)
- [Rabbit-Spec/Surge 流媒体面板](https://github.com/Rabbit-Spec/Surge/tree/Master/Module/Panel/Stream-All)（检测思路参考；未直接打包其脚本）

代码按仓库 MIT 许可证分发。
