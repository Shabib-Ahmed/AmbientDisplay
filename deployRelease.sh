#!/bin/bash
set -e

APP_NAME="AmbientDisplay"
SCHEME="AmbientDisplay" 
CONFIG="Release"
DEVICE_HOST="localhost"
DEVICE_PORT="2222"
REMOTE_DIR="/var/containers/Bundle/Application/AmbientDisplayDev" 

xcodebuild \
    -project            AmbientDisplay.xcodeproj \
    -scheme             "$SCHEME" \
    -configuration      "$CONFIG" \
    -sdk                iphoneos \
    -destination        "generic/platform=iOS" \
    -derivedDataPath    build CODE_SIGNING_ALLOWED=NO build

APP_PATH="build/Build/Products/$CONFIG-iphoneos/$APP_NAME.app"

codesign --force --sign - --entitlements entitlements.plist "$APP_PATH/$APP_NAME"

ssh -p $DEVICE_PORT root@$DEVICE_HOST "mkdir -p $REMOTE_DIR"
rsync -avz -e "ssh -p $DEVICE_PORT" "$APP_PATH" root@$DEVICE_HOST:$REMOTE_DIR/

ssh -p $DEVICE_PORT root@$DEVICE_HOST "uicache -p $REMOTE_DIR/$APP_NAME.app"

echo "Deploy Script Done" 
