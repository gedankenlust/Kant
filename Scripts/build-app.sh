#!/bin/bash
#
# Builds Kant.app — a proper macOS application bundle.
#
# A bare `swift run` binary cannot reliably hold the permissions Kant needs
# (Accessibility / Input Monitoring for the global hotkey + mouse shortcut,
# Automation for running Apple Shortcuts). Those grants are tied to a stable
# bundle identifier and a code signature, so the app has to be packaged + signed.
#
# Usage:  ./Scripts/build-app.sh [--run]
#
set -euo pipefail

INSTALL_TO_APP=0
NOTARIZE=0
RUN_APP=0

for arg in "$@"; do
    case $arg in
        --run) RUN_APP=1 ;;
        --install) INSTALL_TO_APP=1 ;;
        --notarize) NOTARIZE=1 ;;
    esac
done

cd "$(dirname "$0")/.."

APP_NAME="Kant"
BUNDLE_ID="com.gedankenlust.kant"
VERSION="$(cat VERSION 2>/dev/null || echo "0.0.0")"
# Set SIGN_IDENTITY to a Developer ID (e.g. "Developer ID Application: Name (TEAMID)")
# for a stable signature that survives rebuilds; defaults to ad-hoc ("-").
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
BUILD_DIR=".build/release"
APP_DIR="build/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"

echo "▶ Building release binary…"
swift build -c release

echo "▶ Assembling ${APP_DIR}…"
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BUILD_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"

# App icon: generate it from code if it doesn't exist yet.
if [ ! -f "Resources/AppIcon.icns" ]; then
    ./Scripts/make-icon.sh
fi
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
    ICON_ENTRY="<key>CFBundleIconFile</key><string>AppIcon</string>"
else
    ICON_ENTRY=""
fi

# Menu-bar status icon (template image, tinted by macOS for light/dark).
if [ -f "Resources/MenuBarIcon.png" ]; then
    cp "Resources/MenuBarIcon.png" "${RESOURCES_DIR}/MenuBarIcon.png"
fi

cat > "${CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <!-- Menu-bar / accessory app: no Dock icon, no main window. -->
    <key>LSUIElement</key>
    <true/>
    ${ICON_ENTRY}
    <key>NSAppleEventsUsageDescription</key>
    <string>Kant runs the Apple Shortcuts you configure.</string>
</dict>
</plist>
PLIST

if [ "${SIGN_IDENTITY}" = "-" ]; then
    echo "▶ Ad-hoc code signing…"
else
    echo "▶ Code signing as: ${SIGN_IDENTITY}"
fi
codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP_DIR}"

echo "✓ Built ${APP_DIR} (v${VERSION})"
if [ "${SIGN_IDENTITY}" = "-" ]; then
    echo "  Note: ad-hoc signatures change each rebuild, so macOS may re-prompt for"
    echo "  permissions after every build. Set SIGN_IDENTITY to a Developer ID for a"
    echo "  stable identity (and notarize for distribution)."
fi

if [ "${NOTARIZE}" -eq 1 ] && [ "${SIGN_IDENTITY}" != "-" ]; then
    echo "▶ Notarizing app…"
    if [ -z "${APPLE_ID:-}" ] || [ -z "${APPLE_PASSWORD:-}" ] || [ -z "${TEAM_ID:-}" ]; then
        echo "Error: APPLE_ID, APPLE_PASSWORD, and TEAM_ID environment variables must be set for notarization."
        exit 1
    fi
    # Zip the app for notarization
    ditto -c -k --keepParent "${APP_DIR}" "build/${APP_NAME}.zip"
    xcrun notarytool submit "build/${APP_NAME}.zip" --apple-id "${APPLE_ID}" --password "${APPLE_PASSWORD}" --team-id "${TEAM_ID}" --wait
    echo "▶ Stapling ticket…"
    xcrun stapler staple "${APP_DIR}"
fi

FINAL_APP_PATH="${APP_DIR}"

if [ "${INSTALL_TO_APP}" -eq 1 ]; then
    echo "▶ Installing to /Applications…"
    # We use ditto because it correctly handles app bundles and extended attributes.
    # Note: If this fails with permission denied, you may need to run with sudo.
    
    # Quit any running instance to ensure we can overwrite
    pkill -x "${APP_NAME}" || true
    
    # Remove old version and copy new one
    rm -rf "/Applications/${APP_NAME}.app"
    ditto "${APP_DIR}" "/Applications/${APP_NAME}.app"
    
    # Force Finder to see the new modification date
    touch "/Applications/${APP_NAME}.app"
    
    FINAL_APP_PATH="/Applications/${APP_NAME}.app"
    echo "✓ Installed at ${FINAL_APP_PATH}"
fi

if [ "${RUN_APP}" -eq 1 ]; then
    echo "▶ Launching…"
    open "${FINAL_APP_PATH}"
fi
