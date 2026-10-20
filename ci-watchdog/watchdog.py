#!/usr/bin/env python3
"""Central GitHub Actions CI watchdog for all authorized repositories.

Run by a one-minute systemd timer on a private VPS. Notifications begin at
5 minutes and repeat at 5-minute intervals until a run terminates.
Pure Python stdlib. No GitHub actions are triggered, cancelled, or modified.
"""
from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request

UTC = dt.timezone.utc
FIVE_MINUTES = 300
ONE_MINUTE = 60
TERMINAL = {"completed"}
DEFAULT_REPOS = (
    "Jackyhuang83/vps-bootstrap",
    "Jackyhuang83/MiniProbe",
    "Jackyhuang83/HomeSphere",
    "Jackyhuang83/NodeShell",
    "Jackyhuang83/F50-Proxy",
)


def timestamp(value: str | None) -> float:
    if not value:
        return 0.0
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()


def elapsed_label(seconds: float) -> str:
    m = max(0, int(seconds)) // 60
    return f"{m // 60}小时{m % 60}分" if m >= 60 else f"{m}分"


class GitHub:
    def __init__(self, token: str):
        if not token:
            raise ValueError("CI_WATCHDOG_READ_TOKEN is required")
        self.token = token

    def request(self, method: str, uri: str, data: dict | None = None) -> object:
        url = "https://api.github.com" + uri
        headers = {
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {self.token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "ci-watchdog/1.0",
        }
        payload = None
        if data is not None:
            payload = json.dumps(data, ensure_ascii=False).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(url, data=payload, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                body = response.read(2_000_000)
                return json.loads(body) if body else {}
        except urllib.error.HTTPError as error:
            # Never print request headers, tokens, or API response bodies.
            raise RuntimeError(f"GitHub API HTTP {error.code} at {uri.split('?')[0]}") from None
        except urllib.error.URLError as error:
            raise RuntimeError(f"GitHub API network failure at {uri.split('?')[0]}: {error.reason}") from None

    def discover_repos(self, owner: str) -> list[str]:
        found = []
        for page in range(1, 11):
            data = self.request("GET", f"/user/repos?affiliation=owner&per_page=100&page={page}")
            if not isinstance(data, list):
                raise RuntimeError("Unexpected repository discovery response")
            for item in data:
                name = str(item.get("full_name", ""))
                if not item.get("archived") and name.lower().startswith(owner.lower() + "/"):
                    found.append(name)
            if len(data) < 100:
                break
        return sorted(set(found))

    def recent_runs(self, repo: str, now: float) -> list[dict]:
        # All recently created workflows, including in progress, queued, cancelled,
        # failed and successful. Do not hide CI jobs on secondary branches.
        since = dt.datetime.fromtimestamp(now - 24 * 3600, UTC).strftime("%Y-%m-%d")
        quoted = urllib.parse.quote(repo, safe="/")
        out = []
        for page in range(1, 4):
            qs = urllib.parse.urlencode({"per_page": "100", "page": page, "created": f">={since}"})
            data = self.request("GET", f"/repos/{quoted}/actions/runs?{qs}")
            runs = data.get("workflow_runs")
            if not isinstance(runs, list):
                raise RuntimeError(f"Invalid workflow run response for {repo}")
            out.extend(runs)
            if len(runs) < 100:
                break
        return out

    def current_step(self, repo: str, run_id: int) -> str:
        quoted = urllib.parse.quote(repo, safe="/")
        data = self.request("GET", f"/repos/{quoted}/actions/runs/{run_id}/jobs?per_page=100")
        jobs = data.get("jobs", [])
        if not isinstance(jobs, list):
            return "步骤状态不可用"
        for job in jobs:
            if job.get("conclusion") in ("failure", "timed_out", "cancelled"):
                problem = next((s for s in job.get("steps", [])
                                if s.get("conclusion") in ("failure", "timed_out", "cancelled")), None)
                return "失败步骤：" + str((problem or job).get("name", "未知"))
        for job in jobs:
            if job.get("status") == "in_progress":
                step = next((s for s in job.get("steps", [])
                             if s.get("status") == "in_progress"), None)
                return "进行中：" + str((step or job).get("name", "未知"))
        if any(job.get("status") == "queued" for job in jobs):
            return "任务仍在排队"
        return "任务已结束或正在等待分配执行器"


def describe(run: dict, stage: str, now: float) -> str:
    repo = run["_watch_repo"]
    title = str(run.get("name", "未命名工作流"))
    status = run.get("status", "unknown")
    conclusion = run.get("conclusion") or "unknown"
    seconds = now - timestamp(run.get("created_at"))
    url = str(run.get("html_url", ""))
    if status == "completed":
        zh = {"success": "✅ 成功", "failure": "❌ 失败",
              "timed_out": "⏱ 超时", "cancelled": "⚠️ 取消",
              "skipped": "⏭ 跳过"}.get(conclusion, f"结束：{conclusion}")
    else:
        zh = {"queued": "⏳ 排队中", "in_progress": "🔄 构建中",
              "waiting": "⏳ 等待中", "requested": "⏳ 已请求",
              "pending": "⏳ 待运行"}.get(status, f"进行中：{status}")
    return f"{zh}｜{repo}｜{title}｜累计 {elapsed_label(seconds)}\n{stage}\n{url}"


def select_reports(repos: list[str], runs_by_repo: dict[str, list[dict]],
                   state: dict, now: float, step_lookup) -> tuple[list[str], dict]:
    """A pure decision function except for injected step_lookup.

    Never mark anything as reported unless notification has succeeded; caller
    persists returned state only after successful send.
    """
    updated = dict(state)
    notices: list[str] = []
    for repo in repos:
        for source in runs_by_repo.get(repo, []):
            run = dict(source)
            run["_watch_repo"] = repo
            created = timestamp(run.get("created_at"))
            if not created or created > now + 60 or now - created > 24 * 3600:
                continue
            key = f"{repo}#{run.get('id')}#{run.get('run_attempt', 1)}"
            old = dict(updated.get(key, {}))
            is_done = run.get("status") == "completed"
            age = now - created
            last_sent = float(old.get("last_sent", 0.0))
            if is_done:
                if old.get("terminal"):
                    continue
                # Don't backfill old runs when watchdog is first installed.
                if not old and age > 15 * 60:
                    updated[key] = {"terminal": True, "seen": now, "last_sent": 0.0}
                    continue
                why = "已结束"
            else:
                if age < FIVE_MINUTES or (last_sent and now - last_sent < FIVE_MINUTES):
                    updated.setdefault(key, {"seen": now, "last_sent": 0.0})
                    continue
                why = "超过五分钟，持续监控"
            try:
                stage = step_lookup(repo, int(run["id"]))
            except (RuntimeError, KeyError, ValueError, TypeError) as error:
                stage = f"无法读取任务步骤：{error}"
            notices.append(describe(run, f"{why}；{stage}", now))
            updated[key] = {"seen": now, "last_sent": now, "terminal": is_done}
    # Avoid indefinite state growth. Retain old terminal records for 48 h.
    updated = {k: v for k, v in updated.items()
               if now - float(v.get("seen", 0.0)) < 48 * 3600}
    return notices, updated


def atomic_save(path: Path, value: dict) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8",
                                     dir=path.parent, prefix=".watchdog-",
                                     delete=False) as handle:
        tmp = Path(handle.name)
        os.chmod(tmp, 0o600)
        json.dump(value, handle, ensure_ascii=False, sort_keys=True)
        handle.write("\n")
    os.replace(tmp, path)


def notify(text: str, dry_run: bool) -> None:
    if dry_run:
        print("DRY RUN: no message was sent\n" + text)
        return
    endpoint = os.environ.get("CI_WATCHDOG_NOTIFY", "github_issue")
    if endpoint == "stdout":
        print(text, flush=True)
        return
    if endpoint == "telegram":
        token = os.environ.get("CI_WATCHDOG_TELEGRAM_BOT_TOKEN", "")
        chat = os.environ.get("CI_WATCHDOG_TELEGRAM_CHAT_ID", "")
        if not token or not chat.lstrip("-").isdigit():
            raise RuntimeError("Telegram notification needs BOT_TOKEN and numeric CHAT_ID")
        # Avoid exceeding Telegram's 4096-char limit; do not expose token in logs.
        for start in range(0, len(text), 3500):
            payload = json.dumps({
                "chat_id": chat,
                "text": text[start:start + 3500],
                "disable_web_page_preview": True,
            }, ensure_ascii=False).encode("utf-8")
            request = urllib.request.Request(
                f"https://api.telegram.org/bot{token}/sendMessage",
                data=payload, method="POST",
                headers={"Content-Type": "application/json", "User-Agent": "ci-watchdog/1.0"},
            )
            try:
                with urllib.request.urlopen(request, timeout=15) as response:
                    if not json.loads(response.read(10000)).get("ok"):
                        raise RuntimeError("Telegram API declined the alert")
            except urllib.error.HTTPError as error:
                raise RuntimeError(f"Telegram API HTTP {error.code}; no alert sent") from None
            except urllib.error.URLError:
                raise RuntimeError("Telegram network failure; no alert sent") from None
        print("Sent watchdog notification via Telegram")
        return
    if endpoint != "github_issue":
        raise ValueError("CI_WATCHDOG_NOTIFY must be github_issue, telegram or stdout")
    token = os.environ.get("CI_WATCHDOG_NOTIFY_TOKEN", "")
    owner = os.environ.get("CI_WATCHDOG_OWNER", "Jackyhuang83")
    issue = os.environ.get("CI_WATCHDOG_ISSUE_NUMBER", "")
    report_repo = os.environ.get("CI_WATCHDOG_REPORT_REPO", f"{owner}/vps-bootstrap")
    if not token or not issue.isdecimal():
        raise RuntimeError("Notification not configured: need CI_WATCHDOG_NOTIFY_TOKEN and CI_WATCHDOG_ISSUE_NUMBER")
    # Mention the owner to make GitHub notification routing available.
    body = f"@{owner}\n\n{text}"
    GitHub(token).request("POST", f"/repos/{report_repo}/issues/{issue}/comments", {"body": body})
    print(f"Reported {text.count(chr(10) + chr(10)) + 1} notice block(s) to {report_repo} issue #{issue}")


def run_once(now: float, dry_run: bool) -> None:
    token = os.environ.get("CI_WATCHDOG_READ_TOKEN", "")
    github = GitHub(token)
    owner = os.environ.get("CI_WATCHDOG_OWNER", "Jackyhuang83")
    mode = os.environ.get("CI_WATCHDOG_REPO_MODE", "discover")
    if mode == "discover":
        repos = github.discover_repos(owner)
    elif mode == "explicit":
        raw = os.environ.get("CI_WATCHDOG_REPOS", ",".join(DEFAULT_REPOS))
        repos = [item.strip() for item in raw.split(",") if item.strip()]
    else:
        raise ValueError("CI_WATCHDOG_REPO_MODE must be discover or explicit")
    if not repos:
        raise RuntimeError("No repositories are accessible or configured")

    state_file = Path(os.environ.get("CI_WATCHDOG_STATE", "/var/lib/ci-watchdog/state.json"))
    state_file.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    lock = state_file.with_suffix(".lock")
    with lock.open("a+") as lock_fd:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if state_file.exists():
            state = json.loads(state_file.read_text(encoding="utf-8"))
        else:
            state = {}
        by_repo: dict[str, list[dict]] = {}
        repo_errors: list[str] = []
        for repo in repos:
            try:
                by_repo[repo] = github.recent_runs(repo, now)
            except RuntimeError as error:
                repo_errors.append(f"⚠️ {repo}：监控查询失败：{error}")
                # Never assume a failed query means a build succeeded.
        notices, new_state = select_reports(repos, by_repo, state, now, github.current_step)
        if repo_errors:
            error_key = "__repository_access_errors"
            last_error_report = float(state.get(error_key, {}).get("last_sent", 0.0))
            if now - last_error_report >= FIVE_MINUTES:
                notices.extend(repo_errors)
                new_state[error_key] = {"last_sent": now, "seen": now}
        if notices:
            notify("\n\n---\n\n".join(notices), dry_run=dry_run)
        elif dry_run:
            print("DRY RUN: no build has reached the reporting threshold")
        if not dry_run:
            atomic_save(state_file, new_state)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="inspect without notification/state write")
    args = parser.parse_args()
    try:
        run_once(now=dt.datetime.now(UTC).timestamp(), dry_run=args.dry_run)
    except Exception as error:
        # Never echo credentials from environment.
        print(f"CI-WATCHDOG-ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
