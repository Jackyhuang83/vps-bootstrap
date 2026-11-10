#!/usr/bin/env python3
"""Regression checks: fscarmen official WARP installer lives inside SS2022 menu."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
SH = ROOT / "ss2022.sh"
SOURCE = SH.read_text()


class FscarmenWarpMenuTests(unittest.TestCase):
    def function_text(self, name, next_name):
        start = name + "() {"
        end = next_name + "() {"
        self.assertEqual(SOURCE.count(start), 1)
        self.assertEqual(SOURCE.count(end), 1)
        return SOURCE.split(start, 1)[1].split(end, 1)[0]

    def test_upstream_url_mode_and_precautions(self):
        body = self.function_text("ss2022_fscarmen_warp_ipv4",
                                  "ss2022_fscarmen_warp_manage")
        self.assertIn("https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh", body)
        self.assertIn('bash "$tmp" 4', body)
        self.assertIn('bash -n "$tmp"', body)
        self.assertIn('sha256sum "$tmp"', body)
        self.assertIn('[[ "$yes" != YES ]]', body)
        self.assertIn('if grep -qx \'warp=on\'', body)
        self.assertIn('curl -6fsS --noproxy', body)
        self.assertIn('curl -4fsS --noproxy', body)
        self.assertIn('ip -4 route show default', body)
        self.assertIn('command -v warp-cli', body)
        self.assertIn('/etc/wireguard/warp.conf', body)
        self.assertIn('rm -f "$tmp"', body)
        self.assertNotIn("curl | bash", body)
        self.assertNotIn("wget | bash", body)

    def test_existing_upstream_management_is_explicit(self):
        body = self.function_text("ss2022_fscarmen_warp_manage",
                                  "ss2022_ipv6_first_stable_menu")
        self.assertIn('warpbin=$(type -P warp || true)', body)
        self.assertIn('[[ "$yes" == YES ]]', body)
        self.assertIn('"$warpbin"', body)

    def test_numbered_menu_dispatch_matches_labels(self):
        menu = self.function_text("ss2022_ipv6_first_stable_menu",
                                  "routing_management")
        for phrase in (
            "3. fscarmen 一键安装系统 WARP IPv4",
            "4. fscarmen WARP 官方管理菜单",
            "5. 一键启用 SS2022 IPv6 优先",
            "6. 恢复菜单启用前配置",
            "请选择 [0-6]",
            "3) ss2022_fscarmen_warp_ipv4; pause ;;",
            "4) ss2022_fscarmen_warp_manage; pause ;;",
            "5)",
            "6)",
        ):
            self.assertIn(phrase, menu)

    def test_old_warp_proxy_menu_not_merged_into_upstream_installer(self):
        body = self.function_text("warp_management", "chain_add_shadowsocks")
        self.assertIn('warp_install_client', body)
        self.assertNotIn('ss2022_fscarmen_warp_ipv4', body)

    def test_bash_syntax(self):
        p = subprocess.run(["bash", "-n", str(SH)],
                           text=True, capture_output=True)
        self.assertEqual(p.returncode, 0, p.stderr)

    def test_already_healthy_v4_short_circuits_upstream(self):
        # A deliberate safe mock: no upstream download or route change occurs.
        code = (
            "export SS2022_LIB_ONLY=1; source ./ss2022.sh; "
            "PLATFORM_PKG=apt; PLATFORM_INIT=systemd; "
            "ip() { return 0; }; "
            "curl() { if [[ \"$1\" == -4fsS ]]; then printf 'warp=on\\n'; fi; return 0; }; "
            "ss2022_fscarmen_warp_ipv4"
        )
        # The runner need not be root: this isolated script only tests static
        # pass-through when EUID is 0, so it can be skipped under runner uid.
        if subprocess.run(["id", "-u"], capture_output=True, text=True).stdout.strip() != "0":
            self.skipTest("root required for healthy-path shell test")
        p = subprocess.run(["bash", "-c", code], cwd=ROOT,
                           capture_output=True, text=True, timeout=20)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("无需重复安装", p.stdout)


if __name__ == "__main__":
    unittest.main()
