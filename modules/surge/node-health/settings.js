/* SPDX-License-Identifier: MIT
 * Surge 节点体检 v0.1.0-beta.3 — local-only group picker.
 * The request is answered by Surge; no socket, remote API or credentials.
 */
(function () {
  "use strict";
  const ORIGIN = "http://surge-node-health.invalid";
  const KEY = "VB_HEALTH_SELECTED_GROUP_V1";
  let completed = false;

  function respond(status, body, html) {
    if (completed) return;
    completed = true;
    $done({ response: { status: status, headers: {
      "Content-Type": html ? "text/html; charset=utf-8" : "application/json; charset=utf-8",
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

  try {
    const match = String($request.url || "").match(/^http:\/\/surge-node-health\.invalid(?::80)?(\/[^#]*)?(?:#.*)?$/i);
    if (!match) { completed = true; $done({ abort: true }); return; }
    const path = (match[1] || "/").split("?")[0];
    const method = String($request.method || "GET").toUpperCase();
    if (method === "GET" && path === "/") { respond(200, pageHTML(), true); return; }
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
      if (typeof $persistentStore === "undefined" || !$persistentStore.write(JSON.stringify({ version: 1, group: input.group }), KEY)) {
        respond(500, { error: "未能保存选择，请重试。" }); return;
      }
      respond(200, { saved: true, group: input.group });
      return;
    }
    respond(method === "GET" ? 404 : 405, { error: "此页面不支持该操作。" });
  } catch (_) { respond(500, { error: "本地设置暂不可用，请确认 Surge 版本和脚本功能。" }); }

  // Never insert group/node names as HTML: all dynamic labels use textContent.
  function pageHTML() {
    return `<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><title>选择检测策略组</title>
<style>
:root{color-scheme:light dark;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#f4f6fa;color:#17243d}body{margin:0}main{max-width:560px;margin:auto;padding:38px 20px 48px}header small{color:#60718a;font-size:13px}h1{font-size:27px;letter-spacing:-.6px;margin:12px 0}p{line-height:1.65;color:#5d6a7e}.list{display:grid;gap:10px;margin:22px 0}button.group{display:block;text-align:left;appearance:none;border:1px solid #dce2ec;background:white;color:#17243d;border-radius:15px;padding:17px 18px;width:100%;cursor:pointer}button.group strong{display:block;font-size:17px;overflow-wrap:anywhere}button.group small{display:block;font-size:13px;color:#60718a;margin-top:7px;overflow-wrap:anywhere}button.group.selected{border:2px solid #2870ed;background:#f0f5ff;padding:16px 17px}button:disabled{opacity:.55}#status{border-radius:12px;padding:13px 15px;background:#e8eef9;color:#24466f;overflow-wrap:anywhere}#status.error{background:#fff0ee;color:#973a2c}#retry{border:0;color:#2563d6;background:transparent;padding:12px 0;font-size:15px;cursor:pointer}footer{color:#778399;font-size:12px;line-height:1.7;margin-top:24px}@media(prefers-color-scheme:dark){:root{background:#111824;color:#f1f4fa}p{color:#adb9ce}button.group{background:#1c2739;color:#f1f4fa;border-color:#334058}button.group.selected{background:#172d50;border-color:#6b9fff}button.group small,header small{color:#b0bfd5}#status{background:#1d304a;color:#cbdefa}#status.error{background:#482927;color:#ffcdc8}#retry{color:#8bb6ff}}
</style></head><body><main><header><small>节点体检 · 本地设置</small><h1>选择检测策略组</h1><p>点选你平时用来切换节点的那一组。保存一次，以后在 Surge 中选哪个节点，就检测哪个节点。</p></header><div id="status" role="status" aria-live="polite">正在读取 Surge 策略组…</div><div id="groups" class="list"></div><button id="retry" type="button">重新加载列表</button><footer>选择后，返回 Surge，选好节点并点击检测面板刷新。<br>此页面在本机运行，仅保存检测组选择。v0.1.0-beta.3</footer></main>
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
