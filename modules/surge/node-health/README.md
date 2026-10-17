# Surge 节点体检 · v0.1.0-beta.12

选定已有策略组后，在组内选哪个节点就检测哪个。默认面板参考网络信息 𝕏、Stream-All 和 IPPure 的紧凑布局：IP 信息几行、平台一项一行、广州三网各一行。详细诊断放在本地详情页。

**当前为测试版，尚未完成真实 Surge、用户节点、广州测速目录及手机界面的验收。** 本地模拟测试不代表真实解锁或线路测试通过。

## 安装与使用

Surge → 模块 → 从 URL 安装：

```text
https://raw.githubusercontent.com/Jackyhuang83/vps-bootstrap/feat/surge-node-health/modules/surge/node-health/node-health.sgmodule
```

1. 保持默认参数启用模块，点击「检测设置」面板。每点一次切到下一个已有手动选择组，立即保存；选到平时切节点的那一组即可停下。
2. 在该组中选择节点，分别刷新「IP 纯净度」「平台解锁检测」「广州三网延迟」「入口落地查询」。入口落地是独立面板，紧接广州三网下面；每次固定所选具体节点，不批量扫描其他节点。
3. 下次检测同组里的其他节点，只需切节点、刷新检测面板。重新进入策略页只更新设置文字，不自动切组。

不需要通知权限、输入组名、MITM、证书或 HTTP API 监听端口。IP 纯净度面板直接显示完整出口 IP，不再需要 SHOW_IP 开关；旧版 showIP=false 参数仍可读取，但不会隐藏面板地址。保存的详细记录仍会打码。

已有旧版时，用同一安装地址更新模块；脚本 URL 和「检测设置」面板应显示 `v0.1.0-beta.12`。四个检测面板只显示更新时间，完整版本记录在本地详情页。新增面板需要更新模块定义，仅刷新旧面板不会添加它。Beta 1/2 的旧 `policy` 参数仍可读，本机保存的组优先。

需要当前 Surge 的脚本能力。外部订阅节点标识依赖官方标注的 iOS 5.24.0+ / Mac 6.11.0+；旧版无法识别时会提示，不回退直连。嵌套手动组可解析；自动测速、故障转移或负载均衡子组无法固定到具体节点时，会要求改选具体节点。

## 默认面板

- **IP 纯净度**：先显示出口、国旗/位置、ASN 公司；空行后显示 IP 属性和风险分。只显示 IPPure 风险分及等级，分数越低风险越低；不同时堆叠反向计算的纯净度分。出口不同、单来源有效或地区库有差异才增加提示，完整交叉核对保留在详情。图标颜色反映评分状态。
- **平台解锁检测**：ChatGPT、Gemini、Claude、Google 为第一段；Netflix、Disney+、YouTube Premium、myTV SUPER、TikTok 为第二段。每项按「平台：短结论 · 地区」显示，两段间留一行空白。明确国家代码加国旗，常见三字代码（如 JPN）规范为 JP；未识别地区保留原值，不猜测国旗。ChatGPT 的 Cloudflare 地区明确标注「边缘」，不当作服务授权地区。Google 页脚地区保留原始名称，不从节点位置补齐。
- **广州三网延迟**：广州电信、广州联通、广州移动各一行，显示有效样本的中位耗时。部分成功标注有效次数；没有有效结果则显示测点不可用或超时。
- **入口落地查询**：独立放在广州三网下面，分公网 IP（直连）、入口 IP、落地 IP 三段，取得地址时显示完整 IP、地理库位置和 ASN 公司。节点及本次更新时间保留在底部。
- **检测设置**：选定后为四行：策略组、当前节点、点按切组/组序号/版本，以及选组/详情地址。不显示常规提示图标，读取或保存失败时保留警示样式。

平台和三网结果直接显示文字结论或耗时，不使用状态表情符号。网页可达、地区检查、样本片库可见均不等于账号权益、DRM、实际播放或对话通过。

四个检测面板统一为结果、空行、节点、时间/检测范围，先看结论，底部核对本次检测的节点。短结论区分「地区支持」「网页可达」「授权样本可见」「地区受限」「需要验证」「检测超时」等，不把有限证据统称为完整支持。完整原因、Netflix 有效样本次数仍在详情保留。

不使用空格强行对齐不同长度的名称，不增加状态表情或长横线。不展示接口列表、HTTP 状态、API 认证正文、样本编号、逐次耗时或诊断段落；这些内容在详情页查看。每张卡片保留上次刷新结果，切节点后需分别刷新并核对节点和时间。原生 Panel 使用官方文字与图标接口，不承诺逐项加粗或单独着色。

## 本地选组和检测详情

保持 Surge 和模块启用，在 Safari 打开：

```text
http://surge-node-health.invalid/
```

页面上方可切换「选检测组」「检测详情」。网页组列表点一下即保存，与设置面板共用同一绑定；策略组多时可以直接点选。Safari 分享 → 添加到主屏幕，可保存「节点体检设置」入口。

详情页按四张检测卡片保存最近一次结果，显示各自节点、时间和版本。刷新记录只读取本机缓存，不发起检测。可查看来源、分项 HTTP 状态、耗时、样本与失败原因。四张卡片可能来自不同节点或不同时刻，核对后再比较；保存的公网、入口和落地地址均打码。

记录只保存在本机 Surge 脚本存储中，出口 IP 始终打码，不保存原始响应、用户 Cookie/Key 或 CDN 临时 URL 参数。名称和记录均按纯文本展示。设置写入校验来源、请求头及现有组列表；读取响应禁用缓存，不开放 CORS。

保留地址的 `http://`。这是 HTTP 请求脚本返回的本地页面，模块为保留域名添加文档地址 Host 映射，正常启用时不会请求真实外部站点。若打不开，核对脚本是否已下载、Surge/模块是否启用，以及浏览器是否改成 HTTPS。配置中的绕过项、拒绝项或优先请求脚本也可能阻止本地拦截。无需开放端口。

## IP 与平台检测依据

IPPure、IP.SB GeoIP 和 Cloudflare Trace 并行读取自身出口。至少两个来源有效时核对 IP，IPv6 先规范化；不同 IP 和同 IP 的地区库差异分别提示。IPPure 失败时仍可显示备用来源信息，风险分保持未知。

面板显示 IPPure 风险分（越低越好）；详情仍保留 `100 − IPPure 风险分` 的参考值，不是安全概率。只接受 0–100 有限数值；缺失、异常、限流和 HTML 不评分。IPPure 不评估 IPv6，IPv6 不生成纯净度分。住宅、机房、广播字段独立处理，不推断原生属性。各来源可能连接不同地址族，不据此宣称双栈均已检测。

| 平台 | 详情保留的检测证据 |
| --- | --- |
| ChatGPT | Web、iOS App 入口、OpenAI API 模型入口、ChatGPT 边缘 Trace；边缘地区明确标注，不当作服务授权地区 |
| Gemini | 自身网页地区/功能标志、Gemini API 模型入口；标志缺失不判地区不支持 |
| Claude | Web、明确地区拒绝页/跳转、Claude API 模型入口 |
| Google | 一次小型搜索的结果列表、验证码及可识别的页脚地区，不强制国家参数 |
| Netflix | 两个区域样本 81280792/70143836、自制样本 80018499；Fast.com 分配 CDN 后对 HTTPS *.nflxvideo.net 发一次 HEAD |
| Disney+ | 匿名设备会话的地区和严格布尔值 inSupportedLocation |
| YouTube Premium | Premium 地区及 ad-free 内容标识；另读 Googlevideo CDN 调度标识 |
| myTV SUPER | 匿名会话明确的 country_code；香港结果不代表频道可播 |
| TikTok | 两种公开网页应用上下文的地区，不从任意用户资料 region 猜测 |

AI API 不发送用户 Key、不生成对话。仅平台特定结构化认证错误可标为“入口可达，需 Key”；通用 401/403 不通过。API 与 Web 结果分开保留。Netflix 样本结论限于所查样本，CDN HEAD 不代表视频播放；YouTube 调度标识不代表实际视频下载。人机验证、限流、地区拒绝、DNS、TLS、连接拒绝和超时分开记录。未知地区不默认 US，也不套用 IPPure 地区。

## 入口与落地的范围

- **公网 IP（直连）**：只有这个区块显式使用 DIRECT，实测当前网络访问探测站的公网出口；不是手机 LAN 地址，也不保证代表物理宽带归属（其他系统隧道仍可能影响出口）。
- **落地 IP**：通过已固定的所选节点访问探测站；不因失败改成 DIRECT。两个区块各用独立的本次标识，Cloudflare trace 为首选，失败后使用 IP.SB 备用；每个请求 4 秒。
- **入口 IP**：探测完成后只读 Surge 的最近请求，严格匹配本次节点探测的唯一 URL、所选具体节点身份和 remoteAddress 的 `(Proxy)` 标记。只取连接记录中的 IP，不把探测站地址、旧记录或域名 DNS 结果当作入口；IPv4 端口和括号 IPv6 可解析。多个不同地址显示待确认，保留打码后的详情；记录不可读、缺失或格式变化时只将入口标为未取得。
- **位置与公司**：按明确 IP 查询 IP.SB，核对响应 IP 一致才采用地理资料；相同地址只查一次。缺失字段可使用 Surge 本地国家/ASN/组织库，缺失城市不猜测。私有入口不提交外部查询。所有地理资料均为数据库归属参考，不代表机房物理地址。

不需要 VPS 程序、HTTP API 监听、MITM 或通知，也不开启抓包。仅在本地处理匹配到的探测记录，不保存其他请求、请求头、Cookie 或原始 API 响应。记录格式与在线接口仍需真实 Surge 验收。此功能不还原服务商隐藏转发，不根据入口/落地差异推断中转跳数，也不解析客户端配置链。

## 广州三网的测量范围

**目标只取广州电信、广州联通、广州移动。** 首次通过选中节点请求 Ookla 当前测速目录，筛选城市名 Guangzhou/广州、中国、广州范围坐标和单一运营商字段；同运营商优先选择已知 ID，否则按 ID 稳定排序选择合格记录。位置与运营商归属以目录声明为依据，未独立测绘物理机房或回程路由。

三个测点齐全时在本机固定 30 分钟，切换节点继续测相同测点，减少目标变更带来的比较误差。过期后重新取得目录；目录失败、缺少某运营商、字段异常或目标不可用时明确显示未知，**不改用其他城市或全国官网，也不使用过期快照伪装当前可用测点**。服务器 ID、域名和目录状态保存在本地详情。

每站串行 5 次 GET 小型 `latency.txt`，三站并行。只将 HTTP 200 且正文严格为 `test=test` 的正常测速响应计入中位数；验证码、403、限流、跳转、异常 HTML 不生成延迟。详情保存逐次结果、范围和相邻有效样本耗时差均值，不跨失败样本计算。单次 3 秒，总保护时限 25 秒，模块超时 30 秒；不下载测速大文件。

**这里测量的是手机 → 所选节点 → 广州测速点的 HTTP 往返，包含手机到节点和服务器处理时间。** 它不是节点端逐跳回程、纯 ICMP/TCP Ping、丢包率或 CN2/CMIN2/CUII 等级。真正查看节点到广州每一跳，需要该节点端能运行 traceroute/NextTrace 或提供等价检测能力；纯 Surge 模块无法替代。

## 手机验收

1. 通知保持关闭，切换检测组，重新进入策略页后确认绑定不变。
2. 在同组选择两个出口不同的节点分别刷新 IP，核对节点/IP 跟随，默认卡片是否保持简洁。
3. 平台卡片应每平台一行；在详情页核对 AI/API、样本/CDN 等分项，并用同一节点实际登录、播放或对话对照。
4. 广州卡片应只有三个广州目标。若提示暂无测点，查看目录状态，不将其解释为节点到国内断网；30 分钟内换节点时核对详情中的服务器 ID 一致。
5. IP 面板应显示完整 IPv4/IPv6，即使沿用旧版 showIP=false 参数；检测详情保留各卡片独立时间和版本，仍对出口打码，刷新记录不发起网络检测。
6. 更新模块后，广州三网下面应出现独立入口落地面板；点击后核对直连公网、入口、落地三个区块。入口未取得时查看本地详情，不把落地 IP 复制成入口；换节点后分别刷新并核对底部节点和时间。

当前执行环境无法连接外部探测站，未得到用户节点的真实接口返回；手机面板布局、本地页面拦截和广州目录/测速服务仍需实测。macOS 亦未实机验证。

## 开发验证

无第三方 npm 依赖：

```bash
node --check modules/surge/node-health/node-health.js
node --check modules/surge/node-health/settings.js
node --test modules/surge/node-health/tests/node-health.test.cjs
```

模拟测试覆盖检测边界、指定节点、无直连回退、面板轮换、记录隐私、紧凑展示、网页纯文本呈现、广州筛选/快照/过期/异常响应及请求并发上限；入口落地另验证直连/节点分离、唯一探测匹配、外部节点标识、入口歧义、IPv6、地理响应地址核对、本地库回退、私有地址、失败独立和超时收尾。它们不替代真实 Surge 和在线节点验收。CI 运行相同验证。

## 参考

- [网络信息 𝕏](https://github.com/xream/scripts/tree/main/surge/modules/network-info)、[Stream-All](https://github.com/Rabbit-Spec/Surge/tree/Master/Module/Panel/Stream-All)、[IPPure 模块](https://github.com/Likhixang/Egerny/blob/main/sgmodule/IPPure.sgmodule)：信息布局参考，检测与选组逻辑独立实现。
- [Surge 信息面板](https://manual.nssurge.com/tools/panel.html)、[脚本 API](https://manual.nssurge.com/scripting/api.html)、[HTTP API](https://manual.nssurge.com/tools/http-api.html)。
- [IP.SB GeoIP API](https://ip.sb/api/)、[Cloudflare cdn-cgi 文档](https://developers.cloudflare.com/fundamentals/reference/cdn-cgi-endpoint/)。入口连接字段的读取方式参考网络信息 𝕏，但增加本次 URL 和策略身份严格匹配。
- [IPPure API](https://ippure.com/en/MyIP-Info-API)、[IPv6/评分说明](https://ippure.com/faq)、[IP.SB API](https://ip.sb/api/)、[Cloudflare Trace](https://developers.cloudflare.com/fundamentals/reference/cdn-cgi-endpoint/)。
- [RegionRestrictionCheck](https://github.com/lmc999/RegionRestrictionCheck)、[Gemini 误判反馈](https://github.com/lmc999/RegionRestrictionCheck/issues/177)、[TikTokCheck](https://github.com/lmc999/TikTokCheck)：检测入口及误判边界参考。
- [Speedtest CLI](https://github.com/sivel/speedtest-cli/blob/master/speedtest.py)：小型延迟探测响应格式参考；[当前广州目录入口](https://www.speedtest.net/api/js/servers?engine=js&limit=100&search=Guangzhou)。

代码按仓库 MIT 许可证分发。
