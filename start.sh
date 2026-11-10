#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATIC_DIR="$PROJECT_DIR/web-preview"
WEB_DIR="${OPENCODE_WEB_DIR:-/home/runner/work/_temp/omgithub-web}"
PORT="${PORT:-${APP_PORT:-3000}}"

[[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT > 0 && PORT < 65536 )) || { echo 'PORT must be an integer from 1 to 65535.' >&2; exit 1; }
/usr/bin/time -p test -f "$STATIC_DIR/index.html"
/usr/bin/time -p mkdir -p "$WEB_DIR"
PROJECT_DIR="$PROJECT_DIR" STATIC_DIR="$STATIC_DIR" WEB_DIR="$WEB_DIR" /usr/bin/time -p node -e 'const fs=require("node:fs"); fs.writeFileSync(`${process.env.WEB_DIR}/deployment-output.json`, JSON.stringify({project:process.env.PROJECT_DIR,directory:process.env.STATIC_DIR}));'
export PORT
exec /usr/bin/time -p python3 -m http.server "$PORT" --bind 0.0.0.0 --directory "$STATIC_DIR"
