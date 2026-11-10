#!/usr/bin/env python3
"""vps-bootstrap SS2022 native IPv6-first, WARP-IPv4 fallback.

Runs in-process from the ss2022.sh menu. No installer, network download, node
credential access or global route manipulation. Python 3 standard library only.
"""
import copy
import datetime as dt
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess as sp
import sys
import tempfile
import time

CONF = Path("/etc/sing-box/config.json")
CORE = Path("/usr/local/bin/sing-box")
BACKUPS = Path("/var/backups/vps-bootstrap-ipv6-first")
STATE = Path("/etc/ss2022/ipv6-first-stable.json")
OLD_HELPER_RULE = {"action": "resolve", "server": "local-dns", "strategy": "prefer_ipv6"}
SERVICE = "sing-box"


def run(args, timeout=20):
    try:
        return sp.run(args, capture_output=True, text=True, timeout=timeout, check=False)
    except sp.TimeoutExpired:
        return sp.CompletedProcess(args, 124, "", "timeout")


def stop(message):
    raise RuntimeError(message)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def ip_family(raw):
    try:
        return "IPv" + str(ipaddress.ip_address(raw.strip()).version)
    except ValueError:
        return "ERROR"


def service_active():
    return run(["systemctl", "is-active", "--quiet", SERVICE]).returncode == 0


def load_config():
    if not CONF.is_file() or not CORE.is_file():
        stop("未安装 sing-box 或缺少原配置，未修改")
    conf = json.loads(CONF.read_text(encoding="utf-8"))
    if not isinstance(conf, dict):
        stop("sing-box JSON 配置结构异常，未修改")
    return conf


def direct_entry(conf):
    outs = conf.get("outbounds")
    if not isinstance(outs, list):
        stop("outbounds 缺失或不是数组，未修改")
    hits = [item for item in outs if isinstance(item, dict) and
            item.get("type") == "direct" and item.get("tag") == "direct"]
    if len(hits) != 1:
        stop("未找到唯一 direct 出站，拒绝修改自定义结构")
    direct = hits[0]
    if any(k in direct for k in ("detour", "inet4_bind_address", "inet6_bind_address",
                                "bind_interface", "routing_mark")):
        stop("direct 出站存在自定义绑定/路由，拒绝覆盖")
    if direct.get("domain_strategy") not in (None, "prefer_ipv6"):
        stop("direct 已设置其他地址族策略，拒绝覆盖")
    return direct


def network_check():
    if not shutil.which("curl") or not shutil.which("ip"):
        stop("缺少 curl/ip，未修改")
    if run(["ip", "-6", "route", "get", "2606:4700:4700::1111"]).returncode:
        stop("没有可用的原生 IPv6 路由，未修改")
    for fam, expected in (("-6", "off"), ("-4", "on")):
        result = run(["curl", fam, "--noproxy", "*", "-fsS", "--connect-timeout", "5",
                      "--max-time", "12", "https://www.cloudflare.com/cdn-cgi/trace"], 16)
        if result.returncode or ("warp=" + expected) not in result.stdout.splitlines():
            stop("IPv6 原生 / IPv4 WARP 实测不符合预期，未修改系统路由")
    print("PASS: IPv6 原生 + WARP IPv4 系统出口")


def pick_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def check_config(path):
    result = run([str(CORE), "check", "-c", str(path)], 22)
    return result.returncode == 0, (result.stderr or result.stdout)[-500:]


def run_trial(original, new_strategy):
    """Isolated localhost SOCKS instance, without production inbound/secrets."""
    port = pick_port()
    test = {
        "log": {"level": "warn"},
        "dns": copy.deepcopy(original.get("dns", {})),
        "route": {"final": "direct"},
        "inbounds": [{"type": "socks", "tag": "ipv6-first-test",
                      "listen": "127.0.0.1", "listen_port": port}],
        "outbounds": [{"type": "direct", "tag": "direct"}]
    }
    if new_strategy:
        test["outbounds"][0]["domain_strategy"] = "prefer_ipv6"
    else:
        rules = original.get("route", {}).get("rules", [])
        if isinstance(rules, list) and OLD_HELPER_RULE in rules:
            test["route"]["rules"] = [copy.deepcopy(OLD_HELPER_RULE)]
    with tempfile.TemporaryDirectory(prefix="ss2022-ipv6-first-ab-") as root:
        config = Path(root) / "isolated.json"
        log_file = Path(root) / "service.log"
        config.write_text(json.dumps(test, ensure_ascii=False, indent=2) + "\n")
        valid, error = check_config(config)
        if not valid:
            stop("独立候选配置不兼容当前 sing-box：" + error)
        with log_file.open("w+") as handle:
            proc = sp.Popen([str(CORE), "run", "-c", str(config)],
                            stdin=sp.DEVNULL, stdout=handle, stderr=sp.STDOUT)
            try:
                ready = False
                for _ in range(40):
                    if proc.poll() is not None:
                        break
                    try:
                        with socket.create_connection(("127.0.0.1", port), timeout=.2):
                            ready = True
                            break
                    except OSError:
                        time.sleep(.15)
                if not ready:
                    handle.flush()
                    handle.seek(0)
                    stop("独立测试实例启动失败：" + handle.read()[-400:])
                result = {}
                for label, url in (("dual", "https://api64.ipify.org"),
                                   ("ipv4only", "https://api4.ipify.org")):
                    reply = run(["curl", "-fsS", "--noproxy", "",
                                 "--connect-timeout", "5", "--max-time", "12",
                                 "--proxy", f"socks5h://127.0.0.1:{port}", url], 16)
                    result[label] = ip_family(reply.stdout) if reply.returncode == 0 else "ERROR"
                return result
            finally:
                if proc.poll() is None:
                    proc.terminate()
                    try:
                        proc.wait(timeout=5)
                    except sp.TimeoutExpired:
                        proc.kill()
                        proc.wait(timeout=3)


def build_candidate(original):
    target = copy.deepcopy(original)
    direct_entry(target)["domain_strategy"] = "prefer_ipv6"
    route = target.get("route")
    if isinstance(route, dict) and isinstance(route.get("rules"), list):
        # Remove exactly the obsolete rule created by our earlier helper;
        # leave all other user routing rules untouched.
        route["rules"] = [r for r in route["rules"] if r != OLD_HELPER_RULE]
    return target


def atomic_write(path, raw):
    stat = path.stat()
    fd, tmp = tempfile.mkstemp(prefix=".ss2022-ipv6-first-", dir=path.parent)
    try:
        os.fchmod(fd, stat.st_mode & 0o7777)
        os.fchown(fd, stat.st_uid, stat.st_gid)
        with os.fdopen(fd, "wb") as output:
            output.write(raw)
            output.flush()
            os.fsync(output.fileno())
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def write_private(path, data):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with path.open("xb") as file:
        file.write(data)
    path.chmod(0o600)


def version():
    return run([str(CORE), "version"]).stdout.splitlines()[:1]


def status():
    if not CONF.is_file() or not CORE.is_file():
        print("状态: 未安装 sing-box")
        return 0
    conf = load_config()
    print("sing-box:", version())
    print("服务:", "Running" if service_active() else "Stopped")
    outs = conf.get("outbounds", [])
    direct = [x for x in outs if isinstance(x, dict) and
              x.get("type") == "direct" and x.get("tag") == "direct"]
    current = direct[0].get("domain_strategy", "default") if len(direct) == 1 else "UNKNOWN"
    print("SS2022 direct 出站:", current)
    print("策略: IPv6 优先 / IPv4-only 走系统路由" if current == "prefer_ipv6"
          else "策略: 未启用本功能或存在自定义配置")
    print("菜单备份:", str(STATE) if STATE.exists() else "无（可能由外部脚本配置）")
    return 0


def precheck():
    if os.geteuid() != 0:
        stop("需要 root")
    conf = load_config()
    direct_entry(conf)
    if not service_active():
        stop("sing-box 服务未运行")
    if Path("/etc/ss2022/routing.json").is_file():
        routing = json.loads(Path("/etc/ss2022/routing.json").read_text())
        if routing.get("global_ip_family", "default") != "default":
            stop("工具箱全局地址族不是 default；请先改回默认（不能强制 IPv4/IPv6）")
    network_check()
    candidate = build_candidate(conf)
    with tempfile.TemporaryDirectory(prefix="ss2022-ipv6-validate-", dir=CONF.parent) as folder:
        path = Path(folder) / "candidate.json"
        path.write_text(json.dumps(candidate, ensure_ascii=False, indent=2) + "\n")
        valid, error = check_config(path)
        if not valid:
            stop("正式候选配置语法检查失败（当前核心可能不支持此参数）：" + error)
    test = run_trial(conf, True)
    print("PASS: A/B 独立实例 IPv6-first 候选结果", test)
    if test.get("dual") != "IPv6" or test.get("ipv4only") != "IPv4":
        stop("候选实例未同时通过双栈 IPv6 / IPv4-only IPv4，未修改")
    return conf, candidate


def enable():
    config = load_config()
    direct = direct_entry(config)
    if direct.get("domain_strategy") == "prefer_ipv6":
        print("STABLE_BASELINE: 该 VPS 已启用 IPv6 优先；没有修改配置或重启服务")
        return 0
    old_config, candidate = precheck()
    original = CONF.read_bytes()
    if CONF.read_bytes() != original:
        stop("正式配置在预检期间已变化")
    new_bytes = (json.dumps(candidate, ensure_ascii=False, indent=2) + "\n").encode()
    if original == new_bytes:
        print("STABLE_BASELINE: 已是目标配置")
        return 0
    now = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = BACKUPS / ("menu-" + now + ".json")
    write_private(backup, original)
    applied = False
    try:
        atomic_write(CONF, new_bytes)
        applied = True
        restart = run(["systemctl", "restart", SERVICE], 40)
        time.sleep(2)
        if restart.returncode or not service_active():
            stop("sing-box 重启失败")
        network_check()
        # Mark only successful menu-managed changes; do not overwrite old records.
        STATE.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        if STATE.is_file():
            previous = json.loads(STATE.read_text())
            if previous.get("applied_sha256") != sha(original):
                print("NOTICE: 存在较旧回滚记录，已保留备份但不覆盖旧记录")
            else:
                STATE.unlink()
        if not STATE.exists():
            write_private(STATE, json.dumps({
                "backup": str(backup), "applied_sha256": sha(new_bytes)
            }, ensure_ascii=False).encode())
        print("APPLY_SUCCESS: SS2022 默认直连 IPv6 优先，IPv4-only 经系统 WARP")
        print("BACKUP:", backup)
        print("提示: 特殊分流规则仍按各自显式设置执行")
        return 0
    except Exception:
        if applied:
            print("ROLLBACK: 正在恢复原始 sing-box 配置")
            atomic_write(CONF, original)
            r = run(["systemctl", "restart", SERVICE], 40)
            print("ROLLBACK_PASS" if r.returncode == 0 and service_active()
                  else "ROLLBACK_NEEDS_MANUAL_REVIEW")
        raise


def rollback():
    if not STATE.is_file():
        stop("本菜单未保存回滚记录；不会覆盖手动创建的稳定基线")
    info = json.loads(STATE.read_text())
    backup = Path(info.get("backup", ""))
    if not str(backup).startswith(str(BACKUPS) + os.sep) or not backup.is_file():
        stop("备份文件缺失或路径不受管理，拒绝恢复")
    if sha(CONF.read_bytes()) != info.get("applied_sha256"):
        stop("正式配置已被其他操作更新，为避免覆盖分流变化，不自动回滚")
    old = backup.read_bytes()
    with tempfile.TemporaryDirectory(prefix="ss2022-ipv6-rollback-", dir=CONF.parent) as folder:
        check_path = Path(folder) / "original.json"
        check_path.write_bytes(old)
        valid, error = check_config(check_path)
        if not valid:
            stop("历史备份与当前核心不兼容，拒绝恢复：" + error)
    latest = CONF.read_bytes()
    try:
        atomic_write(CONF, old)
        r = run(["systemctl", "restart", SERVICE], 40)
        time.sleep(2)
        if r.returncode or not service_active():
            stop("恢复原配置后 sing-box 未启动")
    except Exception:
        atomic_write(CONF, latest)
        run(["systemctl", "restart", SERVICE], 40)
        raise
    STATE.unlink()
    print("RESTORE_SUCCESS: 已恢复菜单启用前 sing-box 配置")
    print("历史备份保留:", backup)
    return 0


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "status"
    if action == "status":
        return status()
    if action == "precheck":
        precheck()
        print("PRECHECK_PASS: 未修改正式配置或重启服务")
        return 0
    if action == "enable":
        return enable()
    if action == "rollback":
        return rollback()
    stop("有效命令: status | precheck | enable | rollback")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print("STOP:", exc, file=sys.stderr)
        sys.exit(1)
