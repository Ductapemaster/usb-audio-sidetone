#!/bin/bash
set -e

APP=Sidetone.app
MACOS=$APP/Contents/MacOS
RESOURCES=$APP/Contents/Resources

# Clean previous build
rm -rf "$APP"

# Create bundle structure
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

# Compile
clang -framework CoreAudio \
      -framework Foundation \
      -framework AppKit \
      -framework ServiceManagement \
      -fobjc-arc \
      -mmacosx-version-min=13.0 \
      -o "$MACOS/Sidetone" \
      main.m AppDelegate.m

# Copy Info.plist
cp Info.plist "$APP/Contents/Info.plist"

# Generate app icon
clang -framework AppKit -framework Foundation -fobjc-arc \
      -mmacosx-version-min=13.0 \
      -o make_icon make_icon.m
./make_icon
iconutil -c icns AppIcon.iconset -o "$RESOURCES/AppIcon.icns"
rm -rf AppIcon.iconset make_icon

echo "Built $APP"
