#!/usr/bin/env bash
#
# Copies the website's images out of the golden tests and the app icon.
#
# The goldens *are* the screenshots: rendered from the real widgets with demo
# data (test/screenshots/site_screenshots_test.dart), so they cannot drift from
# the product and never show a real host name. site/img is gitignored; the Pages
# workflow runs this before deploying, and a missing golden fails the build.
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGES=(
  "test/screenshots/goldens/desktop_running.png:site/img/desktop-running.png"
  "test/screenshots/goldens/phone_home.png:site/img/phone-home.png"
  "test/screenshots/goldens/schedule.png:site/img/schedule.png"
  "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png:site/img/icon-192.png"
)

mkdir -p site/img
for pair in "${IMAGES[@]}"; do
  src=${pair%%:*} dst=${pair#*:}
  [[ -f $src ]] || { echo "missing $src — regenerate with: flutter test test/screenshots --update-goldens" >&2; exit 1; }
  cp "$src" "$dst"
done
echo "site/img: ${#IMAGES[@]} images"
