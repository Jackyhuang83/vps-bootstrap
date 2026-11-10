#!/usr/bin/env python3
"""Offline regression tests for the reusable SS2022 IPv6-first menu."""
import copy
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "scripts" / "ss2022-ipv6-first-stable.py"
SPEC = importlib.util.spec_from_file_location("ipv6_first_stable", HELPER)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class StableBaselineTests(unittest.TestCase):
    def sample(self):
        return {
            "dns": {"servers": [{"tag": "local-dns", "address": "local"}]},
            "inbounds": [{"type": "shadowsocks", "tag": "ss-in", "method": "test-secret"}],
            "outbounds": [
                {"type": "direct", "tag": "direct"},
                {"type": "socks", "tag": "route-other", "server": "127.0.0.1"}
            ],
            "route": {
                "rules": [
                    copy.deepcopy(MODULE.OLD_HELPER_RULE),
                    {"action": "sniff", "timeout": "300ms"},
                    {"domain_suffix": ["example.com"], "outbound": "route-other"}
                ],
                "final": "direct"
            }
        }

    def test_only_direct_modified_and_previous_helper_removed(self):
        initial = self.sample()
        original = copy.deepcopy(initial)
        result = MODULE.build_candidate(initial)
        self.assertEqual(initial, original, "input should not be mutated")
        self.assertEqual(result["outbounds"][0]["domain_strategy"], "prefer_ipv6")
        self.assertEqual(result["outbounds"][1], initial["outbounds"][1])
        self.assertEqual(result["inbounds"], initial["inbounds"])
        self.assertNotIn(MODULE.OLD_HELPER_RULE, result["route"]["rules"])
        self.assertEqual(len(result["route"]["rules"]), 2)
        self.assertEqual(result["route"]["final"], "direct")

    def test_idempotent_and_no_extra_changes(self):
        initial = self.sample()
        initial["route"]["rules"] = [{"action": "sniff", "timeout": "300ms"}]
        once = MODULE.build_candidate(initial)
        twice = MODULE.build_candidate(once)
        self.assertEqual(once, twice)
        self.assertEqual(len(twice["route"]["rules"]), 1)

    def test_unknown_custom_strategy_is_rejected(self):
        initial = self.sample()
        initial["outbounds"][0]["domain_strategy"] = "ipv4_only"
        with self.assertRaisesRegex(RuntimeError, "其他地址族策略"):
            MODULE.build_candidate(initial)

    def test_missing_direct_is_rejected(self):
        initial = self.sample()
        initial["outbounds"] = []
        with self.assertRaisesRegex(RuntimeError, "唯一 direct"):
            MODULE.build_candidate(initial)

    def test_binding_is_not_overridden(self):
        initial = self.sample()
        initial["outbounds"][0]["bind_interface"] = "eth0"
        with self.assertRaisesRegex(RuntimeError, "自定义绑定"):
            MODULE.build_candidate(initial)

    def test_embedded_script_is_exactly_the_tested_source(self):
        shell = (ROOT / "ss2022.sh").read_text()
        start = "python3 - \"\u0024{1:-status}\" <<'SS2022_IPV6_FIRST_STABLE_PY'\n"
        self.assertEqual(shell.count(start), 1)
        embedded = shell.split(start, 1)[1].split("\nSS2022_IPV6_FIRST_STABLE_PY\n", 1)[0]
        self.assertEqual(embedded.rstrip(), HELPER.read_text().rstrip())

    def test_no_global_route_edits(self):
        source = HELPER.read_text()
        for needle in ("warp-cli", "ip route add", "ip -4 route add", "iptables -", "nft add"):
            self.assertNotIn(needle, source)


if __name__ == "__main__":
    unittest.main()
