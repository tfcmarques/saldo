#!/bin/bash
# Builds a release Saldo.app and installs it to /Applications/Saldo.app.
set -euo pipefail
cd "$(dirname "$0")/.."

# Version comes from the newest vX.Y.Z tag, the build number from the commit count.
VERSION="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || echo v0.0.0)"
VERSION="${VERSION#v}"
BUILD="$(git rev-list --count HEAD)"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Saldo"

APP="build/Saldo.app"
INSTALL="/Applications/Saldo.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Saldo"

ICON_WORK="$(mktemp -d)"
ICONSET="$ICON_WORK/AppIcon.iconset"
swift scripts/draw-icon.swift "$ICON_WORK/source.png"
swift scripts/make-icon.swift "$ICON_WORK/source.png" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Saldo</string>
    <key>CFBundleDisplayName</key><string>Saldo</string>
    <key>CFBundleIdentifier</key><string>local.saldo.app</string>
    <key>CFBundleExecutable</key><string>Saldo</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.finance</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"

if pgrep -xq Saldo; then
  echo "Closing Saldo so /Applications/Saldo.app can be replaced..."
  osascript -e 'tell application "Saldo" to quit' >/dev/null 2>&1 || true
  for _ in $(seq 1 25); do
    pgrep -xq Saldo || break
    sleep 0.2
  done
fi

rm -rf "$INSTALL"
ditto "$APP" "$INSTALL"
codesign --force --sign - "$INSTALL"
echo "Updated $INSTALL to $VERSION ($BUILD)"
