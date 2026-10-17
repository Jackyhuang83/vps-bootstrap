/* SPDX-License-Identifier: MIT
 * VPS Bootstrap — Surge 节点体检 v0.1.0-beta.11
 * Runs locally in Surge. No MITM, policy mutations, credentials or uploads.
 */
(function () {
  "use strict";

  const VERSION = "0.1.0-beta.11";
  const SETTINGS_URL = "http://surge-node-health.invalid/";
  const SETTINGS_KEY = "VB_HEALTH_SELECTED_GROUP_V1";
  const TITLES = { ip: "IP 纯净度", unlock: "平台解锁检测", latency: "广州三网延迟" };
  const REPORT_KEY = "VB_HEALTH_REPORT_V1_";
  const UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";
  const TARGETS = [
    { name: "广州电信", carrier: /China\s*Telecom|Telecom-GZ|电信/i, preferred: "27594" },
    { name: "广州联通", carrier: /Unicom|联通/i, preferred: "26678" },
    { name: "广州移动", carrier: /China\s*Mobile|GZ-CMCC|CMCC|移动/i, preferred: "6611" }
  ];
  const SERVER_DIRECTORY = "https://www.speedtest.net/api/js/servers?engine=js&limit=100&search=Guangzhou";
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
    const match = String(raw || "").match(/^mode=(ip|unlock|latency)(?:&showIP=(?:true|false))?(?:&policy=([\s\S]*))?$/);
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
      function settle(error, response, data) {
        if (settled) return;
        settled = true;
        resolve({ error: error ? networkError(error) : "",
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
      catch (error) { settle(error, null, ""); }
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
  function probeServer(record, target) {
    if (!record || !/^(Guangzhou|Guang Zhou|广州|广州市)$/i.test(String(record.name || "").trim()) ||
      !/^(China|CN|中国)$/i.test(String(record.country || record.cc || "")) || !/^\d{1,9}$/.test(String(record.id || ""))) return null;
    const lat = Number(record.lat), lon = Number(record.lon);
    if (!Number.isFinite(lat) || !Number.isFinite(lon) || lat < 22.4 || lat > 24 || lon < 112.8 || lon > 114.2) return null;
    const sponsor = String(record.sponsor || "");
    if (!target.carrier.test(sponsor) || TARGETS.filter(function (t) { return t.carrier.test(sponsor); }).length !== 1) return null;
    const address = String(record.url || "");
    const match = address.match(/^(https?):\/\/([a-z0-9.-]+)(?::(80|443|8080))?\//i);
    if (!match || /[\s\\@]/.test(address)) return null;
    const host = match[2].toLowerCase();
    if (/^[\d.]+$/.test(host)) {
      if (!validIP(host)) return null;
      const p = host.split(".").map(Number);
      if ([0, 10, 127].indexOf(p[0]) !== -1 || p[0] >= 224 || p[0] === 169 && p[1] === 254 || p[0] === 172 && p[1] >= 16 && p[1] <= 31 || p[0] === 192 && p[1] === 168 || p[0] === 100 && p[1] >= 64 && p[1] <= 127) return null;
    } else if (!/^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/i.test(host) || /\.(local|localhost|invalid|internal|test|example)$/i.test(host)) return null;
    const authority = host + (match[3] ? ":" + match[3] : "");
    if (record.host && String(record.host).toLowerCase() !== authority) return null;
    return { name: target.name, id: String(record.id), sponsor: clean(sponsor), host: authority,
      url: match[1].toLowerCase() + "://" + authority + "/speedtest/latency.txt",
      record: { id: String(record.id), name: "Guangzhou", country: "China", lat: lat, lon: lon, sponsor: clean(sponsor), host: authority,
        url: match[1].toLowerCase() + "://" + authority + "/speedtest/upload.php" } };
  }
  async function guangzhouServers(context) {
    const key = "VB_HEALTH_GZ_TARGETS_V1";
    try {
      const cache = json($persistentStore.read(key) || "");
      if (cache && cache.version === 1 && typeof cache.updatedAt === "number" && cache.updatedAt <= Date.now() && Date.now() - cache.updatedAt < 1800000 && Array.isArray(cache.records) && cache.records.length === 3) {
        const selected = TARGETS.map(function (t, i) { return probeServer(cache.records[i], t); });
        if (selected.every(Boolean)) return { servers: selected, source: "广州目录快照（30 分钟内固定测点，便于比较节点）" };
      }
    } catch (_) { /* Missing, stale or invalid cache requires a fresh directory. */ }
    const response = await request(context, SERVER_DIRECTORY, { headers: { Accept: "application/json", Referer: "https://www.speedtest.net/" } });
    const list = !problem(response) && json(response.body);
    const servers = TARGETS.map(function (target) {
      const matches = Array.isArray(list) ? list.map(function (record) { return probeServer(record, target); }).filter(Boolean) : [];
      matches.sort(function (a, b) { return (a.id === target.preferred ? -1 : b.id === target.preferred ? 1 : Number(a.id) - Number(b.id)); });
      return matches[0] || null;
    });
    if (servers.every(Boolean)) {
      try { $persistentStore.write(JSON.stringify({ version: 1, updatedAt: Date.now(), records: servers.map(function (s) { return s.record; }) }), key); } catch (_) { /* Still use the current validated directory. */ }
    }
    return { servers: servers, source: evidence("广州测速目录", response, Array.isArray(list) ? "仅采纳广州且运营商明确的记录" : problem(response) || "目录格式未知") };
  }
  async function latencyTarget(context, target) {
    const samples = [];
    for (let i = 0; i < 5 && !completed; i += 1) {
      samples.push(await request(context, target.url + "?vb_probe=" + Date.now() + "_" + i,
        { method: "get", timeout: 3, headers: { "Cache-Control": "no-cache, no-store" } }));
    }
    function validSample(s) { return !s.error && s.status === 200 && s.body.trim() === "test=test"; }
    const replies = samples.filter(validSample);
    const details = [target.name + " · ID " + target.id + " · " + target.host + " · " + target.sponsor,
      "逐次：" + samples.map(function (s) { return s.error || "HTTP " + s.status + " · " + s.ms + " ms" + (validSample(s) ? "" : "（测点响应异常）"); }).join(" / ")];
    if (!replies.length) {
      const reason = samples.every(function (s) { return s.error === "超时"; }) ? "检测超时" : samples.some(function (s) { return s.status === 403 || s.status === 429; }) ? "测点拒绝" : "测点不可用";
      return { line: target.name + "：" + reason, details: details.join("\n") };
    }
    const values = replies.map(function (s) { return s.ms; });
    const changes = [];
    samples.forEach(function (s, i) { if (i && validSample(s) && validSample(samples[i - 1])) changes.push(Math.abs(s.ms - samples[i - 1].ms)); });
    const fluctuation = changes.length ? Math.round(changes.reduce(function (a, b) { return a + b; }, 0) / changes.length) + " ms" : "样本不足";
    details.push("中位数 " + median(values) + " ms · 有效 " + replies.length + "/5 · 范围 " + Math.min.apply(null, values) + "–" + Math.max.apply(null, values) + " ms · HTTP 波动 " + fluctuation);
    return { line: target.name + "：" + median(values) + " ms" + (replies.length < 5 ? " · " + replies.length + "/5" : ""), details: details.join("\n") };
  }
  async function latencyPanel(context) {
    const directory = await guangzhouServers(context);
    const results = await Promise.all(TARGETS.map(function (target, i) { return directory.servers[i] ? latencyTarget(context, directory.servers[i]) :
      { line: target.name + "：暂无可用测点", details: target.name + "：目录未取得合格广州测点；未改用其他城市或全国网站。" }; }));
    finish(results.map(function (r) { return r.line; }).join("\n"), "info",
      [preamble(context), directory.source].concat(results.map(function (r) { return r.details; }),
        ["HTTP 波动：相邻有效样本耗时差绝对值均值；不跨失败样本计算。", "测量包含手机到节点及站点响应；不是节点端逐跳回程、ICMP 或线路等级判定。"]).join("\n"),
      { icon: "antenna.radiowaves.left.and.right", "icon-color": "#007AFF" }, "手机经节点到广州 · HTTP 往返");
  }

  (async function () {
    try {
      const args = parseArgument(typeof $argument === "undefined" ? "" : $argument);
      mode = args.mode;
      setTimeout(function () {
        if (completed) return;
        if (deadlineResult) deadlineResult();
        else finish("本次检测超过总时限，请点击面板重试。\n未生成本次检测结论。", "alert");
      }, 25000);
      const context = await resolvePolicy(args.policy);
      detectedNode = clean(context.label);
      if (mode === "ip") await ipPanel(context);
      else if (mode === "unlock") await unlockPanel(context);
      else await latencyPanel(context);
    } catch (error) { finish(clean(error.message || error), "alert"); }
  })();
})();

