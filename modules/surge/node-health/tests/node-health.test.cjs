// End-to-end Surge runtime contract tests. All responses are synthetic.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '..', 'node-health.js'), 'utf8');
const settingsSource = fs.readFileSync(path.join(__dirname, '..', 'settings.js'), 'utf8');
const SETTINGS_KEY = 'VB_HEALTH_SELECTED_GROUP_V1';

async function run(options = {}) {
  let clock = 0;
  let result;
  let doneCount = 0;
  let activeRequests = 0;
  let peakRequests = 0;
  let lateRequests = 0;
  let sequence = 0;
  const timers = [];
  const requests = [];
  const storage = options.storage || {};
  const schedule = (fn, delay = 0) => timers.push({ fn, at: clock + delay, id: ++sequence });
  class Clock extends Date { constructor(...args) { super(...(args.length ? args : [1792123200000 + clock])); } static now() { return clock; } }
  const env = {
    Date: Clock,
    setTimeout: (fn, delay) => schedule(fn, delay === 25000 && options.deadlineMs ? options.deadlineMs : delay),
    $argument: options.argument || `mode=${options.mode || 'ip'}&showIP=false&policy=Group`,
    $done: value => { result = value; doneCount++; },
    $persistentStore: { read: key => Object.hasOwn(storage, key) ? storage[key] : null },
    $surge: { selectGroupDetails: () => ({ decisions: options.decisions || { Group: 'Tokyo' } }) },
    $httpAPI: (method, url, body, callback) => {
      assert.equal(method, 'GET');
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
      const reply = options.reply ? options.reply(config, method, index) : { body: JSON.stringify({ ip: '203.0.113.7', fraudScore: 25, countryCode: 'JP', asn: 64496, isResidential: false }) };
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
  requests.forEach(r => {
    assert.equal(r.policy, options.expectedPolicy || 'Tokyo');
    assert.equal(r['auto-redirect'], false);
    assert.equal(r['auto-cookie'], false);
    assert.ok(r.timeout > 0 && r.timeout <= 6, 'timeouts use seconds');
    assert.equal(r.insecure, undefined);
  });
  return { result, requests, clock, peakRequests };
}

test('zero fraud score stays zero; missing classification is unknown, IP masked', async () => {
  const { result } = await run({ reply: () => ({ body: JSON.stringify({ ip: '203.0.113.7', fraudScore: 0 }) }) });
  assert.match(result.content, /100\/100/);
  assert.match(result.content, /类型：未知/);
  assert.match(result.content, /203\.0\.\*\.\*/);
  assert.doesNotMatch(result.content, /203\.0\.113\.7|原生属性：是|机房：是/);
  assert.match(result.content, /住宅：未知 · 机房：未知 · 原生属性：未验证/);
});

test('missing, null, strings and out-of-range scores never become perfect purity', async () => {
  for (const fraudScore of [undefined, null, '', '0', false, -1, 101]) {
    const { result } = await run({ reply: () => ({ body: JSON.stringify({ ip: '203.0.113.7', fraudScore }) }) });
    assert.match(result.content, /纯净度：未知/);
    assert.doesNotMatch(result.content, /100\/100/);
  }
});

test('IPv6 never receives IPPure score, even when the API sends one', async () => {
  const { result } = await run({ reply: () => ({ body: JSON.stringify({ ip: '2001:db8::1', fraudScore: 0 }) }) });
  assert.match(result.content, /不评估 IPv6/);
  assert.doesNotMatch(result.content, /100\/100/);
});

test('API HTML, rate limiting and absent response become actionable unknown', async () => {
  for (const reply of [{ body: '<html>error</html>' }, { status: 429 }, { error: 'network', noResponse: true }, null]) {
    const { result } = await run({ reply: () => reply });
    assert.equal(result.style, 'alert');
    assert.doesNotMatch(result.content, /100\/100/);
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
  assert.doesNotMatch(result.content, /完整解锁|US|检查通过|网页可达/);
  assert.match(result.content, /未取得有效片库证据/);
  assert.match(result.content, /接口格式变化/);
});

test('unlock: exact Disney session boolean and catalogue markup give bounded conclusions', async () => {
  const { result } = await run({ mode: 'unlock', reply: c => {
    if (c.url.includes('bamgrid')) return { body: JSON.stringify({ extensions: { sdk: { session: { inSupportedLocation: true, location: { countryCode: 'JP' } } } } }) };
    if (c.url.includes('netflix')) return { body: '81280792 {"@type":"TVSeries","countryCode":"JP"}' };
    if (c.url.includes('youtube')) return { body: 'ytcfg.set({"INNERTUBE_CONTEXT_GL":"JP"}); YouTube Premium ad-free' };
    if (c.url.includes('trace')) return { body: 'loc=JP\nip=203.0.113.7' };
    return { body: '<html>ChatGPT Gemini</html>' };
  } });
  assert.match(result.content, /Disney\+：地区检查通过 · JP/);
  assert.match(result.content, /Netflix：授权片样本可见/);
  assert.match(result.content, /ChatGPT：网页可达，待验证对话 · JP/);
  assert.match(result.content, /Gemini：网页可达，待登录验证/);
  assert.doesNotMatch(result.content, /完整解锁|203\.0\.113\.7/);
});

test('unlock: false or missing Disney flags cannot pass', async () => {
  for (const flag of [false, undefined, 'true']) {
    const { result } = await run({ mode: 'unlock', reply: c => c.url.includes('bamgrid') ? { body: JSON.stringify({ extensions: { sdk: { session: { inSupportedLocation: flag } } } }) } : { body: '<html></html>' } });
    assert.doesNotMatch(result.content, /Disney\+：地区检查通过/);
  }
});

test('challenge and timeout are not reported as a regional ban', async () => {
  for (const reply of [{ status: 403, body: '<title>Just a moment</title>cf-chl-' }, null]) {
    const { result } = await run({ mode: 'unlock', reply: () => reply });
    assert.doesNotMatch(result.content, /地区受限|地区不支持|检查通过/);
    assert.match(result.content, /人机验证|超时/);
  }
});

test('latency makes fifteen HEAD probes, counts responses not packet loss, preserves HTTP errors', async () => {
  const counts = {};
  const { result, requests } = await run({ mode: 'latency', reply: c => {
    const host = new URL(c.url).host;
    counts[host] = (counts[host] || 0) + 1;
    if (host === 'iservice.10010.com' && counts[host] === 2) return null;
    return { status: host === 'www.189.cn' ? 412 : 200, delay: counts[host] * 100 };
  } });
  assert.equal(requests.length, 15);
  assert.ok(requests.every(r => r.method === 'head'));
  assert.match(result.content, /电信：300 ms · 响应 5\/5/);
  assert.match(result.content, /HTTP 412/);
  assert.match(result.content, /联通：350 ms · 响应 4\/5/);
  assert.match(result.content, /范围 100–500 ms · HTTP 波动 100 ms/);
  assert.match(result.content, /逐次：100ms\(412\) \/ 200ms\(412\)/);
  assert.match(result.content, /站点拒绝当前请求，已保留响应耗时/);
  assert.match(result.content, /非 Ping/);
  assert.doesNotMatch(result.content, /丢包/);
});

test('all latency targets timing out finish within the declared script budget', async () => {
  const { result, clock, requests } = await run({ mode: 'latency', reply: () => null });
  assert.equal(requests.length, 15);
  assert.match(result.content, /无响应 0\/5/);
  assert.ok(clock < 25000);
});

test('same-origin page redirects retain the node; external redirects are not followed', async () => {
  const { result, requests } = await run({ mode: 'unlock', reply: c => {
    if (c.url === 'https://gemini.google.com/') return { status: 302, headers: { Location: '/app' } };
    if (c.url === 'https://gemini.google.com/app') return { body: '<html>Gemini</html>' };
    if (c.url.includes('netflix')) return { status: 302, headers: { Location: 'https://example.invalid/login' } };
    return { body: '<html></html>' };
  } });
  assert.match(result.content, /Gemini：网页可达/);
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
    assert.doesNotMatch(result.content, /100\/100/);
  }
});

test('all nine platform labels appear with bounded unknown results for generic HTTP 200', async () => {
  const { result } = await run({ mode: 'unlock', reply: () => ({ body: '<html>Welcome</html>' }) });
  for (const platform of ['ChatGPT', 'Gemini', 'Claude', 'Google', 'Netflix', 'Disney+', 'YouTube Premium', 'myTV SUPER', 'TikTok']) {
    assert.ok(result.content.includes(platform + '：'), platform);
  }
  assert.doesNotMatch(result.content, /检查通过|搜索结果可达|网页地区 [A-Z]|完整解锁/);
  assert.match(result.content, /v0\.1\.0-beta\.6/);
});

test('Claude identifies the documented regional redirect without following external hosts', async () => {
  const { result, requests } = await run({ mode: 'unlock', reply: c => c.url.includes('claude.ai')
    ? { status: 302, headers: { Location: 'https://www.anthropic.com/app-unavailable-in-region' } }
    : { body: '<html></html>' } });
  assert.match(result.content, /Claude：地区受限/);
  assert.ok(requests.every(r => new URL(r.url).host !== 'www.anthropic.com'));
});

test('Claude login page is web reachability, never dialogue or API success', async () => {
  const { result } = await run({ mode: 'unlock', reply: c => ({ body: c.url.includes('claude.ai') ? '<html><title>Claude</title>Log in</html>' : '<html></html>' }) });
  assert.match(result.content, /Claude：网页可达，待验证对话/);
  assert.doesNotMatch(result.content, /Claude：.*解锁|Claude：.*对话成功/);
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
    assert.match(result.content, expected);
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
    assert.match(result.content, expected);
    assert.doesNotMatch(result.content, /myTV SUPER：.*可播放|myTV SUPER：.*完整解锁/);
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
    assert.match(result.content, expected);
  }
});

test('new services retain rate-limit, auth and challenge states rather than claiming unlocked', async () => {
  for (const reply of [{ status: 429 }, { status: 401 }, { status: 403, body: '<title>Just a moment</title>cf-chl-' }, null]) {
    const { result } = await run({ mode: 'unlock', reply: () => reply });
    assert.doesNotMatch(result.content, /地区受限|地区检查通过|搜索结果可达|网页地区 [A-Z]/);
    for (const platform of ['Claude', 'Google', 'myTV SUPER', 'TikTok']) assert.ok(result.content.includes(platform + '：'));
  }
});

test('IP sources independently verify the exit and preserve default masking everywhere', async () => {
  const { result, requests } = await run({ reply:c=>({body:c.url.includes('cloudflare')
    ? 'ip=203.0.113.7\nloc=JP\ncolo=NRT\nwarp=on'
    :JSON.stringify({ip:'203.0.113.7',fraudScore:15,country:'Japan',countryCode:'JP',isResidential:false,isDataCenter:true})}) });
  assert.equal(requests.length,3);
  assert.match(result.content,/3 个来源 IP 一致/);
  assert.match(result.content,/WARP 已启用/);
  assert.match(result.content,/接入点 NRT/);
  assert.match(result.content,/住宅：否 · 机房：是 · 原生属性：未验证/);
  assert.doesNotMatch(result.content,/203\.0\.113\.7/);
  assert.match(result.content,/IPPure：HTTP 200 · 100 ms/);
});

test('different destination exits are disclosed and scores stay attached to IPPure', async () => {
  const { result } = await run({ reply:c=>c.url.includes('ippure')?{body:JSON.stringify({ip:'203.0.113.7',fraudScore:10})}
    :c.url.includes('ip.sb')?{body:JSON.stringify({ip:'198.51.100.8',fraudScore:0})}:{body:'ip=2001:db8::1\nloc=JP\nwarp=off'} });
  assert.equal(result.style,'alert');
  assert.match(result.content,/不同站点出口不一致/);
  assert.match(result.content,/纯净度参考：90\/100/);
  assert.match(result.content,/IP\.SB：HTTP 200 · 100 ms · 198\.51\.\*\.\*/);
  assert.doesNotMatch(result.content,/203\.0\.113\.7|198\.51\.100\.8|2001:db8::1|100\/100/);
});

test('IP lookup falls back to remaining sources without inventing a risk score', async () => {
  const { result } = await run({reply:c=>c.url.includes('ippure')?{status:429}:c.url.includes('ip.sb')
    ?{body:JSON.stringify({ip:'203.0.113.8',country:'Japan',asn:64496,asn_organization:'Example ISP',fraudScore:0})}
    :{body:'ip=203.0.113.8\nloc=JP\ncolo=NRT\nwarp=off'}});
  assert.match(result.content,/主信息来源 IP\.SB/);
  assert.match(result.content,/ASN：64496 · Example ISP/);
  assert.match(result.content,/纯净度：未知/);
  assert.match(result.content,/IPPure：HTTP 429/);
  assert.doesNotMatch(result.content,/100\/100/);
});

test('equivalent IPv6 spellings agree without scoring or claiming dual-stack coverage', async () => {
  const { result }=await run({reply:c=>({body:c.url.includes('cloudflare')?'ip=2001:db8::1\nloc=JP'
    :JSON.stringify({ip:c.url.includes('ippure')?'2001:0db8:0:0:0:0:0:1':'2001:db8::1',fraudScore:0})})});
  assert.match(result.content,/3 个来源 IP 一致/);
  assert.match(result.content,/IPPure 不评估 IPv6/);
  assert.doesNotMatch(result.content,/100\/100|双栈通过|出口不一致/);
});

test('GeoIP country disagreements are distinguished from different exit IPs', async () => {
  const { result }=await run({reply:c=>({body:c.url.includes('cloudflare')?'ip=203.0.113.7\nloc=US'
    :JSON.stringify({ip:'203.0.113.7',countryCode:'JP',fraudScore:10})})});
  assert.match(result.content,/3 个来源 IP 一致/);
  assert.match(result.content,/地区库差异：JP \/ US（IP 一致，地区资料不同）/);
  assert.doesNotMatch(result.content,/出口不一致/);
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
  for(const name of ['OpenAI API','Claude API','Gemini API'])assert.match(result.content,new RegExp(name+'：HTTP (401|403) · 100 ms · 入口可达，需 API Key'));
  assert.match(result.content,/App 入口：HTTP 302 · 100 ms · 转到官方登录入口/);
  assert.match(result.content,/API 认证响应仅证明入口可达，不等于调用通过/);
  assert.ok(requests.every(r=>!Object.keys(r.headers).some(h=>/authorization|x-api-key|cookie/i.test(h))||r.url.includes('bamgrid')));
  const denied=await run({mode:'unlock',reply:()=>({status:401,body:'<html>Denied</html>'})});
  assert.doesNotMatch(denied.result.content,/入口可达，需 API Key/);
});

test('an API-only country rejection does not overwrite a reachable ChatGPT website', async () => {
  const { result }=await run({mode:'unlock',reply:c=>c.url.includes('api.openai.com')
    ?{status:403,body:JSON.stringify({error:{code:'unsupported_country_region_territory'}})}
    :{body:'<html>ChatGPT</html>'}});
  assert.match(result.content,/ChatGPT：网页可达，待验证对话/);
  assert.match(result.content,/OpenAI API：HTTP 403 · 100 ms · 地区受限/);
  assert.doesNotMatch(result.content,/ChatGPT：地区受限/);
});

test('Gemini records its own runtime region and absent flags remain inconclusive', async () => {
  const enabled=await run({mode:'unlock',reply:c=>({body:c.url.includes('gemini.google.com')
    ?'<html>Gemini [45631641,null,true] [0,2,1,200,"JPN"]</html>':'<html></html>'})});
  assert.match(enabled.result.content,/Gemini：网页功能标志已启用，待登录验证 · JPN/);
  const absent=await run({mode:'unlock',reply:c=>({body:c.url.includes('gemini.google.com')?'<html>Gemini</html>':'<html></html>'})});
  assert.match(absent.result.content,/Gemini：网页可达，待登录验证/);
  assert.doesNotMatch(absent.result.content,/Gemini：地区受限|Gemini：地区不支持/);
});

test('Gemini API auth classification requires a matching service, not any JSON 403', async () => {
  for(const metadata of [{service:'another.googleapis.com'},{}]) {
    const { result }=await run({mode:'unlock',reply:c=>c.url.includes('generativelanguage.googleapis.com')
      ?{status:403,body:JSON.stringify({error:{status:'PERMISSION_DENIED',details:[{reason:'CREDENTIALS_MISSING',metadata}]}})}:{body:'<html></html>'}});
    assert.doesNotMatch(result.content,/Gemini API：[^\n]*入口可达/);
  }
});

test('Netflix separates two unavailable regional samples from its visible original sample', async () => {
  const { result }=await run({mode:'unlock',reply:c=>c.url.includes('netflix.com/title/')
    ?c.url.endsWith('80018499')?{body:'80018499 {"@type":"TVSeries","countryCode":"JP"}'}:{status:404}
    :{body:'<html></html>'}});
  assert.match(result.content,/Netflix：仅自制片样本可见（两个授权样本不可见） · JP/);
  assert.match(result.content,/授权样本 81280792：HTTP 404/);
  assert.match(result.content,/授权样本 70143836：HTTP 404/);
  assert.doesNotMatch(result.content,/完整解锁/);
});

test('Netflix CDN checks only an allowlisted HTTPS target with HEAD and hides its query', async () => {
  const target='https://ipv4-c001-nrt001-example.1.oca.nflxvideo.net/speedtest/range/0-0?secret=ephemeral';
  const { result,requests }=await run({mode:'unlock',reply:c=>c.url.includes('api.fast.com')
    ?{body:JSON.stringify({targets:[{url:target,location:{country:'JP',city:'Tokyo'}}]})}
    :{status:200,body:'<html></html>'}});
  assert.ok(requests.some(r=>r.url===target&&r.method==='head'&&r.policy==='Tokyo'));
  assert.match(result.content,/CDN 连接：HTTP 200 · 100 ms · HEAD 响应通过/);
  assert.match(result.content,/CDN 分配：HTTP 200.*nflxvideo.net · JP · Tokyo/);
  assert.doesNotMatch(result.content,/ephemeral|secret=|Netflix：授权片样本可见/);
  for(const url of ['http://x.nflxvideo.net/a','https://127.0.0.1/a','https://x.nflxvideo.net.evil.com/a','https://x.nflxvideo.net@evil.com/a','https://x.nflxvideo.net/a\n']) {
    const checked=await run({mode:'unlock',reply:c=>c.url.includes('api.fast.com')?{body:JSON.stringify({targets:[{url}]})}:{body:'<html></html>'}});
    assert.ok(checked.requests.every(r=>r.url!==url));
  }
});

test('YouTube CDN mapping adds routing evidence without exposing its source IP or proving playback', async () => {
  const { result }=await run({mode:'unlock',reply:c=>({body:c.url.includes('report_mapping')
    ?'203.0.113.7 => example-nrt1 (203.0.113.8)':'<html></html>'})});
  assert.match(result.content,/CDN 调度：HTTP 200 · 100 ms · 标识 example-nrt1/);
  assert.doesNotMatch(result.content,/203\.0\.113\.[78]|YouTube Premium：页面地区检查通过|视频播放通过/);
});

test('DNS, TLS and connection refusal remain distinct in per-probe failures', async () => {
  for(const [error,label] of [['DNS lookup failed','DNS 解析失败'],['TLS certificate invalid','TLS/证书失败'],['connection refused','连接被拒绝']]) {
    const { result }=await run({mode:'unlock',reply:()=>({error,noResponse:true})});
    assert.ok(result.content.includes(label));
    assert.doesNotMatch(result.content,/地区受限|入口可达，需 API Key/);
  }
});

test('deadline retains completed platforms while marking only pending checks unknown', async () => {
  const { result }=await run({mode:'unlock',deadlineMs:1000,reply:c=>c.url.includes('gemini.google.com')
    ?{status:302,headers:{Location:'/app'},delay:2000}
    :{body:c.url.includes('www.google.com')?'<html><div id="search"><h3>Result</h3></div></html>':'<html></html>'}});
  assert.match(result.content,/Google：搜索结果可达/);
  assert.match(result.content,/Gemini：检测尚未完成（总时限）/);
  for(const platform of ['ChatGPT','Gemini','Claude','Google','Netflix','Disney+','YouTube Premium','myTV SUPER','TikTok'])assert.ok(result.content.includes(platform+'：'));
});

test('rate-limit or server error pages cannot turn regional wording into a restriction verdict', async () => {
  for(const status of [429,503]) {
    const { result }=await run({mode:'unlock',reply:()=>({status,body:'<html>Gemini is not supported in your country. Netflix is not available in your country. Claude is not available in your country. forbidden-location</html>'})});
    assert.doesNotMatch(result.content,/：地区受限|：地区不支持/);
    assert.match(result.content,status===429?/请求限流/:/HTTP 503/);
  }
});

test('redirect evidence measures the complete same-origin path', async () => {
  const { result }=await run({mode:'unlock',reply:c=>c.url==='https://gemini.google.com/'
    ?{status:302,headers:{Location:'/app'},delay:150}:c.url==='https://gemini.google.com/app'
    ?{body:'<html>Gemini</html>',delay:250}:{body:'<html></html>'}});
  assert.match(result.content,/Web：HTTP 200 · 400 ms · 跳转 1 次/);
});

test('module adds only local settings interception, host and panels; no capture, MITM or rules', () => {
  const moduleText = fs.readFileSync(path.join(__dirname, '..', 'node-health.sgmodule'), 'utf8');
  assert.deepEqual([...moduleText.matchAll(/^\[([^\]]+)\]/gm)].map(m => m[1]), ['Panel', 'Script', 'Host']);
  assert.equal((moduleText.match(/update-interval=-1/g) || []).length, 3);
  assert.equal((moduleText.match(/type=generic/g) || []).length, 4);
  assert.match(moduleText, /VB-Health-Settings-Entry = script-name=VB-Health-Settings-Entry/);
  assert.equal((moduleText.match(/type=http-request/g) || []).length, 1);
  assert.match(moduleText, /pattern=\^http:\/\/surge-node-health\\\.invalid/);
  assert.match(moduleText, /surge-node-health\.invalid = 192\.0\.2\.1/);
  assert.doesNotMatch(moduleText, /\{\{\{POLICY\}\}\}|#!arguments=POLICY/);
  assert.doesNotMatch(moduleText, /type=cron|type=event|insecure=true/);
});

function settings(options = {}) {
  const storage = options.storage || {};
  let result;
  let writes = 0;
  let done = 0;
  const notifications = [];
  const groups = options.groups || { Group: ['Tokyo', 'Other'], '🚀 常用节点': ['Other'] };
  const decisions = options.decisions || { Group: 'Tokyo', '🚀 常用节点': 'Other' };
  const headers = options.headers === undefined ? { Origin: 'http://surge-node-health.invalid', 'X-VB-Health-Settings': '1', 'Content-Type': 'application/json' } : options.headers;
  vm.runInNewContext(settingsSource, {
    $request: options.panel ? undefined : { url: options.url || 'http://surge-node-health.invalid' + (options.path || '/'), method: options.method || 'GET', headers, body: options.body || '' },
    $trigger: options.trigger,
    $notification: options.noNotifications ? undefined : { post: (...args) => { if(options.notificationThrows) throw new Error('Notification error'); notifications.push(args); } },
    $surge: { selectGroupDetails: () => options.badDetails ? {} : ({ groups, decisions }), setSelectGroupPolicy: () => { throw new Error('Must not change selected node'); } },
    $persistentStore: { read: key => Object.hasOwn(storage, key) ? storage[key] : null, write: (value, key) => { writes++; if(options.writeFail) return false; storage[key] = value; return true; } },
    $done: value => { result = value; done++; }
  }, { timeout: 1000 });
  assert.equal(done, 1);
  assert.ok(result);
  return { result, storage, writes, notifications, value: result.response && result.response.headers['Content-Type'].startsWith('application/json') ? JSON.parse(result.response.body) : undefined };
}

test('panel taps cycle existing groups, save exact names and wrap without notifications', () => {
  const storage = {};
  for (const [name, node, index] of [['Group','Tokyo',1],['🚀 常用节点','Other',2],['Group','Tokyo',1]]) {
    const { result, notifications, writes } = settings({ panel:true, trigger:'button', storage, noNotifications:true });
    assert.equal(result.title,'检测设置');
    assert.ok(result.content.includes('已绑定：'+name));
    assert.ok(result.content.includes('当前选择：'+node));
    assert.ok(result.content.includes('第 '+index+'/2 组'));
    assert.match(result.content,/再点切换到/);
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
      if(binding==='🚀 常用节点') assert.match(result.content,/当前选择：Other/);
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
  for(const mode of ['ip','unlock','latency']) {
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
    assert.doesNotMatch(result.content,/已绑定：🚀 常用节点/);
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
  assert.match(first.result.content,/第 1\/1 组/);
  const second = settings(options);
  assert.equal(second.writes,0);
  assert.match(second.result.content,/仅有这 1 个/);
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
  for (const mode of ['ip', 'unlock', 'latency']) {
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

