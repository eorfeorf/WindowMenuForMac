#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
APP_NAME="Window Menu"
IDENTIFIER="local.ef.WindowsMenuForMac"
DIST_DIR="$PROJECT_DIR/dist"
BUILD_ROOT="$PROJECT_DIR/.build/release-universal"
ARM64_ROOT="$BUILD_ROOT/arm64"
X86_64_ROOT="$BUILD_ROOT/x86_64"
APP_DIR="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION-universal.dmg"
ZIP_PATH="$DIST_DIR/$APP_NAME-$VERSION-universal.zip"

mkdir -p "$DIST_DIR" "$BUILD_ROOT"

echo "Building Apple Silicon release..."
CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/clang-arm64" \
SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ROOT/modules-arm64" \
swift build -c release --triple arm64-apple-macosx13.0 --scratch-path "$ARM64_ROOT" --disable-sandbox

echo "Building Intel release..."
CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/clang-x86_64" \
SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ROOT/modules-x86_64" \
swift build -c release --triple x86_64-apple-macosx13.0 --scratch-path "$X86_64_ROOT" --disable-sandbox

ARM64_BIN="$ARM64_ROOT/arm64-apple-macosx/release/WindowsMenuForMac"
X86_64_BIN="$X86_64_ROOT/x86_64-apple-macosx/release/WindowsMenuForMac"
for binary in "$ARM64_BIN" "$X86_64_BIN"; do
    if [[ ! -x "$binary" ]]; then
        echo "Expected release binary was not produced: $binary" >&2
        exit 1
    fi
done

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
lipo -create "$ARM64_BIN" "$X86_64_BIN" -output "$APP_DIR/Contents/MacOS/WindowsMenuForMac"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
codesign --force --sign - --identifier "$IDENTIFIER" "$APP_DIR"

STAGE_DIR="$(mktemp -d "$DIST_DIR/.dmg-stage.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
ditto "$APP_DIR" "$STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$STAGE_DIR/Applications"
cp "$DIST_DIR/インストール方法.txt" "$STAGE_DIR/インストール方法.txt"

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH"

(cd "$DIST_DIR" && shasum -a 256 "$APP_NAME-$VERSION-universal.dmg" "$APP_NAME-$VERSION-universal.zip" > SHA256SUMS.txt)

echo "Built universal app: $APP_DIR"
echo "Built installer disk image: $DMG_PATH"
echo "Built app archive: $ZIP_PATH"
