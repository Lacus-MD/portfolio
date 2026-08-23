#!/bin/zsh
# Lefordítja és elindítja a Portfólió appot az iPhone 17 szimulátoron.
cd "$(dirname "$0")"
UDID=$(xcrun simctl list devices available | grep "iPhone 17 (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -z "$UDID" ] && { echo "Nincs iPhone 17 szimulátor."; exit 1; }

command -v xcodegen >/dev/null && xcodegen generate
xcodebuild -project Portfolio.xcodeproj -scheme Portfolio \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath build build || exit 1

open -a Simulator
xcrun simctl boot "$UDID" 2>/dev/null
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" build/Build/Products/Debug-iphonesimulator/Portfolio.app
xcrun simctl launch "$UDID" hu.halasz.portfolio
