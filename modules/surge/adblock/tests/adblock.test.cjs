'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const moduleText = fs.readFileSync(path.join(__dirname, '..', 'adblock.sgmodule'), 'utf8');
const readmeText = fs.readFileSync(path.join(__dirname, '..', 'README.md'), 'utf8');
const lines = moduleText.split(/\r?\n/);
const section = lines.filter(line => /^\[[^\]]+\]$/.test(line));
const rawRules = lines.filter(line => /^(DOMAIN|DOMAIN-SUFFIX|DOMAIN-KEYWORD|IP-CIDR|IP-ASN|AND|OR|URL-REGEX|RULE-SET),/.test(line));
const rules = rawRules.map(line => {
  const [kind, hostname, action, ...extras] = line.split(',');
  return { kind, hostname, action, extras };
});
const matches = (host) => {
  const hostname = host.toLowerCase();
  return rules.some(rule => rule.kind === 'DOMAIN'
    ? hostname === rule.hostname
    : hostname === rule.hostname || hostname.endsWith('.' + rule.hostname));
};

test('the standalone module consists exclusively of local domain rejection rules', () => {
  assert.deepEqual(section, ['[Rule]']);
  assert.equal(rules.length, 50);
  assert.ok(moduleText.includes('#\u0021name=VPS Bootstrap'));
  for (const rule of rules) {
    assert.ok(['DOMAIN', 'DOMAIN-SUFFIX'].includes(rule.kind), rule.kind);
    assert.equal(rule.action, 'REJECT');
    assert.deepEqual(rule.extras, []);
    assert.match(rule.hostname, /^(?=.{4,253}$)[a-z0-9-]+(?:\.[a-z0-9-]+)+$/);
    assert.ok(!rule.hostname.startsWith('-'));
  }
});

test('every rule is unique and targets a specific advertiser endpoint or provider', () => {
  const seen = new Set();
  for (const rule of rules) {
    const id = rule.kind + ':' + rule.hostname.toLowerCase();
    assert.ok(!seen.has(id), 'duplicate: ' + id);
    seen.add(id);
  }
  const forbiddenSuffixes = ['com', 'cn', 'net', 'qq.com', 'tencent.com', 'baidu.com',
    'taobao.com', 'zijieapi.com', 'bytecdn.cn', 'douyin.com', 'snssdk.com',
    'google.com', 'cloudflare.com', 'wxs.qq.com', 'music.163.com'];
  for (const rule of rules.filter(rule => rule.kind === 'DOMAIN-SUFFIX')) {
    assert.ok(!forbiddenSuffixes.includes(rule.hostname), rule.hostname);
  }
});

test('known independent advertising domains and subdomains are blocked', () => {
  for (const host of ['ad.tencentmusic.com', 'tmead.y.qq.com', 'ads5-normal.zijieapi.com',
    'mobads.baidu.com', 'foo.pangle.io', 'ads.1rtb.net',
    'creative.googlesyndication.com', 'ads.adkwai.com', 'ad.cyapi.cn',
    'adashx.m.taobao.com', 'adx-api.zdmimg.com']) {
    assert.ok(matches(host), 'expected to block ' + host);
  }
});

test('first-party API, sign-in, push, CDN, streaming and node test targets are not blocked', () => {
  for (const host of [
    'api.openai.com', 'chatgpt.com', 'api.cloudflare.com',
    'api.pinduoduo.com', 'm.taobao.com', 'trade.taobao.com',
    'wxa.wxs.qq.com', 'tpns.qq.com', 'jpush.cn', 'getui.com', 'mob.com',
    'security.snssdk.com', 'i.snssdk.com', 'api.douyin.com', 'douyin.com',
    'music.163.com', 'video.qq.com', 'api.bilibili.com',
    'www.baidu.com', 'pan.baidu.com', 'api.cyapi.cn',
    'dlcv2.cnspeedtest.cn', 'ad.12306.cn'
  ]) assert.ok(!matches(host), 'must not block ' + host);
});

test('nothing can decrypt HTTPS, run remote code, rewrite bodies, route DIRECT, or block IP ranges', () => {
  assert.doesNotMatch(moduleText, /^\[(?:MITM|Script|Body Rewrite|Map Local|URL Rewrite|Host|General)\]$/m);
  assert.doesNotMatch(moduleText, /^(?:[A-Z-]+),[^\n]*,(?:DIRECT|PROXY|REJECT-DROP),/m);
  assert.doesNotMatch(moduleText, /^\s*(?:script-path|hostname\s*=|force-http-engine-hosts|skip-server-cert-verify|certificate)\b/im);
  assert.ok(!rawRules.some(rule => /IP-(?:CIDR|ASN)|URL-REGEX|DOMAIN-KEYWORD|RULE-SET|AND|OR/.test(rule)));
  assert.doesNotMatch(moduleText, /^\s*(?:https:\/\/|http:\/\/)[^\n]+$/m);
});

test('documentation identifies it as optional and explains the limits and rollback', () => {
  assert.match(readmeText, /单独安装/);
  assert.match(readmeText, /关闭|禁用/);
  assert.match(readmeText, /MITM/);
  assert.match(readmeText, /不会|无法/);
  assert.match(readmeText, /Blockads\.sgmodule/);
  assert.match(readmeText, /adblock\.sgmodule/);
  assert.match(readmeText, /Surge/);
});

test('current Surge node-health is not imported, overridden, or implicitly enabled', () => {
  assert.doesNotMatch(moduleText, /VB-Health-|surge-node-health|ss2022\.sh|@import|^#!include=/m);
});
