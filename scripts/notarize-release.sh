#!/bin/bash
set -e

# Usage: ./scripts/notarize-release.sh <version>
#
# Prerequisites:
#   1. "Developer ID Application" certificate installed in Keychain
#   2. App-specific password stored in Keychain:
#      xcrun notarytool store-credentials "claudebar-notarize" \
#        --apple-id "your@email.com" \
#        --team-id "YOUR_TEAM_ID" \
#        --password "xxxx-xxxx-xxxx-xxxx"
#   3. gh CLI authenticated: gh auth login

VERSION="${1:?Usage: ./scripts/notarize-release.sh <version> (e.g. 1.1.0)}"
APP_NAME="ClaudeBar"
BUILD_DIR=".build/release"
BUNDLE_DIR="$BUILD_DIR/$APP_NAME.app"
ZIP_FILE="$BUILD_DIR/$APP_NAME-v$VERSION.zip"
SIGN_IDENTITY="Developer ID Application"
KEYCHAIN_PROFILE="claudebar-notarize"

# Verify Developer ID certificate exists
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "ERROR: No 'Developer ID Application' certificate found."
    echo "Create one at: https://developer.apple.com/account/resources/certificates/list"
    exit 1
fi

# Verify notarytool credentials
if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" > /dev/null 2>&1; then
    echo "ERROR: Notarization credentials not found. Run:"
    echo "  xcrun notarytool store-credentials \"$KEYCHAIN_PROFILE\" \\"
    echo "    --apple-id \"your@email.com\" \\"
    echo "    --team-id \"YOUR_TEAM_ID\" \\"
    echo "    --password \"app-specific-password\""
    echo ""
    echo "Generate an app-specific password at: https://appleid.apple.com/account/manage"
    exit 1
fi

echo "==> Updating version to $VERSION"
sed -i '' "s/static let currentVersion = \".*\"/static let currentVersion = \"$VERSION\"/" Sources/Services/UpdateChecker.swift
sed -i '' "s/<string>[0-9]*\.[0-9]*\.[0-9]*<\/string>/<string>$VERSION<\/string>/g" Sources/Info.plist

echo "==> Building release"
swift build -c release

echo "==> Creating app bundle"
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$BUNDLE_DIR/Contents/MacOS/"
cp Sources/Info.plist "$BUNDLE_DIR/Contents/"
cp Sources/Resources/AppIcon.icns "$BUNDLE_DIR/Contents/Resources/"

echo "==> Signing with Developer ID (hardened runtime)"
codesign --force --sign "$SIGN_IDENTITY" --options runtime "$BUNDLE_DIR"

echo "==> Verifying signature"
codesign --verify --verbose=2 "$BUNDLE_DIR"

echo "==> Zipping for notarization"
rm -f "$ZIP_FILE"
cd "$BUILD_DIR" && zip -r -q "$APP_NAME-v$VERSION.zip" "$APP_NAME.app" && cd - > /dev/null

echo "==> Submitting for notarization (this may take a few minutes)..."
xcrun notarytool submit "$ZIP_FILE" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "$BUNDLE_DIR"

echo "==> Re-zipping with stapled ticket"
rm -f "$ZIP_FILE"
cd "$BUILD_DIR" && zip -r -q "$APP_NAME-v$VERSION.zip" "$APP_NAME.app" && cd - > /dev/null

echo "==> Running tests"
swift test 2>&1 | tail -3

echo "==> Committing version bump"
git add Sources/Services/UpdateChecker.swift Sources/Info.plist
git commit -m "release: v$VERSION"
git tag "v$VERSION"
git push origin main --tags

echo "==> Creating GitHub release"
gh release create "v$VERSION" "$ZIP_FILE" \
    --title "ClaudeBar v$VERSION" \
    --notes "$(cat <<NOTES
### Install

Download \`ClaudeBar-v$VERSION.zip\`, unzip, and move to Applications:

\`\`\`bash
mv ClaudeBar.app /Applications/
\`\`\`

This release is signed and notarized by Apple.
NOTES
)"

echo "==> Done! Release: https://github.com/chiliec/claudebar/releases/tag/v$VERSION"
