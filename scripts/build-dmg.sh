#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$DIR")"
VOL_NAME="DockFlow"
RW_DMG="/tmp/DockFlow-rw.dmg"
OUT_DIR="${2:-${HOME}/Desktop}"
mkdir -p "$OUT_DIR"
FINAL_DMG="${OUT_DIR}/DockFlow-Installer.dmg"
FINAL_SHA="${FINAL_DMG}.sha256"
MOUNT_DIR="/Volumes/$VOL_NAME"
BUNDLE_STAGE="/tmp/DockFlow-build.app"
BUNDLE_ID="com.dockflow.app"

APP_SRC="${1:-}"
if [ -z "$APP_SRC" ]; then
    echo "0. Compiling DockFlow.app (arm64, macOS 14.0+)..."
    rm -rf "$BUNDLE_STAGE"
    mkdir -p "$BUNDLE_STAGE/Contents/MacOS" "$BUNDLE_STAGE/Contents/Resources"

    SWIFT_FILES=(
        "$PROJECT_DIR/DockMinimizer/L10n.swift"
        "$PROJECT_DIR/DockMinimizer/Services/LogService.swift"
        "$PROJECT_DIR/DockMinimizer/Services/HapticFeedbackService.swift"
        "$PROJECT_DIR/DockMinimizer/Services/AppExclusionManager.swift"
        "$PROJECT_DIR/DockMinimizer/Services/WindowClassifier.swift"
        "$PROJECT_DIR/DockMinimizer/Services/DockGeometryService.swift"
        "$PROJECT_DIR/DockMinimizer/Services/WindowMinimizer.swift"
        "$PROJECT_DIR/DockMinimizer/Services/AutoQuitter.swift"
        "$PROJECT_DIR/DockMinimizer/Services/UpdateService.swift"
        "$PROJECT_DIR/DockMinimizer/Services/DockMonitor.swift"
        "$PROJECT_DIR/DockMinimizer/Views/UpdateWindow.swift"
        "$PROJECT_DIR/DockMinimizer/AppDelegate.swift"
        "$PROJECT_DIR/DockMinimizer/DockMinimizerApp.swift"
    )

    swiftc "${SWIFT_FILES[@]}" \
        -o "$BUNDLE_STAGE/Contents/MacOS/DockFlow" \
        -parse-as-library \
        -target arm64-apple-macos14.0 \
        -O

    cp "$PROJECT_DIR/DockMinimizer/Info.plist" "$BUNDLE_STAGE/Contents/Info.plist"
    cp -R "$PROJECT_DIR/DockMinimizer/Resources/"* "$BUNDLE_STAGE/Contents/Resources/"
    APP_SRC="$BUNDLE_STAGE"
fi

# Clean up any previous mounts or files
hdiutil detach "$MOUNT_DIR" 2>/dev/null || true
rm -f "$RW_DMG" "$FINAL_DMG" "$FINAL_SHA"

echo "1. Signing app bundle ($APP_SRC)..."
if security find-identity -v -p codesigning | grep -q '"DockFlow"'; then
    codesign --force --deep -o runtime -s "DockFlow" -r="designated => identifier \"$BUNDLE_ID\"" "$APP_SRC"
else
    codesign --force --deep -s - -r="designated => identifier \"$BUNDLE_ID\"" "$APP_SRC"
fi
codesign --verify --deep --strict "$APP_SRC"

echo "2. Creating read-write DMG image..."
hdiutil create -size 40m -volname "$VOL_NAME" -fs HFS+ -ov "$RW_DMG" >/dev/null

echo "3. Mounting image..."
hdiutil attach "$RW_DMG" -readwrite -nobrowse >/dev/null
sleep 1

echo "4. Copying app and assets..."
mkdir -p "$MOUNT_DIR/.background"
if [ -f "$PROJECT_DIR/scripts/assets/dmg_background.png" ]; then
    cp "$PROJECT_DIR/scripts/assets/dmg_background.png" "$MOUNT_DIR/.background/background.png"
elif [ -f "/tmp/dmg_background.png" ]; then
    cp /tmp/dmg_background.png "$MOUNT_DIR/.background/background.png"
fi
cp -R "$APP_SRC" "$MOUNT_DIR/DockFlow.app"
ln -s /Applications "$MOUNT_DIR/Applications"

echo "5. Setting window layout via Finder..."
osascript << 'APPLESCRIPT' || true
tell application "Finder"
    tell disk "DockFlow"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 150, 860, 590}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 108
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "DockFlow.app" of container window to {165, 215}
        set position of item "Applications" of container window to {495, 215}
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

echo "6. Finalizing image..."
sync
sleep 1
hdiutil detach "$MOUNT_DIR" >/dev/null

echo "7. Compressing into release DMG and generating .sha256..."
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG" -ov >/dev/null
rm -f "$RW_DMG" "$BUNDLE_STAGE" 2>/dev/null || rm -rf "$RW_DMG" "$BUNDLE_STAGE"

(cd "$(dirname "$FINAL_DMG")" && shasum -a 256 "$(basename "$FINAL_DMG")" > "$(basename "$FINAL_SHA")")

echo "✅ Done! Final DMG & SHA-256 created:"
ls -lh "$FINAL_DMG" "$FINAL_SHA"
cat "$FINAL_SHA"
