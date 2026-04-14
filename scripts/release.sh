#!/bin/bash
set -e

VERSION="${1:?Usage: ./scripts/release.sh <version> (e.g. 1.1.0)}"
APP_NAME="ClaudeBar"
BUILD_DIR=".build/release"
BUNDLE_DIR="$BUILD_DIR/$APP_NAME.app"
ZIP_FILE="$BUILD_DIR/$APP_NAME-v$VERSION.zip"
SIGN_IDENTITY="Apple Development: Vladimir Babin (8FNR8DGE9N)"

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

echo "==> Signing"
codesign --force --sign "$SIGN_IDENTITY" "$BUNDLE_DIR"

echo "==> Zipping"
rm -f "$ZIP_FILE"
cd "$BUILD_DIR" && zip -r -q "$APP_NAME-v$VERSION.zip" "$APP_NAME.app" && cd - > /dev/null

echo "==> Running tests"
swift test 2>&1 | tail -3

echo "==> Committing version bump"
git add Sources/Services/UpdateChecker.swift Sources/Info.plist
git diff --cached --quiet || git commit -m "release: v$VERSION"
git tag -f "v$VERSION"
git push origin main --tags --force

echo "==> Creating GitHub release"
gh release create "v$VERSION" "$ZIP_FILE" \
    --title "ClaudeBar v$VERSION" \
    --notes "$(cat <<'NOTES'
### Install

Download `ClaudeBar.zip`, unzip, then run:

```bash
xattr -d com.apple.quarantine ClaudeBar.app
rm -rf /Applications/ClaudeBar.app && mv ClaudeBar.app /Applications/
```
NOTES
)"

echo "==> Done! Release: https://github.com/chiliec/claudebar/releases/tag/v$VERSION"
