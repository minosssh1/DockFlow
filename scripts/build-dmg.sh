#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$DIR")"
VOL_NAME="DockFlow"
RW_DMG="/tmp/DockFlow-rw.dmg"
FINAL_DMG="${HOME}/Desktop/DockFlow-Installer.dmg"
MOUNT_DIR="/Volumes/$VOL_NAME"

# Clean up any previous mounts or files
hdiutil detach "$MOUNT_DIR" 2>/dev/null || true
rm -f "$RW_DMG" "$FINAL_DMG"

echo "1. Creating read-write DMG image..."
hdiutil create -size 40m -volname "$VOL_NAME" -fs HFS+ -ov "$RW_DMG" >/dev/null

echo "2. Mounting image..."
hdiutil attach "$RW_DMG" -readwrite -nobrowse >/dev/null
sleep 1

APP_SRC="${1:-/Applications/DockFlow.app}"

echo "3. Copying app ($APP_SRC) and assets..."
mkdir -p "$MOUNT_DIR/.background"
if [ -f "$PROJECT_DIR/scripts/assets/dmg_background.png" ]; then
    cp "$PROJECT_DIR/scripts/assets/dmg_background.png" "$MOUNT_DIR/.background/background.png"
elif [ -f "/tmp/dmg_background.png" ]; then
    cp /tmp/dmg_background.png "$MOUNT_DIR/.background/background.png"
fi
cp -R "$APP_SRC" "$MOUNT_DIR/DockFlow.app"
ln -s /Applications "$MOUNT_DIR/Applications"

echo "4. Setting window layout via Finder..."
osascript << 'APPLESCRIPT'
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

echo "5. Finalizing image..."
sync
sleep 1
hdiutil detach "$MOUNT_DIR" >/dev/null

echo "6. Compressing into release DMG..."
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG" -ov >/dev/null
rm -f "$RW_DMG"

echo "✅ Done! Final DMG created at $FINAL_DMG"
ls -lh "$FINAL_DMG"
