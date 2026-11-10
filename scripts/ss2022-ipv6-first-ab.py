#!/usr/bin/env python3
"""A/B validate IPv6-first sing-box 1.13 direct dialing; apply ONLY if proven.

Uses two isolated SOCKS listeners on 127.0.0.1, no production inbound secrets,
no changes to WARP, SSH or routes. Optional --apply is guarded by a successful
runtime A/B result, full-config check, owned backup and automatic service rollback.
"""
import copy
import datetime
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

PROD = Path("/etc/sing-box/config.json")
BIN = Path("/usr/local/bin/sing-box")
UNIT = "sing-box"
OLD_RESOLVE = {"action": "resolve", "server": "local-dns", "strategy": "prefer_ipv6"}


def cmd(argv, timeout=20):
    try:
        return sp.run(argv, capture_output=True, text=True, timeout=timeout, check=False)
    except sp.TimeoutExpired:
        return sp.CompletedProcess(argv, 124, "", "timeout")


def ip_family(raw):
    try:
        return "IPv" + str(ipaddress.ip_address(raw.strip()).version)
    except ValueError:
        return "ERROR"


def pick_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def check(path):
    p = cmd([str(BIN), "check", "-c", str(path)], 20)
    return p.returncode == 0, (p.stderr or p.stdout)[-500:]


def trial(conf, name, work):
    port = pick_port()
    conf = copy.deepcopy(conf)
    conf["inbounds"] = [{
        "type": "socks", "tag": "local-ab",
        "listen": "127.0.0.1", "listen_port": port
    }]
    path = work / (name + ".json")
    logpath = work / (name + ".log")
    path.write_text(json.dumps(conf, ensure_ascii=False, indent=2) + "\n")
    ok, error = check(path)
    if not ok:
        print("SKIP:", name, "sing-box check:", error)
        return None
    with logpath.open("w+") as log:
        proc = sp.Popen([str(BIN), "run", "-c", str(path)],
                        stdin=sp.DEVNULL, stdout=log, stderr=sp.STDOUT)
        try:
            up = False
            for _ in range(40):
                if proc.poll() is not None:
                    break
                try:
                    with socket.create_connection(("127.0.0.1", port), 0.2):
                        up = True
                        break
                except OSError:
                    time.sleep(0.15)
            if not up:
                log.flush()
                log.seek(0)
                print("SKIP:", name, "isolated process failed:", log.read()[-350:])
                return None
            results = {}
            for label, url in [("dual", "https://api64.ipify.org"),
                               ("ipv4only", "https://api4.ipify.org")]:
                args = ["curl", "-fsS", "--noproxy", "", "--connect-timeout", "5",
                        "--max-time", "12", "--proxy",
                        "socks5h://127.0.0.1:" + str(port), url]
                p = cmd(args, 16)
                results[label] = ip_family(p.stdout) if p.returncode == 0 else "ERROR"
                print("TEST:", name, label, results[label],
                      p.stdout.strip() if p.returncode == 0 else (p.stderr or "")[-150:])
            return results
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except sp.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=3)


def make_probe(prod, candidate):
    return {
        "log": {"level": "warn"},
        "dns": copy.deepcopy(prod.get("dns", {})),
        "route": {"rules": copy.deepcopy(
            prod.get("route", {}).get("rules", []) if not candidate else []),
                  "final": "direct"},
        "outbounds": [{"type": "direct", "tag": "direct", **(
            {"domain_strategy": "prefer_ipv6"} if candidate else {})}]
    }


def atomic_replace(path, raw):
    stat = path.stat()
    fd, temp = tempfile.mkstemp(prefix=".ss2022-v6fix-", dir=path.parent)
    try:
        os.fchmod(fd, stat.st_mode & 0o7777)
        os.fchown(fd, stat.st_uid, stat.st_gid)
        with os.fdopen(fd, "wb") as file:
            file.write(raw)
            file.flush()
            os.fsync(file.fileno())
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def apply_fix(conf, work):
    if os.geteuid() != 0:
        print("STOP: --apply requires root")
        return 2
    if cmd(["systemctl", "is-active", "--quiet", UNIT]).returncode:
        print("STOP: production sing-box is not active")
        return 2
    outs = conf.get("outbounds", [])
    rules = conf.get("route", {}).get("rules", [])
    if len(outs) != 1 or outs[0].get("type") != "direct" or outs[0].get("tag") != "direct":
        print("STOP: nonstandard outbound set; no automatic changes")
        return 2
    if rules != [OLD_RESOLVE]:
        print("STOP: production route differs from the previous helper; refuse to change other rules")
        return 2
    if "domain_strategy" in outs[0]:
        print("STOP: outbound domain_strategy already customized")
        return 2
    original = PROD.read_bytes()
    new = copy.deepcopy(conf)
    new["outbounds"][0]["domain_strategy"] = "prefer_ipv6"
    new["route"]["rules"] = []
    candidate = work / "production-candidate.json"
    candidate.write_text(json.dumps(new, ensure_ascii=False, indent=2) + "\n")
    ok, error = check(candidate)
    if not ok:
        print("STOP: full production candidate check failed:", error)
        return 2
    # Do not overwrite a changed config after testing.
    if PROD.read_bytes() != original:
        print("STOP: production config changed during testing")
        return 2
    bdir = Path("/var/backups/vps-bootstrap-ipv6-first")
    bdir.mkdir(mode=0o700, parents=True, exist_ok=True)
    backup = bdir / ("ab-fix-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S") + ".json")
    with backup.open("xb") as handle:
        handle.write(original)
    os.chmod(backup, 0o600)
    try:
        atomic_replace(PROD, candidate.read_bytes())
        p = cmd(["systemctl", "restart", UNIT], 40)
        time.sleep(2)
        if p.returncode or cmd(["systemctl", "is-active", "--quiet", UNIT]).returncode:
            raise RuntimeError("production sing-box restart failed")
        print("APPLY_SUCCESS: sing-box IPv6 first enabled; original backup:", backup)
        print("NOTICE: vps-bootstrap routing regeneration may overwrite this setting.")
        return 0
    except Exception as exc:
        print("ROLLBACK:", str(exc))
        atomic_replace(PROD, original)
        p = cmd(["systemctl", "restart", UNIT], 40)
        print("ROLLBACK_PASS" if p.returncode == 0 else "ROLLBACK_NEEDS_MANUAL_REVIEW")
        return 3


def main():
    if not PROD.is_file() or not BIN.is_file() or not shutil.which("curl"):
        print("STOP: production sing-box config/binary/curl missing")
        return 2
    conf = json.loads(PROD.read_text())
    if not isinstance(conf, dict) or not isinstance(conf.get("dns", {}), dict):
        print("STOP: invalid production config")
        return 2
    if conf.get("route", {}).get("rules", []) != [OLD_RESOLVE]:
        print("STOP: unexpected production route rules; no automated A/B rewrite")
        return 2
    print("CORE:", cmd([str(BIN), "version"]).stdout.splitlines()[0:1])
    with tempfile.TemporaryDirectory(prefix="ss2022-v6-ab-") as td:
        work = Path(td)
        baseline = trial(make_probe(conf, False), "baseline-resolve", work)
        candidate = trial(make_probe(conf, True), "direct-prefer-v6", work)
        if baseline is None or candidate is None:
            print("VERDICT: UNSUPPORTED; no production changes")
            return 2
        print("RESULT: baseline", baseline, "candidate", candidate)
        if candidate.get("dual") == "IPv6" and candidate.get("ipv4only") == "IPv4":
            print("VERDICT: CANDIDATE_PASS")
            if baseline.get("dual") == "IPv6":
                print("INFO: baseline already selects IPv6 in isolated test; production not changed.")
                return 0
            if "--apply" in sys.argv[1:]:
                return apply_fix(conf, work)
            print("INFO: Candidate solves IPv6-first. Run with --apply to apply guarded fix.")
            return 0
        print("VERDICT: CANDIDATE_FAIL; no production changes")
        return 2


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print("STOP:", type(exc).__name__, str(exc))
        sys.exit(2)
