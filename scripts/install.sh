#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SOURCE="$PWD/dist/RightPilot.app"
DEST="${RIGHTPILOT_INSTALL_PATH:-$HOME/Applications/RightPilot.app}"
if [[ ! -d "$SOURCE" ]]; then bash scripts/build-app.sh; fi
if [[ -e "$DEST" ]]; then
    ACTUAL_ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$DEST/Contents/Info.plist")
    [[ "$ACTUAL_ID" == cn.aichanning.RightPilot ]] || { printf 'Destination belongs to another app: %s\n' "$DEST" >&2; exit 1; }
    # Stop only our own binaries before replacing a local installation.
    pkill -f "^$DEST/Contents/MacOS/RightPilot([[:space:]]|$)" || true
    pluginkit -e ignore -i cn.aichanning.RightPilot.Finder || true
    pkill -f "^$DEST/Contents/PlugIns/RightPilotFinder.appex/Contents/MacOS/RightPilotFinder([[:space:]]|$)" || true
fi
mkdir -p "$(dirname "$DEST")"
ditto "$SOURCE" "$DEST"
codesign --verify --deep --strict "$DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
pluginkit -a "$DEST/Contents/PlugIns/RightPilotFinder.appex"
pluginkit -e use -i cn.aichanning.RightPilot.Finder
pluginkit -m -v -i cn.aichanning.RightPilot.Finder
printf 'Installed: %s\nLaunch it and confirm Finder extension status in settings.\n' "$DEST"
