#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

SIGN_IDENTITY="${SIGN_IDENTITY:-$1}"
if [ -z "$SIGN_IDENTITY" ]; then
    DETECTED_ID=$(security find-identity -p codesigning -v 2>/dev/null | grep "Developer ID Application:" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
    if [ -n "$DETECTED_ID" ]; then
        SIGN_IDENTITY="$DETECTED_ID"
    fi
fi

NOTARY_PROFILE="${NOTARY_PROFILE:-${2:-claude-pool-notary}}"

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

if [ -n "$SIGN_IDENTITY" ]; then
    echo "==> Signing DMG with identity: ${SIGN_IDENTITY}..."
    codesign --force --timestamp --sign "${SIGN_IDENTITY}" "${DMG_NAME}"
fi

# Notarize and staple if identity is Developer ID and notary profile is configured
if [ "$NO_NOTARIZE" != "1" ] && [ -n "$SIGN_IDENTITY" ]; then
    if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        echo "==> Submitting ${DMG_NAME} to Apple notary service (profile: ${NOTARY_PROFILE})..."
        xcrun notarytool submit "${DMG_NAME}" --keychain-profile "${NOTARY_PROFILE}" --wait
        
        echo "==> Stapling notarization ticket to ${DMG_NAME}..."
        xcrun stapler staple "${DMG_NAME}"
        
        echo "==> Stapling notarization ticket to ${APP_NAME}.app..."
        xcrun stapler staple "${APP_NAME}.app" || true

        echo "==> Verifying notarization with spctl..."
        spctl -a -t open --context context:primary-signature -v "${DMG_NAME}"
        spctl -a -t exec -v "${APP_NAME}.app"
    else
        echo "==> Skipping notarization: keychain profile '${NOTARY_PROFILE}' not found."
        echo "    To set up credentials: xcrun notarytool store-credentials \"${NOTARY_PROFILE}\" --apple-id ... --team-id ..."
    fi
fi

echo "==> Successfully created ${DMG_NAME} ($(du -sh "${DMG_NAME}" | cut -f1))"
