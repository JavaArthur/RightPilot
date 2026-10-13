#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="${ARCH:-$(uname -m)}"
APP="$PWD/dist/RightPilot.app"
EXT="$APP/Contents/PlugIns/RightPilotFinder.appex"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$EXT/Contents/MacOS"
xcrun swiftc -swift-version 5 -O -sdk "$SDK" -target "$ARCH-apple-macosx13.0" Sources/RightPilotCore/*.swift Shared/*.swift Sources/RightPilot/*.swift -o "$APP/Contents/MacOS/RightPilot"
xcrun swiftc -swift-version 5 -O -sdk "$SDK" -target "$ARCH-apple-macosx13.0" -module-name RightPilotFinder -parse-as-library -Xlinker -e -Xlinker _NSExtensionMain Sources/RightPilotCore/*.swift Shared/MenuRenderer.swift Shared/PilotArtwork.swift Sources/RightPilotFinder/*.swift -o "$EXT/Contents/MacOS/RightPilotFinder"
cp Resources/App-Info.plist "$APP/Contents/Info.plist"
cp Resources/Extension-Info.plist "$EXT/Contents/Info.plist"
mkdir -p .build/tools
xcrun swiftc -swift-version 5 Sources/RightPilotCore/*.swift Shared/PilotArtwork.swift scripts/make-icon.swift -o .build/tools/make-icon
.build/tools/make-icon "$APP/Contents/Resources"
IDENTITY="${SIGNING_IDENTITY:--}"
codesign --force --sign "$IDENTITY" --entitlements Resources/Extension.entitlements "$EXT"
codesign --force --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
printf '%s\n' "$APP"
