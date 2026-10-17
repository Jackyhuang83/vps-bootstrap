// End-to-end Surge runtime contract tests. All responses are synthetic.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '..', 'node-health.js'), 'utf8');
const settingsSource = fs.readFileSync(path.join(__dirname, '..', 'settings.js'), 'utf8');
const SETTINGS_KEY = 'VB_HEALTH_SELECTED_GROUP_V1';
const gzDirectory = ['China Telecom', 'China Unicom', 'China Mobile'].map((sponsor,i)=>({id:['27594','26678','6611'][i],name:'Guangzhou',country:'China',lat:'23.1333',lon:'113.2667',sponsor,host:['ct.gzspeed.net:8080','cu.gzspeed.net:8080','cm.gzspeed.net:8080'][i],url:'http://'+['ct.gzspeed.net:8080','cu.gzspeed.net:8080','cm.gzspeed.net:8080'][i]+'/speedtest/upload.php'}));

function pathReply(config) {
  if(config.url.includes('/cdn-cgi/trace?vb_health_path=')) return {body:'ip='+(config.policy==='DIRECT'?'203.0.113.7':'203.0.113.9')+'\nloc=JP\ncolo=NRT'};
  const pathname=new URL(config.url).pathname;
  const ip=pathname==='/geoip'?(config.policy==='DIRECT'?'203.0.113.7':'203.0.113.9'):decodeURIComponent(pathname.slice('/geoip/'.length));
  return {body:JSON.stringify({ip,country:'Japan',country_code:'JP',city:'Tokyo',asn:64496,asn_organization:'Example ISP'})};
}

async function run(options = {}) {
  let clock = 0;
  let result;
  let doneCount = 0;
  let activeRequests = 0;
  let peakRequests = 0;
  let lateRequests = 0;
  let lateAPICalls = 0;
  let sequence = 0;
  const timers = [];
  const requests = [];
  const apiCalls = [];
  const storage = options.storage || {};
  const pathMode = options.mode==='path' || /^mode=path(?:&|$)/.test(options.argument||'');
  const schedule = (fn, delay = 0) => timers.push({ fn, at: clock + delay, id: ++sequence });
  class Clock extends Date { constructor(...args) { super(...(args.length ? args : [(options.epoch || 1792123200000) + clock])); } static now() { return (options.epoch || 1792123200000) + clock; } }
  const env = {
    Date: Clock,
    setTimeout: (fn, delay) => schedule(fn, delay === 25000 && options.deadlineMs ? options.deadlineMs : delay),
    $argument: options.argument || `mode=${options.mode || 'ip'}&showIP=false&policy=Group`,
    $done: value => { result = value; doneCount++; },
    $persistentStore: { read: key => Object.hasOwn(storage, key) ? storage[key] : null, write: (value,key) => { if(options.writeFail) return false; storage[key]=value; return true; } },
    $surge: { selectGroupDetails: () => ({ decisions: options.decisions || { Group: 'Tokyo' } }) },
    $utils: options.utilsMissing ? undefined : Object.fromEntries(['geoip','ipasn','ipaso'].map(name=>[name,ip=>{
      const value=typeof options.localGeo==='function'?options.localGeo(ip):options.localGeo||{};
      return value[name]||null;
    }])),
    $httpAPI: (method, url, body, callback) => {
      assert.equal(method, 'GET');
      if(doneCount) lateAPICalls++;
      apiCalls.push({method,url,body});
      if(url==='/v1/requests/recent') {
        if(options.recentHang) return;
        const recent=typeof options.recent==='function'?options.recent(requests):options.recent;
        const value=recent===undefined?{requests:requests.filter(r=>r.policy!=='DIRECT'&&/vb_health_path=.*_node$/.test(r.url)).map(r=>({URL:r.url,policyName:r.policy,remoteAddress:'198.51.100.42 (Proxy)'}))}:recent;
        schedule(()=>callback(value),1);return;
      }
      assert.equal(url, '/v1/policies');
      if (!options.apiHang) schedule(() => callback(options.policies || { proxies: ['Tokyo', 'Other'], 'policy-groups': ['Group'] }), 1);
    },
    $httpClient: Object.fromEntries(['get', 'post', 'head'].map(method => [method, (config, callback) => {
      const index = requests.length;
      if(doneCount) lateRequests++;
      activeRequests++;
      peakRequests = Math.max(peakRequests, activeRequests);
      assert.ok(peakRequests <= 20, 'must remain within the Surge concurrent request limit');
      requests.push({ method, ...config });
      const directory = /^https:\/\/www\.speedtest\.net\/api\/js\/(?:servers|config-sdk)\?/.test(config.url);
      const directoryKey = config.url.includes('config-sdk?') ? 'sdk' : config.url.includes('search=Guangzhou') ? 'en' : 'zh';
      const reply = directory ? (options.directoryReplies && Object.hasOwn(options.directoryReplies,directoryKey) ? options.directoryReplies[directoryKey] : options.directoryReply === undefined ? {body:JSON.stringify(gzDirectory)} : options.directoryReply) : options.reply ? options.reply(config, method, index) : pathMode ? pathReply(config) : config.url.includes('/speedtest/latency.txt') ? {body:'test=test'} : { body: JSON.stringify({ ip: '203.0.113.7', fraudScore: 25, countryCode: 'JP', asn: 64496, isResidential: false }) };
      if (reply === null) return;
      schedule(() => { activeRequests--; callback(reply.error || null, reply.noResponse ? null : { status: reply.status || 200, headers: reply.headers || {} }, reply.body || ''); }, reply.delay || 100);
    }]))
  };
  vm.runInNewContext(source, env, { timeout: 1000 });
  for (let i = 0; i < 300 && !result; i++) {
    await new Promise(resolve => setImmediate(resolve));
    if (result) break;
    timers.sort((a, b) => a.at - b.at || a.id - b.id);
    const next = timers.shift();
    assert.ok(next, 'script must finish or schedule a callback');
    clock = next.at;
    next.fn();
  }
  assert.ok(result, 'script must call $done');
  // Late callbacks/watchdogs must not produce a second panel result.
  for (const timer of timers) timer.fn();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(doneCount, 1);
  assert.equal(lateRequests, 0, 'a finished run must not start more network requests');
  assert.equal(lateAPICalls,0,'a finished run must not start more local API calls');
  requests.forEach(r => {
    if(r.policy==='DIRECT') {
      assert.ok(pathMode,'DIRECT is reserved for the new path panel');
      assert.match(r.url,/^https:\/\/(?:www\.cloudflare\.com\/cdn-cgi\/trace|api\.ip\.sb\/geoip)\?vb_health_path=[\w]+_direct$/);
    } else assert.equal(r.policy, options.expectedPolicy || 'Tokyo');
    assert.equal(r['auto-redirect'], false);
    assert.equal(r['auto-cookie'], false);
    assert.ok(r.timeout > 0 && r.timeout <= 6, 'timeouts use seconds');
    assert.equal(r.insecure, undefined);
  });
  // Probe assertions read the actual persisted diagnostics; compact UI is tested separately.
  const report=storage['VB_HEALTH_REPORT_V1_'+(options.mode||(options.argument||'').match(/^mode=(\w+)/)?.[1]||'ip')];
  result.diagnosticContent=report?JSON.parse(report).details:result.content;
  return { result, requests, clock, peakRequests, storage, apiCalls };
}

test('zero fraud score stays zero; missing classification is unknown, IP masked', async () => {
  const { result } = await run({ reply: () => ({ body: JSON.stringify({ ip: '203.0.113.7', fraudScore: 0 }) }) });
  assert.match(result.diagnosticContent, /100\/100/);
  assert.match(result.diagnosticContent, /类型：未知/);
  assert.match(result.diagnosticContent, /203\.0\.\*\.\*/);
  assert.doesNotMatch(result.diagnosticContent, /203\.0\.113\.7|原生属性：是|机房：是/);
  assert.match(result.diagnosticContent, /住宅：未知 · 机房：未知 · 原生属性：未验证/);
});

test('missing, null, strings and out-of-range scores never become perfect purity', async () => {
  for (const fraudScore of [undefined, null, '', '0', false, -1, 101]) {
    const { result } = await run({ reply: () => ({ body: JSON.stringify({ ip: '203.0.113.7', fraudScore }) }) });
    assert.match(result.diagnosticContent, /纯净度：未知/);
    assert.doesNotMatch(result.diagnosticContent, /100\/100/);
  }
});

test('IPv6 never receives IPPure score, even when the API sends one', async () => {
  const { result } = await run({ reply: () => ({ body: JSON.stringify({ ip: '2001:db8::1', fraudScore: 0 }) }) });
  assert.match(result.diagnosticContent, /不评估 IPv6/);
  assert.doesNotMatch(result.diagnosticContent, /100\/100/);
});

test('API HTML, rate limiting and absent response become actionable unknown', async () => {
  for (const reply of [{ body: '<html>error</html>' }, { status: 429 }, { error: 'network', noResponse: true }, null]) {
    const { result } = await run({ reply: () => reply });
    assert.equal(result.style, 'alert');
    assert.doesNotMatch(result.diagnosticContent, /100\/100/);
  }
});

test('unknown/missing/direct/reject and automatic group do not send public traffic', async () => {
  for (const policy of ['Missing', '填写节点', 'DIRECT', 'REJECT', 'Auto']) {
    const { result, requests } = await run({ argument: `mode=ip&showIP=false&policy=${policy}`, policies: { proxies: ['Tokyo'], 'policy-groups': ['Auto'] } });
    assert.equal(result.style, 'alert');
    assert.equal(requests.length, 0);
  }
});

test('nested manual group is pinned; names containing ampersands stay intact', async () => {
  const { requests } = await run({ argument: 'mode=ip&showIP=false&policy=A&B=50%+', decisions: { 'A&B=50%+': 'Nested', Nested: 'Tokyo' } });
  assert.equal(requests.length, 3);
});

test('cyclic group and API timeout stop without external requests', async () => {
  for (const options of [{ decisions: { Group: 'Nested', Nested: 'Group' } }, { apiHang: true }]) {
    const { result, requests } = await run(options);
    assert.equal(result.style, 'alert');
    assert.equal(requests.length, 0);
  }
});

test('external nodes use Surge identifiers, never their ambiguous display name', async () => {
  const { requests } = await run({ expectedPolicy: 'POLICY::opaque', policies: { proxies: [], 'policy-groups': ['Group'], 'external-policies': [{ name: 'Tokyo', group: 'Group', identifier: 'POLICY::opaque' }] } });
  assert.equal(requests.length, 3);
});

test('unlock: generic HTTP 200 cannot become full unlock, US region, or dialogue success', async () => {
  const { result } = await run({ mode: 'unlock', reply: () => ({ body: '<html>Welcome</html>' }) });
  assert.doesNotMatch(result.diagnosticContent, /完整解锁|US|检查通过|网页可达/);
  assert.match(result.diagnosticContent, /未取得有效片库证据/);
  assert.match(result.diagnosticContent, /接口格式变化/);
  assert.match(result.content, /^ChatGPT：待确认$/m);
  assert.doesNotMatch(result.content, /地区支持|完整支持|已解锁/);
});

test('unlock: exact Disney session boolean and catalogue markup give bounded conclusions', async () => {
  const { result } = await run({ mode: 'unlock', reply: c => {
    if (c.url.includes('bamgrid')) return { body: JSON.stringify({ extensions: { sdk: { session: { inSupportedLocation: true, location: { countryCode: 'JP' } } } } }) };
    if (c.url.includes('netflix')) return { body: '81280792 {"@type":"TVSeries","countryCode":"JP"}' };
    if (c.url.includes('youtube')) return { body: 'ytcfg.set({"INNERTUBE_CONTEXT_GL":"JP"}); YouTube Premium ad-free' };
    if (c.url.includes('trace')) return { body: 'loc=JP\nip=203.0.113.7' };
    return { body: '<html>ChatGPT Gemini</html>' };
  } });
  assert.match(result.diagnosticContent, /Disney\+：地区检查通过 · JP/);
  assert.match(result.diagnosticContent, /Netflix：授权片样本可见/);
  assert.match(result.diagnosticContent, /ChatGPT：网页可达，待验证对话 · JP/);
  assert.match(result.diagnosticContent, /Gemini：网页可达，待登录验证/);
  assert.match(result.content, /^Disney\+：地区支持 · 🇯🇵 JP$/m);
  assert.match(result.content, /^Netflix：授权样本可见 · 🇯🇵 JP$/m);
  assert.match(result.content, /^ChatGPT：网页可达 · 边缘 🇯🇵 JP$/m);
  assert.doesNotMatch(result.content, /完整支持|完整解锁/);
  assert.doesNotMatch(result.diagnosticContent, /完整解锁|203\.0\.113\.7/);
});

test('unlock: false or missing Disney flags cannot pass', async () => {
  for (const flag of [false, undefined, 'true']) {
    const { result } = await run({ mode: 'unlock', reply: c => c.url.includes('bamgrid') ? { body: JSON.stringify({ extensions: { sdk: { session: { inSupportedLocation: flag } } } }) } : { body: '<html></html>' } });
    assert.doesNotMatch(result.diagnosticContent, /Disney\+：地区检查通过/);
  }
});

test('challenge and timeout are not reported as a regional ban', async () => {
  for (const reply of [{ status: 403, body: '<title>Just a moment</title>cf-chl-' }, null]) {
    const { result } = await run({ mode: 'unlock', reply: () => reply });
    assert.doesNotMatch(result.diagnosticContent, /地区受限|地区不支持|检查通过/);
    assert.match(result.diagnosticContent, /人机验证|超时/);
  }
});

test('Guangzhou latency uses validated small replies and never counts denial pages as latency', async () => {
  const counts = {};
  const { result, requests } = await run({ mode: 'latency', reply: c => {
    const host = new URL(c.url).host;
    counts[host] = (counts[host] || 0) + 1;
    if (host === 'cu.gzspeed.net:8080' && counts[host] === 2) return null;
    return { status: /cm\.gzspeed|dpdfsd/.test(host) ? 412 : 200, body:'test=test', delay: counts[host] * 100 };
  } });
  assert.equal(requests.length, 15);
  assert.equal(requests.filter(r=>r.url.includes('/speedtest/latency.txt')).length,12);
  assert.ok(requests.every(r => r.method === 'get'));
  assert.match(result.content, /^广州电信：300 ms$/m);
  assert.match(result.diagnosticContent, /HTTP 412/);
  assert.match(result.content, /^广州联通：350 ms · 4\/5$/m);
  assert.match(result.diagnosticContent, /范围 100–500 ms · HTTP 波动 100 ms/);
  assert.match(result.diagnosticContent, /HTTP 412 · 100 ms（测点响应异常）/);
  assert.match(result.content, /^广州移动：测点不可用$/m);
  assert.match(result.diagnosticContent, /不是节点端逐跳回程/);
  assert.doesNotMatch(result.diagnosticContent, /丢包/);
});

test('all latency targets timing out finish within the declared script budget', async () => {
  const { result, clock, requests } = await run({ mode: 'latency', reply: () => null });
  assert.equal(requests.length, 7);
  assert.equal((result.content.match(/检测超时/g)||[]).length,3);
  assert.ok(clock < 25000);
});

test('same-origin page redirects retain the node; external redirects are not followed', async () => {
  const { result, requests } = await run({ mode: 'unlock', reply: c => {
    if (c.url === 'https://gemini.google.com/') return { status: 302, headers: { Location: '/app' } };
    if (c.url === 'https://gemini.google.com/app') return { body: '<html>Gemini</html>' };
    if (c.url.includes('netflix')) return { status: 302, headers: { Location: 'https://example.invalid/login' } };
    return { body: '<html></html>' };
  } });
  assert.match(result.diagnosticContent, /Gemini：网页可达/);
  assert.ok(requests.some(r => r.url === 'https://gemini.google.com/app'));
  assert.ok(requests.every(r => !r.url.includes('example.invalid')));
});

test('redirect loops and malformed IP responses are bounded', async () => {
  const { requests, clock } = await run({ mode: 'unlock', reply: c => ({ status: 302, headers: { Location: c.url } }) });
  // Two redirects per page, regardless of how many platforms are enabled.
  const perUrl = {};
  for (const r of requests) perUrl[r.url] = (perUrl[r.url] || 0) + 1;
  assert.ok(Object.values(perUrl).every(count => count <= 3));
  assert.ok(clock < 20000);
  for (const ip of ['::::', ':::1', ':1:2:3:4:5:6:7:8', '1:2:3:4:5:6:7:8:', 'xyz', '999.1.1.1', '2001:db8:12345::1']) {
    const { result } = await run({ reply: () => ({ body: JSON.stringify({ ip, fraudScore: 0 }) }) });
    assert.equal(result.style, 'alert');
    assert.doesNotMatch(result.diagnosticContent, /100\/100/);
  }
});

test('all nine platform labels appear with bounded unknown results for generic HTTP 200', async () => {
  const { result } = await run({ mode: 'unlock', reply: () => ({ body: '<html>Welcome</html>' }) });
  for (const platform of ['ChatGPT', 'Gemini', 'Claude', 'Google', 'Netflix', 'Disney+', 'YouTube Premium', 'myTV SUPER', 'TikTok']) {
    assert.ok(result.diagnosticContent.includes(platform + '：'), platform);
  }
  assert.doesNotMatch(result.diagnosticContent, /检查通过|搜索结果可达|网页地区 [A-Z]|完整解锁/);
  assert.match(result.content, /播放\/对话未测 · \d{2}:\d{2}:\d{2}$/);
});

test('Claude identifies the documented regional redirect without following external hosts', async () => {
  const { result, requests } = await run({ mode: 'unlock', reply: c => c.url.includes('claude.ai')
    ? { status: 302, headers: { Location: 'https://www.anthropic.com/app-unavailable-in-region' } }
    : { body: '<html></html>' } });
  assert.match(result.diagnosticContent, /Claude：地区受限/);
  assert.ok(requests.every(r => new URL(r.url).host !== 'www.anthropic.com'));
});

test('Claude login page is web reachability, never dialogue or API success', async () => {
  const { result } = await run({ mode: 'unlock', reply: c => ({ body: c.url.includes('claude.ai') ? '<html><title>Claude</title>Log in</html>' : '<html></html>' }) });
  assert.match(result.diagnosticContent, /Claude：网页可达，待验证对话/);
  assert.doesNotMatch(result.diagnosticContent, /Claude：.*解锁|Claude：.*对话成功/);
});

test('Google separates search results, CAPTCHA, JS shell and unknown region', async () => {
  const cases = [
    [{ body: '<html>Google<div id="search"><h3>result</h3></div><div id="fbar"><div class="uU7dJb">Japan</div></div></html>' }, /Google：搜索结果可达 · 页面地区 Japan/],
    [{ body: '<html>Google<div id="search"><h3>result</h3></div></html>' }, /Google：搜索结果可达 · 地区未知/],
    [{ body: '<html>Google Please enable JavaScript</html>' }, /Google：网页可达，搜索待验证 · 地区未知/],
    [{ status: 302, headers: { Location: 'https://ipv4.google.com/sorry/index' } }, /Google：需要验证码/],
    [{ body: '<html>Our systems have detected unusual traffic</html>' }, /Google：需要验证码/]
  ];
  for (const [reply, expected] of cases) {
    const { result, requests } = await run({ mode: 'unlock', reply: c => c.url.includes('www.google.com') ? reply : { body: '<html></html>' } });
    assert.match(result.diagnosticContent, expected);
    assert.ok(requests.filter(r => r.url.includes('www.google.com')).every(r => !/[?&](gl|cr)=/.test(r.url)));
  }
});

test('myTV SUPER requires one explicit session country; HK does not imply channels playable', async () => {
  const cases = [
    [{ country_code: 'HK', region: 1 }, /myTV SUPER：香港地区检查通过 · HK/],
    [{ data: { country_code: 'JP' } }, /myTV SUPER：非香港地区 · JP/],
    [{ region: 1 }, /myTV SUPER：地区未知/],
    [{ country_code: 'HK', content: { country_code: 'JP' } }, /myTV SUPER：地区未知/],
    [{ error_code: 123, country_code: 'HK' }, /myTV SUPER：会话证据不足/]
  ];
  for (const [body, expected] of cases) {
    const { result } = await run({ mode: 'unlock', reply: c => c.url.includes('mytvsuper.com') ? { body: JSON.stringify(body) } : { body: '<html></html>' } });
    assert.match(result.diagnosticContent, expected);
    assert.doesNotMatch(result.diagnosticContent, /myTV SUPER：.*可播放|myTV SUPER：.*完整解锁/);
  }
});

test('TikTok reads app context region, rejects generic user regions, conflicts and captcha', async () => {
  const modern = region => `<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">${JSON.stringify({ __DEFAULT_SCOPE__: { 'webapp.app-context': { region } } })}</script>`;
  const cases = [
    [modern('JP'), /TikTok：网页地区 JP，播放待验证/],
    ['<script id="SIGI_STATE">{"AppContext":{"appContext":{"region":"US"}}}</script>', /TikTok：网页地区 US，播放待验证/],
    ['<html>TikTok {"user":{"region":"JP"}}</html>', /TikTok：网页可达，地区未知/],
    [modern('JP') + '<script id="SIGI_STATE">{"AppContext":{"appContext":{"region":"US"}}}</script>', /TikTok：页面地区冲突，未知/],
    [modern('JP') + '<div id="captcha-verify-container"></div>', /TikTok：需要人机验证/],
    ['<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__">broken</script>', /TikTok：页面证据不足/]
  ];
  for (const [body, expected] of cases) {
    const { result } = await run({ mode: 'unlock', reply: c => c.url.includes('tiktok.com') ? { body } : { body: '<html></html>' } });
    assert.match(result.diagnosticContent, expected);
  }
});

test('new services retain rate-limit, auth and challenge states rather than claiming unlocked', async () => {
  for (const reply of [{ status: 429 }, { status: 401 }, { status: 403, body: '<title>Just a moment</title>cf-chl-' }, null]) {
    const { result } = await run({ mode: 'unlock', reply: () => reply });
    assert.doesNotMatch(result.diagnosticContent, /地区受限|地区检查通过|搜索结果可达|网页地区 [A-Z]/);
    for (const platform of ['Claude', 'Google', 'myTV SUPER', 'TikTok']) assert.ok(result.diagnosticContent.includes(platform + '：'));
  }
});

test('IP sources independently verify the exit and preserve default masking everywhere', async () => {
  const { result, requests } = await run({ reply:c=>({body:c.url.includes('cloudflare')
    ? 'ip=203.0.113.7\nloc=JP\ncolo=NRT\nwarp=on'
    :JSON.stringify({ip:'203.0.113.7',fraudScore:15,country:'Japan',countryCode:'JP',isResidential:false,isDataCenter:true})}) });
  assert.equal(requests.length,3);
  assert.match(result.diagnosticContent,/3 个来源 IP 一致/);
  assert.match(result.diagnosticContent,/WARP 已启用/);
  assert.match(result.diagnosticContent,/接入点 NRT/);
  assert.match(result.diagnosticContent,/住宅：否 · 机房：是 · 原生属性：未验证/);
  assert.doesNotMatch(result.diagnosticContent,/203\.0\.113\.7/);
  assert.match(result.diagnosticContent,/IPPure：HTTP 200 · 100 ms/);
});

test('different destination exits are disclosed and scores stay attached to IPPure', async () => {
  const { result } = await run({ reply:c=>c.url.includes('ippure')?{body:JSON.stringify({ip:'203.0.113.7',fraudScore:10})}
    :c.url.includes('ip.sb')?{body:JSON.stringify({ip:'198.51.100.8',fraudScore:0})}:{body:'ip=2001:db8::1\nloc=JP\nwarp=off'} });
  assert.equal(result['icon-color'],'#FF9500');
  assert.match(result.diagnosticContent,/不同站点出口不一致/);
  assert.match(result.diagnosticContent,/纯净度参考：90\/100/);
  assert.match(result.diagnosticContent,/IP\.SB：HTTP 200 · 100 ms · 198\.51\.\*\.\*/);
  assert.doesNotMatch(result.diagnosticContent,/203\.0\.113\.7|198\.51\.100\.8|2001:db8::1|100\/100/);
});

test('IP lookup falls back to remaining sources without inventing a risk score', async () => {
  const { result } = await run({reply:c=>c.url.includes('ippure')?{status:429}:c.url.includes('ip.sb')
    ?{body:JSON.stringify({ip:'203.0.113.8',country:'Japan',asn:64496,asn_organization:'Example ISP',fraudScore:0})}
    :{body:'ip=203.0.113.8\nloc=JP\ncolo=NRT\nwarp=off'}});
  assert.match(result.diagnosticContent,/主信息来源 IP\.SB/);
  assert.match(result.diagnosticContent,/ASN：64496 · Example ISP/);
  assert.match(result.diagnosticContent,/纯净度：未知/);
  assert.match(result.diagnosticContent,/IPPure：HTTP 429/);
  assert.doesNotMatch(result.diagnosticContent,/100\/100/);
});

test('equivalent IPv6 spellings agree without scoring or claiming dual-stack coverage', async () => {
  const { result }=await run({reply:c=>({body:c.url.includes('cloudflare')?'ip=2001:db8::1\nloc=JP'
    :JSON.stringify({ip:c.url.includes('ippure')?'2001:0db8:0:0:0:0:0:1':'2001:db8::1',fraudScore:0})})});
  assert.match(result.diagnosticContent,/3 个来源 IP 一致/);
  assert.match(result.diagnosticContent,/IPPure 不评估 IPv6/);
  assert.doesNotMatch(result.diagnosticContent,/100\/100|双栈通过|出口不一致/);
});

test('GeoIP country disagreements are distinguished from different exit IPs', async () => {
  const { result }=await run({reply:c=>({body:c.url.includes('cloudflare')?'ip=203.0.113.7\nloc=US'
    :JSON.stringify({ip:'203.0.113.7',countryCode:'JP',fraudScore:10})})});
  assert.match(result.diagnosticContent,/3 个来源 IP 一致/);
  assert.match(result.diagnosticContent,/地区库差异：JP \/ US（IP 一致，地区资料不同）/);
  assert.doesNotMatch(result.diagnosticContent,/出口不一致/);
});

test('AI probes distinguish structured authentication gates from a generic denial', async () => {
  const { result, requests }=await run({mode:'unlock',reply:c=>{
    if(c.url.includes('api.openai.com'))return {status:401,body:JSON.stringify({error:{type:'invalid_request_error',code:null,message:"You didn't provide an API key."}})};
    if(c.url.includes('api.anthropic.com'))return {status:401,body:JSON.stringify({type:'error',error:{type:'authentication_error',message:'x-api-key header is required'}})};
    if(c.url.includes('generativelanguage.googleapis.com'))return {status:403,body:JSON.stringify({error:{status:'PERMISSION_DENIED',details:[{reason:'CREDENTIALS_MISSING',metadata:{service:'generativelanguage.googleapis.com'}}]}})};
    if(c.url.includes('trace'))return {body:'loc=JP\ncolo=NRT'};
    if(c.url.includes('ios.chat.openai.com'))return {status:302,headers:{Location:'https://chatgpt.com/auth/login'}};
    return {body:'<html>ChatGPT Gemini Claude</html>'};
  }});
  for(const name of ['OpenAI API','Claude API','Gemini API'])assert.match(result.diagnosticContent,new RegExp(name+'：HTTP (401|403) · 100 ms · 入口可达，需 API Key'));
  assert.match(result.diagnosticContent,/App 入口：HTTP 302 · 100 ms · 转到官方登录入口/);
  assert.match(result.diagnosticContent,/API 认证响应仅证明入口可达，不等于调用通过/);
  assert.ok(requests.every(r=>!Object.keys(r.headers).some(h=>/authorization|x-api-key|cookie/i.test(h))||r.url.includes('bamgrid')));
  const denied=await run({mode:'unlock',reply:()=>({status:401,body:'<html>Denied</html>'})});
  assert.doesNotMatch(denied.result.diagnosticContent,/入口可达，需 API Key/);
});

test('an API-only country rejection does not overwrite a reachable ChatGPT website', async () => {
  const { result }=await run({mode:'unlock',reply:c=>c.url.includes('api.openai.com')
    ?{status:403,body:JSON.stringify({error:{code:'unsupported_country_region_territory'}})}
    :{body:'<html>ChatGPT</html>'}});
  assert.match(result.diagnosticContent,/ChatGPT：网页可达，待验证对话/);
  assert.match(result.diagnosticContent,/OpenAI API：HTTP 403 · 100 ms · 地区受限/);
  assert.doesNotMatch(result.diagnosticContent,/ChatGPT：地区受限/);
});

test('Gemini records its own runtime region and absent flags remain inconclusive', async () => {
  const enabled=await run({mode:'unlock',reply:c=>({body:c.url.includes('gemini.google.com')
    ?'<html>Gemini [45631641,null,true] [0,2,1,200,"JPN"]</html>':'<html></html>'})});
  assert.match(enabled.result.diagnosticContent,/Gemini：网页功能标志已启用，待登录验证 · JPN/);
  assert.match(enabled.result.content,/^Gemini：网页可达 · 🇯🇵 JP$/m);
  const absent=await run({mode:'unlock',reply:c=>({body:c.url.includes('gemini.google.com')?'<html>Gemini</html>':'<html></html>'})});
  assert.match(absent.result.diagnosticContent,/Gemini：网页可达，待登录验证/);
  assert.doesNotMatch(absent.result.diagnosticContent,/Gemini：地区受限|Gemini：地区不支持/);
});

test('Gemini API auth classification requires a matching service, not any JSON 403', async () => {
  for(const metadata of [{service:'another.googleapis.com'},{}]) {
    const { result }=await run({mode:'unlock',reply:c=>c.url.includes('generativelanguage.googleapis.com')
      ?{status:403,body:JSON.stringify({error:{status:'PERMISSION_DENIED',details:[{reason:'CREDENTIALS_MISSING',metadata}]}})}:{body:'<html></html>'}});
    assert.doesNotMatch(result.diagnosticContent,/Gemini API：[^\n]*入口可达/);
  }
});

test('Netflix separates two unavailable regional samples from its visible original sample', async () => {
  const { result }=await run({mode:'unlock',reply:c=>c.url.includes('netflix.com/title/')
    ?c.url.endsWith('80018499')?{body:'80018499 {"@type":"TVSeries","countryCode":"JP"}'}:{status:404}
    :{body:'<html></html>'}});
  assert.match(result.diagnosticContent,/Netflix：仅自制片样本可见（两个授权样本不可见） · JP/);
  assert.match(result.diagnosticContent,/授权样本 81280792：HTTP 404/);
  assert.match(result.diagnosticContent,/授权样本 70143836：HTTP 404/);
  assert.doesNotMatch(result.diagnosticContent,/完整解锁/);
});

test('Netflix CDN checks only an allowlisted HTTPS target with HEAD and hides its query', async () => {
  const target='https://ipv4-c001-nrt001-example.1.oca.nflxvideo.net/speedtest/range/0-0?secret=ephemeral';
  const { result,requests }=await run({mode:'unlock',reply:c=>c.url.includes('api.fast.com')
    ?{body:JSON.stringify({targets:[{url:target,location:{country:'JP',city:'Tokyo'}}]})}
    :{status:200,body:'<html></html>'}});
  assert.ok(requests.some(r=>r.url===target&&r.method==='head'&&r.policy==='Tokyo'));
  assert.match(result.diagnosticContent,/CDN 连接：HTTP 200 · 100 ms · HEAD 响应通过/);
  assert.match(result.diagnosticContent,/CDN 分配：HTTP 200.*nflxvideo.net · JP · Tokyo/);
  assert.doesNotMatch(result.diagnosticContent,/ephemeral|secret=|Netflix：授权片样本可见/);
  for(const url of ['http://x.nflxvideo.net/a','https://127.0.0.1/a','https://x.nflxvideo.net.evil.com/a','https://x.nflxvideo.net@evil.com/a','https://x.nflxvideo.net/a\n']) {
    const checked=await run({mode:'unlock',reply:c=>c.url.includes('api.fast.com')?{body:JSON.stringify({targets:[{url}]})}:{body:'<html></html>'}});
    assert.ok(checked.requests.every(r=>r.url!==url));
  }
});

test('YouTube CDN mapping adds routing evidence without exposing its source IP or proving playback', async () => {
  const { result }=await run({mode:'unlock',reply:c=>({body:c.url.includes('report_mapping')
    ?'203.0.113.7 => example-nrt1 (203.0.113.8)':'<html></html>'})});
  assert.match(result.diagnosticContent,/CDN 调度：HTTP 200 · 100 ms · 标识 example-nrt1/);
  assert.doesNotMatch(result.diagnosticContent,/203\.0\.113\.[78]|YouTube Premium：页面地区检查通过|视频播放通过/);
});

test('DNS, TLS and connection refusal remain distinct in per-probe failures', async () => {
  for(const [error,label] of [['DNS lookup failed','DNS 解析失败'],['TLS certificate invalid','TLS/证书失败'],['connection refused','连接被拒绝']]) {
    const { result }=await run({mode:'unlock',reply:()=>({error,noResponse:true})});
    assert.ok(result.diagnosticContent.includes(label));
    assert.doesNotMatch(result.diagnosticContent,/地区受限|入口可达，需 API Key/);
  }
});

test('deadline retains completed platforms while marking only pending checks unknown', async () => {
  const { result }=await run({mode:'unlock',deadlineMs:1000,reply:c=>c.url.includes('gemini.google.com')
    ?{status:302,headers:{Location:'/app'},delay:2000}
    :{body:c.url.includes('www.google.com')?'<html><div id="search"><h3>Result</h3></div></html>':'<html></html>'}});
  assert.match(result.diagnosticContent,/Google：搜索结果可达/);
  assert.match(result.diagnosticContent,/Gemini：检测尚未完成（总时限）/);
  for(const platform of ['ChatGPT','Gemini','Claude','Google','Netflix','Disney+','YouTube Premium','myTV SUPER','TikTok'])assert.ok(result.diagnosticContent.includes(platform+'：'));
});

test('rate-limit or server error pages cannot turn regional wording into a restriction verdict', async () => {
  for(const status of [429,503]) {
    const { result }=await run({mode:'unlock',reply:()=>({status,body:'<html>Gemini is not supported in your country. Netflix is not available in your country. Claude is not available in your country. forbidden-location</html>'})});
    assert.doesNotMatch(result.diagnosticContent,/：地区受限|：地区不支持/);
    assert.match(result.diagnosticContent,status===429?/请求限流/:/HTTP 503/);
  }
});

test('redirect evidence measures the complete same-origin path', async () => {
  const { result }=await run({mode:'unlock',reply:c=>c.url==='https://gemini.google.com/'
    ?{status:302,headers:{Location:'/app'},delay:150}:c.url==='https://gemini.google.com/app'
    ?{body:'<html>Gemini</html>',delay:250}:{body:'<html></html>'}});
  assert.match(result.diagnosticContent,/Web：HTTP 200 · 400 ms · 跳转 1 次/);
});

test('path panel separates DIRECT public IP, observed entrance and pinned-node exit, with masked local reports', async () => {
  const {result,requests,apiCalls,storage}=await run({mode:'path'});
  assert.equal(result.title,'入口落地查询');
  assert.match(result.content,/^公网 IP（直连）：203\.0\.113\.7/m);
  assert.match(result.content,/^入口 IP：198\.51\.100\.42/m);
  assert.match(result.content,/^落地 IP：203\.0\.113\.9/m);
  assert.equal(requests.filter(r=>r.policy==='DIRECT').length,1);
  assert.equal(requests.filter(r=>r.url.includes('/geoip/')).length,3);
  assert.equal(apiCalls.filter(r=>r.url==='/v1/requests/recent').length,1);
  assert.match(result.content,/ASN：AS64496 Example ISP/);
  assert.match(result.content,/节点：Tokyo\n更新 · \d{2}:\d{2}:\d{2}$/);
  const report=storage.VB_HEALTH_REPORT_V1_path;
  for(const ip of ['203.0.113.7','198.51.100.42','203.0.113.9']) assert.ok(!report.includes(ip));
  assert.doesNotMatch(report,/vb_health_path=/);
  assert.match(result.diagnosticContent,/未还原服务商隐藏转发链路/);
  const {value}=settings({path:'/api/reports',storage});
  assert.equal(value.reports.length,1);
  assert.equal(value.reports[0].mode,'path');
});

test('entrance matching ignores stale URLs, another selected node, and destination addresses without a proxy marker', async () => {
  for(const change of [r=>({...r,URL:r.URL+'&old=1'}),r=>({...r,policyName:'Other'}),r=>({...r,remoteAddress:'192.0.2.66'})]) {
    const {result,storage}=await run({mode:'path',recent:requests=>({requests:requests.filter(r=>r.policy==='Tokyo').map(r=>change({URL:r.url,policyName:'Tokyo',remoteAddress:'192.0.2.66 (Proxy)',headers:{Cookie:'unrelated-private-cookie'}}))})});
    assert.match(result.content,/入口 IP：未取得（未取得本次节点连接地址）/);
    assert.doesNotMatch(result.content,/192\.0\.2\.66/);
    assert.doesNotMatch(storage.VB_HEALTH_REPORT_V1_path,/unrelated-private-cookie|Cookie|old=1/);
  }
});

test('entrance records support IPv4 ports and bracketed or bare IPv6 without treating a hostname as an IP', async () => {
  for(const [remote,address]of[['198.51.100.42:443 (Proxy)','198.51.100.42'],['[2001:db8::5]:443 (Proxy)','2001:db8::5'],['2001:db8::5 (Proxy)','2001:db8::5'],['entry.example.com:443 (Proxy)','']]) {
    const {result}=await run({mode:'path',recent:requests=>({requests:requests.filter(r=>r.policy==='Tokyo'&&r.url.includes('vb_health_path=')).map(r=>({URL:r.url,policyName:'Tokyo',remoteAddress:remote}))})});
    if(address) assert.ok(result.content.includes('入口 IP：'+address));
    else assert.match(result.content,/入口 IP：未取得/);
  }
});

test('multiple observed entrance addresses stay ambiguous rather than choosing one arbitrarily', async () => {
  const {result,requests,storage}=await run({mode:'path',reply:c=>c.policy==='Tokyo'&&c.url.includes('/cdn-cgi/trace')?{status:503}:pathReply(c),
    recent:requests=>({requests:requests.filter(r=>r.policy==='Tokyo'&&r.url.includes('vb_health_path=')).map((r,i)=>({URL:r.url,policyName:'Tokyo',remoteAddress:'198.51.100.'+(42+i)+' (Proxy)'}))})});
  assert.match(result.content,/入口 IP：未取得（多个连接地址，待确认）/);
  assert.match(result.content,/落地 IP：203\.0\.113\.9/);
  assert.ok(requests.every(r=>!r.url.includes('/geoip/198.51.100.')));
  assert.doesNotMatch(storage.VB_HEALTH_REPORT_V1_path,/198\.51\.100\.(42|43)/);
});

test('geolocation must match the requested IP and can fall back to independent local ASN fields', async () => {
  const {result}=await run({mode:'path',localGeo:{geoip:'US',ipasn:'64497',ipaso:'Local ASN Org'},reply:c=>c.url.includes('/geoip/')
    ?{body:JSON.stringify({ip:'192.0.2.99',country:'WrongCountry',city:'WrongCity',asn:64500,asn_organization:'WrongOrg'})}:pathReply(c)});
  assert.match(result.content,/位置：🇺🇸 US/);
  assert.match(result.content,/ASN：AS64497 Local ASN Org/);
  assert.doesNotMatch(result.content,/Wrong|64500/);
  assert.match(result.diagnosticContent,/地址不匹配或格式变化/);
});

test('equivalent IPv6 endpoints share one geolocation lookup and keep full panel addresses', async () => {
  const ip='2001:db8::5';
  const {result,requests}=await run({mode:'path',reply:c=>c.url.includes('/cdn-cgi/trace')?{body:'ip='+ip+'\nloc=JP'}:
    {body:JSON.stringify({ip:'2001:0db8:0:0:0:0:0:5',country_code:'JP',asn:64496,asn_organization:'IPv6 Org'})},
    recent:requests=>({requests:requests.filter(r=>r.policy==='Tokyo').map(r=>({URL:r.url,policyName:'Tokyo',remoteAddress:'[2001:0db8:0:0:0:0:0:5]:443 (Proxy)'}))})});
  assert.equal(requests.filter(r=>r.url.includes('/geoip/')).length,1);
  assert.ok(result.content.includes(ip));
  assert.match(result.content,/ASN：AS64496 IPv6 Org/);
});

test('DIRECT and node probe failures remain independent and never substitute one exit for the other', async () => {
  for(const policy of ['DIRECT','Tokyo']) {
    const {result,clock}=await run({mode:'path',reply:c=>c.policy===policy&&c.url.includes('vb_health_path=')?null:pathReply(c)});
    if(policy==='DIRECT') { assert.match(result.content,/公网 IP（直连）：未取得（超时）/);assert.match(result.content,/落地 IP：203\.0\.113\.9/); }
    else { assert.match(result.content,/公网 IP（直连）：203\.0\.113\.7/);assert.match(result.content,/落地 IP：未取得（超时）/); }
    assert.ok(clock<25000);
  }
});

test('unreadable connection records preserve public and exit results while reporting entrance as unknown', async () => {
  for(const options of [{recent:{error:'unavailable'}},{recent:{requests:[]}},{recentHang:true}]) {
    const {result,clock}=await run({mode:'path',...options});
    assert.match(result.content,/入口 IP：未取得/);
    assert.match(result.content,/公网 IP（直连）：203\.0\.113\.7/);
    assert.match(result.content,/落地 IP：203\.0\.113\.9/);
    assert.ok(clock<25000);
  }
});

test('path deadline retains observed addresses, finishes once and starts no late probes', async () => {
  const {result,clock}=await run({mode:'path',deadlineMs:150});
  assert.equal(clock,150);
  assert.match(result.content,/公网 IP（直连）：203\.0\.113\.7/);
  assert.match(result.content,/落地 IP：203\.0\.113\.9/);
  assert.match(result.content,/ASN：待查询/);
});

test('path detection stops before DIRECT traffic if no valid concrete node is selected', async () => {
  for(const options of [{argument:'mode=path'},{decisions:{Group:'DIRECT'}},{decisions:{Group:'REJECT'}},{decisions:{Group:'Missing'}}]) {
    const {requests}=await run({mode:'path',...options});
    assert.equal(requests.length,0);
  }
});

test('path metadata and exit use the external policy identifier, while entrance may carry its display name', async () => {
  const {result,requests}=await run({mode:'path',expectedPolicy:'POLICY::opaque',policies:{proxies:[],'policy-groups':['Group'],'external-policies':[{name:'Tokyo',group:'Group',identifier:'POLICY::opaque'}]},
    recent:requests=>({requests:requests.filter(r=>r.policy==='POLICY::opaque').map(r=>({URL:r.url,policyName:'Tokyo',remoteAddress:'198.51.100.42 (Proxy)'}))})});
  assert.match(result.content,/入口 IP：198\.51\.100\.42/);
  assert.ok(requests.some(r=>r.policy==='POLICY::opaque'));
});

test('private entrance addresses are displayed but are never submitted to an external geolocation API', async () => {
  for(const ip of ['10.0.0.1','192.168.1.1','fc00::1','fe80::1','::ffff:7f00:1']) {
    const {result,requests}=await run({mode:'path',recent:requests=>({requests:requests.filter(r=>r.policy==='Tokyo').map(r=>({URL:r.url,policyName:'Tokyo',remoteAddress:ip+' (Proxy)'}))})});
    assert.ok(result.content.includes('入口 IP：'+ip));
    assert.match(result.content,/位置：内网地址/);
    assert.ok(!requests.some(r=>r.url.includes('/geoip/'+encodeURIComponent(ip))));
  }
});

test('module adds only local settings interception, host and panels; no capture, MITM or rules', () => {
  const moduleText = fs.readFileSync(path.join(__dirname, '..', 'node-health.sgmodule'), 'utf8');
  assert.deepEqual([...moduleText.matchAll(/^\[([^\]]+)\]/gm)].map(m => m[1]), ['General', 'Panel', 'Script', 'Host']);
  assert.match(moduleText,/^tun-included-routes = %INSERT% 192\.0\.2\.1\/32$/m);
  assert.match(moduleText,/^force-http-engine-hosts = %INSERT% surge-node-health\.invalid:80, 192\.0\.2\.1:80$/m);
  assert.match(moduleText,/^always-raw-tcp-hosts = %INSERT% -surge-node-health\.invalid:80, -192\.0\.2\.1:80$/m);
  assert.equal((moduleText.match(/update-interval=-1/g) || []).length, 4);
  assert.equal((moduleText.match(/type=generic/g) || []).length, 6);
  assert.ok(moduleText.indexOf('VB-Health-Path = script-name=')>moduleText.indexOf('VB-Health-Latency = script-name='));
  assert.match(moduleText,/VB-Health-Path = type=generic[^\n]+argument="mode=path"/);
  assert.ok(moduleText.indexOf('VB-Health-Reports = script-name=')>moduleText.indexOf('VB-Health-Path = script-name='));
  assert.match(moduleText,/VB-Health-Reports = type=generic[^\n]+settings\.js[^\n]+argument="mode=reports"/);
  assert.match(moduleText, /VB-Health-Settings-Entry = script-name=VB-Health-Settings-Entry/);
  assert.equal((moduleText.match(/type=http-request/g) || []).length, 1);
  assert.ok(moduleText.includes('pattern=^http://(?:surge-node-health\\.invalid|192\\.0\\.2\\.1)(?::80)?(?:/|$)'));
  assert.match(moduleText, /surge-node-health\.invalid = 192\.0\.2\.1/);
  assert.doesNotMatch(moduleText, /\{\{\{POLICY\}\}\}|#!arguments=POLICY/);
  assert.doesNotMatch(moduleText, /type=cron|type=event|insecure=true/);
});

test('native cards are compact while evidence remains available in the local report', async () => {
  const ip=await run();
  assert.ok(ip.result.content.split('\n').length<=9);
  assert.equal(ip.result.icon,'checkmark.seal.fill');
  assert.equal(ip.result.style,undefined);
  assert.match(ip.result.content,/^风险分：25\/100 · 低风险$/m);
  assert.match(ip.result.content,/^IPv4：/);
  assert.match(ip.result.content,/ASN：[^\n]+\n\n属性：/);
  assert.match(ip.result.content,/\n\n节点：Tokyo\n更新 · \d{2}:\d{2}:\d{2}$/);
  assert.doesNotMatch(ip.result.content,/纯净度：|v0\.1\.0|源一致/);
  assert.doesNotMatch(ip.result.content,/HTTP |IP\.SB：|主信息来源|asOrganization/);
  assert.match(ip.result.diagnosticContent,/IPPure：HTTP 200/);
  const platforms=await run({mode:'unlock',reply:()=>({body:'<html>ChatGPT Gemini Claude</html>'})});
  assert.equal(platforms.result.icon,'play.tv.fill');
  assert.equal(platforms.result['icon-color'],'#FF2D55');
  assert.equal((platforms.result.content.match(/^(?:ChatGPT|Gemini|Claude|Google|Netflix|Disney\+|YouTube Premium|myTV SUPER|TikTok)：/gm)||[]).length,9);
  assert.doesNotMatch(platforms.result.content, /✅|◐|🚫|❔/);
  assert.ok(platforms.result.content.split('\n').length<=14);
  assert.match(platforms.result.content,/Google：[^\n]+\n\nNetflix：/);
  assert.match(platforms.result.content,/^ChatGPT：/);
  assert.match(platforms.result.content,/\n\n节点：Tokyo\n播放\/对话未测 · \d{2}:\d{2}:\d{2}$/);
  assert.doesNotMatch(platforms.result.content,/v0\.1\.0/);
  assert.doesNotMatch(platforms.result.content,/HTTP |OpenAI API|App 入口|逐次：|inSupportedLocation/);
  assert.match(platforms.result.diagnosticContent,/OpenAI API：HTTP 200/);
  const latency=await run({mode:'latency'});
  assert.match(latency.result.content,/^广州电信：/);
  assert.match(latency.result.content,/\n\n节点：Tokyo\n手机经节点到广州 · HTTP 往返 · \d{2}:\d{2}:\d{2}$/);
});

test('native IPv4 and IPv6 are complete by default, old masking arguments cannot hide them, records stay masked', async () => {
  for(const argument of ['mode=ip&policy=Group','mode=ip&showIP=false&policy=Group','mode=ip&showIP=true&policy=Group']) {
    for(const [ip,masked]of[['203.0.113.7','203.0.*.*'],['2001:db8::abcd','2001:db8:****']]) {
      const {result,storage}=await run({argument,reply:()=>({body:JSON.stringify({ip,fraudScore:0})})});
      assert.ok(result.content.includes(ip));
      assert.ok(!storage.VB_HEALTH_REPORT_V1_ip.includes(ip));
      assert.ok(storage.VB_HEALTH_REPORT_V1_ip.includes(masked));
    }
  }
});

test('Guangzhou discovery rejects other cities, wrong coordinates and ambiguous carriers; removed old hosts are never probed', async () => {
  const bad=gzDirectory.flatMap(r=>[{...r,name:'Shenzhen'},{...r,country:'Japan'},{...r,lat:'31.2',lon:'121.4'},{...r,sponsor:'China Telecom China Unicom'}]);
  const {result,requests}=await run({mode:'latency',directoryReply:{body:JSON.stringify(bad)}});
  assert.equal(requests.length,8);
  assert.ok(requests.every(r=>!r.url.includes('gzspeed.net')));
  assert.match(result.content,/广州电信：未取得广州测点/);
  assert.match(result.content,/广州联通：未取得广州测点/);
  assert.match(result.content,/广州移动：100 ms · 候选测点/);
  assert.match(result.diagnosticContent,/非广州城市 3 · 国家缺失或不符 3 · 坐标缺失或超出广州 3 · 运营商证据冲突 3/);
  assert.match(result.diagnosticContent,/未发起测点请求/);
  assert.doesNotMatch(source,/www\.gdspeedtest\.com|speedtest1\.gzuni\.com|speedtest1\.gd\.chinamobile\.com/);
});

test('Guangzhou discovery rejects private addresses and unsafe server URLs', async () => {
  for(const url of ['http://127.0.0.1:8080/','http://192.168.1.1/','http://10.0.0.1/','http://100.64.0.1/','http://localhost:8080/','http://x.local/','http://user:pass@ct.gzspeed.net:8080/','file:///x','http://ct.gzspeed.net:22/']) {
    const records=gzDirectory.map(r=>({...r,url,host:''}));
    const {requests}=await run({mode:'latency',directoryReply:{body:JSON.stringify(records)}});
    assert.equal(requests.length,8,url);
    assert.ok(requests.every(r=>!r.url.startsWith(url)),url);
  }
});

test('Guangzhou targets remain the same across selected nodes for a fresh local snapshot', async () => {
  const storage={};
  const extra={...gzDirectory[0],id:'99999',host:'other.gzspeed.net:8080',url:'http://other.gzspeed.net:8080/speedtest/upload.php'};
  const first=await run({mode:'latency',storage,directoryReply:{body:JSON.stringify([extra,...gzDirectory].reverse())}});
  assert.ok(first.requests.some(r=>r.url.startsWith('http://ct.gzspeed.net:8080/')));
  assert.ok(first.requests.every(r=>!r.url.includes('other.gzspeed.net')));
  const second=await run({mode:'latency',storage,epoch:1792123210000,decisions:{Group:'Other'},expectedPolicy:'Other',directoryReply:{status:503}});
  assert.equal(second.requests.length,15);
  assert.ok(second.requests.every(r=>r.url.includes('/speedtest/latency.txt')));
  assert.match(second.result.diagnosticContent,/30 分钟内固定测点/);
});

test('expired and old rewritten V2 snapshots are not reused', async () => {
  const storage={VB_HEALTH_GZ_TARGETS_V2:JSON.stringify({version:2,updatedAt:1792123200000,records:gzDirectory})};
  const initial=await run({mode:'latency',storage});
  assert.equal(initial.requests.length,18);
  assert.equal(JSON.parse(storage.VB_HEALTH_GZ_TARGETS_V3).version,3);
  const {result,requests}=await run({mode:'latency',storage,epoch:1792125100000,directoryReply:{status:503}});
  assert.equal(requests.length,8);
  assert.ok(requests.every(r=>!r.url.includes('gzspeed.net')));
  assert.match(result.content,/广州电信：未取得广州测点/);
  assert.match(result.diagnosticContent,/HTTP 503/);
});

test('a generic HTTP 200 page or a denial response cannot generate a Guangzhou latency', async () => {
  for(const reply of [{body:'<html>Welcome</html>'},{body:'test=test\nextra text'},{status:403,body:'test=test'}]) {
    const {result,requests}=await run({mode:'latency',reply:()=>reply});
    assert.equal(requests.length,7);
    assert.doesNotMatch(result.content,/广州(?:电信|联通|移动)：\d+ ms/);
    assert.match(result.diagnosticContent,/测点响应异常/);
  }
});

test('parallel directory timeout retains the mobile candidate and accurately reports missing CT/CU targets', async () => {
  const {result,requests,clock}=await run({mode:'latency',directoryReply:null});
  assert.equal(requests.length,8);
  assert.ok(clock<25000);
  assert.equal((result.content.match(/未取得广州测点/g)||[]).length,2);
  assert.match(result.content,/广州移动：100 ms · 候选测点/);
  assert.match(result.diagnosticContent,/超时/);
  assert.doesNotMatch(source,/www\.189\.cn|iservice\.10010\.com|www\.10086\.cn/);
});

test('directory rejection, HTML, changed shape and empty list have distinct diagnostics', async () => {
  for(const [directoryReply,reason]of[[{status:403},'请求被拒'],[{body:'<html>Blocked</html>'},'目录格式未知'],
    [{body:'{}'},'目录格式未知'],[{body:'[]'},'目录返回空列表']]) {
    const {result,requests}=await run({mode:'latency',directoryReply});
    assert.equal(requests.filter(r=>r.url.includes('/speedtest/latency.txt')).length,5);
    assert.match(result.content,/广州电信：未取得广州测点/);
    assert.ok(result.diagnosticContent.includes(reason));
    assert.ok(requests.every(r=>r.policy==='Tokyo'));
  }
});

test('Chinese search and SDK servers envelope supply current targets when English search is empty', async () => {
  const {result,requests}=await run({mode:'latency',directoryReplies:{
    en:{body:'[]'},zh:{body:JSON.stringify([gzDirectory[1]])},sdk:{body:JSON.stringify({servers:[gzDirectory[0],gzDirectory[2]]})}
  }});
  assert.equal(requests.length,18);
  assert.match(result.content,/广州电信：100 ms/);
  assert.match(result.content,/广州联通：100 ms/);
  assert.match(result.content,/广州移动：100 ms/);
  assert.match(result.diagnosticContent,/Ookla 英文目录：HTTP 200 · 100 ms · 返回 0 条 · 合格记录 0\/3/);
  assert.match(result.diagnosticContent,/Ookla 中文目录：HTTP 200 · 100 ms · 返回 1 条 · 合格记录 1\/3/);
  assert.match(result.diagnosticContent,/Ookla SDK 目录：HTTP 200 · 100 ms · 返回 2 条 · 合格记录 2\/3/);
});

test('directory rejection details explain missing fields and never persist arbitrary raw response data', async () => {
  const records=[{...gzDirectory[0],lat:null}, {...gzDirectory[1],sponsor:'Unknown',country:' CN '},
    {...gzDirectory[2],host:'other.public.net:8080'}].map(r=>({...r,token:'RAW_TOKEN_MARKER',headers:{Cookie:'RAW_COOKIE_MARKER'}}));
  const {result}=await run({mode:'latency',directoryReply:{body:JSON.stringify(records)}});
  assert.match(result.diagnosticContent,/坐标缺失或超出广州 1 · 运营商未识别 1 · 主机别名不匹配 1/);
  assert.match(result.diagnosticContent,/未采用：ID 27594 · 城市 Guangzhou · China Telecom · 坐标缺失或超出广州/);
  assert.doesNotMatch(result.diagnosticContent,/RAW_TOKEN_MARKER|RAW_COOKIE_MARKER|other\.public/);
});

test('Guangzhou-5G mapping accepts the exact raw or official alias URL and preserves the advertised scheme across cache', async () => {
  const mobile={id:'60794',name:'Guangzhou',country:'China',lat:'23.1291',lon:'113.2644',sponsor:'GuangZhou-5G',
    host:'speedtest2.dpdfsd.com.prod.hosts.ooklaserver.net:8080',url:'http://speedtest2.dpdfsd.com:8080/speedtest/upload.php',https_functional:1};
  for(const provider of [undefined,'CM']) for(const advertised of [mobile.url,'https://'+mobile.host+'/speedtest/upload.php']) {
    const storage={};
    const first=await run({mode:'latency',storage,directoryReply:{body:JSON.stringify([gzDirectory[0],gzDirectory[1],{...mobile,url:advertised,provider}])}});
    const selected=first.requests.filter(r=>r.url.includes('dpdfsd'));
    assert.equal(selected.length,5);
    const origin=new URL(advertised).origin;
    assert.ok(selected.every(r=>r.url.startsWith(origin+'/')));
    assert.match(first.result.diagnosticContent,/合格记录 3\/3/);
    const second=await run({mode:'latency',storage,epoch:1792123210000});
    assert.equal(second.requests.length,15);
    assert.ok(second.requests.filter(r=>r.url.includes('dpdfsd')).every(r=>r.url.startsWith(origin+'/')));
    assert.match(second.result.diagnosticContent,/30 分钟内固定测点/);
  }
});

test('carrier conflicts, unknown sponsors and arbitrary aliases cannot enter the candidate pool', async () => {
  const mobile={...gzDirectory[2],id:'99888',sponsor:'GuangZhou-5G',host:'unverified.gzspeed.net:8080',url:'http://unverified.gzspeed.net:8080/speedtest/upload.php'};
  for(const record of [mobile,{...mobile,sponsor:'China Telecom',provider:'CM'},
    {...mobile,sponsor:'China Mobile',host:'other.public.net:8080'},
    {...mobile,sponsor:'China Mobile',host:'unverified.gzspeed.net.evil.ooklaserver.net:8080'}]) {
    const {result,requests}=await run({mode:'latency',directoryReply:{body:JSON.stringify([gzDirectory[0],gzDirectory[1],record])}});
    assert.ok(requests.every(r=>!/unverified|other\.public|evil/.test(r.url)));
    assert.match(result.diagnosticContent,/合格记录 2\/3/);
  }
});

test('a failed advertised URL tries only its exact declared alternate; statistics stay on the selected URL', async () => {
  const record={...gzDirectory[0],host:'ct.gzspeed.net.prod.hosts.ooklaserver.net:8080',https_functional:1};
  const {result,requests}=await run({mode:'latency',directoryReply:{body:JSON.stringify([record,...gzDirectory.slice(1)])},reply:c=>
    c.url.startsWith('http://ct.gzspeed.net:8080/')?{error:'DNS resolve failed',delay:900}:{body:'test=test',delay:250}});
  assert.equal(requests.filter(r=>r.url.startsWith('http://ct.gzspeed.net:8080/')).length,1);
  assert.equal(requests.filter(r=>r.url.startsWith('https://ct.gzspeed.net.prod.hosts.ooklaserver.net:8080/')).length,5);
  assert.match(result.content,/^广州电信：250 ms$/m);
  assert.match(result.diagnosticContent,/地址：http:\/\/ct\.gzspeed\.net:8080\/speedtest\/latency\.txt/);
  assert.match(result.diagnosticContent,/DNS 解析失败/);
  assert.match(result.diagnosticContent,/中位数 250 ms · 有效 5\/5 · 范围 250–250 ms/);
  assert.doesNotMatch(result.diagnosticContent,/中位数 900/);
});

test('each discovered carrier reports actual failures without inventing latency', async () => {
  for(const [reply,reason]of[[{error:'DNS resolve failed'},'DNS 解析失败'],[{error:'connection refused'},'连接被拒绝'],
    [{error:'TLS certificate failed'},'TLS/证书失败'],[{status:403,body:'test=test'},'测点拒绝']]) {
    const {result}=await run({mode:'latency',reply:()=>reply});
    for(const name of ['广州电信','广州联通','广州移动']) assert.ok(result.content.includes(name+'：'+reason));
    assert.doesNotMatch(result.content,/：\d+ ms/);
  }
});

test('hung directories and advertised mobile URL plus slow HTTPS alternate remain within the Surge budget', async () => {
  const {result,clock,requests}=await run({mode:'latency',directoryReply:null,reply:c=>
    c.url.startsWith('http://speedtest2.dpdfsd.com:8080/')?null:{body:'test=test',delay:3000}});
  assert.ok(clock<25000);
  assert.match(result.content,/广州移动：3000 ms · 候选测点/);
  assert.equal(requests.filter(r=>r.url.startsWith('http://speedtest2.dpdfsd.com:8080/')).length,1);
  assert.equal(requests.filter(r=>r.url.startsWith('https://speedtest2.dpdfsd.com.prod.hosts.ooklaserver.net:8080/')).length,5);
});

test('latency deadline keeps the carriers already completed and never starts later probes', async () => {
  const {result}=await run({mode:'latency',deadlineMs:800,reply:c=>c.url.includes('ct.gzspeed.net')?{body:'test=test',delay:100}:null});
  assert.match(result.content,/^广州电信：100 ms$/m);
  assert.match(result.content,/^广州联通：检测超时$/m);
  assert.match(result.content,/^广州移动：检测超时$/m);
});

test('report write failure does not prevent the native panel from completing', async () => {
  const {result,storage}=await run({writeFail:true});
  assert.match(result.content,/风险分：25\/100 · 低风险/);
  assert.equal(storage.VB_HEALTH_REPORT_V1_ip,undefined);
});

test('native platform errors remain short while diagnostic HTTP status is retained', async () => {
  const {result}=await run({mode:'unlock',reply:()=>({status:503})});
  assert.doesNotMatch(result.content,/HTTP |逐次：|API Key/);
  assert.match(result.content,/服务异常/);
  assert.match(result.diagnosticContent,/HTTP 503/);
});

function settings(options = {}) {
  const storage = options.storage || {};
  let result;
  let writes = 0;
  let done = 0;
  let groupReads = 0;
  const notifications = [];
  const groups = options.groups || { Group: ['Tokyo', 'Other'], '🚀 常用节点': ['Other'] };
  const decisions = options.decisions || { Group: 'Tokyo', '🚀 常用节点': 'Other' };
  const headers = options.headers === undefined ? { Origin: 'http://surge-node-health.invalid', 'X-VB-Health-Settings': '1', 'Content-Type': 'application/json' } : options.headers;
  vm.runInNewContext(settingsSource, {
    $argument: options.argument,
    $request: options.panel ? undefined : { url: options.url || 'http://surge-node-health.invalid' + (options.path || '/'), method: options.method || 'GET', headers, body: options.body || '' },
    $trigger: options.trigger,
    $notification: options.noNotifications ? undefined : { post: (...args) => { if(options.notificationThrows) throw new Error('Notification error'); notifications.push(args); } },
    $surge: { selectGroupDetails: () => { groupReads++; return options.badDetails ? {} : ({ groups, decisions }); }, setSelectGroupPolicy: () => { throw new Error('Must not change selected node'); } },
    $httpClient: Object.fromEntries(['get','head','post'].map(method=>[method,()=>{throw new Error('Settings/report reader must not make external requests');}])),
    $httpAPI: () => { throw new Error('Settings/report reader must not call the HTTP API'); },
    $persistentStore: { read: key => Object.hasOwn(storage, key) ? storage[key] : null, write: (value, key) => { writes++; if(options.writeFail) return false; storage[key] = value; return true; } },
    $done: value => { result = value; done++; }
  }, { timeout: 1000 });
  assert.equal(done, 1);
  assert.ok(result);
  return { result, storage, writes, notifications, groupReads, value: result.response && result.response.headers['Content-Type'].startsWith('application/json') ? JSON.parse(result.response.body) : undefined };
}

test('native report reader shows the latest real cached diagnostic without browser, probes or group access', async () => {
  const {storage}=await run({mode:'latency',directoryReply:{status:403},reply:()=>({status:404,body:'<html>Not found</html>'})});
  const before=JSON.stringify(storage);
  const summary=settings({panel:true,argument:'mode=reports',trigger:'auto-interval',storage,badDetails:true,noNotifications:true});
  assert.match(summary.result.content,/最近检测：广州三网延迟/);
  assert.equal(summary.groupReads,0);
  assert.equal(summary.writes,0);
  assert.equal(JSON.stringify(storage),before);
  const expanded=settings({panel:true,argument:'mode=reports',trigger:'button',storage,badDetails:true,noNotifications:true});
  assert.equal(expanded.result.title,'检测详情 · 广州三网延迟');
  assert.match(expanded.result.content,/第 1\/\d+ 页/);
  assert.match(expanded.result.content,/HTTP 403|HTTP 404/);
  assert.equal(expanded.groupReads,0);
  assert.deepEqual(expanded.notifications,[]);
  assert.equal(storage[SETTINGS_KEY],undefined);
  assert.doesNotMatch(expanded.result.content,/http:\/\/surge-node-health/);
});

test('native diagnostic pages preserve every character and fold after the final page', () => {
  const details='节点：Test\n'+('HTTP 404 · 🇯🇵 · 😀 · 单次 100 ms\n'.repeat(120));
  const report={version:1,mode:'latency',title:'广州三网延迟',build:'test',updatedAt:1792123200000,details};
  const binding=JSON.stringify({version:1,group:'🚀 常用节点'});
  const storage={VB_HEALTH_REPORT_V1_latency:JSON.stringify(report),[SETTINGS_KEY]:binding};
  const pageCount=Math.ceil(Array.from(details).length/700);
  let restored='';
  for(let page=0;page<pageCount;page++) {
    const shown=settings({panel:true,argument:'mode=reports',trigger:'button',storage});
    assert.ok(shown.result.content.includes('第 '+(page+1)+'/'+pageCount+' 页'));
    const body=shown.result.content.slice(shown.result.content.indexOf('\n\n')+2);
    assert.ok(Array.from(body).length<=700);
    assert.ok(!/^[\udc00-\udfff]|[\ud800-\udbff]$/.test(body));
    restored+=body;
    assert.equal(shown.writes,1);
    assert.equal(shown.groupReads,0);
    assert.equal(storage[SETTINGS_KEY],binding);
  }
  assert.equal(restored,details);
  const folded=settings({panel:true,argument:'mode=reports',trigger:'button',storage});
  assert.equal(folded.result.title,'检测详情');
  assert.match(folded.result.content,/最近检测：广州三网延迟/);
  assert.doesNotMatch(folded.result.content,/HTTP 404/);
});

test('native report background refreshes retain the page, while a new report resets to the summary', async () => {
  const {storage}=await run({mode:'latency'});
  settings({panel:true,argument:'mode=reports',trigger:'button',storage});
  const before=JSON.stringify(storage);
  for(const trigger of ['auto-interval','editor','http-api','intent',undefined]) {
    const current=settings({panel:true,argument:'mode=reports',trigger,storage});
    assert.match(current.result.content,/第 1\/\d+ 页/);
    assert.equal(current.writes,0);
    assert.equal(JSON.stringify(storage),before);
  }
  storage.VB_HEALTH_REPORT_V1_ip=JSON.stringify({version:1,mode:'ip',title:'IP 纯净度',build:'new',updatedAt:1792123300000,details:'新 IP 记录 · 203.0.*.*'});
  const current=settings({panel:true,argument:'mode=reports',trigger:'auto-interval',storage});
  assert.match(current.result.content,/最近检测：IP 纯净度/);
  assert.doesNotMatch(current.result.content,/第 \d+\/|广州三网/);
  const expanded=settings({panel:true,argument:'mode=reports',trigger:'button',storage});
  assert.match(expanded.result.content,/第 1\/1 页/);
  assert.match(expanded.result.content,/新 IP 记录/);
});

test('native report reader skips corrupt/oversized records and invalid page state without changing bindings', () => {
  for(const raw of ['broken',JSON.stringify({version:1,mode:'latency',details:'x'.repeat(24001)}),JSON.stringify({version:1,mode:'latency',updatedAt:-1,title:'x',build:'x',details:'x'})]) {
    const storage={VB_HEALTH_REPORT_V1_latency:raw};
    const result=settings({panel:true,argument:'mode=reports',trigger:'button',storage});
    assert.match(result.result.content,/暂无检测记录/);
    assert.equal(result.writes,0);
    assert.equal(result.groupReads,0);
  }
  for(const page of [null,NaN,-2,100,0.5,'0']) {
    const storage={VB_HEALTH_REPORT_V1_latency:JSON.stringify({version:1,mode:'latency',title:'广州三网延迟',build:'t',updatedAt:1,details:'record'}),
      VB_HEALTH_REPORT_VIEW_V1:JSON.stringify({version:1,mode:'latency',build:'t',updatedAt:1,page})};
    assert.match(settings({panel:true,argument:'mode=reports',storage}).result.content,/最近检测/);
    assert.match(settings({panel:true,argument:'mode=reports',trigger:'button',storage}).result.content,/第 1\/1 页/);
  }
});

test('native report is readable even if cursor persistence fails and cached IPs remain masked', async () => {
  const {storage}=await run();
  const before=JSON.stringify(storage);
  const shown=settings({panel:true,argument:'mode=reports',trigger:'button',storage,writeFail:true});
  assert.match(shown.result.content,/第 1\/\d+ 页/);
  assert.match(shown.result.content,/翻页位置未保存，请重试/);
  assert.match(shown.result.content,/203\.0\.\*\.\*/);
  assert.doesNotMatch(shown.result.content,/203\.0\.113\.7/);
  assert.equal(JSON.stringify(storage),before);
});

test('panel taps cycle existing groups, save exact names and wrap without notifications', () => {
  const storage = {};
  for (const [name, node, index] of [['Group','Tokyo',1],['🚀 常用节点','Other',2],['Group','Tokyo',1]]) {
    const { result, notifications, writes } = settings({ panel:true, trigger:'button', storage, noNotifications:true });
    assert.equal(result.title,'检测设置');
    assert.ok(result.content.includes('策略组：'+name));
    assert.ok(result.content.includes('当前节点：'+node));
    assert.ok(result.content.includes('点按切组 · '+index+'/2'));
    assert.ok(result.content.split('\n').length<=4);
    assert.equal(result.style,undefined);
    assert.match(result.content,/http:\/\/surge-node-health\.invalid\//);
    assert.equal(JSON.parse(storage[SETTINGS_KEY]).group,name);
    assert.equal(notifications.length,0);
    assert.equal(writes,1);
  }
});

test('non-button settings refresh never chooses or advances a detection group', () => {
  for(const trigger of ['auto-interval',undefined,'editor','http-api','intent']) {
    for(const binding of [undefined,'🚀 常用节点','Deleted']) {
      const storage = binding === undefined ? {} : { [SETTINGS_KEY]:JSON.stringify({version:1,group:binding}) };
      const before = JSON.stringify(storage);
      const { result, notifications, writes } = settings({panel:true,trigger,storage});
      if(binding===undefined) assert.match(result.content,/尚未选择/);
      if(binding==='🚀 常用节点') assert.match(result.content,/当前节点：Other/);
      if(binding==='Deleted') assert.match(result.content,/原检测组已不存在/);
      assert.equal(JSON.stringify(storage),before);
      assert.equal(notifications.length,0);
      assert.equal(writes,0);
    }
  }
});

test('button-selected group is followed by all checks and tracks its selected node', async () => {
  const storage = {};
  settings({ panel:true, trigger:'button', storage });
  settings({ panel:true, trigger:'button', storage });
  for(const mode of ['ip','unlock','latency','path']) {
    const { result, requests } = await run({storage,argument:`mode=${mode}&showIP=false`,decisions:{'🚀 常用节点':'Other'},expectedPolicy:'Other'});
    assert.match(result.content,/节点：Other/);
    assert.ok(requests.length>0);
  }
  const { result } = await run({storage,argument:'mode=ip&showIP=false',decisions:{'🚀 常用节点':'Tokyo'}});
  assert.match(result.content,/节点：Tokyo/);
});

test('binding persistence failure keeps previous selection and reports no success', () => {
  for(const initial of [undefined,'Group']) {
    const storage = initial ? {[SETTINGS_KEY]:JSON.stringify({version:1,group:initial})} : {};
    const before = JSON.stringify(storage);
    const { result, notifications } = settings({panel:true,trigger:'button',storage,writeFail:true});
    assert.equal(result.style,'alert');
    assert.match(result.content,/未能保存选择/);
    assert.doesNotMatch(result.content,/策略组：🚀 常用节点/);
    assert.equal(JSON.stringify(storage),before);
    assert.equal(notifications.length,0);
  }
});

test('missing groups or runtime details never alter the binding', () => {
  for(const options of [{groups:{},decisions:{}},{badDetails:true}]) {
    const { result, writes } = settings({panel:true,trigger:'button',...options});
    assert.equal(result.style,'alert');
    assert.equal(writes,0);
    assert.match(result.content,/http:\/\/surge-node-health\.invalid\//);
  }
});

test('single group and stale binding select correctly without redundant writes', () => {
  const storage = {[SETTINGS_KEY]:JSON.stringify({version:1,group:'Deleted'})};
  const name = '🚀 常用&节点=50%+';
  const options = {panel:true,trigger:'button',storage,groups:{[name]:['Tokyo']},decisions:{[name]:'Tokyo'}};
  const first = settings(options);
  assert.equal(first.writes,1);
  assert.equal(JSON.parse(storage[SETTINGS_KEY]).group,name);
  assert.match(first.result.content,/仅有 1 个手动组/);
  const second = settings(options);
  assert.equal(second.writes,0);
  assert.match(second.result.content,/仅有 1 个手动组/);
});

test('local picker lists existing manual groups and current choices, preserving exact names', () => {
  const { result, value } = settings({ path: '/api/groups', groups: { '🚀 常用&节点=50%+': ['Tokyo'], Empty: [], Auto: ['Other'] }, decisions: { '🚀 常用&节点=50%+': 'Tokyo' } });
  assert.equal(result.response.status, 200);
  assert.deepEqual(value.groups, [{ name: '🚀 常用&节点=50%+', selected: 'Tokyo' }]);
  assert.equal(result.response.headers['Cache-Control'], 'no-store');
  assert.equal(result.response.headers['Access-Control-Allow-Origin'], undefined);
});

test('selecting an existing group saves it locally; each panel follows its current node', async () => {
  const { value, storage } = settings({ path: '/api/select', method: 'POST', body: JSON.stringify({ group: '🚀 常用节点' }) });
  assert.equal(value.saved, true);
  assert.equal(JSON.parse(storage[SETTINGS_KEY]).group, '🚀 常用节点');
  for (const mode of ['ip', 'unlock', 'latency', 'path']) {
    const { result, requests } = await run({ storage, argument: `mode=${mode}&showIP=false`, decisions: { '🚀 常用节点': 'Other' }, expectedPolicy: 'Other' });
    assert.match(result.content, /节点：Other/);
    assert.ok(requests.length > 0);
  }
  const changed = await run({ storage, argument: 'mode=ip&showIP=false', decisions: { '🚀 常用节点': 'Tokyo' } });
  assert.match(changed.result.content, /节点：Tokyo/);
});

test('picker selection takes priority over old manual parameters', async () => {
  const storage = { [SETTINGS_KEY]: JSON.stringify({ version: 1, group: 'Saved' }) };
  const { result } = await run({ storage, argument: 'mode=ip&showIP=false&policy=Group', decisions: { Saved: 'Other', Group: 'Tokyo' }, expectedPolicy: 'Other' });
  assert.match(result.content, /节点：Other/);
});

test('missing, corrupt and stale selection never use guessed or direct routes', async () => {
  for (const stored of [undefined, 'broken', JSON.stringify({ version: 1, group: 'Deleted' })]) {
    const storage = stored === undefined ? {} : { [SETTINGS_KEY]: stored };
    const { result, requests } = await run({ storage, argument: 'mode=ip&showIP=false' });
    assert.equal(requests.length, 0);
    assert.equal(result.style, 'alert');
    assert.match(result.content, /surge-node-health\.invalid/);
  }
});

test('picker writes require same origin JSON and custom header; GET never saves', () => {
  const valid = { Origin: 'http://surge-node-health.invalid', 'X-VB-Health-Settings': '1', 'Content-Type': 'application/json' };
  const badHeaders = [{}, { ...valid, Origin: 'https://example.com' }, { ...valid, Origin: 'null' }, { ...valid, 'Content-Type': 'text/plain' }, { Origin: valid.Origin, 'Content-Type': valid['Content-Type'] }];
  for (const headers of badHeaders) {
    const { result, writes } = settings({ path: '/api/select', method: 'POST', headers, body: '{"group":"Group"}' });
    assert.equal(result.response.status, 403);
    assert.equal(writes, 0);
  }
  for (const method of ['GET', 'OPTIONS', 'PUT']) {
    const { result, writes } = settings({ path: '/api/select', method, body: '{"group":"Group"}' });
    assert.ok(result.response.status >= 400);
    assert.equal(writes, 0);
  }
});

test('removed group, malformed input and failed persistence do not report saved', () => {
  for (const body of ['{', 'null', '{"group":"Missing"}']) {
    const { result, writes } = settings({ path: '/api/select', method: 'POST', body });
    assert.equal(result.response.status, 400);
    assert.equal(writes, 0);
  }
  const failed = settings({ path: '/api/select', method: 'POST', body: '{"group":"Group"}', writeFail: true });
  assert.equal(failed.result.response.status, 500);
  assert.equal(failed.value.saved, undefined);
});

test('picker returns self-contained HTML and fails closed on unrelated hosts', () => {
  const { result } = settings();
  assert.equal(result.response.status, 200);
  assert.match(result.response.body, /选择检测策略组/);
  assert.doesNotMatch(result.response.body, /<script[^>]+src=|innerHTML/);
  const scripts = [...result.response.body.matchAll(/<script>([\s\S]*?)<\/script>/g)];
  assert.equal(scripts.length, 1);
  new vm.Script(scripts[0][1]);
  assert.equal(settings({ url: 'http://surge-node-health.invalid.evil.com/' }).result.abort, true);
  assert.equal(settings({ path: '/api/groups', badDetails: true }).result.response.status, 500);
});

test('picker page runs list, save and reload interactions without typing group names', async () => {
  // Execute the actual inline UI against the actual handler. The minimal DOM
  // supplies browser element methods; this does not simulate Surge interception.
  const storage = {};
  const unsafe = '<img src=x onerror="window.injected=1">';
  const groups = { '🚀 常用节点': ['Tokyo'], [unsafe]: ['Other'] };
  const decisions = { '🚀 常用节点': 'Tokyo', [unsafe]: 'Other' };
  const html = settings().result.response.body;
  const script = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)][0][1];
  const elementsCreated = [];
  class Element {
    constructor(tag) { this.tagName=tag; this.children=[]; this.events={}; this.attributes={}; this.className=''; this.disabled=false; this.text=''; this.classList={ toggle: (name,on) => { const names=this.className.split(' ').filter(n=>n && n!==name);if(on)names.push(name);this.className=names.join(' '); } }; }
    set textContent(value) { this.text=String(value);this.children=[]; }
    get textContent() { return this.text+this.children.map(c=>c.textContent).join(''); }
    get firstElementChild() { return this.children[0]; }
    set innerHTML(_) { throw new Error('Unsafe HTML insertion'); }
    append(...children) { this.children.push(...children); }
    replaceChildren() { this.children=[];this.text=''; }
    setAttribute(key,value) { this.attributes[key]=value; }
    addEventListener(name,fn) { this.events[name]=fn; }
  }
  async function loadUI() {
    const nodes={ groups:new Element('div'),status:new Element('div'),retry:new Element('button') };
    vm.runInNewContext(script, {
      document:{ getElementById:id=>nodes[id], createElement:tag=>{ elementsCreated.push(tag);return new Element(tag); } },
      fetch:async (path,options={})=>{
        const result=settings({ path,method:options.method||'GET',headers:{ Origin:'http://surge-node-health.invalid',...(options.headers||{}) },body:options.body,storage,groups,decisions });
        return { ok:result.result.response.status===200,json:async ()=>result.value };
      }
    });
    await new Promise(resolve=>setImmediate(resolve));
    return nodes;
  }
  let ui=await loadUI();
  assert.equal(ui.groups.children.length,2);
  assert.equal(ui.groups.children[1].firstElementChild.textContent,unsafe);
  ui.groups.children[0].events.click();
  await new Promise(resolve=>setImmediate(resolve));
  assert.match(ui.status.textContent,/已绑定：🚀 常用节点/);
  assert.equal(JSON.parse(storage[SETTINGS_KEY]).group,'🚀 常用节点');
  ui=await loadUI();
  assert.equal(ui.groups.children[0].attributes['aria-pressed'],'true');
  ui.groups.children[1].events.click();
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(JSON.parse(storage[SETTINGS_KEY]).group,unsafe);
  assert.ok(elementsCreated.every(tag=>['button','strong','small'].includes(tag)));
});

test('reports API returns actual locally saved probes without changing the selected group', async () => {
  const {storage}=await run();
  const before=JSON.stringify(storage);
  const {value,writes,result}=settings({path:'/api/reports',storage});
  assert.equal(value.reports.length,1);
  assert.equal(value.reports[0].mode,'ip');
  assert.match(value.reports[0].details,/IPPure：HTTP 200/);
  assert.equal(result.response.headers['Cache-Control'],'no-store');
  assert.equal(writes,0);
  assert.equal(JSON.stringify(storage),before);
  storage.VB_HEALTH_REPORT_V1_unlock='broken';
  storage.VB_HEALTH_REPORT_V1_latency=JSON.stringify({version:1,mode:'latency',details:'x'.repeat(24001)});
  assert.equal(settings({path:'/api/reports',storage}).value.reports.length,1);
});

test('details page renders cached diagnostics as plain text and refreshes without probing', async () => {
  const {storage}=await run({policies:{proxies:['<img src=x onerror=alert(1)>'],'policy-groups':['Group']},decisions:{Group:'<img src=x onerror=alert(1)>'},expectedPolicy:'<img src=x onerror=alert(1)>'});
  const html=settings({path:'/reports'}).result.response.body;
  assert.match(html,/href="\/"/);
  assert.doesNotMatch(html,/innerHTML|<script[^>]+src=/);
  const script=[...html.matchAll(/<script>([\s\S]*?)<\/script>/g)][0][1];
  const created=[];
  class Element {
    constructor(tag){this.tag=tag;this.children=[];this.events={};this.text='';}
    set textContent(value){this.text=String(value);this.children=[];}
    get textContent(){return this.text+this.children.map(c=>c.textContent).join('');}
    set innerHTML(_){throw new Error('Unsafe HTML insertion');}
    append(...children){this.children.push(...children);}
    replaceChildren(){this.children=[];this.text='';}
    addEventListener(name,fn){this.events[name]=fn;}
  }
  const nodes={reports:new Element('div'),reload:new Element('button')};
  let reads=0;
  vm.runInNewContext(script,{document:{getElementById:id=>nodes[id],createElement:tag=>{created.push(tag);return new Element(tag);}},
    fetch:async path=>{assert.equal(path,'/api/reports');reads++;return {ok:true,json:async()=>settings({path,storage}).value};}});
  await new Promise(resolve=>setImmediate(resolve));
  assert.match(nodes.reports.textContent,/<img src=x onerror=alert\(1\)>/);
  assert.match(nodes.reports.textContent,/IPPure：HTTP 200/);
  await nodes.reload.events.click();
  assert.equal(reads,2);
  assert.ok(created.every(tag=>['article','h2','small','pre'].includes(tag)));
});


function copyUI(storage,options={}) {
  const served=settings({url:'http://192.0.2.1/copy',storage});
  assert.equal(served.result.response.status,200);
  assert.equal(served.groupReads,0);
  const html=served.result.response.body;
  const encoded=html.match(/<textarea\b[^>]*>([\s\S]*?)<\/textarea>/)[1];
  const plain=encoded.replace(/&#39;/g,"'").replace(/&quot;/g,'"').replace(/&gt;/g,'>').replace(/&lt;/g,'<').replace(/&amp;/g,'&');
  const nodes={
    'report-text':{value:plain,focus(){this.focused=true;},select(){this.selected=true;},setSelectionRange(start,end){this.selection=[start,end];}},
    'copy-report':{disabled:/id="copy-report"[^>]* disabled/.test(html),events:{},addEventListener(name,fn){this.events[name]=fn;}},
    'select-report':{disabled:/id="select-report"[^>]* disabled/.test(html),events:{},addEventListener(name,fn){this.events[name]=fn;}},
    'copy-status':{textContent:''}
  };
  const copied=[];
  const script=html.match(/<script>([\s\S]*?)<\/script>/)[1];
  vm.runInNewContext(script,{
    window:{isSecureContext:!!options.secure},navigator:options.navigator||{},
    document:{getElementById:id=>nodes[id],execCommand:options.noExec?undefined:command=>{
      assert.equal(command,'copy');assert.ok(nodes['report-text'].focused&&nodes['report-text'].selected);
      assert.deepEqual(nodes['report-text'].selection,[0,plain.length]);
      if(options.execThrows)throw new Error('Clipboard unavailable');
      if(options.execResult!==false)copied.push(plain);
      return options.execResult!==false;
    }},
    fetch:()=>{throw new Error('Copy page must not make a network request');}
  });
  return {html,nodes,copied,plain,served};
}

test('literal-IP copy and text endpoints read the complete latest report without group access or writes', async () => {
  const {storage}=await run({mode:'latency',directoryReply:{status:403},reply:()=>({status:404})});
  const before=JSON.stringify(storage);
  const view=copyUI(storage);
  const plain=settings({url:'http://192.0.2.1/reports.txt',storage});
  assert.equal(plain.result.response.headers['Content-Type'],'text/plain; charset=utf-8');
  assert.equal(plain.result.response.body,view.plain);
  assert.match(view.plain,/广州三网延迟/);
  assert.match(view.plain,/HTTP 403/);
  assert.match(view.plain,/HTTP 404/);
  assert.ok(view.plain.length>700,'export must include all native pages');
  assert.equal(plain.groupReads,0);
  assert.equal(plain.writes,0);
  assert.deepEqual(view.copied,[],'no copying until the user clicks');
  view.nodes['copy-report'].events.click();
  assert.deepEqual(view.copied,[plain.result.response.body]);
  assert.match(view.nodes['copy-status'].textContent,/已复制全文/);
  assert.equal(JSON.stringify(storage),before);
});

test('copy page safely embeds literal text including textarea/script delimiters and preserves masked IPs', async () => {
  const {storage}=await run();
  const report=JSON.parse(storage.VB_HEALTH_REPORT_V1_ip);
  report.details+='\n</textarea><script>globalThis.unsafe=true</script>&lt; "quotes" & \'single\' 🇯🇵';
  storage.VB_HEALTH_REPORT_V1_ip=JSON.stringify(report);
  const view=copyUI(storage);
  assert.equal((view.html.match(/<textarea\b/g)||[]).length,1);
  assert.equal((view.html.match(/<script>/g)||[]).length,1);
  assert.ok(!view.html.includes('<script>globalThis.unsafe'));
  assert.ok(view.plain.endsWith(report.details));
  assert.match(view.plain,/203\.0\.\*\.\*/);
  assert.doesNotMatch(view.plain,/203\.0\.113\.7/);
  view.nodes['copy-report'].events.click();
  assert.equal(view.copied[0],view.plain);
});

test('HTTP copy fallback reports failure truthfully and leaves selectable text when browser copying is blocked', () => {
  const storage={VB_HEALTH_REPORT_V1_latency:JSON.stringify({version:1,mode:'latency',title:'广州三网延迟',build:'test',updatedAt:1,details:'HTTP 404'})};
  for(const options of [{execResult:false},{execThrows:true},{noExec:true}]) {
    const view=copyUI(storage,options);
    view.nodes['copy-report'].events.click();
    assert.match(view.nodes['copy-status'].textContent,/未能自动复制/);
    assert.doesNotMatch(view.nodes['copy-status'].textContent,/已复制/);
    assert.ok(view.nodes['report-text'].selected);
    assert.deepEqual(view.copied,[]);
    view.nodes['select-report'].events.click();
    assert.match(view.nodes['copy-status'].textContent,/已选中全文/);
  }
});

test('secure-context clipboard success and rejection both keep the exact full export text', async () => {
  const storage={VB_HEALTH_REPORT_V1_latency:JSON.stringify({version:1,mode:'latency',title:'广州三网延迟',build:'test',updatedAt:1,details:'HTTP 404'})};
  const saved=[];
  const success=copyUI(storage,{secure:true,navigator:{clipboard:{writeText:value=>{saved.push(value);return Promise.resolve();}}}});
  success.nodes['copy-report'].events.click();
  await new Promise(resolve=>setImmediate(resolve));
  assert.deepEqual(saved,[success.plain]);
  assert.deepEqual(success.copied,[]);
  assert.match(success.nodes['copy-status'].textContent,/已复制全文/);
  const fallback=copyUI(storage,{secure:true,navigator:{clipboard:{writeText:()=>Promise.reject(new Error('Denied'))}}});
  fallback.nodes['copy-report'].events.click();
  await new Promise(resolve=>setImmediate(resolve));
  assert.deepEqual(fallback.copied,[fallback.plain]);
  assert.match(fallback.nodes['copy-status'].textContent,/已复制全文/);
});

test('literal-IP export origin cannot read group listings or mutate group binding', () => {
  const storage={[SETTINGS_KEY]:JSON.stringify({version:1,group:'Group'})};
  const before=JSON.stringify(storage);
  for(const path of ['/api/select','/api/groups','/unrelated']) {
    const response=settings({url:'http://192.0.2.1'+path,method:path==='/api/select'?'POST':'GET',body:JSON.stringify({group:'🚀 常用节点'}),storage});
    assert.ok([404,405].includes(response.result.response.status));
    assert.equal(response.groupReads,0);
    assert.equal(response.writes,0);
  }
  for(const url of ['http://192.0.2.11/copy','http://192.0.2.1.evil.com/copy','https://192.0.2.1/copy','http://192.0.2.1:8080/copy','http://user@192.0.2.1/copy']) {
    assert.equal(settings({url,storage}).result.abort,true);
  }
  assert.equal(JSON.stringify(storage),before);
});

test('empty copy page disables copy/select actions and serves a readable plain text explanation', () => {
  const view=copyUI({});
  assert.equal(view.nodes['copy-report'].disabled,true);
  assert.equal(view.nodes['select-report'].disabled,true);
  view.nodes['copy-report'].events.click();
  assert.deepEqual(view.copied,[]);
  assert.match(view.plain,/暂无检测记录/);
  assert.match(settings({url:'http://192.0.2.1/reports.txt'}).result.response.body,/暂无检测记录/);
});
