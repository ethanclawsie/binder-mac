#!/usr/bin/env bash
# Builds an Apple Silicon, ad-hoc signed mousebutton.app into ./dist.
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${VERSION:-$(cat VERSION 2>/dev/null || echo 1.0.0)}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
APP="dist/mousebutton.app"

echo "▸ Building mousebutton $VERSION ($BUILD)"
swift build -c release --arch arm64 --product mousebutton -Xswiftc -Osize -Xswiftc -gnone -Xlinker -dead_strip

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/arm64-apple-macosx/release/mousebutton "$APP/Contents/MacOS/mousebutton"
strip -x "$APP/Contents/MacOS/mousebutton"

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature with stable designated requirement preserving Accessibility permissions
codesign --force --sign - --requirements '=designated => identifier "com.ethanclawsie.mousebutton"' --timestamp=none "$APP"
codesign --verify --strict "$APP"

echo "✓ $APP ($(du -sh "$APP" | cut -f1 | xargs), $(lipo -archs "$APP/Contents/MacOS/mousebutton"))"
