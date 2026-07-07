#!/bin/bash
# Build script to create a distributable DMG

set -e

APP_NAME="Build Notifier"
DMG_NAME="Build-Notifier"
VERSION="1.1.0"

# First build the app
echo "Building app..."
./build-app.sh

# Create DMG
echo "Creating DMG..."

# Create a temporary directory for DMG contents
DMG_TEMP="dmg-temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

# Copy app to temp directory
cp -r "$APP_NAME.app" "$DMG_TEMP/"

# Create a symbolic link to Applications folder
ln -s /Applications "$DMG_TEMP/Applications"

# Create the DMG
DMG_FILE="${DMG_NAME}-${VERSION}.dmg"
rm -f "$DMG_FILE"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$DMG_FILE"

# Clean up
rm -rf "$DMG_TEMP"

echo ""
echo "Done! DMG created: $DMG_FILE"
echo ""
echo "To install:"
echo "  1. Open $DMG_FILE"
echo "  2. Drag '$APP_NAME' to Applications"
echo ""
ls -lh "$DMG_FILE"
