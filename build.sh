#!/bin/sh
# Builds PR Tracker.app without Xcode (Swift Package Manager + manual bundling).
set -eu
cd "$(dirname "$0")"

swift build -c release

if [ ! -f Resources/AppIcon.icns ]; then
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    swift Tools/make-icon.swift "$ICONSET"
    iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
    rm -rf "$ICONSET"
fi

APP="build/PR Tracker.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/PRTracker "$APP/Contents/MacOS/PRTracker"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

echo "Built: $APP"
echo "Run:   open \"$APP\""
