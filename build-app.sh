#!/bin/bash
# Build script to create a proper macOS .app bundle with menubar-only mode

set -e

APP_NAME="Build Notifier"
BUNDLE_ID="com.buildnotifier.circleci"
VERSION="1.5.0"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ENTITLEMENTS_FILE="entitlements.plist"
ICONSET_DIR="BuildNotifier/Assets/AppIcon.iconset"
ICON_FILE="BuildNotifier/Assets/AppIcon.icns"
ICON_GENERATOR="scripts/generate-app-icon.swift"

# Load local secrets (e.g. SENTRY_DSN) if present. .env is gitignored.
if [ -f ".env" ]; then
    set -a
    . ./.env
    set +a
fi

# Bake the Sentry DSN into Info.plist so the packaged app (which can't read
# shell env) can report crashes. Omitted entirely when SENTRY_DSN is unset.
if [ -n "${SENTRY_DSN:-}" ]; then
    SENTRY_DSN_PLIST="    <key>SentryDSN</key>
    <string>${SENTRY_DSN}</string>"
else
    SENTRY_DSN_PLIST=""
fi

echo "Building BuildNotifier..."
swift build -c release

if [ "${REGENERATE_APP_ICON:-0}" = "1" ] && [ -f "$ICON_GENERATOR" ]; then
    echo "Creating icon source set..."
    swift "$ICON_GENERATOR"
fi

if [ -d "$ICONSET_DIR" ]; then
    echo "Generating app icon..."
    rm -f "$ICON_FILE"
    if ! iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"; then
        ICON_SOURCE="$ICONSET_DIR/icon_512x512@2x.png"
        if [ -f "$ICON_SOURCE" ]; then
            TEMP_TIFF="/tmp/build-notifier-app-icon.tiff"
            sips -s format tiff "$ICON_SOURCE" --out "$TEMP_TIFF" >/dev/null
            tiff2icns "$TEMP_TIFF" "$ICON_FILE"
            rm -f "$TEMP_TIFF"
        fi
    fi
fi

echo "Creating app bundle..."
APP_DIR="$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Clean up existing bundle
rm -rf "$APP_DIR"

# Create directory structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
cp .build/release/BuildNotifier "$MACOS_DIR/"

# Copy every SPM resource bundle (our own plus dependencies like LucideIcons).
# Missing a dependency's bundle crashes at runtime when its resources load.
for bundle in .build/release/*.bundle; do
    [ -e "$bundle" ] && cp -r "$bundle" "$RESOURCES_DIR/"
done

if [ -f "$ICON_FILE" ]; then
    cp "$ICON_FILE" "$RESOURCES_DIR/AppIcon.icns"
fi

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>BuildNotifier</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright 2025. All rights reserved.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
$SENTRY_DSN_PLIST
</dict>
</plist>
EOF

# Create PkgInfo
echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

# Sign the app. Defaults to ad-hoc signing, but callers can provide a local
# signing identity, for example:
#   SIGN_IDENTITY="Apple Development: Name (TEAMID)" ./build-app.sh
echo "Signing app bundle..."
if [ -f "$ENTITLEMENTS_FILE" ]; then
    codesign --force --deep --entitlements "$ENTITLEMENTS_FILE" --sign "$SIGN_IDENTITY" "$APP_DIR"
else
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
fi

if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "Signed with ad-hoc identity."
else
    echo "Signed with identity: $SIGN_IDENTITY"
fi

echo "Done! App bundle created at: $APP_DIR"

# The repo lives under ~/Documents, so a bundle left here gets registered with
# LaunchServices and makes macOS prompt for Documents access every launch. By
# default, install to /Applications and remove the repo copy. build-dmg.sh sets
# SKIP_INSTALL=1 because it needs the bundle in place to build the DMG.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -u "$PWD/$APP_DIR" >/dev/null 2>&1 || true

if [ "${SKIP_INSTALL:-0}" = "1" ]; then
    echo ""
    echo "Left in repo (SKIP_INSTALL=1). To run: open \"$APP_DIR\""
else
    echo "Installing to /Applications..."
    rm -rf "/Applications/$APP_NAME.app"
    cp -r "$APP_DIR" "/Applications/"
    "$LSREGISTER" -f "/Applications/$APP_NAME.app" >/dev/null 2>&1 || true
    rm -rf "$APP_DIR"
    echo "Installed at /Applications/$APP_NAME.app"
    echo "To run: open \"/Applications/$APP_NAME.app\""
fi
