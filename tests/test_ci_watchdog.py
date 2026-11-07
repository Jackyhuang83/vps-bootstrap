"""Offline CI-watchdog policy tests; no GitHub credentials or network access."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest

SRC = Path(__file__).resolve().parents[1] / "ci-watchdog" / "watchdog.py"
spec = importlib.util.spec_from_file_location("ci_watchdog", SRC)
assert spec and spec.loader
watch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(watch)

NOW = 1_800_000_000.0


def test_run(identifier=10, start_seconds=0, status="in_progress",
             conclusion=None, name="Build"):
    import datetime as dt
    started = dt.datetime.fromtimestamp(NOW + start_seconds, dt.timezone.utc)
    return {
        "id": identifier,
        "name": name,
        "created_at": started.isoformat().replace("+00:00", "Z"),
        "status": status,
        "conclusion": conclusion,
        "run_attempt": 1,
        "html_url": f"https://github.com/owner/repo/actions/runs/{identifier}",
    }


def select(runs, state, now=NOW, name="owner/repo"):
    return watch.select_reports(
        [name],
        {name: runs},
        state,
        now,
        lambda r, i: "进行中：Kotlin 编译" if i == 10 else "失败步骤：测试",
    )


class WatchdogPolicyTests(unittest.TestCase):
    def test_no_notification_before_five_minutes(self):
        messages, state = select([test_run(start_seconds=-299)], {})
        self.assertEqual([], messages)
        self.assertTrue(state)

    def test_five_ten_fifteen_minute_reports(self):
        item = test_run(start_seconds=-300)
        five, state = select([item], {})
        self.assertEqual(1, len(five))
        self.assertIn("累计 5分", five[0])
        quiet, state = select([item], state, NOW + 299)
        self.assertEqual([], quiet)
        ten, state = select([item], state, NOW + 300)
        self.assertEqual(1, len(ten))
        fifteen, state = select([item], state, NOW + 600)
        self.assertEqual(1, len(fifteen))

    def test_fast_success_reported_once(self):
        item = test_run(start_seconds=-105, status="completed", conclusion="success")
        first, state = select([item], {})
        self.assertIn("✅ 成功", first[0])
        later, state = select([item], state, NOW + 600)
        self.assertEqual([], later)

    def test_failure_reports_stage(self):
        item = test_run(start_seconds=-350, status="completed", conclusion="failure")
        messages, state = select([item], {})
        self.assertIn("❌ 失败", messages[0])
        self.assertIn("失败步骤：", messages[0])
        self.assertTrue(state["owner/repo#10#1"]["terminal"])

    def test_terminal_after_active_report(self):
        item = test_run(start_seconds=-550)
        interim, state = select([item], {})
        self.assertEqual(1, len(interim))
        item["status"] = "completed"
        item["conclusion"] = "cancelled"
        completed, state = select([item], state, NOW + 10)
        self.assertEqual(1, len(completed))
        self.assertIn("取消", completed[0])
        duplicate, _ = select([item], state, NOW + 100)
        self.assertEqual([], duplicate)

    def test_each_project_tracked_independently(self):
        first = test_run(start_seconds=-301)
        second = test_run(identifier=42, start_seconds=-350)
        notices, state = watch.select_reports(
            ["owner/repo", "owner/another"],
            {"owner/repo": [first], "owner/another": [second]},
            {}, NOW, lambda repo, i: f"正在运行：{repo}",
        )
        self.assertEqual(2, len(notices))
        self.assertEqual(2, len(state))
        self.assertTrue(any("owner/another" in notice for notice in notices))

    def test_install_does_not_backfill_old_completed_runs(self):
        item = test_run(start_seconds=-3600, status="completed", conclusion="success")
        notices, state = select([item], {})
        self.assertEqual([], notices)
        self.assertTrue(state["owner/repo#10#1"]["terminal"])

    def test_atomic_state_written_with_owner_only_permissions(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "state.json"
            watch.atomic_save(path, {"hello": 42})
            self.assertEqual('{"hello": 42}\n', path.read_text())
            self.assertEqual(0o600, path.stat().st_mode & 0o777)

    def test_elapsed_label(self):
        self.assertEqual("5分", watch.elapsed_label(300))
        self.assertEqual("1小时6分", watch.elapsed_label(4000))


if __name__ == "__main__":
    unittest.main()
