#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
SOURCE_APP="$ROOT_DIR/build/Antigravity Proxy.app"
DEST_APP="$INSTALL_DIR/Antigravity Proxy.app"

"$ROOT_DIR/scripts/build-app.sh"
mkdir -p "$INSTALL_DIR"

if [[ -e "$DEST_APP" ]]; then
  BACKUP_APP="$DEST_APP.backup-$(/bin/date +%Y%m%d-%H%M%S)"
  mv "$DEST_APP" "$BACKUP_APP"
  printf 'Previous installation backed up to: %s\n' "$BACKUP_APP"
fi

/usr/bin/ditto "$SOURCE_APP" "$DEST_APP"

LSREGISTER='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
[[ -x "$LSREGISTER" ]] && "$LSREGISTER" -f "$DEST_APP" >/dev/null 2>&1 || true

printf 'Installed: %s\n' "$DEST_APP"
printf 'Launch this app instead of the official Antigravity app.\n'

if [[ ! -d '/Applications/Antigravity.app' ]]; then
  printf 'Warning: /Applications/Antigravity.app was not found.\n' >&2
fi
