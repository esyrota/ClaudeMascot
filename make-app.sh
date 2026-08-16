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

# Copy the icon. Info.plist names it via CFBundleIconFile, so the bundle shows a
# generic icon in Finder without this step -- LSUIElement keeps it out of the Dock,
# but Finder, Spotlight and the plugin-install alert all still show it.
# Rebuild it with `python art/make_icon.py` after changing art/sources/logo.gif.
echo "Copying icon..."
if [ ! -f "Sources/ClaudeMascot/Resources/AppIcon.icns" ]; then
  echo "ERROR: AppIcon.icns missing -- run: venv/bin/python art/make_icon.py" >&2
  exit 1
fi
cp "Sources/ClaudeMascot/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"

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

# Sign the app with a STABLE identity if one exists.
#
# This is a Bluetooth requirement, not a distribution one. macOS records the TCC
# grant against the bundle's designated requirement. Signed with a certificate,
# that requirement is "this bundle id, signed by this leaf" -- identical on every
# rebuild, so the grant survives. Ad-hoc signing (`--sign -`) has no certificate to
# name, so the requirement falls back to the *cdhash* of the binary, which changes
# on every build: macOS then sees each build as a different app and asks for
# Bluetooth permission again, every time. That is exactly the symptom
# `Docs/Reference/macOS Bluetooth TCC.md` describes.
#
# Any codesigning identity in the keychain does the job -- an Apple Development
# certificate, or a self-signed one from Keychain Access > Certificate Assistant.
# Set CODESIGN_IDENTITY to pick a specific one; otherwise the first is used.
echo "Code signing..."
if [ -z "${CODESIGN_IDENTITY:-}" ]; then
  CODESIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*) [0-9A-F]* "\(.*\)"$/\1/p' | head -n 1)
fi

if [ -n "$CODESIGN_IDENTITY" ]; then
  echo "  identity: $CODESIGN_IDENTITY"
  codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE"
else
  echo "  WARNING: no codesigning identity found -- falling back to ad-hoc." >&2
  echo "  macOS will re-prompt for Bluetooth on EVERY rebuild. Create a" >&2
  echo "  self-signed code-signing certificate in Keychain Access to stop that." >&2
  codesign --force --deep --sign - "$APP_BUNDLE"
fi

# Print the final app path
FINAL_PATH="$(pwd)/$APP_BUNDLE"
echo "✓ $FINAL_PATH"
