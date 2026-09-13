#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Compatibility entry point. The menu bar implementation is now the stable app.
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/build}" \
BUNDLE_ID="${BUNDLE_ID:-io.github.antigravity-proxy.launcher}" \
  exec "$ROOT_DIR/scripts/build-app.sh"
