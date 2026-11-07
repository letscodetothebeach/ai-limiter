#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "==> Ensuring AppIcon.icns exists..."
if [ ! -f "AppIcon.icns" ]; then
    swift generate-icon.swift
fi

echo "==> Building in release mode..."
swift build -c release

APP_NAME="AI Limiter"
BUNDLE_DIR="${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

cp .build/release/AILimiter "${MACOS_DIR}/AILimiter"
cp AppIcon.icns "${RESOURCES_DIR}/AppIcon.icns"

cat << 'EOF' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>AILimiter</string>
    <key>CFBundleIdentifier</key>
    <string>io.letscodetothebeach.ailimiter</string>
    <key>CFBundleName</key>
    <string>AI Limiter</string>
    <key>CFBundleDisplayName</key>
    <string>AI Limiter</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.1</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

chmod +x "${MACOS_DIR}/AILimiter"
touch "${BUNDLE_DIR}"

SIGN_IDENTITY="${SIGN_IDENTITY:-$1}"
if [ -n "$SIGN_IDENTITY" ]; then
    echo "==> Signing app bundle with identity: ${SIGN_IDENTITY}..."
    codesign --force --deep --options runtime --sign "${SIGN_IDENTITY}" "${BUNDLE_DIR}"
else
    echo "==> Ad-hoc signing app bundle (use SIGN_IDENTITY='...' to sign with Apple Developer)..."
    codesign --force --deep --sign - "${BUNDLE_DIR}"
fi

echo "==> Built successfully: ${BUNDLE_DIR} with AppIcon.icns"
