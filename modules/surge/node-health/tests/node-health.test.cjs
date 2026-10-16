// End-to-end Surge runtime contract tests. All responses are synthetic.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '..', 'node-health.js'), 'utf8');

async function run(options = {}) {
  let clock = 0;
  let result;
  let doneCount = 0;
  let sequence = 0;
  const timers = [];
  const requests = [];
  const schedule = (fn, delay = 0) => timers.push({ fn, at: clock + delay, id: ++sequence });
  class Clock extends Date { constructor(...args) { super(...(args.length ? args : [1792123200000 + clock])); } static now() { return clock; } }
  const env = {
    Date: Clock,
    setTimeout: schedule,
    $argument: options.argument || `mode=${options.mode || 'ip'}&showIP=false&policy=Group`,
    $done: value => { result = value; doneCount++; },
    $surge: { selectGroupDetails: () => ({ decisions: options.decisions || { Group: 'Tokyo' } }) },
    $httpAPI: (method, url, body, callback) => {
      assert.equal(method, 'GET');
      assert.equal(url, '/v1/policies');
      if (!options.apiHang) schedule(() => callback(options.policies || { proxies: ['Tokyo', 'Other'], 'policy-groups': ['Group'] }), 1);
    },
    $httpClient: Object.fromEntries(['get', 'post', 'head'].map(method => [method, (config, callback) => {
      const index = requests.length;
      requests.push({ method, ...config });
      const reply = options.reply ? options.reply(config, method, index) : { body: JSON.stringify({ ip: '203.0.113.7', fraudScore: 25, countryCode: 'JP', asn: 64496, isResidential: false }) };
      if (reply === null) return;
      schedule(() => callback(reply.error || null, reply.noResponse ? null : { status: reply.status || 200, headers: reply.headers || {} }, reply.body || ''), reply.delay || 100);
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
  requests.forEach(r => {
    assert.equal(r.policy, options.expectedPolicy || 'Tokyo');
    assert.equal(r['auto-redirect'], false);
    assert.equal(r['auto-cookie'], false);
    assert.ok(r.timeout > 0 && r.timeout <= 6, 'timeouts use seconds');
    assert.equal(r.insecure, undefined);
  });
  return { result, requests, clock };
}

test('zero fraud score stays zero; missing classification is unknown, IP masked', async () => {
  const { result } = await run({ reply: () => ({ body: JSON.stringify({ ip: '203.0.113.7', fraudScore: 0 }) }) });
  assert.match(result.content, /100\/100/);
  assert.match(result.content, /类型：未知/);
  assert.match(result.content, /203\.0\.\*\.\*/);
  assert.doesNotMatch(result.content, /203\.0\.113\.7|原生|机房/);
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
  assert.equal(requests.length, 1);
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
  assert.equal(requests.length, 1);
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

test('latency makes nine HEAD probes, counts responses not packet loss, preserves HTTP errors', async () => {
  const counts = {};
  const { result, requests } = await run({ mode: 'latency', reply: c => {
    const host = new URL(c.url).host;
    counts[host] = (counts[host] || 0) + 1;
    if (host === 'iservice.10010.com' && counts[host] === 2) return null;
    return { status: host === 'www.189.cn' ? 412 : 200, delay: counts[host] * 100 };
  } });
  assert.equal(requests.length, 9);
  assert.ok(requests.every(r => r.method === 'head'));
  assert.match(result.content, /电信：200 ms · 响应 3\/3/);
  assert.match(result.content, /HTTP 412/);
  assert.match(result.content, /联通：200 ms · 响应 2\/3/);
  assert.match(result.content, /范围 100–300 ms/);
  assert.match(result.content, /非 Ping/);
  assert.doesNotMatch(result.content, /丢包/);
});

test('all latency targets timing out finish within the declared script budget', async () => {
  const { result, clock, requests } = await run({ mode: 'latency', reply: () => null });
  assert.equal(requests.length, 9);
  assert.match(result.content, /无响应 0\/3/);
  assert.ok(clock < 20000);
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
  for (const ip of ['::::', 'xyz', '999.1.1.1', '2001:db8:12345::1']) {
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
  assert.match(result.content, /v0\.1\.0-beta\.2/);
});

test('Claude identifies the documented regional redirect without following external hosts', async () => {
  const { result, requests } = await run({ mode: 'unlock', reply: c => c.url.includes('claude.ai')
    ? { status: 302, headers: { Location: 'https://www.anthropic.com/app-unavailable-in-region' } }
    : { body: '<html></html>' } });
  assert.match(result.content, /Claude：地区受限/);
  assert.ok(requests.every(r => !r.url.includes('anthropic.com')));
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

test('module contains only scripts and panels; no capture, MITM, rule or automatic timers', () => {
  const moduleText = fs.readFileSync(path.join(__dirname, '..', 'node-health.sgmodule'), 'utf8');
  assert.deepEqual([...moduleText.matchAll(/^\[([^\]]+)\]/gm)].map(m => m[1]), ['Panel', 'Script']);
  assert.equal((moduleText.match(/update-interval=-1/g) || []).length, 3);
  assert.equal((moduleText.match(/type=generic/g) || []).length, 3);
  assert.doesNotMatch(moduleText, /type=cron|type=event|insecure=true/);
});
