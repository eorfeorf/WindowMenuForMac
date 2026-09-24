#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
CONFIGURATION="${1:-release}"
if [[ "$CONFIGURATION" != "debug" && "$CONFIGURATION" != "release" ]]; then
    echo "Usage: scripts/build-app.sh [debug|release]" >&2
    exit 1
fi
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/module-cache"
swift build -c "$CONFIGURATION" --disable-sandbox
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path --disable-sandbox)"
APP_DIR="$PROJECT_DIR/build/Window Menu.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/WindowsMenuForMac" "$APP_DIR/Contents/MacOS/WindowsMenuForMac"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
codesign --force --sign - --identifier local.ef.WindowsMenuForMac "$APP_DIR"
echo "Built: $APP_DIR"
