#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-$(/usr/bin/sed -n "s/^VERSION='\([^']*\)'.*/\1/p" "$ROOT_DIR/src/AntigravityProxy" | /usr/bin/head -n 1)}"
VERSION="${VERSION#v}"
BUNDLE_ID="${BUNDLE_ID:-io.github.antigravity-proxy.launcher}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/build}"
APP_PATH="$OUTPUT_DIR/Antigravity Proxy.app"
CONTENTS="$APP_PATH/Contents"

[[ -n "$VERSION" ]] || VERSION='1.0.0'

/bin/zsh -n "$ROOT_DIR/src/AntigravityProxy"
rm -rf "$APP_PATH"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
/usr/bin/install -m 755 "$ROOT_DIR/src/AntigravityProxy" "$CONTENTS/MacOS/AntigravityProxy"
/usr/bin/install -m 644 "$ROOT_DIR/packaging/Info.plist" "$CONTENTS/Info.plist"
/usr/bin/plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$CONTENTS/Info.plist"
/usr/bin/plutil -replace CFBundleShortVersionString -string "$VERSION" "$CONTENTS/Info.plist"

/usr/bin/xattr -cr "$APP_PATH" 2>/dev/null || true
/usr/bin/codesign --force --deep --sign - "$APP_PATH"
/usr/bin/codesign --verify --deep --strict "$APP_PATH"

printf 'Built: %s\n' "$APP_PATH"
printf 'Version: %s\n' "$VERSION"
printf 'Bundle ID: %s\n' "$BUNDLE_ID"
