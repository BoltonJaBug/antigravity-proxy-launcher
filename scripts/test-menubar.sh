#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_OUTPUT="$ROOT_DIR/build-menu-test"
APP="$TEST_OUTPUT/Antigravity Proxy Menu.app"
WRAPPER="$APP/Contents/MacOS/AntigravityProxy"
MENU_BINARY="$APP/Contents/MacOS/AntigravityProxyMenu"
ENGINE="$APP/Contents/Resources/AntigravityProxy"

/bin/zsh -n "$ROOT_DIR/src/AntigravityProxy"
/bin/zsh -n "$ROOT_DIR/src/AntigravityProxyApp"
OUTPUT_DIR="$TEST_OUTPUT" "$ROOT_DIR/scripts/build-menubar-app.sh"

/usr/bin/plutil -lint "$APP/Contents/Info.plist"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
[[ -x "$WRAPPER" ]]
[[ -x "$MENU_BINARY" ]]
[[ -x "$ENGINE" ]]
[[ -f "$APP/Contents/Resources/AppIcon.icns" ]]
[[ "$(/usr/bin/plutil -extract LSUIElement raw -o - "$APP/Contents/Info.plist")" == 'true' ]]
[[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$APP/Contents/Info.plist")" == 'io.github.antigravity-proxy.launcher.menubar' ]]

"$WRAPPER" --version | /usr/bin/grep -qx '1.0.5'

status_output=$(ANTIGRAVITY_CONFIG_FILE="$TEST_OUTPUT/nonexistent.conf" \
  ANTIGRAVITY_PROXY_URL='http://127.0.0.1:33210' \
  "$WRAPPER" --status)
printf '%s\n' "$status_output" | /usr/bin/grep -q '^PID='
printf '%s\n' "$status_output" | /usr/bin/grep -qx 'PROXY_URL=http://127.0.0.1:33210'
printf '%s\n' "$status_output" | /usr/bin/grep -q '^HAS_PROXY_ENV=[01]$'
printf '%s\n' "$status_output" | /usr/bin/grep -q '^MAIN_BLANK=[01]$'
printf '%s\n' "$status_output" | /usr/bin/grep -q '^PROXY_READY=[01]$'
printf '%s\n' "$status_output" | /usr/bin/grep -q '^APP_PATH='

set +e
auto_recover_output=$(ANTIGRAVITY_SUPPRESS_NOTIFICATIONS=1 \
  ANTIGRAVITY_CONFIG_FILE="$TEST_OUTPUT/nonexistent.conf" \
  ANTIGRAVITY_PROXY_URL='http://127.0.0.1:1' \
  "$ENGINE" --auto-recover 2>&1)
auto_recover_status=$?
set -e
[[ $auto_recover_status -eq 1 ]]
printf '%s\n' "$auto_recover_output" | /usr/bin/grep -qx 'AUTO_RECOVER_ERROR_BEGIN'
printf '%s\n' "$auto_recover_output" | /usr/bin/grep -q '代理 127.0.0.1:1 未运行。'
printf '%s\n' "$auto_recover_output" | /usr/bin/grep -qx 'AUTO_RECOVER_ERROR_END'

printf 'Menu bar tests passed.\n'
