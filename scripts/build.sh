#!/bin/bash
# Builds Sova.app (Apple Silicon + Intel) without Xcode, ad-hoc signed, and zips it into dist/.
# Usage: scripts/build.sh [version]   (default: contents of VERSION)
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=${1:-$(cat VERSION)}

for ARCH in arm64 x86_64; do
  swift build -c release --triple "$ARCH-apple-macosx13.0" --scratch-path ".build/$ARCH"
done

APP=dist/Sova.app
rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create .build/arm64/release/Sova .build/x86_64/release/Sova -output "$APP/Contents/MacOS/Sova"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"

(cd dist && ditto -c -k --keepParent Sova.app "Sova-$VERSION.zip")
shasum -a 256 "dist/Sova-$VERSION.zip"
lipo -info "$APP/Contents/MacOS/Sova"
