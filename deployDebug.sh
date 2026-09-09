#!/bin/bash
set -e

APP_NAME="AmbientDisplay"
SCHEME="AmbientDisplay"
CONFIG="Debug"
BUNDLE_ID="com.causeifeltlikeit.AmbientDisplay"

xcodebuild \
    -project            AmbientDisplay.xcodeproj \
    -scheme             "$SCHEME" \
    -configuration      "$CONFIG" \
    -sdk                iphoneos \
    -destination        "generic/platform=iOS" \
    -derivedDataPath    build CODE_SIGNING_ALLOWED=NO build

BUILD_DIR="build/Build/Products/$CONFIG-iphoneos"
APP_PATH="$BUILD_DIR/$APP_NAME.app"

codesign --force --sign - --entitlements entitlements.plist "$APP_PATH/$APP_NAME"

IPA_PATH="$BUILD_DIR/$APP_NAME.ipa"
PAYLOAD_DIR="$BUILD_DIR/Payload"

rm -rf "$PAYLOAD_DIR" "$IPA_PATH"
mkdir -p "$PAYLOAD_DIR"
cp -R "$APP_PATH" "$PAYLOAD_DIR/"
( cd "$BUILD_DIR" && zip -qry "$APP_NAME.ipa" Payload )

if ! ideviceinstaller upgrade "$IPA_PATH"; then
    echo "Upgrade failed, falling back to a clean install..."
    ideviceinstaller uninstall "$BUNDLE_ID" >/dev/null 2>&1 || true
    ideviceinstaller install "$IPA_PATH"
fi

rm -rf "$PAYLOAD_DIR"

source "$(dirname "$0")/container_path.sh"
resolve_container_path
echo "Container: $CONTAINER_PATH"
echo "$CONTAINER_PATH" > .device_container_path

echo "Deploy Script Done"