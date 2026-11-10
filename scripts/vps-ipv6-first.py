#!/usr/bin/env python3
# vps-bootstrap: IPv6-first egress (IPv4 via existing system WARP).
# This does NOT install WARP or change routes/ports/credentials.
import datetime as dt
import hashlib
import json
import os
import pathlib as pl
import re
import shutil
import subprocess as sp
import sys
import tempfile
import time

BACKUPS = pl.Path("/var/backups/vps-bootstrap-ipv6-first")
SERVICES = {
    "sing-box": ("/etc/sing-box/config.json", "/usr/local/bin/sing-box"),
    "ss2022-xray": ("/etc/ss2022-xray/config.json", "/usr/local/lib/ss2022/xray"),
    "ss2022-hy2": ("/etc/ss2022-hy2/config.json", "/usr/local/lib/ss2022/hysteria"),
    "snell-v6": ("/etc/ss2022-snell-v6/config.conf", "/usr/local/bin/snell-server-v6"),
    "snell-v5": ("/etc/snell/snell-v5.conf", "/usr/local/bin/snell-server-v5"),
}

def run(*args):
    return sp.run(args, capture_output=True, text=True, check=False)

def digest(raw):
    return hashlib.sha256(raw).hexdigest()

def active(unit):
    return run("systemctl", "is-active", "--quiet", unit).returncode == 0

def test_network():
    if run("ip", "-6", "route", "get", "2606:4700:4700::1111").returncode:
        raise RuntimeError("原生 IPv6 路由不可用")
    for fam, label, expected in (("-6", "IPv6 原生", "off"), ("-4", "IPv4 WARP", "on")):
        r = run("curl", fam, "--noproxy", "*", "-fsS", "--connect-timeout", "5",
                "--max-time", "12", "https://www.cloudflare.com/cdn-cgi/trace")
        if r.returncode != 0 or ("warp=" + expected) not in r.stdout.splitlines() or not re.search(r"^ip=\S+", r.stdout, re.M):
            raise RuntimeError(label + " 出口校验失败，未修改任何配置")
        print("PASS:", label, "HTTPS 正常")

def transform(unit, raw):
    if unit in ("snell-v5", "snell-v6"):
        if "[snell-server]" not in raw:
            raise ValueError("Snell 配置结构不匹配")
        key, value = ("ipv6", "true") if unit == "snell-v5" else ("dns-ip-preference", "prefer-ipv6")
        lines = raw.splitlines(keepends=True)
        in_section = False
        found = False
        for index, line in enumerate(lines):
            match = re.match(r"^\s*\[([^]]+)\]", line)
            if match:
                in_section = match.group(1) == "snell-server"
            if in_section and re.match(r"^\s*" + re.escape(key) + r"\s*=", line):
                lines[index] = key + " = " + value + "\n"
                found = True
        if not found:
            index = next(i for i, line in enumerate(lines) if line.strip() == "[snell-server]")
            lines.insert(index + 1, key + " = " + value + "\n")
        return "".join(lines)
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise ValueError("JSON 根节点不是 object")
    outs = data.get("outbounds", [])
    if unit == "sing-box":
        # Compatible with cores which reject direct.domain_resolver.
        # Route resolve is evaluated on domain destinations; existing route
        # matches retain precedence, while unmatched requests use IPv6-first.
        targets = [x for x in outs if x.get("type") == "direct" and x.get("tag") == "direct"]
        if not targets:
            raise ValueError("找不到 direct 出站，不修改")
        for x in targets:
            if x.get("detour") or x.get("inet4_bind_address") or x.get("inet6_bind_address"):
                raise ValueError("direct 存在自定义绑定，拒绝覆盖")
            # Remove the invalid key only if it was produced by the previous helper.
            resolver = x.get("domain_resolver")
            if resolver is not None:
                if resolver == {"server": "local-dns", "strategy": "prefer_ipv6"}:
                    del x["domain_resolver"]
                else:
                    raise ValueError("direct 有自定义 domain_resolver，拒绝覆盖")
        dns = data.setdefault("dns", {})
        if not isinstance(dns, dict):
            raise ValueError("DNS 配置不是 object，不修改")
        servers = dns.setdefault("servers", [])
        if not isinstance(servers, list):
            raise ValueError("DNS servers 不是数组，不修改")
        local = [x for x in servers if isinstance(x, dict) and x.get("tag") == "local-dns"]
        if not local:
            servers.append({"type": "local", "tag": "local-dns", "prefer_go": True})
        elif len(local) != 1 or local[0].get("type") != "local":
            raise ValueError("local-dns 已被自定义或重复使用，拒绝覆盖")
        # Existing explicit per-rule address family decisions are untouched.
        dns["strategy"] = "prefer_ipv6"
        route = data.setdefault("route", {})
        if not isinstance(route, dict):
            raise ValueError("route 不是 object，不修改")
        rules = route.setdefault("rules", [])
        if not isinstance(rules, list):
            raise ValueError("route.rules 不是数组，不修改")
        has_resolve = any(isinstance(x, dict) and x.get("action") == "resolve" for x in rules)
        if not has_resolve:
            rules.append({"action": "resolve", "server": "local-dns", "strategy": "prefer_ipv6"})
    elif unit == "ss2022-xray":
        targets = [x for x in outs if x.get("protocol") == "freedom" and x.get("tag") in ("route-direct", "direct")]
        if not targets:
            raise ValueError("找不到 Freedom direct 出站")
        for x in targets:
            old = x.get("streamSettings", {}).get("sockopt", {}).get("domainStrategy", "AsIs")
            if old not in ("AsIs", "UseIPv6v4"):
                raise ValueError("存在定制 sockopt 域名策略，不覆盖")
            x.setdefault("settings", {})["domainStrategy"] = "UseIPv6v4"
    elif unit == "ss2022-hy2":
        if "outbounds" not in data:
            data["outbounds"] = [{"name": "direct", "type": "direct", "direct": {"mode": "64"}}]
        else:
            if not isinstance(outs, list):
                raise ValueError("outbounds 格式错误")
            targets = [x for x in outs if x.get("type") == "direct"]
            if not targets:
                raise ValueError("HY2 没有 direct 出站，跳过")
            for x in targets:
                d = x.setdefault("direct", {})
                if any(d.get(k) for k in ("bindIPv4", "bindIPv6", "bindDevice")):
                    raise ValueError("HY2 direct 出站存在绑定，不覆盖")
                d["mode"] = "64"
    return json.dumps(data, ensure_ascii=False, indent=2) + "\n"

def write_atomic(path, data):
    st = path.stat()
    fd, tmp = tempfile.mkstemp(prefix=".vps-ipv6-first.", dir=path.parent)
    try:
        os.fchmod(fd, st.st_mode & 0o7777)
        os.fchown(fd, st.st_uid, st.st_gid)
        with os.fdopen(fd, "wb") as out:
            out.write(data)
            out.flush()
            os.fsync(out.fileno())
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

def validate(unit, binary, path):
    if unit == "sing-box":
        p = run(binary, "check", "-c", str(path))
    elif unit == "ss2022-xray":
        p = run(binary, "run", "-test", "-config", str(path))
    else:
        return True
    if p.returncode:
        print("SKIP:", unit, "语法检查失败", (p.stderr or p.stdout)[-400:])
    return p.returncode == 0

def backup_apply():
    test_network()
    route = pl.Path("/etc/ss2022/routing.json")
    if route.exists() and json.loads(route.read_text()).get("global_ip_family", "default") != "default":
        raise RuntimeError("工具箱全局地址族被强制指定，请先改回 default")
    changes = []
    for unit, (name, binary) in SERVICES.items():
        p = pl.Path(name)
        if not p.is_file() or not pl.Path(binary).is_file() or not active(unit):
            continue
        old = p.read_bytes()
        try:
            new = transform(unit, old.decode("utf-8")).encode("utf-8")
        except (ValueError, json.JSONDecodeError) as e:
            print("SKIP:", unit, e)
            continue
        if new == old:
            print("OK:", unit, "已采用目标策略")
            continue
        fd, tmp = tempfile.mkstemp(prefix=".vps-ipv6-test.", dir=p.parent)
        os.close(fd)
        try:
            pl.Path(tmp).write_bytes(new)
            if not validate(unit, binary, pl.Path(tmp)):
                continue
        finally:
            os.unlink(tmp)
        changes.append((unit, p, old, new))
    if not changes:
        print("完成：没有需要修改的运行中服务")
        return
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    target = BACKUPS / stamp
    target.mkdir(parents=True, mode=0o700, exist_ok=False)
    manifest = []
    for unit, p, old, new in changes:
        shutil.copy2(p, target / (unit + ".bak"))
        manifest.append({"unit": unit, "path": str(p), "new_sha256": digest(new)})
    manifest_path = target / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
    manifest_path.chmod(0o600)
    touched = []
    try:
        for unit, p, old, new in changes:
            write_atomic(p, new)
            touched.append((unit, p, old))
            r = run("systemctl", "restart", unit)
            time.sleep(2)
            if r.returncode or not active(unit):
                raise RuntimeError(unit + " 重启后未处于 active")
            print("PASS:", unit, "IPv6 优先已应用")
        test_network()
    except Exception:
        print("WARN: 检测到故障，自动恢复已经更改的配置")
        for unit, p, old in reversed(touched):
            write_atomic(p, old)
            run("systemctl", "restart", unit)
            print("ROLLBACK:", unit)
        raise
    print("SUCCESS: 代理 IPv6 优先；IPv4 通过系统 WARP")
    print("备份:", target)
    print("注意：Snell v5 仅开启 IPv6 支持，不能严格指定 IPv6 优先。")

def rollback():
    options = sorted(x for x in BACKUPS.glob("20*") if (x / "manifest.json").is_file() and not (x / "restored").exists())
    if not options:
        raise RuntimeError("没有可用的历史备份")
    source = options[-1]
    manifest = json.loads((source / "manifest.json").read_text())
    for entry in manifest:
        path = pl.Path(entry["path"])
        if not path.is_file() or digest(path.read_bytes()) != entry["new_sha256"]:
            raise RuntimeError(str(path) + " 已变化；拒绝覆盖后续手动配置")
        if not (source / (entry["unit"] + ".bak")).is_file():
            raise RuntimeError("备份不完整")
    for entry in reversed(manifest):
        unit, path = entry["unit"], pl.Path(entry["path"])
        write_atomic(path, (source / (unit + ".bak")).read_bytes())
        p = run("systemctl", "restart", unit)
        time.sleep(2)
        if p.returncode or not active(unit):
            raise RuntimeError(unit + " 原配置已写回，但服务需人工检查")
        print("RESTORED:", unit)
    (source / "restored").write_text("ok\n")
    print("ROLLBACK_PASS: 已恢复原始配置")

def main():
    if os.geteuid() != 0 or not pl.Path("/run/systemd/system").exists():
        raise RuntimeError("仅支持 root 下的 Debian/Ubuntu systemd")
    op = sys.argv[1] if len(sys.argv) > 1 else "apply"
    if op == "apply":
        backup_apply()
    elif op == "rollback":
        rollback()
    else:
        raise RuntimeError("用法: apply|rollback")

if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print("STOP:", exc, file=sys.stderr)
        sys.exit(1)
