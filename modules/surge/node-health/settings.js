/* SPDX-License-Identifier: MIT
 * Surge 节点体检 v1.0.0 — local-only group picker.
 * The request is answered by Surge; no socket, remote API or credentials.
 */
(function () {
  "use strict";
  const ORIGIN = "http://surge-node-health.invalid";
  const COPY_URL = "http://192.0.2.1/copy";
  const KEY = "VB_HEALTH_SELECTED_GROUP_V1";
  const REPORT_VIEW_KEY = "VB_HEALTH_REPORT_VIEW_V1";
  let completed = false;

  function respond(status, body, html) {
    if (completed) return;
    completed = true;
    $done({ response: { status: status, headers: {
      "Content-Type": html === "text" ? "text/plain; charset=utf-8" : html ? "text/html; charset=utf-8" : "application/json; charset=utf-8",
      "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "X-Frame-Options": "DENY",
      "Content-Security-Policy": "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      "Referrer-Policy": "no-referrer"
    }, body: html ? body : JSON.stringify(body) } });
  }
  function header(name) {
    const headers = $request.headers || {};
    const key = Object.keys(headers).find(function (k) { return k.toLowerCase() === name.toLowerCase(); });
    return key ? String(headers[key]) : "";
  }
  function details() {
    if (typeof $surge === "undefined" || typeof $surge.selectGroupDetails !== "function") throw new Error("当前 Surge 无法读取策略组，请更新 Surge 后重试。");
    const value = $surge.selectGroupDetails();
    if (!value || !value.groups || typeof value.groups !== "object" || !value.decisions || typeof value.decisions !== "object") throw new Error("无法读取策略组，请更新 Surge 后重试。");
    return value;
  }
  function groupList(value) {
    return Object.keys(value.groups).filter(function (name) {
      return Array.isArray(value.groups[name]) && value.groups[name].length > 0 &&
        Object.prototype.hasOwnProperty.call(value.decisions, name) && typeof value.decisions[name] === "string";
    }).map(function (name) { return { name: name, selected: value.decisions[name] }; });
  }
  function saved() {
    try {
      const value = JSON.parse($persistentStore.read(KEY) || "null");
      return value && value.version === 1 && typeof value.group === "string" ? value.group : "";
    } catch (_) { return ""; }
  }
  function saveGroup(group) {
    if (typeof $persistentStore === "undefined" || !$persistentStore.write(JSON.stringify({ version: 1, group: group }), KEY)) {
      throw new Error("未能保存选择，请重试。");
    }
  }
  function label(value) { return String(value || "").replace(/[\r\n\t]+/g, " "); }

  function reports() {
    return ["ip", "unlock", "latency", "path"].map(function (mode) {
      try {
        const value = JSON.parse($persistentStore.read("VB_HEALTH_REPORT_V1_" + mode) || "null");
        return value && value.version === 1 && value.mode === mode && typeof value.details === "string" && value.details.length <= 24000 &&
          typeof value.updatedAt === "number" && Number.isFinite(value.updatedAt) && value.updatedAt > 0 && typeof value.title === "string" && value.title.length <= 60 && typeof value.build === "string" && value.build.length <= 80 ?
          { mode: mode, title: value.title, build: value.build, updatedAt: value.updatedAt, details: value.details } : null;
      } catch (_) { return null; }
    }).filter(Boolean);
  }

  function latestReport() { return reports().sort(function (a, b) { return b.updatedAt - a.updatedAt; })[0]; }
  function stamp(updatedAt) {
    const date = new Date(updatedAt);
    function pad(n) { return String(n).padStart(2, "0"); }
    return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate()) + " " +
      pad(date.getHours()) + ":" + pad(date.getMinutes()) + ":" + pad(date.getSeconds());
  }
  function exportText(report) {
    return report ? label(report.title) + "\n" + stamp(report.updatedAt) + " · v" + label(report.build) + "\n\n" + report.details : "暂无检测记录，请先在 Surge 刷新要查看的检测面板。";
  }
  function escaped(value) {
    return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
  }

  function nativeReport() {
    const report = latestReport();
    completed = true;
    if (!report) {
      $done({ title: "检测详情", content: "暂无检测记录\n先刷新任一检测面板，再点按这里读取。" });
      return;
    }
    // Pure local reader: no policy resolution, HTTP API, browser or new probes.
    const points = Array.from(report.details);
    const pages = [];
    for (let start = 0; start < points.length; start += 700) pages.push(points.slice(start, start + 700).join(""));
    if (!pages.length) pages.push("此记录没有详细内容。");
    let page = -1;
    let cursorSaved = true;
    try {
      const view = JSON.parse($persistentStore.read(REPORT_VIEW_KEY) || "null");
      if (view && view.version === 1 && view.mode === report.mode && view.updatedAt === report.updatedAt && view.build === report.build &&
        Number.isInteger(view.page) && view.page >= -1 && view.page < pages.length) page = view.page;
    } catch (_) { /* An invalid cursor always starts at the summary. */ }
    if (typeof $trigger !== "undefined" && $trigger === "button") {
      page = page + 1 < pages.length ? page + 1 : -1;
      try { cursorSaved = $persistentStore.write(JSON.stringify({ version: 1, mode: report.mode, updatedAt: report.updatedAt, build: report.build, page: page }), REPORT_VIEW_KEY) === true; }
      catch (_) { cursorSaved = false; /* A failed cursor write must not hide the report. */ }
    }
    $done({ title: page < 0 ? "检测详情" : "检测详情 · " + label(report.title), content: page < 0 ?
      "最近检测：" + label(report.title) + "\n" + stamp(report.updatedAt) + " · v" + label(report.build) + "\n点按查看详情 · 仅读取本机记录\n复制全文：" + COPY_URL :
      stamp(report.updatedAt) + " · v" + label(report.build) + "\n第 " + (page + 1) + "/" + pages.length + " 页 · " +
      (!cursorSaved ? "翻页位置未保存，请重试" : page + 1 < pages.length ? "点按下一页" : "再次点按收起") + "\n复制全文：" + COPY_URL + "\n\n" + pages[page] });
  }

  if (typeof $request === "undefined" && typeof $argument !== "undefined" && $argument === "mode=reports") {
    nativeReport();
    return;
  }

  if (typeof $request === "undefined") {
    let group = saved();
    let message = "";
    let style = "info";
    try {
      const groups = groupList(details());
      if (!groups.length) throw new Error("未找到手动选择组，请先在 Surge 中确认策略组。");
      let index = groups.findIndex(function (g) { return g.name === group; });
      // Only an explicit panel tap changes the local detection binding.
      // View entry, editor evaluation and API/intent runs are read-only.
      if (typeof $trigger !== "undefined" && $trigger === "button") {
        const next = (index + 1) % groups.length;
        if (group !== groups[next].name) saveGroup(groups[next].name);
        group = groups[next].name;
        index = next;
      }
      if (index >= 0) {
        message = "当前节点：" + label(groups[index].selected) + "\n" +
          (groups.length > 1 ? "点按切组 · " + (index + 1) + "/" + groups.length : "仅有 1 个手动组") + " · v1.0.0";
      } else {
        if (group) { message = "原检测组已不存在。\n"; style = "alert"; }
        message += "点按选择：" + label(groups[0].name) + "\n共 " + groups.length + " 组 · v1.0.0";
      }
    } catch (error) {
      message = error.message || "无法读取策略组，请更新 Surge 后重试。";
      style = "alert";
    }
    completed = true;
    const result = { title: "检测设置", content: (group ? "策略组：" + label(group) : "尚未选择检测策略组") + "\n" + message + "\n网页选组（可选）：" + ORIGIN + "/" };
    if (style === "alert") result.style = style;
    $done(result);
    return;
  }

  try {
    const match = String($request.url || "").match(/^http:\/\/(surge-node-health\.invalid|192\.0\.2\.1)(?::80)?(\/[^#]*)?(?:#.*)?$/i);
    if (!match) { completed = true; $done({ abort: true }); return; }
    const path = (match[2] || "/").split("?")[0];
    const method = String($request.method || "GET").toUpperCase();
    // The literal-IP fallback is strictly read-only; it never exposes group writes.
    if (match[1] === "192.0.2.1" && (method !== "GET" || ["/", "/copy", "/reports", "/reports.txt", "/api/reports"].indexOf(path) < 0)) {
      respond(method === "GET" ? 404 : 405, { error: "此入口仅供读取和复制检测记录。" }); return;
    }
    if (method === "GET" && (path === "/copy" || match[1] === "192.0.2.1" && path === "/")) { respond(200, copyHTML(), true); return; }
    if (method === "GET" && path === "/reports.txt") { respond(200, exportText(latestReport()), "text"); return; }
    if (method === "GET" && path === "/") { respond(200, pageHTML(), true); return; }
    if (method === "GET" && path === "/reports") { respond(200, reportHTML(), true); return; }
    if (method === "GET" && path === "/api/reports") {
      respond(200, { reports: reports() }); return;
    }
    if (method === "GET" && path === "/api/groups") {
      const groups = groupList(details());
      respond(200, { groups: groups, saved: saved() });
      return;
    }
    if (method === "POST" && path === "/api/select") {
      // Cross-origin forms cannot set this header; no CORS/preflight is allowed.
      if (header("origin") !== ORIGIN || header("x-vb-health-settings") !== "1" ||
        !/^application\/json(?:\s*;|$)/i.test(header("content-type"))) {
        respond(403, { error: "请从本地设置页面选择策略组。" }); return;
      }
      let input;
      try { input = JSON.parse($request.body || ""); } catch (_) { respond(400, { error: "选择无效，请重新加载列表。" }); return; }
      if (!input || typeof input.group !== "string" || !groupList(details()).some(function (g) { return g.name === input.group; })) {
        respond(400, { error: "该策略组已不存在，请重新加载列表。" }); return;
      }
      try { saveGroup(input.group); } catch (_) {
        respond(500, { error: "未能保存选择，请重试。" }); return;
      }
      respond(200, { saved: true, group: input.group });
      return;
    }
    respond(method === "GET" ? 404 : 405, { error: "此页面不支持该操作。" });
  } catch (_) { respond(500, { error: "本地设置暂不可用，请确认 Surge 版本和脚本功能。" }); }

  function copyHTML() {
    const report = latestReport();
    const text = exportText(report);
    return `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><title>复制检测详情</title>
<style>:root{color-scheme:light dark;font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#f4f6fa;color:#17243d}body{margin:0}main{max-width:680px;margin:auto;padding:28px 18px 40px}nav,.actions{display:flex;flex-wrap:wrap;gap:12px}nav{margin-bottom:26px}a{color:#2870ed;font-size:15px}h1{font-size:27px;letter-spacing:-.5px}p{color:#657386;line-height:1.7}textarea{display:block;box-sizing:border-box;width:100%;min-height:360px;resize:vertical;margin:18px 0;border:1px solid #d5dce7;border-radius:14px;background:white;color:#17243d;padding:16px;font:15px/1.7 -apple-system,BlinkMacSystemFont,sans-serif;-webkit-user-select:text;user-select:text}button{appearance:none;border:0;border-radius:11px;padding:13px 18px;font:600 16px -apple-system,BlinkMacSystemFont,sans-serif;color:white;background:#2870ed}button.secondary{background:#e5ecf7;color:#24466f}button:disabled{opacity:.5}#copy-status{min-height:28px}small{color:#657386}@media(prefers-color-scheme:dark){:root{background:#111824;color:#f1f4fa}textarea{background:#1c2739;color:#f1f4fa;border-color:#334058}p,small{color:#adb9ce}button.secondary{background:#253c5c;color:#d6e7ff}}</style></head><body><main><nav><a href="/copy">刷新记录</a><a href="/reports.txt">纯文本</a><a href="/reports">全部记录</a></nav><small>节点体检 · 仅本机</small><h1>复制检测详情</h1><p>显示最近一次检测的完整记录。要排查广州三网，请先刷新该检测，再打开或刷新此页。</p><div class="actions"><button type="button" id="copy-report"${report ? "" : " disabled"}>复制全文</button><button type="button" class="secondary" id="select-report"${report ? "" : " disabled"}>选中全文</button></div><p id="copy-status" role="status" aria-live="polite">若浏览器未允许复制，可点「选中全文」后长按复制。</p><textarea id="report-text" readonly aria-label="完整检测记录" spellcheck="false">${escaped(text)}</textarea><p>IP 已打码。复制与选中文本都在本机完成。</p></main><script>
"use strict";
var area=document.getElementById("report-text"),copyButton=document.getElementById("copy-report"),selectButton=document.getElementById("select-report"),statusBox=document.getElementById("copy-status");
function selectText(){area.focus();area.select();area.setSelectionRange(0,area.value.length);}
function fallbackCopy(){selectText();var copied=false;try{copied=typeof document.execCommand==="function"&&document.execCommand("copy")===true;}catch(error){}statusBox.textContent=copied?"已复制全文，可以返回聊天粘贴。":"未能自动复制，已选中全文，请在文本框内长按复制。";}
copyButton.addEventListener("click",function(){if(copyButton.disabled)return;selectText();if(typeof navigator!=="undefined"&&typeof window!=="undefined"&&window.isSecureContext&&navigator.clipboard&&typeof navigator.clipboard.writeText==="function"){try{navigator.clipboard.writeText(area.value).then(function(){statusBox.textContent="已复制全文，可以返回聊天粘贴。";},fallbackCopy);}catch(error){fallbackCopy();}}else{fallbackCopy();}});
selectButton.addEventListener("click",function(){if(selectButton.disabled)return;selectText();statusBox.textContent="已选中全文，请在文本框内长按复制。";});
</script></body></html>`;
  }

  // Never insert group/node names as HTML: dynamic labels use textContent or escaped textarea text.
  function reportHTML() {
    return `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>节点检测详情</title>
<style>:root{color-scheme:light dark;font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#f4f6fa;color:#17243d}main{max-width:680px;margin:auto;padding:26px 16px}nav{display:flex;gap:20px;margin-bottom:26px}a{color:#2870ed}h1{font-size:26px}p,small{color:#697689;line-height:1.7}article{padding:18px;border-radius:14px;background:white;margin:18px 0}h2{font-size:19px;margin:0 0 8px}pre{white-space:pre-wrap;overflow-wrap:anywhere;font:14px/1.8 -apple-system,BlinkMacSystemFont,sans-serif;margin:14px 0 0}button{border:0;border-radius:10px;padding:10px 16px;color:white;background:#2870ed;font-size:15px}@media(prefers-color-scheme:dark){:root{background:#111824;color:#f1f4fa}article{background:#1c2739}p,small{color:#adb9ce}}</style></head><body><main><nav><a href="/">返回首页</a><a href="/copy">复制最新记录</a></nav><h1>节点检测详情</h1><p>各项保留最近一次检测。先核对节点和时间；这里不会自动发起检测。</p><div id="reports" aria-live="polite"></div><button id="reload" type="button">刷新记录</button><p>详细记录仅保存在本机，IP 已打码。</p></main><script>
"use strict";var box=document.getElementById("reports"),reload=document.getElementById("reload");async function load(){reload.disabled=true;box.replaceChildren();try{var response=await fetch("/api/reports",{cache:"no-store"});if(!response.ok)throw new Error("读取失败，请重试");var value=await response.json();if(!Array.isArray(value.reports)||!value.reports.length){box.textContent="还没有检测记录，请返回 Surge 刷新检测面板。";return;}value.reports.forEach(function(report){var card=document.createElement("article"),title=document.createElement("h2"),time=document.createElement("small"),text=document.createElement("pre");title.textContent=report.title;time.textContent=new Date(report.updatedAt).toLocaleString("zh-CN")+" · v"+report.build;text.textContent=report.details;card.append(title,time,text);box.append(card);});}catch(error){box.textContent=error.message;}finally{reload.disabled=false;}}reload.addEventListener("click",load);load();
</script></body></html>`;
  }
  function pageHTML() {
    return `<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><title>选择检测策略组</title>
<style>
:root{color-scheme:light dark;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#f4f6fa;color:#17243d}body{margin:0}main{max-width:560px;margin:auto;padding:38px 20px 48px}header small{color:#60718a;font-size:13px}h1{font-size:27px;letter-spacing:-.6px;margin:12px 0}p{line-height:1.65;color:#5d6a7e}.list{display:grid;gap:10px;margin:22px 0}button.group{display:block;text-align:left;appearance:none;border:1px solid #dce2ec;background:white;color:#17243d;border-radius:15px;padding:17px 18px;width:100%;cursor:pointer}button.group strong{display:block;font-size:17px;overflow-wrap:anywhere}button.group small{display:block;font-size:13px;color:#60718a;margin-top:7px;overflow-wrap:anywhere}button.group.selected{border:2px solid #2870ed;background:#f0f5ff;padding:16px 17px}button:disabled{opacity:.55}#status{border-radius:12px;padding:13px 15px;background:#e8eef9;color:#24466f;overflow-wrap:anywhere}#status.error{background:#fff0ee;color:#973a2c}#retry{border:0;color:#2563d6;background:transparent;padding:12px 0;font-size:15px;cursor:pointer}footer{color:#778399;font-size:12px;line-height:1.7;margin-top:24px}@media(prefers-color-scheme:dark){:root{background:#111824;color:#f1f4fa}p{color:#adb9ce}button.group{background:#1c2739;color:#f1f4fa;border-color:#334058}button.group.selected{background:#172d50;border-color:#6b9fff}button.group small,header small{color:#b0bfd5}#status{background:#1d304a;color:#cbdefa}#status.error{background:#482927;color:#ffcdc8}#retry{color:#8bb6ff}}
</style></head><body><main><nav style="display:flex;gap:20px;margin-bottom:24px"><a href="/" style="color:#2870ed">选检测组</a><a href="/reports" style="color:#2870ed">检测详情</a></nav><header><small>节点体检 · 本地设置</small><h1>选择检测策略组</h1><p>点选你平时用来切换节点的那一组。保存一次，以后在 Surge 中选哪个节点，就检测哪个节点。</p></header><div id="status" role="status" aria-live="polite">正在读取 Surge 策略组…</div><div id="groups" class="list"></div><button id="retry" type="button">重新加载列表</button><footer>选择后，返回 Surge，选好节点并点击检测面板刷新。<br>详细检测记录可在上方「检测详情」查看。v1.0.0</footer></main>
<script>
"use strict";
var list=document.getElementById("groups"),statusBox=document.getElementById("status"),retry=document.getElementById("retry"),busy=false;
function message(value,error){statusBox.textContent=value;statusBox.className=error?"error":"";}
async function call(path,options){var response=await fetch(path,Object.assign({cache:"no-store"},options||{}));var value=await response.json();if(!response.ok)throw new Error(value.error||"操作失败，请重试。");return value;}
async function load(){if(busy)return;busy=true;retry.disabled=true;list.replaceChildren();message("正在读取 Surge 策略组…");try{var value=await call("/api/groups");if(!Array.isArray(value.groups)||!value.groups.length){message("未找到可用的手动选择组，请先在 Surge 中确认你的策略组。",true);return;}value.groups.forEach(function(group){var button=document.createElement("button"),name=document.createElement("strong"),node=document.createElement("small");button.type="button";button.className="group"+(value.saved===group.name?" selected":"");button.setAttribute("aria-pressed",String(value.saved===group.name));name.textContent=group.name;node.textContent="当前选中："+group.selected;button.append(name,node);button.addEventListener("click",function(){select(group.name);});list.append(button);});var found=value.groups.some(function(g){return g.name===value.saved;});message(found?"已绑定："+value.saved+"。可点选其他组进行更改。":value.saved?"原检测组已不存在，请重新点选一组。":"请点选下面的一组，点击即保存。");}catch(error){message(error.message,true);}finally{busy=false;retry.disabled=false;}}
async function select(group){if(busy)return;busy=true;retry.disabled=true;Array.from(list.children).forEach(function(b){b.disabled=true;});message("正在保存…");try{var value=await call("/api/select",{method:"POST",headers:{"Content-Type":"application/json","X-VB-Health-Settings":"1"},body:JSON.stringify({group:group})});Array.from(list.children).forEach(function(b){var active=b.firstElementChild.textContent===value.group;b.classList.toggle("selected",active);b.setAttribute("aria-pressed",String(active));});message("已绑定："+value.group+"。请返回 Surge，选好节点后刷新检测面板。");}catch(error){message(error.message,true);}finally{busy=false;retry.disabled=false;Array.from(list.children).forEach(function(b){b.disabled=false;});}}
retry.addEventListener("click",load);load();
</script></body></html>`;
  }
})();

