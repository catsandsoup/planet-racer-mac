#!/bin/zsh
# Build "Planet Racer.app" (arm64, macOS 26+) from the Swift package.
# The asset pack (assets/) must already be baked from your own planetracer.swf: see README.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --arch arm64 --product PlanetRacer
BIN=$(swift build -c release --arch arm64 --show-bin-path)/PlanetRacer
APP="dist/Planet Racer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Planet Racer"
sed -e 's/${MACOSX_BUNDLE_EXECUTABLE_NAME}/Planet Racer/' -e 's/${MACOSX_BUNDLE_GUI_IDENTIFIER}/com.planetracer.port/' \
    -e 's/${MACOSX_BUNDLE_BUNDLE_NAME}/Planet Racer/' -e 's/${MACOSX_BUNDLE_SHORT_VERSION_STRING}/0.1.0/' \
    -e 's/${MACOSX_BUNDLE_BUNDLE_VERSION}/1/' packaging/Info.plist.in > "$APP/Contents/Info.plist"
cp -R data assets "$APP/Contents/Resources/"
codesign --force --deep --sign - "$APP" >/dev/null
echo "built $APP"
