#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${RUNTIME_DIR:?RUNTIME_DIR must point to the preview runtime}"
: "${CAPTURE_URL:?Set CAPTURE_URL to the preview URL}"
: "${CAPTURE_DIR:?Set CAPTURE_DIR to the screenshot output directory}"
/usr/bin/time -p test -f "$RUNTIME_DIR/scripts/default-capture.mjs"
cd "$PROJECT_DIR"
CAPTURE_STRICT="${CAPTURE_STRICT:-1}" /usr/bin/time -p node "$RUNTIME_DIR/scripts/default-capture.mjs"
/usr/bin/time -p test -s "$CAPTURE_DIR/final-desktop.png"
/usr/bin/time -p test -s "$CAPTURE_DIR/final-mobile.png"
