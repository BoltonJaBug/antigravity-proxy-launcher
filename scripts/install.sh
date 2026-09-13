#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
SOURCE_APP="$ROOT_DIR/build/Antigravity Proxy.app"
DEST_APP="$INSTALL_DIR/Antigravity Proxy.app"
LEGACY_APP="$INSTALL_DIR/Antigravity Proxy Menu.app"

"$ROOT_DIR/scripts/build-app.sh"
mkdir -p "$INSTALL_DIR"

# Stop either app generation before replacing its bundle. The legacy preview
# used a separate bundle identifier and must not monitor Antigravity alongside
# the promoted stable menu bar app.
/usr/bin/osascript -e 'tell application id "io.github.antigravity-proxy.launcher.menubar" to quit' >/dev/null 2>&1 || true
/usr/bin/osascript -e 'tell application id "io.github.antigravity-proxy.launcher" to quit' >/dev/null 2>&1 || true
/bin/sleep 1

if [[ -e "$LEGACY_APP" ]]; then
  LEGACY_BACKUP="$LEGACY_APP.backup-$(/bin/date +%Y%m%d-%H%M%S)"
  mv "$LEGACY_APP" "$LEGACY_BACKUP"
  printf 'Legacy menu bar preview backed up to: %s\n' "$LEGACY_BACKUP"
fi

if [[ -e "$DEST_APP" ]]; then
  BACKUP_APP="$DEST_APP.backup-$(/bin/date +%Y%m%d-%H%M%S)"
  mv "$DEST_APP" "$BACKUP_APP"
  printf 'Previous installation backed up to: %s\n' "$BACKUP_APP"
fi

/usr/bin/ditto "$SOURCE_APP" "$DEST_APP"

LSREGISTER='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
[[ -x "$LSREGISTER" ]] && "$LSREGISTER" -f "$DEST_APP" >/dev/null 2>&1 || true

printf 'Installed: %s\n' "$DEST_APP"
printf 'Launch this app once, then enable Launch at Login from its menu.\n'

if [[ ! -d '/Applications/Antigravity.app' ]]; then
  printf 'Warning: /Applications/Antigravity.app was not found.\n' >&2
fi
