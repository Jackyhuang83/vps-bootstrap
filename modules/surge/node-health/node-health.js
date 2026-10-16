/* SPDX-License-Identifier: MIT
 * VPS Bootstrap — Surge 节点体检 v0.1.0-beta.1
 * Runs locally in Surge. No MITM, policy mutations, credentials or uploads.
 */
(function () {
  "use strict";

  const VERSION = "0.1.0-beta.1";
  const TITLES = { ip: "IP 纯净度", unlock: "平台解锁初检", latency: "三网站点 HTTP 耗时" };
  const UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";
  const TARGETS = [
    { name: "电信", host: "www.189.cn", url: "https://www.189.cn/favicon.ico" },
    { name: "联通", host: "iservice.10010.com", url: "https://iservice.10010.com/favicon.ico" },
    { name: "移动", host: "www.10086.cn", url: "https://www.10086.cn/favicon.ico" }
  ];
  let completed = false;
  let mode = "ip";

  function finish(content, style) {
    if (completed) return;
    completed = true;
    $done({ title: TITLES[mode] || "节点体检", content: content, style: style || "info" });
  }

  function parseArgument(raw) {
    // Policy is last: node/group names may contain &, =, + or literal %.
    const match = String(raw || "").match(/^mode=(ip|unlock|latency)&showIP=(true|false)&policy=([\s\S]*)$/);
    if (!match) throw new Error("模块参数不完整，请重新安装模块。");
    const policy = match[3].trim();
    if (!policy || /[\r\n]/.test(policy) || /填写|\{\{\{/.test(policy)) {
      throw new Error("请在模块参数 POLICY 填写已有的节点或手动选择策略组名称。");
    }
    return { mode: match[1], showIP: match[2] === "true", policy: policy };
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
      return p.name === current && (!seen.length || seen.indexOf(p.group) !== -1);
    });
    if (policies.proxies.indexOf(current) !== -1) return { policy: current, label: current };
    if (external.length === 1 && external[0].identifier) return { policy: external[0].identifier, label: current };
    if (policies["policy-groups"].indexOf(current) !== -1) {
      throw new Error("请填写具体节点或手动选择组；自动测速、故障转移等组无法固定本次检测节点。");
    }
    throw new Error("找不到检测节点「" + current + "」，请核对 POLICY 参数与节点名称。");
  }

  function request(context, url, options) {
    const config = options || {};
    const seconds = config.timeout || 6;
    return new Promise(function (resolve) {
      const start = Date.now();
      let settled = false;
      function settle(error, response, data) {
        if (settled) return;
        settled = true;
        resolve({ error: error ? (/timed?\s*out|timeout|超时/i.test(String(error)) ? "超时" : "连接失败") : "",
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
  async function page(context, url) {
    // Follow at most two same-origin redirects, pinning the same node each time.
    // JSC does not guarantee the browser URL API, so restrict to simple paths.
    const origin = url.match(/^https:\/\/[^/]+/)[0];
    let current = url;
    for (let hop = 0; hop <= 2; hop += 1) {
      const response = await request(context, current, { timeout: 5 });
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
    const groups = ip.split(":").filter(Boolean);
    if (!groups.every(function (s) { return /^[0-9a-f]{1,4}$/i.test(s); })) return false;
    return compressed.length === 2 ? groups.length < 8 : groups.length === 8;
  }

  async function ipPanel(context, showIP) {
    const response = await request(context, "https://my.ippure.com/v1/info");
    const issue = problem(response);
    if (issue) return finish(preamble(context) + "\nIPPure：" + issue + "\n风险分未知；点击面板重新检测。", "alert");
    const data = json(response.body);
    if (!data || !validIP(data.ip)) return finish(preamble(context) + "\nIPPure 返回格式未知；未生成纯净度分数。", "alert");
    const ipv6 = data.ip.indexOf(":") !== -1;
    const rawScore = data.fraudScore;
    const score = !ipv6 && typeof rawScore === "number" && Number.isFinite(rawScore) && rawScore >= 0 && rawScore <= 100 ? rawScore : null;
    const risk = score === null ? "未知" : score <= 25 ? "低" : score <= 50 ? "轻度" : score <= 70 ? "中度" : "高";
    const types = [];
    if (data.isResidential === true) types.push("住宅");
    if (data.isDataCenter === true) types.push("机房");
    if (typeof data.isBroadcast === "boolean") types.push(data.isBroadcast ? "广播" : "非广播");
    const location = [data.country || country(data.countryCode), data.region, data.city].filter(Boolean).map(clean).filter(function (v, i, a) { return a.indexOf(v) === i; }).join(" · ");
    const lines = [preamble(context), "出口：" + masked(data.ip, showIP) + (ipv6 ? "（IPv6）" : "（IPv4）"), location || "地区未知",
      score === null ? "纯净度：未知" + (ipv6 ? "（IPPure 不评估 IPv6）" : "（无有效风险分）") : "纯净度参考：" + (100 - score) + "/100 · 风险" + risk,
      "IPPure 风险分：" + (score === null ? "未知" : score + "/100（越低越好）"),
      "类型：" + (types.join(" · ") || "未知"),
      "ASN：" + clean(data.asn || "未知") + " · " + clean(data.asOrganization || "未知"),
      "来源 IPPure · " + time() + "\n第三方评分，仅供参考"];
    finish(lines.join("\n"), score === null || score > 50 ? "alert" : "info");
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
    const results = await Promise.all(["81280792", "80018499"].map(function (id) { return page(context, "https://www.netflix.com/title/" + id); }));
    if (netflixSample(results[0], "81280792")) return "Netflix：授权片样本可见" + suffix(netflixRegion(results[0]));
    if (results[0].status === 404 && netflixSample(results[1], "80018499")) return "Netflix：仅自制片样本可见" + suffix(netflixRegion(results[1]));
    const regionBlock = results.some(function (r) { return /Netflix is not available in your country|not yet available in your (?:country|region)/i.test(r.body); });
    if (regionBlock) return "Netflix：地区受限";
    return "Netflix：" + (problem(results[0]) || "未取得有效片库证据");
  }

  async function disney(context) {
    // Published browser application identifier, not a subscriber credential.
    const client = "ZGlzbmV5JmJyb3dzZXImMS4wLjA.Cu56AgSfBTDag5NiRA81oLHkDZfu5L3CKadnefEAY84";
    const response = await request(context, "https://disney.api.edge.bamgrid.com/graph/v1/device/graphql", {
      method: "post", headers: { Authorization: client, "Content-Type": "application/json" },
      body: JSON.stringify({ query: "mutation registerDevice($input: RegisterDeviceInput!) { registerDevice(registerDevice: $input) { grant { grantType assertion } } }",
        variables: { input: { applicationRuntime: "chrome", attributes: { browserName: "chrome", browserVersion: "131.0.0", manufacturer: "apple", model: null, operatingSystem: "macintosh", operatingSystemVersion: "10.15.7", osDeviceIds: [] }, deviceFamily: "browser", deviceLanguage: "en", deviceProfile: "macosx" } } }) });
    if (!response.error && !challenge(response.body) && /forbidden-location|unsupported-location/i.test(response.body)) return "Disney+：地区受限";
    const issue = problem(response);
    if (issue) return "Disney+：" + issue;
    const data = json(response.body);
    const session = data && data.extensions && data.extensions.sdk && data.extensions.sdk.session;
    if (!data || (Array.isArray(data.errors) && data.errors.length) || !session) return "Disney+：接口格式变化，未知";
    const region = country(session.location && session.location.countryCode);
    if (session.inSupportedLocation === true) return "Disney+：地区检查通过" + suffix(region);
    if (session.inSupportedLocation === false) return "Disney+：地区不支持" + suffix(region);
    return "Disney+：地区状态未知";
  }

  async function youtube(context) {
    const response = await page(context, "https://www.youtube.com/premium");
    const issue = problem(response);
    if (issue) return "YouTube Premium：" + issue;
    const body = response.body;
    const match = body.match(/"INNERTUBE_CONTEXT_GL"\s*:\s*"([A-Z]{2})"/) || body.match(/"countryCode"\s*:\s*"([A-Z]{2})"/);
    const region = match ? country(match[1]) : "";
    if (/Premium is not available in your country/i.test(body)) return "YouTube Premium：地区不支持" + suffix(region);
    if (region && /ad-free|YouTube Premium/i.test(body) && /ytInitialData|ytcfg\.set/.test(body)) return "YouTube Premium：页面地区检查通过" + suffix(region);
    return "YouTube Premium：页面证据不足，未知";
  }

  async function chatgpt(context) {
    const responses = await Promise.all([page(context, "https://chatgpt.com/"), request(context, "https://chatgpt.com/cdn-cgi/trace")]);
    const home = responses[0];
    let region = "";
    if (!problem(responses[1])) {
      const match = responses[1].body.match(/^loc=([A-Z]{2})$/m);
      region = match ? country(match[1]) : "";
    }
    if (!home.error && !challenge(home.body) && /unsupported_country|not available in your country|country, region, or territory not supported/i.test(home.body)) return "ChatGPT：地区受限" + suffix(region);
    const issue = problem(home);
    if (issue) return "ChatGPT：" + issue + suffix(region);
    if (/ChatGPT/.test(home.body) && /<html|<!doctype/i.test(home.body)) return "ChatGPT：网页可达，待验证对话" + suffix(region);
    return "ChatGPT：页面证据不足，未知";
  }

  async function gemini(context) {
    const response = await page(context, "https://gemini.google.com/");
    const issue = problem(response);
    if (issue) return "Gemini：" + issue;
    if (/Gemini (?:isn.t|is not|is currently not) (?:supported|available) in your country|not supported in your (?:country|region)/i.test(response.body)) return "Gemini：地区受限";
    if (/Gemini/.test(response.body) && /<html|<!doctype/i.test(response.body)) return "Gemini：网页可达，待登录验证";
    return "Gemini：页面证据不足，未知";
  }

  async function unlockPanel(context) {
    const results = await Promise.all([netflix, disney, youtube, chatgpt, gemini].map(async function (check) {
      try { return await check(context); } catch (_) { return "检测异常，待重试"; }
    }));
    finish([preamble(context)].concat(results, ["未登录初检；实际播放/对话待实测", "点击刷新 · " + time()]).join("\n"));
  }

  function median(values) {
    const sorted = values.slice().sort(function (a, b) { return a - b; });
    const middle = Math.floor(sorted.length / 2);
    return Math.round(sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2);
  }
  async function latencyTarget(context, target) {
    const samples = [];
    for (let i = 0; i < 3 && !completed; i += 1) {
      samples.push(await request(context, target.url + "?vb_probe=" + Date.now() + "_" + i,
        { method: "head", timeout: 4, headers: { "Cache-Control": "no-cache, no-store" } }));
    }
    const replies = samples.filter(function (s) { return !s.error && s.status >= 100 && s.status <= 599; });
    if (!replies.length) return target.name + "：无响应 0/3（" + (samples.some(function (s) { return s.error === "超时"; }) ? "超时" : "连接失败") + "）\n" + target.host;
    const values = replies.map(function (s) { return s.ms; });
    const codes = replies.map(function (s) { return s.status; }).filter(function (v, i, a) { return a.indexOf(v) === i; }).join("/");
    return target.name + "：" + median(values) + " ms · 响应 " + replies.length + "/3\n" + target.host + " · HTTP " + codes + "\n范围 " + Math.min.apply(null, values) + "–" + Math.max.apply(null, values) + " ms";
  }
  async function latencyPanel(context) {
    const results = await Promise.all(TARGETS.map(function (target) { return latencyTarget(context, target); }));
    finish([preamble(context), "手机 → 节点 → 三网站点"].concat(results,
      ["HTTP 含连接/站点响应；非 Ping", "站点可能使用 CDN · " + time()]).join("\n"));
  }

  (async function () {
    try {
      const args = parseArgument(typeof $argument === "undefined" ? "" : $argument);
      mode = args.mode;
      setTimeout(function () { finish("本次检测超过总时限，请点击面板重试。\n未生成本次检测结论。", "alert"); }, 20000);
      const context = await resolvePolicy(args.policy);
      if (mode === "ip") await ipPanel(context, args.showIP);
      else if (mode === "unlock") await unlockPanel(context);
      else await latencyPanel(context);
    } catch (error) { finish(clean(error.message || error) + "\nv" + VERSION, "alert"); }
  })();
})();
