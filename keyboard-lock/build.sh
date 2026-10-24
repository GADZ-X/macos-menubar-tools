#!/bin/bash
# KeyboardLock.app'i derler ve ~/Applications içine kurar.
# Kullanım: bash build.sh

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="KeyboardLock"
DEST="$HOME/Applications/$APP_NAME.app"
BUILD="$SRC_DIR/build"

echo "==> derleniyor"
rm -rf "$BUILD"
mkdir -p "$BUILD"
swiftc -O -o "$BUILD/$APP_NAME" "$SRC_DIR/main.swift" -framework Cocoa

echo "==> uygulama paketi oluşturuluyor"
rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS"
mv "$BUILD/$APP_NAME" "$DEST/Contents/MacOS/$APP_NAME"
cp "$SRC_DIR/Info.plist" "$DEST/Contents/Info.plist"

codesign --force --deep --sign - "$DEST" 2>/dev/null || \
  echo "    (codesign atlandı, sorun değil)"

rm -rf "$BUILD"

echo
echo "Kuruldu: $DEST"
echo "Başlatmak için:  open \"$DEST\""
echo
echo "NOT: yeniden derlendiğinde imza değişir, macOS Erişilebilirlik iznini"
echo "     tekrar isteyebilir. Bu normal."
