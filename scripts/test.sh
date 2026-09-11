#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_OUTPUT="$ROOT_DIR/build/test"
APP="$TEST_OUTPUT/Antigravity Proxy.app"
LAUNCHER="$APP/Contents/MacOS/AntigravityProxy"

/bin/zsh -n "$ROOT_DIR/src/AntigravityProxy"
OUTPUT_DIR="$TEST_OUTPUT" "$ROOT_DIR/scripts/build-app.sh"
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"

"$LAUNCHER" --version | /usr/bin/grep -qx '1.0.0'

TEST_CONFIG="$TEST_OUTPUT/nonexistent.conf"
config_output=$(ANTIGRAVITY_CONFIG_FILE="$TEST_CONFIG" ANTIGRAVITY_PROXY_URL='http://127.0.0.1:7890' "$LAUNCHER" --print-config)
printf '%s\n' "$config_output" | /usr/bin/grep -qx 'HTTP_PROXY=http://127.0.0.1:7890'
printf '%s\n' "$config_output" | /usr/bin/grep -qx 'HTTPS_PROXY=http://127.0.0.1:7890'
printf '%s\n' "$config_output" | /usr/bin/grep -qx 'GRPC_PROXY=http://127.0.0.1:7890'

printf 'All tests passed.\n'
