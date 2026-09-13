#!/usr/bin/env bash
# Rasterise the SVG previews to PNG for quick review.
#
# Review aid only — nothing here ships. Needs a Chromium binary; point CHROME at one.
# On a Mac:  CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" tools/render_preview_png.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHROME="${CHROME:-chromium}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

python3 "$ROOT/tools/preview_room.py"

for t in morning day evening night; do
  cat > "$TMP/$t.html" <<EOF
<!doctype html><style>html,body{margin:0;padding:0;overflow:hidden}img{display:block;width:1366px;height:1024px}</style>
<img src="file://$ROOT/docs/preview/room-$t.svg">
EOF
  "$CHROME" --headless --no-sandbox --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=1 --window-size=1366,1024 \
    --screenshot="$ROOT/docs/preview/room-$t.png" "file://$TMP/$t.html" >/dev/null 2>&1
  echo "wrote docs/preview/room-$t.png"
done
