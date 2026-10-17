/* SPDX-License-Identifier: MIT
 * VPS Bootstrap — Surge 节点体检 v0.1.0-beta.18
 * Runs locally in Surge. No MITM, policy mutations, credentials or uploads.
 */
(function () {
  "use strict";

  const VERSION = "0.1.0-beta.18";
  const SETTINGS_URL = "http://surge-node-health.invalid/";
  const SETTINGS_KEY = "VB_HEALTH_SELECTED_GROUP_V1";
  const TITLES = { ip: "IP 纯净度", unlock: "平台解锁检测", latency: "广州三网延迟", path: "入口落地查询" };
  const REPORT_KEY = "VB_HEALTH_REPORT_V1_";
  const UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";
  const TARGETS = [
    { name: "广州电信", code: "CT", carrier: "电信", fallback: { hostid: "1101", pname: "广东", city: "广州", port: "65499", hostname: "广州电信", hostip: "61.144.6.18" } },
    { name: "广州联通", code: "CU", carrier: "联通", fallback: { hostid: "1102", pname: "广东", city: "广州", port: "65499", hostname: "广州联通", hostip: "218.107.8.18" } },
    { name: "广州移动", code: "CM", carrier: "移动", fallback: { hostid: "1103", pname: "广东", city: "广州", port: "65499", hostname: "广州移动", hostip: "183.235.59.38" } }
  ];
  // Public discovery and session protocol: Gaimoydev/better-speedtest@238741b0,
  // internal/nodes/cnspeed.go + assets/config.default.json. No account credentials.
  // Fallback metadata was returned by the directory on 2026-10-17; all three
  // completed the session handshake and authenticated HEAD checks in this environment.
  const CN_DIRECTORY = "https://dlcv2.cnspeedtest.cn:8443/dataServer/mobilematch_many.php?network=4&province=%E5%B9%BF%E4%B8%9C&city=%E5%B9%BF%E5%B7%9E&mobileoperid=0&ipv6=0&model=Android&pkg=com.cnspeedtest.globalspeed&wifioper=";
  const CN_UA = "Dalvik/2.1.0 (Linux; U; Android 12; RMX3031 Build/SP1A.210812.016)";
  const CN_SAMPLES = 3;
  let completed = false;
  let mode = "ip";
  let deadlineResult = null;
  let detectedNode = "";

  function reportText(value) {
    return String(value || "").replace(/(?:\d{1,3}\.){3}\d{1,3}/g, function (ip) { return validIP(ip) ? masked(ip, false) : ip; })
      .replace(/[0-9a-f:]{3,}/gi, function (ip) { return ip.indexOf(":") >= 0 && validIP(ip) ? masked(ip, false) : ip; }).slice(0, 24000);
  }
  function finish(content, style, details, visual, footer) {
    if (completed) return;
    completed = true;
    const panelContent = content + "\n\n" + (detectedNode ? "节点：" + detectedNode + "\n" : "") + (footer || "更新") + " · " + time();
    try {
      if (typeof $persistentStore !== "undefined" && typeof $persistentStore.write === "function") {
        $persistentStore.write(JSON.stringify({ version: 1, build: VERSION, mode: mode, title: TITLES[mode], updatedAt: Date.now(),
          summary: reportText(panelContent), details: reportText(details || panelContent) }), REPORT_KEY + mode);
      }
    } catch (_) { /* Diagnostic storage never prevents a panel result. */ }
    $done(Object.assign({ title: TITLES[mode] || "节点体检", content: panelContent }, visual || { style: style || "info" }));
  }

  function parseArgument(raw) {
    // Policy is last: node/group names may contain &, =, + or literal %.
    // Legacy showIP remains readable; the native IP panel now always shows the complete address.
    const match = String(raw || "").match(/^mode=(ip|unlock|latency|path)(?:&showIP=(?:true|false))?(?:&policy=([\s\S]*))?$/);
    if (!match) throw new Error("模块参数不完整，请重新安装模块。");
    mode = match[1];
    let selected = "";
    if (typeof $persistentStore !== "undefined") {
      try {
        const saved = JSON.parse($persistentStore.read(SETTINGS_KEY) || "null");
        if (saved && saved.version === 1 && typeof saved.group === "string") selected = saved.group;
      } catch (_) { /* Corrupt settings must require re-selection, not a guessed group. */ }
    }
    // Preserve exact stored names. Legacy argument remains readable for Beta 1/2.
    const policy = selected || String(match[2] || "").trim();
    if (!policy || /[\r\n]/.test(policy) || (!selected && /填写|\{\{\{/.test(policy))) {
      throw new Error("请点击「检测设置」面板切换到要检测的策略组。也可网页点选：" + SETTINGS_URL);
    }
    return { mode: match[1], policy: policy };
  }

  function api(method, path, body) {
    return new Promise(function (resolve, reject) {
      let settled = false;
      function settle(value, error) {
        if (settled) return;
        settled = true;
        if (error) reject(error); else resolve(value);
      }
      setTimeout(function () { settle(null, new Error("读取 Surge 节点列表超时，请重试。")); }, 2200);
      try {
        if (typeof $httpAPI !== "function") throw new Error("当前 Surge 缺少脚本 HTTP API，请更新 Surge。");
        $httpAPI(method, path, body, function (value) {
          if (!value || value.error) settle(null, new Error("无法读取 Surge 节点列表。"));
          else settle(value);
        });
      } catch (error) { settle(null, error); }
    });
  }

  async function resolvePolicy(name) {
    // Validate before ANY public request. Never fall back to normal rules/DIRECT.
    const policies = await api("GET", "/v1/policies", { include_external: true });
    if (!Array.isArray(policies.proxies) || !Array.isArray(policies["policy-groups"])) {
      throw new Error("Surge 节点列表格式未知，请更新模块或 Surge。");
    }
    let decisions = {};
    if (typeof $surge !== "undefined" && typeof $surge.selectGroupDetails === "function") {
      decisions = ($surge.selectGroupDetails() || {}).decisions || {};
    }
    const seen = [];
    let current = name;
    while (Object.prototype.hasOwnProperty.call(decisions, current)) {
      if (seen.indexOf(current) !== -1 || seen.length >= 16) throw new Error("检测策略组存在循环引用。");
      seen.push(current);
      current = decisions[current];
      if (typeof current !== "string" || !current) throw new Error("检测策略组尚未选择节点。");
    }
    if (/^(DIRECT|REJECT(?:-.+)?|PROXY)$/i.test(current)) {
      throw new Error("请选择具体节点；当前选择为 " + current + "。");
    }
    const external = (policies["external-policies"] || []).filter(function (p) {
      return (p.name === current || p.identifier === current) && (!seen.length || seen.indexOf(p.group) !== -1);
    });
    // A name from the selected external group must use its identifier, even
    // if a local policy happens to have the same display name.
    if (external.length === 1 && external[0].identifier && (seen.length || external[0].identifier === current)) {
      return { policy: external[0].identifier, label: external[0].name || current };
    }
    if (policies.proxies.indexOf(current) !== -1) return { policy: current, label: current };
    if (external.length === 1 && external[0].identifier) return { policy: external[0].identifier, label: external[0].name || current };
    if (policies["policy-groups"].indexOf(current) !== -1) {
      throw new Error("请在检测组内选择具体节点，或用「检测设置」切换手动组；自动测速、故障转移等组无法固定本次检测节点。");
    }
    throw new Error("找不到检测节点「" + current + "」，请点击「检测设置」重新选组。网页选组：" + SETTINGS_URL);
  }

  function request(context, url, options) {
    const config = options || {};
    const seconds = config.timeout || 6;
    if (completed) return Promise.resolve({ error: "检测已结束", status: 0, headers: {}, body: "", ms: 0 });
    return new Promise(function (resolve) {
      const start = Date.now();
      let settled = false;
      function settle(error, response, data, localFailure) {
        if (settled) return;
        settled = true;
        resolve({ error: error ? networkError(error) : "", errorKind: error ? (localFailure ? "脚本调用失败" : connectionKind(error)) : "",
          errorCode: error ? networkSignature(error) : "",
          status: Number(response && response.status) || 0,
          headers: (response && response.headers) || {},
          body: typeof data === "string" ? data : "", ms: Math.max(0, Date.now() - start) });
      }
      setTimeout(function () { settle("timeout", null, ""); }, (seconds + 0.1) * 1000);
      const opts = { url: url, policy: context.policy, timeout: seconds,
        "auto-redirect": false, "auto-cookie": false,
        headers: Object.assign({ "User-Agent": UA, "Accept-Language": "en-US,en;q=0.9", "Cache-Control": "no-cache" }, config.headers || {}) };
      if (config.body !== undefined) opts.body = config.body;
      try { $httpClient[config.method || "get"](opts, settle); }
      catch (error) { settle(error, null, "", true); }
    });
  }

  function json(body) { try { return JSON.parse(body); } catch (_) { return null; } }
  function networkError(error) {
    const value = String(error);
    if (/timed?\s*out|timeout|超时/i.test(value)) return "超时";
    if (/dns|resolve|name.*found|nodename|主机名|解析/i.test(value)) return "DNS 解析失败";
    if (/ssl|tls|certificate|证书/i.test(value)) return "TLS/证书失败";
    if (/refused|拒绝连接/i.test(value)) return "连接被拒绝";
    return "连接失败";
  }
  function connectionKind(error) {
    const value = String(error);
    if (/closed|reset|broken pipe|econnreset|连接.*关闭|连接.*重置/i.test(value)) return "连接被关闭";
    if (/unreachable|no route|not connected|offline|enetunreach|网络.*不可达/i.test(value)) return "网络不可达";
    if (/unsupported|invalid.*(?:url|policy)|policy.*(?:not found|unknown)|unknown.*policy/i.test(value)) return "请求参数被拒";
    if (/not permitted|permission|operation.*denied/i.test(value)) return "请求被阻止";
    if (/cancelled|canceled|取消/i.test(value)) return "请求取消";
    return networkError(error);
  }
  function networkSignature(error) {
    // Keep only system domain/code or a standard errno. Never retain raw errors,
    // which may contain a node address, the full URL, or a session query.
    const value = String(error);
    const match = value.match(/\b((?:NS|CF|SG)[A-Za-z]{0,40}ErrorDomain)\b[\s\S]{0,50}?(?:Code\s*[=:]\s*|error\s+|[-:])(-?\d{1,6})\b/i);
    if (match) return match[1] + "#" + match[2];
    const errno = value.match(/\b(E(?:CONNRESET|CONNABORTED|CONNREFUSED|HOSTUNREACH|NETUNREACH|TIMEDOUT|ACCES|PERM))\b/);
    if (errno) return errno[1];
    const local = value.match(/\b(TypeError|ReferenceError|SyntaxError|RangeError)\b/);
    return local ? local[1] : "";
  }
  async function page(context, url) {
    // Follow at most two same-origin redirects, pinning the same node each time.
    // JSC does not guarantee the browser URL API, so restrict to simple paths.
    const origin = url.match(/^https:\/\/[^/]+/)[0];
    let current = url;
    let elapsed = 0;
    for (let hop = 0; hop <= 2; hop += 1) {
      const response = await request(context, current, { timeout: 5 });
      elapsed += response.ms;
      response.ms = elapsed;
      response.redirects = hop;
      if (response.error || [301, 302, 303, 307, 308].indexOf(response.status) === -1 || hop === 2) return response;
      const location = header(response, "location");
      if (!location || /[\s\\]/.test(location)) return response;
      let next;
      if (location.charAt(0) === "/" && location.charAt(1) !== "/") next = origin + location;
      else if (location.indexOf(origin + "/") === 0) next = location;
      else return response; // Consent/login on a different host needs user action.
      current = next;
    }
  }
  function country(value) { return typeof value === "string" && /^[A-Z]{2,3}$/i.test(value) ? value.toUpperCase() : ""; }
  function suffix(region) { return region ? " · " + region : ""; }
  function clean(value) { return String(value || "").replace(/[\r\n\t]+/g, " ").slice(0, 100); }
  function header(response, name) {
    const key = Object.keys(response.headers).filter(function (k) { return k.toLowerCase() === name.toLowerCase(); })[0];
    return key ? String(response.headers[key]) : "";
  }
  function challenge(body) { return /cf-chl-|challenge-platform|<title>\s*Just a moment|g-recaptcha|unusual traffic from|verify (?:that )?you are human/i.test(body); }
  function problem(response) {
    if (response.error) return response.error;
    if (response.status === 429) return "请求限流";
    if (challenge(response.body)) return "需要人机验证";
    if (response.status >= 300 && response.status < 400) return "页面跳转，待验证";
    if (response.status === 401) return "接口需认证，待验证";
    if (response.status === 403 || response.status === 451) return "请求被拒，原因待确认";
    if (response.status !== 200) return "接口异常 HTTP " + response.status;
    return "";
  }
  function evidence(label, response, note) {
    return label + "：" + (response.error || "HTTP " + response.status) + " · " + response.ms + " ms" +
      (response.redirects ? " · 跳转 " + response.redirects + " 次" : "") + (note ? " · " + note : "");
  }
  function finding(name, state, summary, region, details) {
    return { name: name, state: state, summary: summary, region: region || "", text: name + "：" + summary + suffix(region) +
      (details && details.length ? "\n  " + details.join("\n  ") : "") };
  }
  function flag(code) {
    return /^[A-Z]{2}$/.test(code || "") ? String.fromCodePoint(127397 + code.charCodeAt(0), 127397 + code.charCodeAt(1)) + " " : "";
  }
  function regionLabel(value) {
    // Normalize only known codes. Unrecognized labels stay literal, without a guessed flag.
    const aliases = { JPN: "JP", USA: "US", HKG: "HK", TWN: "TW", SGP: "SG", KOR: "KR", GBR: "GB", DEU: "DE", CAN: "CA", AUS: "AU" };
    const code = country(value);
    const normalized = aliases[code] || code;
    return /^[A-Z]{2}$/.test(normalized) ? flag(normalized) + normalized : clean(value);
  }
  function compactFinding(result) {
    const labels = {
      "网页可达，待验证对话": "网页可达", "网页可达，待登录验证": "网页可达", "网页功能标志已启用，待登录验证": "网页可达",
      "页面地区检查通过": "地区支持", "香港地区检查通过": "地区支持", "地区检查通过": "地区支持",
      "仅自制片样本可见（两个授权样本不可见）": "仅自制样本可见", "未取得有效片库证据": "片库待确认",
      "页面证据不足，未知": "待确认", "接口格式变化，未知": "接口变化", "地区状态未知": "地区待确认",
      "会话证据不足，未知": "会话待确认", "地区未知": "地区待确认", "页面地区冲突，未知": "地区冲突",
      "需要人机验证": "需要验证", "接口需认证，待验证": "需要登录", "页面跳转，待验证": "跳转待确认",
      "请求被拒，原因待确认": "请求被拒", "检测尚未完成（总时限）": "检测超时", "检测异常，待重试": "检测失败",
      "网页可达，地区未知": "网页可达 · 地区待确认"
    };
    let text = labels[result.summary] || result.summary;
    let region = result.region;
    const webRegion = result.name === "TikTok" && result.summary.match(/^网页地区 ([A-Z]{2,3})，播放待验证$/);
    const search = result.name === "Google" && result.summary.match(/^(搜索结果可达|网页可达，搜索待验证) · (?:页面地区 (.+)|地区未知)$/);
    if (webRegion) { text = "网页地区"; region = webRegion[1]; }
    if (search) { text = search[1] === "搜索结果可达" ? "搜索正常" : "搜索待确认"; region = search[2] || "地区待确认"; }
    if (/^授权片样本可见（[12]\/2）$/.test(result.summary)) text = "授权样本可见";
    if (/^接口异常 HTTP \d{3}$/.test(result.summary)) text = "服务异常";
    return result.name + "：" + text + (region ? " · " + (result.name === "ChatGPT" ? "边缘 " : "") + regionLabel(region) : "");
  }
  function traceFields(response) {
    if (problem(response)) return {};
    const fields = {};
    response.body.split(/\r?\n/).forEach(function (line) {
      const match = line.match(/^(ip|loc|colo|warp)=([^\s=]+)$/);
      if (match) fields[match[1]] = fields[match[1]] && fields[match[1]] !== match[2] ? "?" : match[2];
    });
    return fields;
  }
  function time() { return new Date().toLocaleTimeString("zh-CN", { hour12: false }); }
  function preamble(context) { return "节点：" + clean(context.label); }
  function masked(ip, show) {
    if (show) return ip;
    if (ip.indexOf(":") !== -1) return ip.split(":").slice(0, 2).join(":") + ":****";
    return ip.split(".").slice(0, 2).join(".") + ".*.*";
  }
  function validIP(ip) {
    if (typeof ip !== "string") return false;
    if (/^(?:\d{1,3}\.){3}\d{1,3}$/.test(ip)) return ip.split(".").every(function (s) { return Number(s) <= 255; });
    if (!/^[0-9a-f:]+$/i.test(ip) || ip.length > 39) return false;
    const compressed = ip.split("::");
    if (compressed.length > 2) return false;
    const halves = compressed.map(function (half) { return half ? half.split(":") : []; });
    const groups = [].concat.apply([], halves);
    if (!groups.every(function (s) { return /^[0-9a-f]{1,4}$/i.test(s); })) return false;
    if (compressed.length === 1 && (ip.charAt(0) === ":" || ip.charAt(ip.length - 1) === ":")) return false;
    return compressed.length === 2 ? groups.length < 8 : groups.length === 8;
  }
  function ipKey(ip) {
    if (ip.indexOf(":") < 0) return ip.split(".").map(Number).join(".");
    const sides = ip.toLowerCase().split("::");
    const left = sides[0] ? sides[0].split(":") : [];
    const right = sides.length > 1 && sides[1] ? sides[1].split(":") : [];
    const groups = sides.length > 1 ? left.concat(Array(8 - left.length - right.length).fill("0"), right) : left;
    return groups.map(function (v) { return parseInt(v, 16).toString(16); }).join(":");
  }

  async function ipPanel(context) {
    const responses = await Promise.all([request(context, "https://my.ippure.com/v1/info"),
      request(context, "https://api.ip.sb/geoip"), request(context, "https://www.cloudflare.com/cdn-cgi/trace")]);
    const response = responses[0];
    const issue = problem(response);
    const pure = !issue && json(response.body);
    const geo = !problem(responses[1]) && json(responses[1].body);
    const trace = traceFields(responses[2]);
    const sources = [{ name: "IPPure", data: pure, response: response }, { name: "IP.SB", data: geo, response: responses[1] },
      { name: "Cloudflare", data: trace, response: responses[2] }];
    const valid = sources.filter(function (s) { return s.data && validIP(s.data.ip); });
    if (!valid.length) return finish("出口查询失败，请稍后刷新", "alert", [preamble(context), "出口 IP 未取得；未生成纯净度分数。"].concat(sources.map(function (s) {
      return evidence(s.name, s.response, problem(s.response) || "数据格式未知");
    })).join("\n"));
    const primary = valid[0];
    const data = primary.data;
    const ipv6 = data.ip.indexOf(":") !== -1;
    const rawScore = primary.name === "IPPure" ? data.fraudScore : null;
    const score = !ipv6 && typeof rawScore === "number" && Number.isFinite(rawScore) && rawScore >= 0 && rawScore <= 100 ? rawScore : null;
    const risk = score === null ? "未知" : score <= 25 ? "低" : score <= 50 ? "轻度" : score <= 70 ? "中度" : "高";
    const types = [];
    if (data.isResidential === true) types.push("住宅");
    if (data.isDataCenter === true) types.push("机房");
    if (typeof data.isBroadcast === "boolean") types.push(data.isBroadcast ? "广播" : "非广播");
    const location = [data.country || country(data.countryCode || data.country_code || data.loc), data.region, data.city].filter(Boolean).map(clean).filter(function (v, i, a) { return a.indexOf(v) === i; }).join(" · ");
    const unique = valid.map(function (s) { return ipKey(s.data.ip); }).filter(function (v, i, a) { return a.indexOf(v) === i; });
    const comparison = valid.length < 2 ? "出口核对：仅一个来源有效，无法交叉核对" : unique.length === 1 ? "出口核对：" + valid.length + " 个来源 IP 一致" : "出口核对：不同站点出口不一致（可能分站出口或地址族不同）";
    const countries = valid.map(function (s) { return country(s.data.countryCode || s.data.country_code || s.data.loc); }).filter(Boolean)
      .filter(function (v, i, a) { return a.indexOf(v) === i; });
    const classifications = ["住宅：" + (typeof data.isResidential === "boolean" ? data.isResidential ? "是" : "否" : "未知"),
      "机房：" + (typeof data.isDataCenter === "boolean" ? data.isDataCenter ? "是" : "否" : "未知")];
    const warp = trace.warp === "on" || trace.warp === "plus" ? "已启用" + (trace.warp === "plus" ? " Plus" : "") : trace.warp === "off" ? "未启用" : "未知";
    const lines = [preamble(context), "出口：" + data.ip + (ipv6 ? "（IPv6）" : "（IPv4）"), location || "地区未知",
      score === null ? "纯净度：未知" + (ipv6 ? "（IPPure 不评估 IPv6）" : "（无有效风险分）") : "纯净度参考：" + (100 - score) + "/100 · 风险" + risk,
      "IPPure 风险分：" + (score === null ? "未知" : score + "/100（越低越好）"),
      "类型：" + (types.join(" · ") || "未知"),
      classifications.join(" · ") + " · 原生属性：未验证",
      "ASN：" + clean(data.asn || "未知") + " · " + clean(data.asOrganization || data.asn_organization || data.organization || "未知"), comparison,
      "Cloudflare：地区 " + (country(trace.loc) || "未知") + " · 接入点 " + (/^[A-Z]{3}$/.test(trace.colo || "") ? trace.colo : "未知") + " · WARP " + warp];
    sources.forEach(function (s) {
      const value = s.data && validIP(s.data.ip) ? s.data.ip : problem(s.response) || "数据格式未知";
      const region = s.data && validIP(s.data.ip) && country(s.data.countryCode || s.data.country_code || s.data.loc);
      lines.push(evidence(s.name, s.response, value + (region ? " · " + region : "")));
    });
    if (unique.length === 1 && countries.length > 1) lines.push("地区库差异：" + countries.join(" / ") + "（IP 一致，地区资料不同）");
    lines.push("主信息来源 " + primary.name + "；风险分仅来自 IPPure · " + time(), "第三方评分，仅供参考");
    const summary = [(ipv6 ? "IPv6：" : "IPv4：") + data.ip,
      "位置：" + flag(country(data.countryCode || data.country_code || data.loc)) + (location || "未知"),
      "ASN：" + (/^\d+$/.test(String(data.asn || "")) ? "AS" : "") + clean(data.asn || "未知") + " " + clean(data.asOrganization || data.asn_organization || data.organization || ""), "",
      "属性：" + (types.join(" · ") || "未知") + (warp.indexOf("已启用") === 0 ? " · WARP" + (trace.warp === "plus" ? " Plus" : "") : ""),
      score === null ? "风险分：未知" + (ipv6 ? "（IPv6 无评分）" : "") : "风险分：" + score + "/100 · " + risk + "风险"];
    if (unique.length > 1) summary.push("注意：多站出口不同");
    else if (valid.length < 2) summary.push("核对：仅一个来源有效");
    else if (countries.length > 1) summary.push("注意：地区库存在差异");
    const color = unique.length > 1 ? "#FF9500" : score === null ? "#8E8E93" : score <= 25 ? "#34C759" : score <= 50 ? "#FFCC00" : score <= 70 ? "#FF9500" : "#FF3B30";
    finish(summary.join("\n"), "info", lines.join("\n"), { icon: score !== null && score <= 50 && unique.length === 1 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill", "icon-color": color });
  }

  function localGeo(ip) {
    const result = { countryCode: "", asn: "", organization: "" };
    if (typeof $utils === "undefined") return result;
    try { result.countryCode = country($utils.geoip(ip)); } catch (_) { /* Missing local database. */ }
    try { result.asn = $utils.ipasn(ip) || ""; } catch (_) { /* Independent fields. */ }
    try { result.organization = $utils.ipaso(ip) || ""; } catch (_) { /* Independent fields. */ }
    return result;
  }
  function privateAddress(ip) {
    if (ip.indexOf(":") >= 0) {
      const key = ipKey(ip);
      const groups = key.split(":").map(function (v) { return parseInt(v, 16); });
      if (groups.slice(0, 5).every(function (v) { return v === 0; }) && groups[5] === 65535) {
        return privateAddress([groups[6] >> 8, groups[6] & 255, groups[7] >> 8, groups[7] & 255].join("."));
      }
      return key === "0:0:0:0:0:0:0:0" || key === "0:0:0:0:0:0:0:1" ||
        (groups[0] & 65024) === 64512 || (groups[0] & 65472) === 65152 || (groups[0] & 65280) === 65280;
    }
    const p = ip.split(".").map(Number);
    return [0, 10, 127].indexOf(p[0]) >= 0 || p[0] >= 224 || p[0] === 169 && p[1] === 254 ||
      p[0] === 172 && p[1] >= 16 && p[1] <= 31 || p[0] === 192 && p[1] === 168 || p[0] === 100 && p[1] >= 64 && p[1] <= 127;
  }
  function proxyAddress(value) {
    if (typeof value !== "string") return "";
    const match = value.match(/^(\S+)\s+\(Proxy\)$/i);
    if (!match) return "";
    let address = match[1];
    const bracketed = address.match(/^\[([0-9a-f:]+)\](?::(\d{1,5}))?$/i);
    if (bracketed) {
      if (bracketed[2] && (Number(bracketed[2]) < 1 || Number(bracketed[2]) > 65535)) return "";
      address = bracketed[1];
    }
    else if (!validIP(address)) {
      const withPort = address.match(/^((?:\d{1,3}\.){3}\d{1,3}):(\d{1,5})$/);
      if (withPort && Number(withPort[2]) >= 1 && Number(withPort[2]) <= 65535) address = withPort[1];
    }
    return validIP(address) ? address : "";
  }
  async function observedPublicIP(context, tag, state) {
    const traceURL = "https://www.cloudflare.com/cdn-cgi/trace?vb_health_path=" + tag;
    state.urls.push(traceURL);
    const trace = await request(context, traceURL, { timeout: 4 });
    const fields = traceFields(trace);
    state.details.push(evidence("Cloudflare", trace, fields.ip && validIP(fields.ip) ? "出口地址已取得" : problem(trace) || "无有效地址"));
    if (validIP(fields.ip) && !privateAddress(fields.ip)) {
      state.ip = fields.ip; state.countryCode = country(fields.loc); state.reason = "";
      return;
    }
    if (completed) return;
    const fallbackURL = "https://api.ip.sb/geoip?vb_health_path=" + tag;
    state.urls.push(fallbackURL);
    const response = await request(context, fallbackURL, { timeout: 4 });
    const data = !problem(response) && json(response.body);
    state.details.push(evidence("IP.SB 备用", response, data && validIP(data.ip) ? "地址已取得" : problem(response) || "无有效地址"));
    if (data && validIP(data.ip) && !privateAddress(data.ip)) {
      state.ip = data.ip; state.countryCode = country(data.country_code || data.countryCode); state.geoData = data; state.reason = "";
    } else state.reason = problem(response) || problem(trace) || "地址待确认";
  }
  async function pathGeo(context, ip, known) {
    if (privateAddress(ip)) return { location: "内网地址", asn: "未知", note: "私有或非公网地址，不提交给外部地理接口" };
    const local = localGeo(ip);
    let data = known && known.ip && validIP(known.ip) && ipKey(known.ip) === ipKey(ip) ? known : null;
    let note = "IP.SB 备用探测资料";
    if (!data && !completed) {
      const response = await request(context, "https://api.ip.sb/geoip/" + encodeURIComponent(ip), { timeout: 4 });
      const parsed = !problem(response) && json(response.body);
      data = parsed && validIP(parsed.ip) && ipKey(parsed.ip) === ipKey(ip) ? parsed : null;
      note = evidence("IP.SB 地理", response, data ? "返回地址核对一致" : problem(response) || "地址不匹配或格式变化");
    }
    data = data || {};
    function field(value) { return typeof value === "string" ? clean(value) : ""; }
    const code = country(data.country_code || data.countryCode) || local.countryCode;
    const location = [field(data.country) || code, field(data.region), field(data.city)].filter(Boolean)
      .filter(function (v, i, a) { return a.indexOf(v) === i; }).join(" · ");
    const rawASN = data.asn || local.asn;
    const asn = /^\d+$/.test(String(rawASN)) && Number(rawASN) > 0 && Number(rawASN) <= 4294967295 ? "AS" + rawASN : "";
    const organization = field(data.asn_organization || data.asOrganization || data.organization) || field(local.organization);
    return { location: (flag(code) + location).trim() || "未知", asn: [asn, organization].filter(Boolean).join(" ") || "未知", note: note + "；缺失字段可使用 Surge 本地库" };
  }
  async function pathPanel(context) {
    const nonce = Date.now() + "_" + Math.random().toString(36).slice(2);
    function blank(label) { return { label: label, ip: "", countryCode: "", urls: [], details: [], reason: "检测中" }; }
    const direct = blank("公网 IP（直连）"), entrance = blank("入口 IP"), exit = blank("落地 IP");
    function block(state) {
      if (!state.ip) return state.label + "：未取得（" + (state.reason === "检测中" ? "检测超时" : state.reason) + "）";
      return [state.label + "：" + state.ip, "位置：" + (state.geo ? state.geo.location : regionLabel(state.countryCode) || "待查询"),
        "ASN：" + (state.geo ? state.geo.asn : "待查询")].join("\n");
    }
    function render() {
      const states = [direct, entrance, exit];
      const details = [preamble(context)].concat(states.map(function (s) {
        return block(s) + (s.details.length ? "\n" + s.details.join("\n") : "") + (s.geo ? "\n" + s.geo.note : "");
      }), ["公网地址仅由 DIRECT 实测，落地由固定的所选节点实测；未把直连结果代替落地。", "入口仅匹配本次带唯一标识的节点探测 URL、策略身份及带 (Proxy) 标记的连接地址。", "入口和落地不同不能证明中间节点数量，未还原服务商隐藏转发链路。"]).join("\n\n");
      finish(states.map(block).join("\n\n"), "info", details, { icon: "network", "icon-color": "#007AFF" });
    }
    deadlineResult = render;
    await Promise.all([observedPublicIP({ policy: "DIRECT" }, nonce + "_direct", direct), observedPublicIP(context, nonce + "_node", exit)]);
    if (completed) return;
    try {
      const recent = await api("GET", "/v1/requests/recent", {});
      const addresses = [];
      (Array.isArray(recent.requests) ? recent.requests : []).forEach(function (r) {
        if (!r || exit.urls.indexOf(r.URL) < 0 || [context.policy, context.label].indexOf(r.policyName) < 0) return;
        const ip = proxyAddress(r.remoteAddress);
        if (ip && !addresses.some(function (v) { return ipKey(v) === ipKey(ip); })) addresses.push(ip);
      });
      if (addresses.length === 1) { entrance.ip = addresses[0]; entrance.reason = ""; entrance.details.push("来源：本次探测连接记录"); }
      else {
        entrance.reason = addresses.length > 1 ? "多个连接地址，待确认" : "未取得本次节点连接地址";
        if (addresses.length > 1) entrance.details.push("本次记录出现多个入口：" + addresses.join(" / "));
      }
    } catch (_) { entrance.reason = "连接记录暂不可读"; }
    if (completed) return;
    const lookups = Object.create(null);
    await Promise.all([direct, entrance, exit].map(async function (state) {
      if (!state.ip || completed) return;
      const key = ipKey(state.ip);
      if (!lookups[key]) lookups[key] = pathGeo(context, state.ip, state.geoData);
      state.geo = await lookups[key];
      if (state.geo.location === "未知" && state.countryCode) state.geo = Object.assign({}, state.geo, { location: regionLabel(state.countryCode) });
    }));
    render();
  }

  function netflixSample(response, id) {
    if (problem(response)) return false;
    // A generic landing/login page is not evidence of a catalogue entry.
    return response.body.indexOf(id) !== -1 && /"@type"\s*:\s*"(?:Movie|TVSeries)"|data-uia=["']title-info/i.test(response.body) && !/Oh no!|title (?:is )?not available|nfp-error/i.test(response.body);
  }
  function netflixRegion(response) {
    const match = response.body.match(/"countryCode"\s*:\s*"([A-Z]{2})"/) || response.body.match(/"id"\s*:\s*"([A-Z]{2})"\s*,\s*"countryName"/);
    if (match) return country(match[1]);
    const url = header(response, "x-originating-url");
    const path = url.match(/^https:\/\/www\.netflix\.com\/([a-z]{2})-[a-z]{2}\//i);
    return path ? country(path[1]) : "";
  }
  async function netflix(context) {
    const ids = ["81280792", "70143836", "80018499"];
    const all = await Promise.all([Promise.all(ids.map(function (id) { return page(context, "https://www.netflix.com/title/" + id); })), netflixCDN(context)]);
    const results = all[0];
    const visible = results.map(function (r, i) { return netflixSample(r, ids[i]); });
    const regions = results.map(netflixRegion).filter(Boolean).filter(function (v, i, a) { return a.indexOf(v) === i; });
    const region = regions.length === 1 ? regions[0] : "";
    const details = results.map(function (r, i) { return evidence((i < 2 ? "授权样本 " : "自制样本 ") + ids[i], r,
      visible[i] ? "片库可见" : r.status === 404 && !r.error && !challenge(r.body) ? "片库不可见" : problem(r) || "未取得片库证据"); });
    details.push("片库地区：" + (region || (regions.length > 1 ? "结果冲突" : "未知")));
    details.push.apply(details, all[1]);
    const regionBlock = results.some(function (r) { return regionEvidence(r) && /Netflix is not available in your country|not yet available in your (?:country|region)/i.test(r.body); });
    if (regionBlock) return finding("Netflix", "blocked", "地区受限", region, details);
    if (visible[0] || visible[1]) return finding("Netflix", "pass", "授权片样本可见（" + visible.slice(0, 2).filter(Boolean).length + "/2）", region, details);
    if (visible[2] && results.slice(0, 2).every(function (r) { return !r.error && !challenge(r.body) && (r.status === 404 || (r.status === 200 && /Oh no!|title (?:is )?not available/i.test(r.body))); })) {
      return finding("Netflix", "partial", "仅自制片样本可见（两个授权样本不可见）", region, details);
    }
    return finding("Netflix", "unknown", problem(results[0]) || "未取得有效片库证据", region, details);
  }
  async function netflixCDN(context) {
    // Public fast.com application identifier. Fetch metadata, never a speed test.
    const response = await request(context, "https://api.fast.com/netflix/speedtest/v2?https=true&token=YXNkZmFzZGxmbnNkYWZoYXNkZmhrYWxm&urlCount=1");
    const issue = problem(response);
    const data = !issue && json(response.body);
    const targets = data && Array.isArray(data.targets) ? data.targets : Array.isArray(data) ? data : [];
    const target = targets.find(function (t) { return t && typeof t.url === "string" && !/[\s\\]/.test(t.url) && /^https:\/\/[a-z0-9.-]+\.nflxvideo\.net(?::443)?\/[^\s\\]*$/i.test(t.url); });
    if (!target) return [evidence("CDN 分配", response, issue || "未取得有效 Netflix CDN 地址")];
    const host = target.url.match(/^https:\/\/([^/]+)/i)[1];
    const location = target.location || {};
    const head = await request(context, target.url, { method: "head", timeout: 4 });
    return [evidence("CDN 分配", response, clean(host) + (country(location.country) ? " · " + country(location.country) : "") + (location.city ? " · " + clean(location.city) : "")),
      evidence("CDN 连接", head, !head.error && (head.status === 200 || head.status === 206) ? "HEAD 响应通过；未下载视频" : problem(head) || "响应待确认")];
  }

  async function disney(context) {
    // Published browser application identifier, not a subscriber credential.
    const client = "ZGlzbmV5JmJyb3dzZXImMS4wLjA.Cu56AgSfBTDag5NiRA81oLHkDZfu5L3CKadnefEAY84";
    const response = await request(context, "https://disney.api.edge.bamgrid.com/graph/v1/device/graphql", {
      method: "post", headers: { Authorization: client, "Content-Type": "application/json" },
      body: JSON.stringify({ query: "mutation registerDevice($input: RegisterDeviceInput!) { registerDevice(registerDevice: $input) { grant { grantType assertion } } }",
        variables: { input: { applicationRuntime: "chrome", attributes: { browserName: "chrome", browserVersion: "131.0.0", manufacturer: "apple", model: null, operatingSystem: "macintosh", operatingSystemVersion: "10.15.7", osDeviceIds: [] }, deviceFamily: "browser", deviceLanguage: "en", deviceProfile: "macosx" } } }) });
    const details = [evidence("匿名设备会话", response)];
    if (regionEvidence(response) && /forbidden-location|unsupported-location/i.test(response.body)) return finding("Disney+", "blocked", "地区受限", "", details);
    const issue = problem(response);
    if (issue) return finding("Disney+", "unknown", issue, "", details);
    const data = json(response.body);
    const session = data && data.extensions && data.extensions.sdk && data.extensions.sdk.session;
    if (!data || (Array.isArray(data.errors) && data.errors.length) || !session) return finding("Disney+", "unknown", "接口格式变化，未知", "", details);
    const region = country(session.location && session.location.countryCode);
    details.push("会话地区支持：" + (typeof session.inSupportedLocation === "boolean" ? session.inSupportedLocation ? "是" : "否" : "未提供"));
    if (session.inSupportedLocation === true) return finding("Disney+", "pass", "地区检查通过", region, details);
    if (session.inSupportedLocation === false) return finding("Disney+", "blocked", "地区不支持", region, details);
    return finding("Disney+", "unknown", "地区状态未知", region, details);
  }

  async function youtube(context) {
    const responses = await Promise.all([page(context, "https://www.youtube.com/premium"),
      request(context, "https://redirector.googlevideo.com/report_mapping")]);
    const response = responses[0];
    const mapping = !problem(responses[1]) && responses[1].body.match(/=>\s*([a-z0-9][a-z0-9.-]{1,180})(?:\s|$)/i);
    const details = [evidence("Premium 页面", response), evidence("CDN 调度", responses[1], mapping ? "标识 " + clean(mapping[1]) : problem(responses[1]) || "调度标识未知")];
    const issue = problem(response);
    if (issue) return finding("YouTube Premium", "unknown", issue, "", details);
    const body = response.body;
    const match = body.match(/"INNERTUBE_CONTEXT_GL"\s*:\s*"([A-Z]{2})"/) || body.match(/"countryCode"\s*:\s*"([A-Z]{2})"/);
    const region = match ? country(match[1]) : "";
    if (/Premium is not available in your country/i.test(body)) return finding("YouTube Premium", "blocked", "地区不支持", region, details);
    if (region && /ad-free/i.test(body) && /ytInitialData|ytcfg\.set/.test(body)) return finding("YouTube Premium", "pass", "页面地区检查通过", region, details);
    return finding("YouTube Premium", "unknown", "页面证据不足，未知", region, details);
  }

  function regionEvidence(response) {
    return !response.error && [200, 400, 403, 451].indexOf(response.status) !== -1 && !challenge(response.body);
  }
  function regionRejected(response) {
    if (!regionEvidence(response)) return false;
    const data = json(response.body);
    const error = data && data.error;
    const code = error && typeof error === "object" ? error.code || error.type : typeof error === "string" ? error : data && data.code;
    return /^(unsupported_country|unsupported_country_region_territory|country_not_supported|forbidden-location|unsupported-location)$/i.test(String(code || "")) ||
      /not available in your country|country, region, or territory not supported/i.test(response.body);
  }
  function apiAccess(provider, response) {
    if (regionRejected(response)) return "地区受限";
    if (response.error || challenge(response.body) || response.status === 429) return problem(response);
    const data = json(response.body);
    const error = data && data.error;
    if (provider === "OpenAI" && response.status === 401 && error && typeof error === "object" &&
      (/^(invalid_api_key|missing_api_key)$/.test(error.code || "") ||
       (error.type === "invalid_request_error" && /missing|didn.t provide|must provide|no api key/i.test(error.message || "")))) return "入口可达，需 API Key（未测试调用）";
    if (provider === "Claude" && response.status === 401 && data && data.type === "error" && error && error.type === "authentication_error") return "入口可达，需 API Key（未测试调用）";
    if (provider === "Gemini" && response.status === 403 && error && error.status === "PERMISSION_DENIED" && Array.isArray(error.details) && error.details.some(function (d) {
      return d && /^(CREDENTIALS_MISSING|API_KEY_INVALID)$/.test(d.reason || "") && d.metadata && d.metadata.service === "generativelanguage.googleapis.com";
    })) return "入口可达，需 API Key（未测试调用）";
    return problem(response) || "未取得有效 API 证据";
  }
  async function chatgpt(context) {
    const responses = await Promise.all([page(context, "https://chatgpt.com/"), request(context, "https://chatgpt.com/cdn-cgi/trace"),
      request(context, "https://ios.chat.openai.com/"), request(context, "https://api.openai.com/v1/models")]);
    const home = responses[0];
    const trace = traceFields(responses[1]);
    const region = country(trace.loc);
    const app = responses[2];
    const appRedirect = /^https:\/\/(?:chatgpt\.com|(?:auth|chat)\.openai\.com)(?:\/|$)/i.test(header(app, "location"));
    const appNote = regionRejected(app) || (regionEvidence(app) && /(?:disable|turn off|blocked|disallowed)[^<>\n]{0,100}\bVPN\b/i.test(app.body)) ? "入口明确拒绝当前地区/网络" :
      !app.error && app.status >= 300 && app.status < 400 && appRedirect ? "转到官方登录入口" :
      !problem(app) && /ChatGPT|OpenAI/.test(app.body) && /<html|<!doctype/i.test(app.body) ? "入口网页可达" : problem(app) || "入口证据不足";
    const details = [evidence("Web", home, problem(home) || "首页已响应"), evidence("App 入口", app, appNote),
      evidence("OpenAI API", responses[3], apiAccess("OpenAI", responses[3])),
      evidence("边缘地区", responses[1], (region || "未知") + (trace.colo && /^[A-Z]{3}$/.test(trace.colo) ? " · " + trace.colo : "") + "（不是服务授权地区）")];
    if (regionRejected(home)) return finding("ChatGPT", "blocked", "地区受限", region, details);
    const issue = problem(home);
    if (issue) return finding("ChatGPT", "unknown", issue, region, details);
    if (/ChatGPT/.test(home.body) && /<html|<!doctype/i.test(home.body)) return finding("ChatGPT", "partial", "网页可达，待验证对话", region, details);
    return finding("ChatGPT", "unknown", "页面证据不足，未知", region, details);
  }

  async function gemini(context) {
    const responses = await Promise.all([page(context, "https://gemini.google.com/"), request(context, "https://generativelanguage.googleapis.com/v1beta/models")]);
    const response = responses[0];
    const codes = Array.from(response.body.matchAll(/,2,1,200,"([A-Z]{3})"/g)).map(function (m) { return m[1]; }).filter(function (v, i, a) { return a.indexOf(v) === i; });
    const region = codes.length === 1 ? codes[0] : "";
    const enabled = /\b45631641,null,true\b/.test(response.body);
    const details = [evidence("Web", response, problem(response) || "首页已响应"), "页面地区：" + (region || (codes.length > 1 ? "结果冲突" : "未知")),
      "页面功能标志：" + (enabled ? "已出现启用标志（账号可用性另测）" : "未取得；不能据此判定不支持"),
      evidence("Gemini API", responses[1], apiAccess("Gemini", responses[1]))];
    if (regionEvidence(response) && /Gemini (?:isn.t|is not|is currently not) (?:supported|available) in your country|not supported in your (?:country|region)/i.test(response.body)) return finding("Gemini", "blocked", "地区受限", region, details);
    const issue = problem(response);
    if (issue) return finding("Gemini", "unknown", issue, region, details);
    if (/Gemini/.test(response.body) && /<html|<!doctype/i.test(response.body)) return finding("Gemini", "partial", enabled ? "网页功能标志已启用，待登录验证" : "网页可达，待登录验证", region, details);
    return finding("Gemini", "unknown", "页面证据不足，未知", region, details);
  }

  async function claude(context) {
    const responses = await Promise.all([page(context, "https://claude.ai/"),
      request(context, "https://api.anthropic.com/v1/models", { headers: { "anthropic-version": "2023-06-01" } })]);
    const response = responses[0];
    const details = [evidence("Web", response, problem(response) || "首页已响应"), evidence("Claude API", responses[1], apiAccess("Claude", responses[1]))];
    const location = header(response, "location");
    // Known regional rejection may be an external redirect: inspect, do not follow.
    const regionRedirect = /^https:\/\/(?:www\.)?anthropic\.com\/app-unavailable-in-region(?:[/?#]|$)/i.test(location);
    if (!response.error && !challenge(response.body) && (
      (response.status >= 300 && response.status < 400 && regionRedirect) ||
      (regionEvidence(response) && /<title[^>]*>\s*App unavailable in region|Claude (?:is not|isn't|is currently not) available in your (?:country|region)/i.test(response.body))
    )) return finding("Claude", "blocked", "地区受限", "", details);
    const issue = problem(response);
    if (issue) return finding("Claude", "unknown", issue, "", details);
    if (/Claude/.test(response.body) && /<html|<!doctype/i.test(response.body)) return finding("Claude", "partial", "网页可达，待验证对话", "", details);
    return finding("Claude", "unknown", "页面证据不足，未知", "", details);
  }

  function googleLocation(body) {
    // Accept only a country label scoped to Google's footer, never search hits,
    // query parameters, another platform's GeoIP, or a guessed default country.
    const start = body.search(/\bid=["']fbar["']|<footer\b/i);
    if (start < 0) return "";
    const footer = body.slice(start, start + 16000);
    const match = footer.match(/class=["'][^"']*\buU7dJb\b[^"']*["'][^>]*>\s*([^<>]{2,60})\s*</i);
    if (!match) return "";
    return clean(match[1].replace(/&amp;/g, "&").replace(/&nbsp;/g, " ")).trim();
  }
  async function google(context) {
    // One small search; do not force a country via gl/cr parameters.
    const response = await page(context, "https://www.google.com/search?q=surge%20network%20check&hl=en&num=1");
    const details = [evidence("搜索请求", response)];
    const location = header(response, "location");
    const captchaRedirect = /^\/(?!\/)sorry(?:[/?#]|$)/i.test(location) || /^https:\/\/(?:(?:www|ipv4|ipv6)\.)?google\.com\/sorry(?:[/?#]|$)/i.test(location);
    if (!response.error && (captchaRedirect || /our systems have detected unusual traffic|automated queries|id=["']captcha-form["']/i.test(response.body))) return finding("Google", "blocked", "需要验证码", "", details.concat(["本次搜索被风控；不是地区不支持"]));
    const issue = problem(response);
    if (issue) return finding("Google", "unknown", issue, "", details);
    const region = googleLocation(response.body);
    const regionText = region ? " · 页面地区 " + region : " · 地区未知";
    if (/id=["'](?:rso|search)["']/i.test(response.body) && /<h3\b/i.test(response.body)) return finding("Google", "pass", "搜索结果可达" + regionText, "", details.concat(["验证码：本次未触发；" + (region ? "地区取自 Google 页脚" : "页脚未提供可识别地区")]));
    if (/Google/.test(response.body) && /<html|<!doctype/i.test(response.body)) return finding("Google", "partial", "网页可达，搜索待验证" + regionText, "", details.concat(["未取得搜索结果列表，不能判定免验证码"]));
    return finding("Google", "unknown", "页面证据不足，未知", "", details);
  }

  async function mytvsuper(context) {
    const response = await request(context, "https://www.mytvsuper.com/api/auth/getSession/self/");
    const details = [evidence("匿名会话", response)];
    const issue = problem(response);
    if (issue) return finding("myTV SUPER", "unknown", issue, "", details);
    const data = json(response.body);
    if (!data || data.error || data.success === false || data.status === false || data.status === "error" ||
      (Array.isArray(data.errors) && data.errors.length) || (data.error_code !== undefined && data.error_code !== 0 && data.error_code !== "0")) return finding("myTV SUPER", "unknown", "会话证据不足，未知", "", details);
    const containers = [data, data.data, data.content, data.session];
    const regions = containers.filter(function (v) { return v && typeof v === "object" && !Array.isArray(v); })
      .map(function (v) { return country(v.country_code); }).filter(Boolean)
      .filter(function (v, i, a) { return a.indexOf(v) === i; });
    if (regions.length !== 1) return finding("myTV SUPER", "unknown", "地区未知", "", details.concat([regions.length > 1 ? "会话国家字段冲突" : "会话未提供 country_code"]));
    details.push("平台识别地区：" + regions[0], "频道权益、DRM 和实际播放：未检测");
    return finding("myTV SUPER", regions[0] === "HK" ? "pass" : "blocked", regions[0] === "HK" ? "香港地区检查通过" : "非香港地区", regions[0], details);
  }

  function embeddedJSON(body, id) {
    const pattern = new RegExp("<script\\b[^>]*\\bid=[\"']" + id + "[\"'][^>]*>([\\s\\S]*?)<\\/script\\s*>", "i");
    const match = body.match(pattern);
    return match ? json(match[1]) : null;
  }
  async function tiktok(context) {
    const response = await page(context, "https://www.tiktok.com/");
    const details = [evidence("Web", response)];
    const issue = problem(response);
    if (issue) return finding("TikTok", "unknown", issue, "", details);
    if (/id=["'](?:captcha-verify-container|verify-container|tiktok-verify-page)["']/i.test(response.body)) return finding("TikTok", "unknown", "需要人机验证", "", details);
    if (/TikTok (?:is not|isn't|is currently not) available in (?:your|this) (?:country|region)/i.test(response.body)) return finding("TikTok", "blocked", "地区受限", "", details);
    const modern = embeddedJSON(response.body, "__UNIVERSAL_DATA_FOR_REHYDRATION__");
    const scope = modern && modern.__DEFAULT_SCOPE__;
    const contextData = scope && scope["webapp.app-context"];
    const legacy = embeddedJSON(response.body, "SIGI_STATE");
    const legacyContext = legacy && legacy.AppContext && legacy.AppContext.appContext;
    const regions = [contextData, legacyContext].filter(Boolean).map(function (v) { return country(v.region); })
      .filter(Boolean).filter(function (v, i, a) { return a.indexOf(v) === i; });
    if (regions.length === 1) return finding("TikTok", "partial", "网页地区 " + regions[0] + "，播放待验证", "", details.concat([
      "地区来源：" + (contextData ? "webapp.app-context" : "SIGI_STATE AppContext"), "App 地区和视频播放：未检测"]));
    if (regions.length > 1) return finding("TikTok", "unknown", "页面地区冲突，未知", "", details);
    if (/TikTok/.test(response.body) && /<html|<!doctype/i.test(response.body)) return finding("TikTok", "partial", "网页可达，地区未知", "", details);
    return finding("TikTok", "unknown", "页面证据不足，未知", "", details);
  }

  async function unlockPanel(context) {
    const checks = [["ChatGPT", chatgpt], ["Gemini", gemini], ["Claude", claude], ["Google", google],
      ["Netflix", netflix], ["Disney+", disney], ["YouTube Premium", youtube], ["myTV SUPER", mytvsuper], ["TikTok", tiktok]];
    const results = checks.map(function (entry) { return finding(entry[0], "unknown", "检测尚未完成（总时限）", "", []); });
    function render() {
      const counts = { pass: 0, partial: 0, blocked: 0, unknown: 0 };
      results.forEach(function (r) { counts[r.state] += 1; });
      const details = [preamble(context), "通过 " + counts.pass + " · 部分 " + counts.partial + " · 限制 " + counts.blocked + " · 未知 " + counts.unknown]
        .concat(results.map(function (r) { return r.text; }), ["未登录，实际播放/对话未测", "API 认证响应仅证明入口可达，不等于调用通过"]).join("\n");
      const rows = results.map(compactFinding);
      finish(rows.slice(0, 4).concat([""], rows.slice(4)).join("\n"), "info", details,
        { icon: "play.tv.fill", "icon-color": "#FF2D55" }, "播放/对话未测");
    }
    deadlineResult = render;
    await Promise.all(checks.map(async function (entry, index) {
      try { results[index] = await entry[1](context); } catch (_) { results[index] = finding(entry[0], "unknown", "检测异常，待重试", "", []); }
    }));
    render();
  }

  function median(values) {
    const sorted = values.slice().sort(function (a, b) { return a - b; });
    const middle = Math.floor(sorted.length / 2);
    return Math.round(sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2);
  }
  function md5ASCII(input) {
    // RFC 1321, little-endian MD5 for the ASCII-only public protocol strings below.
    const words = Array(Math.ceil((input.length + 9) / 64) * 16).fill(0);
    for (let i = 0; i < input.length; i += 1) words[i >> 2] |= input.charCodeAt(i) << ((i % 4) * 8);
    words[input.length >> 2] |= 128 << ((input.length % 4) * 8);
    words[words.length - 2] = input.length * 8;
    const state = [1732584193, -271733879, -1732584194, 271733878];
    const shifts = [[7, 12, 17, 22], [5, 9, 14, 20], [4, 11, 16, 23], [6, 10, 15, 21]];
    for (let offset = 0; offset < words.length; offset += 16) {
      let a = state[0], b = state[1], c = state[2], d = state[3];
      for (let i = 0; i < 64; i += 1) {
        const round = Math.floor(i / 16);
        const f = round === 0 ? (b & c) | (~b & d) : round === 1 ? (d & b) | (~d & c) : round === 2 ? b ^ c ^ d : c ^ (b | ~d);
        const index = round === 0 ? i : round === 1 ? (5 * i + 1) % 16 : round === 2 ? (3 * i + 5) % 16 : (7 * i) % 16;
        const value = (a + f + (Math.floor(Math.abs(Math.sin(i + 1)) * 4294967296) | 0) + words[offset + index]) | 0;
        const shift = shifts[round][i % 4];
        a = d; d = c; c = b; b = (b + ((value << shift) | (value >>> (32 - shift)))) | 0;
      }
      [a, b, c, d].forEach(function (v, i) { state[i] = (state[i] + v) | 0; });
    }
    return state.map(function (v) {
      return [0, 8, 16, 24].map(function (shift) { return ("0" + ((v >>> shift) & 255).toString(16)).slice(-2); }).join("");
    }).join("");
  }
  function cnServer(record, target, source) {
    if (!record || !/^(广东|广东省)$/.test(record.pname || "") || !/^(广州|广州市)$/.test(record.city || "") ||
      record.hostname !== target.name || !/^\d{1,9}$/.test(String(record.hostid || "")) || !/^(65499|9443)$/.test(String(record.port || ""))) return null;
    const ip = String(record.hostip || "");
    if (ip.indexOf(":") >= 0 || !validIP(ip) || privateAddress(ip)) return null;
    return { id: String(record.hostid), name: target.name, source: source, base: "http://" + ip + ":" + record.port,
      record: { hostid: String(record.hostid), pname: "广东", city: "广州", hostname: target.name, hostip: ip, port: String(record.port) } };
  }
  function cnPool(server, target) {
    const pool = server ? [server] : [];
    const fallback = cnServer(target.fallback, target, "全球网测目录快照 · 2026-10-17");
    if (fallback && !pool.some(function (s) { return s.base === fallback.base; })) pool.push(fallback);
    return pool;
  }
  async function guangzhouServers(context) {
    const key = "VB_HEALTH_GZ_CN_TARGETS_V1";
    try {
      const cache = json($persistentStore.read(key) || "");
      if (cache && cache.version === 1 && typeof cache.updatedAt === "number" && cache.updatedAt <= Date.now() && Date.now() - cache.updatedAt < 1800000 &&
        Array.isArray(cache.records) && cache.records.length === 3) {
        const servers = TARGETS.map(function (t, i) { return cnServer(cache.records[i], t, "全球网测目录快照（30 分钟内）"); });
        if (servers.every(Boolean)) return { pools: servers.map(function (s, i) { return cnPool(s, TARGETS[i]); }), source: "广州测点：30 分钟内固定目录快照；本次仍需握手与响应头校验。" };
      }
    } catch (_) { /* Re-discover invalid or expired public metadata. */ }
    const directories = await Promise.all(TARGETS.map(async function (target) {
      const response = await request(context, CN_DIRECTORY + encodeURIComponent(target.carrier), { timeout: 6, headers: { Accept: "application/json" } });
      const issue = problem(response);
      const records = !issue && response.body.length <= 100000 ? json(response.body) : null;
      const matches = Array.isArray(records) ? records.slice(0, 100).map(function (r) { return cnServer(r, target, "全球网测当前目录"); }).filter(Boolean) : [];
      matches.sort(function (a, b) { return Number(a.id) - Number(b.id); });
      return { server: matches[0] || null, details: evidence(target.name + "目录", response, issue ||
        (Array.isArray(records) ? "返回 " + records.length + " 条 · 合格广州测点 " + matches.length : "目录格式不符")) };
    }));
    if (directories.every(function (d) { return d.server; })) {
      try { $persistentStore.write(JSON.stringify({ version: 1, updatedAt: Date.now(), records: directories.map(function (d) { return d.server.record; }) }), key); } catch (_) { /* Cache is optional. */ }
    }
    return { source: directories.map(function (d) { return d.details; }).join("\n"),
      pools: TARGETS.map(function (t, i) { return cnPool(directories[i].server, t); }) };
  }
  function latencyFailure(samples) {
    if (!samples.length) return "采样未完成";
    if (samples.every(function (s) { return s.error === "超时"; })) return "检测超时";
    if (samples.some(function (s) { return s.status === 403 || s.status === 429; })) return "测点拒绝";
    const errors = ["DNS 解析失败", "TLS/证书失败", "连接被拒绝", "连接失败"];
    for (let i = 0; i < errors.length; i += 1) if (samples.every(function (s) { return s.error === errors[i]; })) return errors[i];
    return "测点响应异常";
  }
  function cnFailure(samples) {
    if (!samples.length) return "采样未完成";
    const kinds = samples.map(function (s) { return s.errorKind; }).filter(Boolean);
    const phases = samples.map(function (s) { return s.phase; }).filter(Boolean).filter(function (v, i, a) { return a.indexOf(v) === i; });
    const codes = samples.map(function (s) { return s.errorCode; }).filter(Boolean).filter(function (v, i, a) { return a.indexOf(v) === i; });
    const reason = kinds.length === samples.length && kinds[0] !== "超时" && kinds.every(function (k) { return k === kinds[0]; }) ? kinds[0] : latencyFailure(samples);
    return (phases.length === 1 ? phases[0] + " · " : "") + reason +
      (codes.length === 1 ? "（" + (codes[0].indexOf("#") >= 0 ? "错误 " + codes[0].split("#")[1] : codes[0]) + "）" : "");
  }
  async function cnSetupRequest(context, url, options, connection) {
    function opts() { return Object.assign({}, options, { headers: Object.assign({}, options.headers || {},
      { "Accept-Encoding": "identity" }, connection.close ? { Connection: "close" } : {}) }); }
    const first = await request(context, url, opts());
    if (completed || connection.close || !first.error || ["连接失败", "连接被关闭"].indexOf(first.errorKind) < 0) return first;
    // Only initialization may retry. Formal samples never hide or merge a failed request.
    connection.close = true;
    const second = await request(context, url, opts());
    second.compatibility = "初始化首次：" + (first.errorKind || first.error) + (first.errorCode ? " · " + first.errorCode : "") + "；Connection: close 重试";
    return second;
  }
  function validCNHead(sample) {
    return !sample.error && sample.status === 200 && /^1073741824$/.test(header(sample, "content-length"));
  }
  function cnEvidence(label, sample, valid) {
    return evidence(label, sample, [valid ? "校验通过" : sample.error ? sample.errorKind : "响应校验未通过", sample.errorCode, sample.compatibility].filter(Boolean).join(" · "));
  }
  function cnLatencyResult(name, target, samples, setup) {
    const replies = samples.filter(validCNHead);
    const details = setup.concat(["采用：ID " + target.id + " · " + target.base + "/speed/File(1G).dl（HEAD）",
      "逐次：" + samples.map(function (s, i) { return cnEvidence(String(i + 1), s, validCNHead(s)); }).join(" / ")]);
    if (!replies.length) return { line: name + "：" + cnFailure(samples), details: details.join("\n"), networkFailure: samples.length > 0 && samples.every(function (s) { return Boolean(s.error); }) };
    const values = replies.map(function (s) { return s.ms; }), changes = [];
    samples.forEach(function (s, i) { if (i && validCNHead(s) && validCNHead(samples[i - 1])) changes.push(Math.abs(s.ms - samples[i - 1].ms)); });
    const fluctuation = changes.length ? Math.round(changes.reduce(function (a, b) { return a + b; }, 0) / changes.length) + " ms" : "样本不足";
    details.push("中位数 " + median(values) + " ms · 有效 " + replies.length + "/" + CN_SAMPLES + " · 范围 " + Math.min.apply(null, values) + "–" + Math.max.apply(null, values) + " ms · HTTP 波动 " + fluctuation);
    return { line: name + "：" + median(values) + " ms" + (replies.length < CN_SAMPLES ? " · " + replies.length + "/" + CN_SAMPLES : ""), details: details.join("\n") };
  }
  async function latencyTarget(context, name, candidates, progress) {
    const setup = [name], failures = [];
    for (let n = 0; n < candidates.length && !completed; n += 1) {
      const target = candidates[n];
      const connection = { close: false };
      setup.push("ID " + target.id + " · " + target.base, "来源：" + target.source);
      // A fresh random protocol identifier, NOT the phone's IMEI. Session values stay in memory only.
      const imei = "TS" + md5ASCII(String(Date.now()) + "_" + Math.random()).slice(8, 24).toUpperCase();
      const seconds = String(Math.floor(Date.now() / 1000));
      const token = md5ASCII(md5ASCII("model=Android&imei=" + imei) + md5ASCII("stime=" + seconds + "&band=200&rand=12345555"));
      const query = "key=&flag=true&bandwidth=200&model=Android&imei=" + imei + "&time=" + seconds + "&app=globalspeed&pkg=com.cnspeedtest.globalspeed&token=" + token;
      const handshake = await cnSetupRequest(context, target.base + "/speed/dovalid?" + query, { timeout: 8, headers: { "User-Agent": CN_UA } }, connection);
      handshake.phase = "握手";
      const key = !handshake.error && handshake.status === 200 && /^1-[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(handshake.body.trim()) ? handshake.body.trim().slice(2) : "";
      setup.push(cnEvidence("会话握手", handshake, Boolean(key)));
      if (!key) { failures.push(handshake); continue; }
      async function sample(index, initialize) {
        // HEAD only: no file body is downloaded, including when a server rejects the request.
        const url = target.base + "/speed/File(1G).dl?r=" + Date.now() + "_" + index + "&key=" + key;
        const options = { method: "head", timeout: 8, headers: { "Cache-Control": "no-cache, no-store", "Accept-Encoding": "identity" } };
        if (connection.close) options.headers.Connection = "close";
        const response = initialize ? await cnSetupRequest(context, url, options, connection) : await request(context, url, options);
        response.phase = initialize ? "预检" : "采样";
        return response;
      }
      if (completed) break;
      const warmup = await sample("warmup", true);
      setup.push(cnEvidence(connection.close ? "预检（独立连接，不计入延迟）" : "预热（不计入延迟）", warmup, validCNHead(warmup)));
      if (!validCNHead(warmup)) { failures.push(warmup); continue; }
      const samples = [];
      for (let i = 0; i < CN_SAMPLES && !completed; i += 1) {
        samples.push(await sample(i));
        progress(cnLatencyResult(name, target, samples, setup));
      }
      return cnLatencyResult(name, target, samples, setup);
    }
    return { line: name + "：" + cnFailure(failures), details: setup.join("\n"), networkFailure: failures.length > 0 && failures.every(function (s) { return Boolean(s.error); }) };
  }
  async function latencyPanel(context) {
    const results = TARGETS.map(function (target) { return { line: target.name + "：检测超时", details: target.name + "：总时限内未完成，未生成数值。" }; });
    let source = "正在读取广州测点目录。";
    let connectivity = "";
    function render() {
      finish(results.map(function (r) { return r.line; }).concat(connectivity ? ["", connectivity] : []).join("\n"), "info",
        [preamble(context), source].concat(results.map(function (r) { return r.details; }), connectivity ? [connectivity] : [],
          ["当前目录优先，失败时尝试 2026-10-17 目录快照；只采用广东广州且运营商名称匹配的测点。", "全球网测会话握手后，只以 HEAD 校验文件响应头，未下载测速文件；预热不计入三次正式采样。", "HTTP 波动：相邻有效样本耗时差绝对值均值；不跨失败样本计算。", "测量包含手机到节点及站点响应；不是节点端逐跳回程、ICMP/TCP Ping 或线路等级判定。", "接口使用 HTTP，结果是连接诊断，不构成服务端身份的密码学证明。"]).join("\n"),
        { icon: "antenna.radiowaves.left.and.right", "icon-color": "#007AFF" }, "手机经节点到广州 · HTTP 往返");
    }
    deadlineResult = render;
    const directory = await guangzhouServers(context);
    source = directory.source;
    await Promise.all(TARGETS.map(async function (target, i) {
      results[i] = await latencyTarget(context, target.name, directory.pools[i], function (partial) { results[i] = partial; });
    }));
    if (!completed && results.every(function (r) { return r.networkFailure; })) {
      connectivity = "常规 HTTPS 对照：进行中";
      const control = await request(context, "https://www.cloudflare.com/cdn-cgi/trace", { timeout: 4 });
      connectivity = validIP(traceFields(control).ip) ? "常规 HTTPS 可达 · 广州测点连接未成功" :
        "常规 HTTPS 对照也未通过：" + (control.errorKind || problem(control) || "响应不符") + (control.errorCode ? " · " + control.errorCode : "");
    }
    render();
  }

  (async function () {
    try {
      const args = parseArgument(typeof $argument === "undefined" ? "" : $argument);
      mode = args.mode;
      setTimeout(function () {
        if (completed) return;
        if (deadlineResult) deadlineResult();
        else finish("本次检测超过总时限，请点击面板重试。\n未生成本次检测结论。", "alert");
      }, mode === "latency" ? 65000 : 25000);
      const context = await resolvePolicy(args.policy);
      detectedNode = clean(context.label);
      if (mode === "ip") await ipPanel(context);
      else if (mode === "unlock") await unlockPanel(context);
      else if (mode === "latency") await latencyPanel(context);
      else await pathPanel(context);
    } catch (error) { finish(clean(error.message || error), "alert"); }
  })();
})();


