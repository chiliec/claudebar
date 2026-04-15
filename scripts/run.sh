#!/bin/bash
set -e

APP_NAME="ClaudeBar"

# Use CODE_SIGN_IDENTITY env var if set, otherwise auto-detect
if [ -z "$CODE_SIGN_IDENTITY" ]; then
    CODE_SIGN_IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)".*/\1/')
fi

if [ -z "$CODE_SIGN_IDENTITY" ]; then
    echo "Warning: No Apple Development certificate found. Using ad-hoc signing."
    echo "  Keychain access will prompt for password on every run."
    echo "  Set CODE_SIGN_IDENTITY env var or install a development certificate."
    CODE_SIGN_IDENTITY="-"
fi

swift build
codesign --force --sign "$CODE_SIGN_IDENTITY" ".build/debug/$APP_NAME"
".build/debug/$APP_NAME"
