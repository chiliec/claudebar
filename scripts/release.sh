#!/bin/bash
set -e

VERSION="${1:?Usage: ./scripts/release.sh <version> (e.g. 1.1.0)}"
APP_NAME="ClaudeBar"
BUILD_DIR=".build/release"
BUNDLE_DIR="$BUILD_DIR/$APP_NAME.app"
ZIP_FILE="$BUILD_DIR/$APP_NAME.zip"
SIGN_IDENTITY="Apple Development: Vladimir Babin (8FNR8DGE9N)"

echo "==> Updating version to $VERSION"
sed -i '' "s/static let currentVersion = \".*\"/static let currentVersion = \"$VERSION\"/" Sources/ClaudeBarUI/Services/UpdateChecker.swift
sed -i '' "s/<string>[0-9]*\.[0-9]*\.[0-9]*<\/string>/<string>$VERSION<\/string>/g" Sources/ClaudeBar/Info.plist

echo "==> Building release"
swift build -c release

echo "==> Creating app bundle"
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$BUNDLE_DIR/Contents/MacOS/"
cp Sources/ClaudeBar/Info.plist "$BUNDLE_DIR/Contents/"
cp Sources/Resources/AppIcon.icns "$BUNDLE_DIR/Contents/Resources/"

echo "==> Signing"
codesign --force --sign "$SIGN_IDENTITY" "$BUNDLE_DIR"

echo "==> Zipping"
rm -f "$ZIP_FILE"
cd "$BUILD_DIR" && zip -r -q "$APP_NAME.zip" "$APP_NAME.app" && cd - > /dev/null

echo "==> Running tests"
swift test 2>&1 | tail -3

echo "==> Committing version bump"
git add Sources/ClaudeBarUI/Services/UpdateChecker.swift Sources/ClaudeBar/Info.plist
git diff --cached --quiet || git commit -m "release: v$VERSION"
git tag -f "v$VERSION"
git push origin main --tags --force

echo "==> Creating GitHub release"
NOTES_FILE=$(mktemp)
trap 'rm -f "$NOTES_FILE"' EXIT
cat > "$NOTES_FILE" <<NOTES
### Install

Paste this in Terminal:

\`\`\`bash
curl -fsSL https://github.com/chiliec/ClaudeBar/releases/latest/download/ClaudeBar.zip -o /tmp/cb.zip && \\
  unzip -oq /tmp/cb.zip -d /tmp && \\
  /usr/bin/xattr -dr com.apple.quarantine /tmp/ClaudeBar.app && \\
  rm -rf /Applications/ClaudeBar.app && \\
  mv /tmp/ClaudeBar.app /Applications/ && \\
  open /Applications/ClaudeBar.app
\`\`\`
NOTES
gh release create "v$VERSION" "$ZIP_FILE" \
    --title "ClaudeBar v$VERSION" \
    --notes-file "$NOTES_FILE"

echo "==> Done! Release: https://github.com/chiliec/ClaudeBar/releases/tag/v$VERSION"
