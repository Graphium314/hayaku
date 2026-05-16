#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="HaYaku"
BUILD_DIR="$SCRIPT_DIR/.build/arm64-apple-macosx/release"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"

echo "==> Building $APP_NAME..."
cd "$SCRIPT_DIR"
swift build -c release

echo "==> Creating .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

echo "==> Ad-hoc signing..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "Done! Created: $APP_BUNDLE"
echo ""
echo "Run with:"
echo "  open '$APP_BUNDLE'"
echo ""
echo "Or drag to Applications folder and launch from Spotlight."
