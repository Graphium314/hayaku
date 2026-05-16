#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="HaYaku"
INSTALL_PATH="/Applications/$APP_NAME.app"
BUNDLE_ID="com.personal.HaYaku"

echo "==> Building $APP_NAME..."
cd "$SCRIPT_DIR"
./build-app.sh

echo "==> Installing to /Applications/..."
pkill -f "$APP_NAME" 2>/dev/null || true
sleep 1

rm -rf "$INSTALL_PATH"
cp -R "$SCRIPT_DIR/$APP_NAME.app" "$INSTALL_PATH"

echo "==> Resetting Accessibility permissions (TCC)..."
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true

echo ""
echo "Done! Launching $APP_NAME..."
echo ""
echo "次のステップ:"
echo "  1. メニューバーの 💬 アイコンをクリック → 「翻訳」を選択"
echo "  2. アクセシビリティ権限ダイアログが出たら「システム設定を開く」"
echo "  3. HaYaku にチェックを入れる"
echo "  4. アプリを終了して再起動"
echo ""

open "$INSTALL_PATH"
