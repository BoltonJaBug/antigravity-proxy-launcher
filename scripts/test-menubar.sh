#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_OUTPUT="$ROOT_DIR/build-menu-test"
APP="$TEST_OUTPUT/Antigravity Proxy.app"
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
[[ -x "$APP/Contents/Resources/AntigravityCLI.command" ]]
[[ -f "$APP/Contents/Resources/AppIcon.icns" ]]
[[ "$(/usr/bin/plutil -extract LSUIElement raw -o - "$APP/Contents/Info.plist")" == 'true' ]]
[[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$APP/Contents/Info.plist")" == 'io.github.antigravity-proxy.launcher' ]]

"$WRAPPER" --version | /usr/bin/grep -qx '1.5.0'

FAKE_AGY="$TEST_OUTPUT/fake-agy"
cat > "$FAKE_AGY" <<'SCRIPT'
#!/bin/zsh
printf 'CLI_HTTPS_PROXY=%s\n' "$HTTPS_PROXY"
printf 'CLI_HTTP_PROXY=%s\n' "$HTTP_PROXY"
printf 'CLI_ALL_PROXY=%s\n' "$ALL_PROXY"
printf 'CLI_NO_PROXY=%s\n' "$NO_PROXY"
SCRIPT
chmod +x "$FAKE_AGY"

status_output=$(ANTIGRAVITY_CONFIG_FILE="$TEST_OUTPUT/nonexistent.conf" \
  ANTIGRAVITY_PROXY_URL='http://127.0.0.1:33210' \
  ANTIGRAVITY_NO_AUTO_DETECT=1 \
  AGY_CLI_BIN="$FAKE_AGY" \
  "$WRAPPER" --status)
printf '%s\n' "$status_output" | /usr/bin/grep -q '^PID='
printf '%s\n' "$status_output" | /usr/bin/grep -qx 'PROXY_URL=http://127.0.0.1:33210'
printf '%s\n' "$status_output" | /usr/bin/grep -q '^HAS_PROXY_ENV=[01]$'
printf '%s\n' "$status_output" | /usr/bin/grep -q '^MAIN_BLANK=[01]$'
printf '%s\n' "$status_output" | /usr/bin/grep -q '^PROXY_READY=[01]$'
printf '%s\n' "$status_output" | /usr/bin/grep -q '^APP_PATH='
printf '%s\n' "$status_output" | /usr/bin/grep -qx 'AGY_CLI_INSTALLED=1'
printf '%s\n' "$status_output" | /usr/bin/grep -qx "AGY_CLI_BIN=$FAKE_AGY"
if printf '%s\n' "$status_output" | /usr/bin/grep -Eiq 'CODEX|ALL_PROXY_URL'; then
  printf 'Removed app status must not appear in --status.\n' >&2
  exit 1
fi

# The Terminal launcher must pass the proxy detected at launch time to the CLI.
FAKE_SCUTIL="$TEST_OUTPUT/fake-agy-scutil"
cat > "$FAKE_SCUTIL" <<'SCRIPT'
#!/bin/zsh
cat <<'OUTPUT'
<dictionary> {
  HTTPEnable : 1
  HTTPProxy : 127.0.0.1
  HTTPPort : 7788
  HTTPSEnable : 1
  HTTPSProxy : 127.0.0.1
  HTTPSPort : 7788
}
OUTPUT
SCRIPT
chmod +x "$FAKE_SCUTIL"
FAKE_NC="$TEST_OUTPUT/fake-agy-nc"
printf '#!/bin/zsh\nexit 0\n' > "$FAKE_NC"
chmod +x "$FAKE_NC"
FAKE_CURL="$TEST_OUTPUT/fake-agy-curl"
printf '#!/bin/zsh\nprintf "200"\n' > "$FAKE_CURL"
chmod +x "$FAKE_CURL"
agy_output=$(ANTIGRAVITY_CONFIG_FILE="$TEST_OUTPUT/nonexistent.conf" \
  ANTIGRAVITY_SCUTIL_BIN="$FAKE_SCUTIL" \
  ANTIGRAVITY_NC_BIN="$FAKE_NC" \
  ANTIGRAVITY_CURL_BIN="$FAKE_CURL" \
  AGY_CLI_BIN="$FAKE_AGY" \
  "$ENGINE" --agy-cli-exec)
printf '%s\n' "$agy_output" | /usr/bin/grep -qx 'CLI_HTTPS_PROXY=http://127.0.0.1:7788'
printf '%s\n' "$agy_output" | /usr/bin/grep -qx 'CLI_HTTP_PROXY=http://127.0.0.1:7788'
printf '%s\n' "$agy_output" | /usr/bin/grep -qx 'CLI_ALL_PROXY=http://127.0.0.1:7788'
printf '%s\n' "$agy_output" | /usr/bin/grep -qx 'CLI_NO_PROXY=localhost,127.0.0.1,::1,.local'

/usr/bin/grep -q '启动 Antigravity CLI（代理模式）' "$ROOT_DIR/src/MenuBar/main.swift"
/usr/bin/grep -q 'ipRefreshMenuItem.view = ipRefreshButtonContainer' "$ROOT_DIR/src/MenuBar/main.swift"
/usr/bin/grep -q 'ipRefreshButton.bezelStyle = .rounded' "$ROOT_DIR/src/MenuBar/main.swift"
/usr/bin/grep -q 'ipRefreshButton.isBordered = true' "$ROOT_DIR/src/MenuBar/main.swift"
/usr/bin/grep -q 'ipRefreshButton.isEnabled = false' "$ROOT_DIR/src/MenuBar/main.swift"
set +e
ip_info_output=$(ANTIGRAVITY_SUPPRESS_NOTIFICATIONS=1 \
  ANTIGRAVITY_CONFIG_FILE="$TEST_OUTPUT/nonexistent.conf" \
  ANTIGRAVITY_PROXY_URL='http://127.0.0.1:1' \
  "$WRAPPER" --ip-info 2>&1)
ip_info_status=$?
set -e
[[ $ip_info_status -eq 1 ]]
printf '%s\n' "$ip_info_output" | /usr/bin/grep -qx 'IP_INFO_STATUS=error'
printf '%s\n' "$ip_info_output" | /usr/bin/grep -qx 'IP_ADDRESS=未知'
printf '%s\n' "$ip_info_output" | /usr/bin/grep -q '^IP_INFO_ERROR=代理 127.0.0.1:1 未运行。'

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

set +e
noninteractive_output=$(ANTIGRAVITY_SUPPRESS_NOTIFICATIONS=1 \
  ANTIGRAVITY_CONFIG_FILE="$TEST_OUTPUT/nonexistent.conf" \
  ANTIGRAVITY_PROXY_URL='http://127.0.0.1:1' \
  "$ENGINE" --noninteractive 2>&1)
noninteractive_status=$?
set -e
[[ $noninteractive_status -eq 1 ]]
printf '%s\n' "$noninteractive_output" | /usr/bin/grep -qx 'AUTO_RECOVER_ERROR_BEGIN'
printf '%s\n' "$noninteractive_output" | /usr/bin/grep -q '代理 127.0.0.1:1 未运行。'
printf '%s\n' "$noninteractive_output" | /usr/bin/grep -qx 'AUTO_RECOVER_ERROR_END'

# Non-interactive menu launches must reject a known unsupported region instead
# of silently bypassing the confirmation used by the standalone launcher.
eval "$(/usr/bin/awk '
  /^confirm_region_warning\(\)/ { capture=1 }
  /^config_value\(\)/ { capture=0 }
  capture { print }
' "$ROOT_DIR/src/AntigravityProxy")"
NONINTERACTIVE=1
show_error() {
  printf '%s\n' "$1"
  return 1
}
set +e
region_warning_output=$(confirm_region_warning 'CN' '中国大陆')
region_warning_status=$?
set -e
[[ $region_warning_status -eq 1 ]]
printf '%s\n' "$region_warning_output" | /usr/bin/grep -q '当前代理出口地区是 中国大陆 (CN)'

printf 'Menu bar tests passed.\n'
