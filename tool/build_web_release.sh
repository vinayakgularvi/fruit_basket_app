#!/usr/bin/env bash
# Release web build with full Material Icons font (avoids missing glyphs on web).
set -euo pipefail
cd "$(dirname "$0")/.."
exec flutter build web --release --no-tree-shake-icons "$@"
