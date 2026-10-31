#!/usr/bin/env bash
# Exercise every template with the selected implementation and the complete
# updater against local downloads. No network, system install, or service use.
set -euo pipefail
cd "$(dirname "$0")/.."
real_mktemp=$(command -v mktemp)
mktemp_tool=("$real_mktemp")
if [[ -n "${SS2022_TEST_BUSYBOX:-}" ]]; then
    mktemp_tool=("$SS2022_TEST_BUSYBOX" mktemp)
fi
fixture_dir=$("${mktemp_tool[@]}" -d /tmp/ss2022-mktemp-regression.XXXXXX)
trap 'rm -rf "$fixture_dir"' EXIT
export SS2022_LIB_ONLY=1
# shellcheck disable=SC1091
source ./ss2022.sh
checks=0
assert() {
    if ! "$@"; then printf 'FAIL: %s\n' "$*" >&2; exit 1; fi
    checks=$((checks + 1))
}
contains() { [[ "$1" == *"$2"* ]]; }

# No suffix extension is allowed after the random component, even on GNU.
if grep -nE 'mktemp.*XXXXXX\.[[:alnum:]_]' ss2022.sh; then
    echo 'FAIL: mktemp template incompatible with BusyBox'; exit 1
fi
mapfile -t templates < <(grep 'mktemp' ss2022.sh | grep -oE '[[:alnum:]_.-]*XXXXXX[[:alnum:]_.-]*' | sort -u)
[[ ${#templates[@]} -gt 30 ]]
for template in "${templates[@]}"; do
    assert test "${template: -6}" = XXXXXX
    file=$("${mktemp_tool[@]}" "$fixture_dir/$template")
    assert test -f "$file"
    assert test "$(stat -c %a "$file")" = 600
    rm -f "$file"
done
if [[ -n "${SS2022_TEST_BUSYBOX:-}" ]]; then
    # Reproduce the user's exact failure before exercising the corrected form.
    if "$SS2022_TEST_BUSYBOX" mktemp "$fixture_dir/old.XXXXXX.sh" >"$fixture_dir/old.out" 2>"$fixture_dir/old.err"; then
        echo 'FAIL: expected BusyBox suffix-template rejection'; exit 1
    fi
    assert test -s "$fixture_dir/old.err"
fi

SCRIPT_INSTALL_PATH="$fixture_dir/ss2022"
SCRIPT_BACKUP_PATH="$fixture_dir/ss2022.bak"
SCRIPT_PROXY_LINK="$fixture_dir/proxy"
running="$fixture_dir/running.sh"
remote="$fixture_dir/remote.sh"
cat >"$running" <<'OLD'
#!/bin/bash
# 项目名称: vps-bootstrap / ss2022.sh
SCRIPT_VERSION="v1.9.1-dev5"
: old
OLD
cat >"$remote" <<'NEW'
#!/bin/bash
# 项目名称: vps-bootstrap / ss2022.sh
SCRIPT_VERSION="v1.9.1-dev6"
: new
NEW
cp "$running" "$SCRIPT_INSTALL_PATH"
cp "$remote" "$fixture_dir/good-remote"

clear() { :; }
pause() { :; }
sleep() { :; }
script_source_path() { printf '%s\n' "$running"; }
exec() { printf '%s\n' "$*" >"$fixture_dir/reexec"; }
mktemp() {
    [[ "${FAIL_MKTEMP:-0}" != 1 ]] || return 1
    # Same basename and implementation, but all test files stay in the sandbox.
    "${mktemp_tool[@]}" "$fixture_dir/${1##*/}"
}
curl() {
    echo called >>"$fixture_dir/downloads"
    local previous='' arg out=''
    for arg in "$@"; do
        [[ "$previous" != -o ]] || out="$arg"
        previous="$arg"
    done
    [[ "${FAIL_CURL:-0}" != 1 ]] || return 22
    cp "$remote" "$out"
}
install() {
    if [[ "${FAIL_INSTALL:-0}" == 1 && "$3" != "$SCRIPT_BACKUP_PATH" ]]; then
        echo partial >"$4"
        return 1
    fi
    command install "$@"
}
cleaned() { ! compgen -G "$fixture_dir/ss2022-update.*" >/dev/null; }

# Verify the one-time repair command users must run before menu 9 can work.
declare -f check_script_update | sed 's@ss2022-update\.sh\.XXXXXX@ss2022-update.XXXXXX.sh@g' >"$fixture_dir/old-updater.sh"
cp -p "$fixture_dir/old-updater.sh" "$fixture_dir/old-updater.before-mktemp-fix"
sed -i 's@ss2022-update\.XXXXXX\.sh@ss2022-update.sh.XXXXXX@g' "$fixture_dir/old-updater.sh"
assert bash -n "$fixture_dir/old-updater.sh"
# shellcheck disable=SC1091
source "$fixture_dir/old-updater.sh"

out=$(check_script_update <<<y)
assert contains "$out" '脚本安装 / 更新完成：v1.9.1-dev6'
assert cmp -s "$SCRIPT_INSTALL_PATH" "$remote"
assert cmp -s "$SCRIPT_BACKUP_PATH" "$running"
assert test "$(stat -c %a "$SCRIPT_INSTALL_PATH")" = 755
assert test -L "$SCRIPT_PROXY_LINK"
assert test -s "$fixture_dir/reexec"
assert cleaned

cp "$running" "$SCRIPT_INSTALL_PATH"
rm -f "$fixture_dir/reexec"
out=$(check_script_update <<<n)
assert contains "$out" '已取消更新'
assert cmp -s "$SCRIPT_INSTALL_PATH" "$running"
assert test ! -e "$fixture_dir/reexec"
assert cleaned

printf '<html>not a script</html>\n' >"$remote"
out=$(check_script_update <<<y)
assert contains "$out" '不是有效的 vps-bootstrap'
assert cmp -s "$SCRIPT_INSTALL_PATH" "$running"
assert cleaned

cp "$fixture_dir/good-remote" "$remote"
printf 'if\n' >>"$remote"
out=$(check_script_update <<<y 2>/dev/null)
assert contains "$out" '未通过 Bash 语法检查'
assert cmp -s "$SCRIPT_INSTALL_PATH" "$running"
assert cleaned

cp "$fixture_dir/good-remote" "$remote"
out=$(FAIL_CURL=1 check_script_update <<<y)
assert contains "$out" '下载 GitHub 最新脚本失败'
assert cmp -s "$SCRIPT_INSTALL_PATH" "$running"
assert cleaned

out=$(FAIL_INSTALL=1 check_script_update <<<y)
assert contains "$out" '新脚本安装失败'
assert cmp -s "$SCRIPT_INSTALL_PATH" "$running"
assert cleaned

sed 's/v1.9.1-dev6/v1.9.0/' "$fixture_dir/good-remote" >"$remote"
out=$(check_script_update <<<y)
assert contains "$out" '为避免误降级'
assert cmp -s "$SCRIPT_INSTALL_PATH" "$running"
assert cleaned

rm -f "$fixture_dir/downloads"
out=$(FAIL_MKTEMP=1 check_script_update <<<y)
assert contains "$out" '无法创建临时文件'
assert cmp -s "$SCRIPT_INSTALL_PATH" "$running"
assert test ! -e "$fixture_dir/downloads"
assert cleaned
echo "PASS: $checks template and updater checks (${mktemp_tool[*]})"
