#!/bin/bash
set -e

APP_NAME="ClaudeBar"
BUILD_DIR=".build/release"
BUNDLE_DIR="$BUILD_DIR/$APP_NAME.app"

echo "Building release..."
swift build -c release

echo "Creating app bundle..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$BUNDLE_DIR/Contents/MacOS/"
cp Sources/App/Info.plist "$BUNDLE_DIR/Contents/"

echo "Signing..."
codesign --force --sign "Apple Development: Vladimir Babin (8FNR8DGE9N)" "$BUNDLE_DIR"

echo "Done: $BUNDLE_DIR"
echo "To install: cp -r $BUNDLE_DIR /Applications/"
