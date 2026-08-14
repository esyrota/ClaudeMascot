#!/bin/bash
set -e

# Get the directory this script is in
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Build paths
BUILD_DIR=".build/release"
APP_NAME="ClaudeMascot"
APP_BUNDLE="$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"

# Remove any existing app bundle for clean rebuild
rm -rf "$APP_BUNDLE"

# Build the release binary
echo "Building $APP_NAME..."
swift build -c release

# Create the app bundle structure
mkdir -p "$APP_MACOS"
mkdir -p "$APP_RESOURCES"

# Copy the binary
echo "Copying binary..."
cp "$BUILD_DIR/$APP_NAME" "$APP_MACOS/$APP_NAME"
chmod +x "$APP_MACOS/$APP_NAME"

# Copy the Info.plist
echo "Copying Info.plist..."
cp "Sources/ClaudeMascot/Resources/Info.plist" "$APP_CONTENTS/Info.plist"

# Ad-hoc sign the app
echo "Code signing..."
codesign --force --deep --sign - "$APP_BUNDLE"

# Print the final app path
FINAL_PATH="$(pwd)/$APP_BUNDLE"
echo "✓ $FINAL_PATH"
