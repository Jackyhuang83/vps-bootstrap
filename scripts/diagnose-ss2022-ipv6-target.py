#!/usr/bin/env python3
"""One-shot, isolated SS2022/sing-box IPv6-first diagnostic.

Starts a SECOND temporary sing-box bound only to 127.0.0.1.
Does not edit production config, routes, DNS, WARP or restart services.
Only reads the production dns+route.resolve configuration; excludes all inbound
credentials, node definitions and production listeners.
"""
import copy
import ipaddress
import json
import pathlib
import shutil
import socket
import subprocess
import sys
import tempfile
import time

BASE = pathlib.Path("/etc/sing-box/config.json")
BIN = pathlib.Path("/usr/local/bin/sing-box")


def out(cmd, timeout=18):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                           check=False)
        return p.returncode, p.stdout.strip(), p.stderr.strip()
    except subprocess.TimeoutExpired:
        return 124, "", "timeout"


def family(value):
    try:
        ip = ipaddress.ip_address(value.strip())
        return f"IPv{ip.version}"
    except ValueError:
        return "UNKNOWN"


def main():
    if not BASE.is_file() or not BIN.is_file() or not shutil.which("curl"):
        print("STOP: missing sing-box config/binary or curl")
        return 1
    conf = json.loads(BASE.read_text())
    direct = [x for x in conf.get("outbounds", [])
              if x.get("type") == "direct" and x.get("tag") == "direct"]
    if len(direct) != 1:
        print("STOP: production direct outbound missing or ambiguous")
        return 1
    rules = conf.get("route", {}).get("rules", [])
    resolve = [r for r in rules if r.get("action") == "resolve"]
    if not resolve:
        print("STOP: production resolve action missing")
        return 1
    # The probe contains no secret or inbound configuration from production.
    test_conf = {
        "log": {"level": "warn"},
        "dns": copy.deepcopy(conf.get("dns", {})),
        "route": {"rules": copy.deepcopy(resolve), "final": "direct"},
        "outbounds": [{"type": "direct", "tag": "direct"}]
    }
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    test_conf["inbounds"] = [{
        "type": "socks", "tag": "one-shot-local-test",
        "listen": "127.0.0.1", "listen_port": port
    }]
    process = None
    with tempfile.TemporaryDirectory(prefix="ss2022-ipv6-diagnose-") as td:
        path = pathlib.Path(td) / "test.json"
        path.write_text(json.dumps(test_conf, ensure_ascii=False))
        rc, stdout, stderr = out([str(BIN), "check", "-c", str(path)])
        if rc:
            print("STOP: isolated sing-box check failed:", (stderr or stdout)[-500:])
            return 1
        print("PASS: isolated config checked; production untouched")
        with open(pathlib.Path(td) / "service.log", "w+") as logfile:
            try:
                process = subprocess.Popen([str(BIN), "run", "-c", str(path)],
                                           stdin=subprocess.DEVNULL,
                                           stdout=logfile, stderr=subprocess.STDOUT)
                up = False
                for _ in range(40):
                    if process.poll() is not None:
                        break
                    try:
                        with socket.create_connection(("127.0.0.1", port), .2):
                            up = True
                            break
                    except (ConnectionRefusedError, OSError, TimeoutError):
                        time.sleep(.15)
                if not up:
                    logfile.seek(0)
                    print("STOP: isolated sing-box failed to start")
                    print(logfile.read()[-500:])
                    return 1
                base = ["curl", "-fsS", "--noproxy", "", "--connect-timeout", "6",
                        "--max-time", "15", "https://api64.ipify.org"]
                # Domain remains a domain in the SOCKS5 request:
                a, aout, aerr = out(base[:-1] + ["--proxy",
                                                  f"socks5h://127.0.0.1:{port}",
                                                  base[-1]], timeout=19)
                # Locally resolves the same hostname to IPv4 before SOCKS5:
                b, bout, berr = out(base[:-1] + ["-4", "--proxy",
                                                  f"socks5://127.0.0.1:{port}",
                                                  base[-1]], timeout=19)
                af = family(aout) if a == 0 else "ERROR"
                bf = family(bout) if b == 0 else "ERROR"
                print(f"TEST_DOMAIN_AS_DOMAIN: {af} ({aout if a == 0 else aerr[-160:]})")
                print(f"TEST_DOMAIN_AS_IPV4: {bf} ({bout if b == 0 else berr[-160:]})")
                if af == "IPv6" and bf == "IPv4":
                    print("VERDICT: SERVER_DOMAIN_STRATEGY_PASS")
                    print("Meaning: when the client forwards a domain, this sing-box config")
                    print("chooses native IPv6; forwarding a literal IPv4 stays on WARP.")
                    print("Surge policy or actual target representation must be checked.")
                    return 0
                if af == "IPv4":
                    print("VERDICT: SERVER_DOMAIN_STRATEGY_FAIL")
                    print("Meaning: even a real domain target selected IPv4.")
                    print("Investigate local DNS resolution and rule behavior on server.")
                    return 2
                print("VERDICT: INCONCLUSIVE; production remains unchanged")
                return 3
            finally:
                if process is not None and process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=3)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print("STOP:", type(exc).__name__, str(exc))
        sys.exit(1)
