#!/usr/bin/env bash
#
# Generates the platform folders (android, ios, macos, windows, linux) and adds
# the permissions the SSH client needs. Safe to re-run: existing files are kept.
#
# The Xcode bundles (ios|macos/Runner.xcodeproj and Runner.xcworkspace) are not
# committed. The project is kept in a Nextcloud-synced folder, and the macOS
# File Provider sync renames bundle folders within seconds ("Runner 2.xcodeproj"),
# so they are generated fresh wherever a build happens — in CI, every run.
#
# Inside a ~/Library/CloudStorage folder this script generates into a temporary
# directory and copies back everything except those bundles. (Xcode cannot build
# there anyway: that folder's path contains a ':', which breaks Xcode's
# dependency files. Builds happen in CI — see .github/workflows/release.yaml.)
set -euo pipefail
cd "$(dirname "$0")/.."

ORG=de.abhishek
NAME=pikeep
PLATFORMS=android,ios,macos,windows,linux

if [[ $PWD == */Library/CloudStorage/* ]]; then
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  flutter create --platforms="$PLATFORMS" --org "$ORG" --project-name "$NAME" "$tmp/$NAME" >/dev/null
  for p in android ios macos windows linux; do
    rsync -a --ignore-existing \
      --exclude 'Runner.xcodeproj' --exclude 'Runner.xcworkspace' \
      --exclude 'ephemeral' --exclude '.gradle' --exclude 'local.properties' \
      "$tmp/$NAME/$p" ./
  done
  echo "Platform folders updated (Xcode bundles skipped inside the synced folder)."
else
  flutter create --platforms="$PLATFORMS" --org "$ORG" --project-name "$NAME" .
fi

# macOS sandbox: allow outgoing connections (SSH).
for f in macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements; do
  [[ -f $f ]] || continue
  if ! grep -q 'com.apple.security.network.client' "$f"; then
    perl -0pi -e 's#<dict>#<dict>\n\t<key>com.apple.security.network.client</key>\n\t<true/>#' "$f"
    echo "added network.client to $f"
  fi
done

# Android: INTERNET permission in the main manifest (debug has it, release does not).
m=android/app/src/main/AndroidManifest.xml
if [[ -f $m ]] && ! grep -q 'android.permission.INTERNET' "$m"; then
  perl -0pi -e 's#(<manifest[^>]*>)#$1\n    <uses-permission android:name="android.permission.INTERNET"/>#' "$m"
  echo "added INTERNET permission to $m"
fi

echo "Done. Linux builds need: sudo apt install libsecret-1-dev libgtk-3-dev"
