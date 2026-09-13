#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_OUTPUT="$ROOT_DIR/build/test"
APP="$TEST_OUTPUT/Antigravity Proxy.app"
LAUNCHER="$APP/Contents/MacOS/AntigravityProxy"
MENU_BINARY="$APP/Contents/MacOS/AntigravityProxyMenu"
ENGINE="$APP/Contents/Resources/AntigravityProxy"

/bin/zsh -n "$ROOT_DIR/src/AntigravityProxy"
OUTPUT_DIR="$TEST_OUTPUT" "$ROOT_DIR/scripts/build-app.sh"
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
[[ -f "$APP/Contents/Resources/AppIcon.icns" ]]
[[ -x "$MENU_BINARY" ]]
[[ -x "$ENGINE" ]]
[[ "$(/usr/bin/plutil -extract CFBundleIconFile raw -o - "$APP/Contents/Info.plist")" == 'AppIcon.icns' ]]
[[ "$(/usr/bin/plutil -extract LSUIElement raw -o - "$APP/Contents/Info.plist")" == 'true' ]]
[[ "$(/usr/bin/plutil -extract LSMultipleInstancesProhibited raw -o - "$APP/Contents/Info.plist")" == 'true' ]]

"$LAUNCHER" --version | /usr/bin/grep -qx '1.1.0'

TEST_CONFIG="$TEST_OUTPUT/nonexistent.conf"
config_output=$(ANTIGRAVITY_CONFIG_FILE="$TEST_CONFIG" ANTIGRAVITY_PROXY_URL='http://127.0.0.1:7890' "$LAUNCHER" --print-config)
printf '%s\n' "$config_output" | /usr/bin/grep -qx 'HTTP_PROXY=http://127.0.0.1:7890'
printf '%s\n' "$config_output" | /usr/bin/grep -qx 'HTTPS_PROXY=http://127.0.0.1:7890'
printf '%s\n' "$config_output" | /usr/bin/grep -qx 'GRPC_PROXY=http://127.0.0.1:7890'
printf '%s\n' "$config_output" | /usr/bin/grep -qx 'REGION_CHECK=1'
printf '%s\n' "$config_output" | /usr/bin/grep -qx 'UNSUPPORTED_REGIONS=CN,HK,MO,RU,BY,IR,KP,SY,CU'
printf '%s\n' "$config_output" | /usr/bin/grep -qx 'REGION_CHECK_TIMEOUT=8'
printf '%s\n' "$config_output" | /usr/bin/grep -qx 'STARTUP_CHECK_SECONDS=35'
printf '%s\n' "$config_output" | /usr/bin/grep -q '^IP_INFO_URL=http://ip-api.com/'
printf '%s\n' "$config_output" | /usr/bin/grep -qx 'IP_INFO_TIMEOUT=6'

# No conventional port is assumed when system-proxy detection is disabled.
set +e
no_proxy_output=$(ANTIGRAVITY_SUPPRESS_NOTIFICATIONS=1 \
  ANTIGRAVITY_CONFIG_FILE="$TEST_CONFIG" \
  ANTIGRAVITY_NO_AUTO_DETECT=1 \
  "$LAUNCHER" --noninteractive --print-config 2>&1)
no_proxy_status=$?
set -e
[[ $no_proxy_status -eq 1 ]]
printf '%s\n' "$no_proxy_output" | /usr/bin/grep -q '未检测到有效的 HTTP/HTTPS 代理'

TEST_CONFIG="$TEST_OUTPUT/config-test.conf"
cat > "$TEST_CONFIG" <<'CONFIG'
ANTIGRAVITY_PROXY_URL='http://127.0.0.1:8899'
ANTIGRAVITY_REGION_CHECK='0'
ANTIGRAVITY_UNSUPPORTED_REGIONS='CN, HK, US'
ANTIGRAVITY_REGION_CHECK_TIMEOUT='5'
ANTIGRAVITY_STARTUP_CHECK_SECONDS='12'
ANTIGRAVITY_IP_INFO_URL='http://127.0.0.1:9999/ip-info'
ANTIGRAVITY_IP_INFO_TIMEOUT='3'
CONFIG

config_output=$(ANTIGRAVITY_CONFIG_FILE="$TEST_CONFIG" "$LAUNCHER" --print-config)
printf '%s\n' "$config_output" | /usr/bin/grep -qx 'HTTP_PROXY=http://127.0.0.1:8899'
printf '%s\n' "$config_output" | /usr/bin/grep -qx 'REGION_CHECK=0'
printf '%s\n' "$config_output" | /usr/bin/grep -qx 'UNSUPPORTED_REGIONS=CN, HK, US'
printf '%s\n' "$config_output" | /usr/bin/grep -qx 'REGION_CHECK_TIMEOUT=5'
printf '%s\n' "$config_output" | /usr/bin/grep -qx 'STARTUP_CHECK_SECONDS=12'
printf '%s\n' "$config_output" | /usr/bin/grep -qx 'IP_INFO_URL=http://127.0.0.1:9999/ip-info'
printf '%s\n' "$config_output" | /usr/bin/grep -qx 'IP_INFO_TIMEOUT=3'

config_output=$(ANTIGRAVITY_CONFIG_FILE="$TEST_CONFIG" ANTIGRAVITY_REGION_CHECK='1' "$LAUNCHER" --print-config)
printf '%s\n' "$config_output" | /usr/bin/grep -qx 'REGION_CHECK=1'

# IP information parsing is independent from the live API so menus and CI can
# be validated without making a network request.
eval "$(/usr/bin/awk '
  /^ip_info_value\(\)/ { capture=1 }
  /^log_line_count\(\)/ { capture=0 }
  capture { print }
' "$ROOT_DIR/src/AntigravityProxy")"

IP_INFO_JSON='{"status":"success","query":"91.110.237.98","country":"英国","regionName":"英格兰","city":"Martlesham","isp":"Cnservers LLC","org":"EE Limited","as":"AS40065 CNSERVERS LLC","asname":"CNSERVERS","mobile":false,"proxy":false,"hosting":true}'
parse_ip_info
[[ "$IP_INFO_STATUS" == 'success' ]]
[[ "$IP_ADDRESS" == '91.110.237.98' ]]
[[ "$IP_LOCATION" == '英国 · 英格兰 · Martlesham' ]]
[[ "$IP_PROVIDER" == 'Cnservers LLC' ]]
[[ "$IP_ASN" == 'AS40065 CNSERVERS LLC' ]]
[[ "$IP_NETWORK_TYPE" == '数据中心 / 机房' ]]

IP_INFO_JSON='{"status":"success","query":"1.2.3.4","country":"美国","regionName":"California","city":"Los Angeles","isp":"Example Mobile","as":"AS64500 Example Mobile","mobile":true,"proxy":false,"hosting":false}'
parse_ip_info
[[ "$IP_NETWORK_TYPE" == '移动网络' ]]

IP_INFO_JSON='{"status":"success","query":"2.3.4.5","country":"美国","city":"New York","isp":"Example VPN","as":"AS64502 Example VPN","mobile":false,"proxy":true,"hosting":false}'
parse_ip_info
[[ "$IP_NETWORK_TYPE" == '代理 / VPN' ]]

IP_INFO_JSON='{"status":"fail","message":"quota exceeded"}'
if parse_ip_info; then
  printf 'Expected IP information parsing to fail.\n' >&2
  exit 1
fi
[[ "$IP_INFO_STATUS" == 'error' ]]
[[ "$IP_INFO_ERROR" == 'quota exceeded' ]]

IP_INFO_JSON='{"status":"success","query":"5.6.7.8","country":"美国","city":"Ashburn","isp":"Example ISP","as":"AS64501 Example ISP","mobile":false,"proxy":false,"hosting":false}'
parse_ip_info
ip_info_output=$(print_ip_info)
printf '%s\n' "$ip_info_output" | /usr/bin/grep -qx 'IP_INFO_STATUS=success'
printf '%s\n' "$ip_info_output" | /usr/bin/grep -qx 'IP_ADDRESS=5.6.7.8'
printf '%s\n' "$ip_info_output" | /usr/bin/grep -qx 'IP_LOCATION=美国 · Ashburn'
printf '%s\n' "$ip_info_output" | /usr/bin/grep -qx 'IP_PROVIDER=Example ISP'
printf '%s\n' "$ip_info_output" | /usr/bin/grep -qx 'IP_NETWORK_TYPE=普通宽带（住宅或企业）'

# Regression test: language_server.log is replaced on every launch. The
# monitor must inspect the new file even when its line count is still below
# the previous file's line count.
eval "$(/usr/bin/awk '
  /^log_line_count\(\)/ { capture=1 }
  /^diagnose_startup\(\)/ { capture=0 }
  capture { print }
' "$ROOT_DIR/src/AntigravityProxy")"

mkdir -p "$TEST_OUTPUT/log-test"
ROTATED_LOG="$TEST_OUTPUT/log-test/language_server.log"
printf 'old line 1\nold line 2\nold line 3\n' > "$ROTATED_LOG"
rotated_start=$(log_line_count "$ROTATED_LOG")
rotated_first=$(log_first_line "$ROTATED_LOG")
printf 'new launch\ninitialized server successfully\n' > "$ROTATED_LOG"
rotated_output=$(log_lines_since "$ROTATED_LOG" "$rotated_start" "$rotated_first")
printf '%s\n' "$rotated_output" | /usr/bin/grep -qx 'initialized server successfully'

# A stale timeout from an older session must not classify a current process as
# blank, and a later language-server success must supersede a transient timeout.
eval "$(/usr/bin/awk '
  /^main_is_blank\(\)/ { capture=1 }
  /^print_runtime_status\(\)/ { capture=0 }
  capture { print }
' "$ROOT_DIR/src/AntigravityProxy")"

BLANK_TEST_HOME="$TEST_OUTPUT/blank-test"
mkdir -p "$BLANK_TEST_HOME/Library/Logs/Antigravity"
(
  HOME="$BLANK_TEST_HOME"
  printf '' > "$HOME/Library/Logs/Antigravity/language_server.log"
  printf 'Failed to load URL: https://127.0.0.1:1234/\n' > "$HOME/Library/Logs/Antigravity/main.log"
  if main_is_blank; then
    printf 'A timeout without a current launch marker must be ignored.\n' >&2
    exit 1
  fi

  printf 'Starting app (v2.12.2)\nFailed to load URL: https://127.0.0.1:1234/\n' > "$HOME/Library/Logs/Antigravity/main.log"
  main_is_blank

  printf 'Serving UI bundle from embedded assets\n' > "$HOME/Library/Logs/Antigravity/language_server.log"
  if main_is_blank; then
    printf 'A successful language-server startup must supersede a transient timeout.\n' >&2
    exit 1
  fi
)

# Regression test: a successful startup must exit the monitor immediately
# rather than waiting for the full diagnostic timeout.
eval "$(/usr/bin/awk '
  /^diagnose_startup\(\)/ { capture=1 }
  /^main_pid\(\)/ { capture=0 }
  capture { print }
' "$ROOT_DIR/src/AntigravityProxy")"

mkdir -p "$TEST_OUTPUT/startup-test/Library/Logs/Antigravity"
STARTUP_TEST_HOME="$TEST_OUTPUT/startup-test"
printf 'Starting app (v2.12.2)\n' > "$STARTUP_TEST_HOME/Library/Logs/Antigravity/main.log"
printf 'old server log\n' > "$STARTUP_TEST_HOME/Library/Logs/Antigravity/language_server.log"
(
  HOME="$STARTUP_TEST_HOME"
  STARTUP_CHECK_SECONDS=4
  main_pid() { printf '12345\n'; }
  show_error() { printf 'unexpected startup error\n' >&2; return 1; }

  main_start=$(log_line_count "$HOME/Library/Logs/Antigravity/main.log")
  main_first=$(log_first_line "$HOME/Library/Logs/Antigravity/main.log")
  server_start=$(log_line_count "$HOME/Library/Logs/Antigravity/language_server.log")
  server_first=$(log_first_line "$HOME/Library/Logs/Antigravity/language_server.log")
  printf 'FAILED_PRECONDITION\nERR_TIMED_OUT\ninitialized server successfully\n' > "$HOME/Library/Logs/Antigravity/language_server.log"

  started_at=$SECONDS
  diagnose_startup "$main_start" "$main_first" "$server_start" "$server_first"
  (( SECONDS - started_at < 3 ))
)

printf 'All tests passed.\n'
