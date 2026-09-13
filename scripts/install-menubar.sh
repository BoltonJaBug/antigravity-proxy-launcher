#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Compatibility entry point. The menu bar implementation is now the stable app.
exec "$ROOT_DIR/scripts/install.sh"
