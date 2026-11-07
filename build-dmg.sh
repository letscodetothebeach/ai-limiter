#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

SIGN_IDENTITY="${SIGN_IDENTITY:-$1}"

echo "==> Ensuring app is built..."
./build-app.sh "$SIGN_IDENTITY"

APP_NAME="AI Limiter"
DMG_NAME="AI-Limiter.dmg"
STAGING_DIR="/tmp/ai_limiter_dmg_staging"

echo "==> Preparing DMG staging area..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

cp -R "${APP_NAME}.app" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Creating compressed disk image: ${DMG_NAME}..."
rm -f "${DMG_NAME}"
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "${DMG_NAME}"

rm -rf "$STAGING_DIR"

SIGN_IDENTITY="${SIGN_IDENTITY:-$1}"
if [ -n "$SIGN_IDENTITY" ]; then
    echo "==> Signing DMG with identity: ${SIGN_IDENTITY}..."
    codesign --sign "${SIGN_IDENTITY}" "${DMG_NAME}"
fi

echo "==> Successfully created ${DMG_NAME} ($(du -sh "${DMG_NAME}" | cut -f1))"
