#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# Extract the production functions without sourcing the interactive installer.
sed -n '/^singbox_restore_failed_takeover() {/,/^}/p' ss2022.sh > "$tmp/functions.sh"
sed -n '/^singbox_assert_safe_ownership() {/,/^}/p' ss2022.sh >> "$tmp/functions.sh"
# shellcheck disable=SC1090
source "$tmp/functions.sh"
RED='' YELLOW='' PLAIN=''
SINGBOX_BIN="$tmp/sing-box"
SINGBOX_CONF="$tmp/config.json"
SINGBOX_SERVICE="$tmp/sing-box.service"
SINGBOX_OPENRC_SERVICE="$tmp/sing-box.openrc"
SINGBOX_MANAGED_MARKER="$tmp/managed"
SINGBOX_ORIGINAL_BACKUP="$tmp/original.bak"
SINGBOX_ORIGINAL_BACKUP_SHA="$tmp/original.sha"
SINGBOX_PENDING_TAKEOVER=1
service_daemon_reload() { :; }
singbox_is_project_managed() { return 1; }
printf 'original binary\n' > "$SINGBOX_BIN"
chmod 751 "$SINGBOX_BIN"
original=$(sha256sum "$SINGBOX_BIN" | cut -d' ' -f1)
cp -p "$SINGBOX_BIN" "$SINGBOX_ORIGINAL_BACKUP"
printf '%s\n' "$original" > "$SINGBOX_ORIGINAL_BACKUP_SHA"
printf 'replacement\n' > "$SINGBOX_BIN"
touch "$SINGBOX_SERVICE" "$SINGBOX_MANAGED_MARKER"
singbox_restore_failed_takeover
[[ "$(sha256sum "$SINGBOX_BIN" | cut -d' ' -f1)" == "$original" ]]
[[ "$(stat -c '%a' "$SINGBOX_BIN")" == 751 ]]
[[ ! -e "$SINGBOX_SERVICE" && ! -e "$SINGBOX_MANAGED_MARKER" ]]
[[ ! -e "$SINGBOX_ORIGINAL_BACKUP" && ! -e "$SINGBOX_ORIGINAL_BACKUP_SHA" ]]
echo 'PASS: rollback restores SHA256, mode, and cleans temporary assets'
cp -p "$SINGBOX_BIN" "$SINGBOX_ORIGINAL_BACKUP"
printf '%s\n' "$original" > "$SINGBOX_ORIGINAL_BACKUP_SHA"
printf 'corrupt\n' > "$SINGBOX_ORIGINAL_BACKUP"
printf 'replacement\n' > "$SINGBOX_BIN"
if singbox_restore_failed_takeover; then echo 'FAIL: corrupt backup accepted'; exit 1; fi
[[ "$(cat "$SINGBOX_BIN")" == replacement ]]
[[ -e "$SINGBOX_ORIGINAL_BACKUP" ]]
echo 'PASS: corrupted backup rejected without touching target'
rm -f "$SINGBOX_ORIGINAL_BACKUP" "$SINGBOX_ORIGINAL_BACKUP_SHA"
SINGBOX_PENDING_TAKEOVER=0
if printf 'n\n' | singbox_assert_safe_ownership; then echo 'FAIL: declined takeover accepted'; exit 1; fi
[[ ! -e "$SINGBOX_ORIGINAL_BACKUP" ]]
touch "$SINGBOX_CONF"
if printf 'y\n' | singbox_assert_safe_ownership; then echo 'FAIL: external config accepted'; exit 1; fi
echo 'PASS: declined takeover and external config protected'
