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

# Copy the animations INTO the bundle. AnimationLibrary looks these up via
# Bundle.main ("Contents/Resources/Animations"), so without this step the app
# builds and signs fine but cannot find a single animation at runtime.
echo "Copying animations..."
cp -R "Sources/ClaudeMascot/Resources/Animations" "$APP_RESOURCES/Animations"

ANIM_COUNT=$(find "$APP_RESOURCES/Animations" -maxdepth 1 -name '*.gif' | wc -l | tr -d ' ')
if [ "$ANIM_COUNT" -lt 6 ]; then
  echo "ERROR: expected at least 6 animations in the bundle, found $ANIM_COUNT" >&2
  exit 1
fi
echo "  $ANIM_COUNT animations bundled"

# Copy the Claude Code plugin INTO the bundle. The plugin payload must be signed
# with the app, so it is copied before codesign rather than installed separately.
echo "Copying plugin..."
mkdir -p "$APP_RESOURCES/ClaudeCodePlugin/.claude-plugin"
cp "packaging/marketplace.json" "$APP_RESOURCES/ClaudeCodePlugin/.claude-plugin/marketplace.json"
cp -R "plugin" "$APP_RESOURCES/ClaudeCodePlugin/plugin"

# Verify the plugin payload landed and the relay is executable
if [ ! -f "$APP_RESOURCES/ClaudeCodePlugin/.claude-plugin/marketplace.json" ]; then
  echo "ERROR: marketplace manifest not bundled" >&2
  exit 1
fi
if [ ! -f "$APP_RESOURCES/ClaudeCodePlugin/plugin/.claude-plugin/plugin.json" ]; then
  echo "ERROR: plugin manifest not bundled" >&2
  exit 1
fi
if [ ! -f "$APP_RESOURCES/ClaudeCodePlugin/plugin/hooks/hooks.json" ]; then
  echo "ERROR: hooks manifest not bundled" >&2
  exit 1
fi
if [ ! -x "$APP_RESOURCES/ClaudeCodePlugin/plugin/hooks/relay.sh" ]; then
  echo "ERROR: relay hook not executable in bundle" >&2
  exit 1
fi
echo "  plugin payload bundled"

# Ad-hoc sign the app
echo "Code signing..."
codesign --force --deep --sign - "$APP_BUNDLE"

# Print the final app path
FINAL_PATH="$(pwd)/$APP_BUNDLE"
echo "✓ $FINAL_PATH"
