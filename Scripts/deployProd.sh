SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

set -e

APP_NAME="AmbientDisplay"
SCHEME="AmbientDisplay"
CONFIG="Release"
BUNDLE_ID="com.causeifeltlikeit.AmbientDisplay"

NO_INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --no-install) NO_INSTALL=1 ;;
        -h|--help)
            sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown option: $arg (try --help)" >&2
            exit 2
            ;;
    esac
done

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

# Version comes from the built app, so it always matches what was compiled.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Info.plist")"
echo "Packaging $APP_NAME $VERSION (build $BUILD_NUMBER)"

PAYLOAD_DIR="$BUILD_DIR/Payload"
STAGED_IPA="$BUILD_DIR/$APP_NAME.ipa"

rm -rf "$PAYLOAD_DIR" "$STAGED_IPA"
mkdir -p "$PAYLOAD_DIR"
cp -R "$APP_PATH" "$PAYLOAD_DIR/"
( cd "$BUILD_DIR" && zip -qry "$APP_NAME.ipa" Payload )
rm -rf "$PAYLOAD_DIR"

mkdir -p dist
IPA_PATH="dist/$APP_NAME-$VERSION.ipa"
cp "$STAGED_IPA" "$IPA_PATH"
echo "IPA: $IPA_PATH"

if [ "$NO_INSTALL" -eq 1 ]; then
    echo "Skipping install (--no-install)."
    echo "Deploy Script Done"
    exit 0
fi

if ideviceinstaller list 2>/dev/null | grep -q "$BUNDLE_ID"; then
    if ! ideviceinstaller upgrade "$IPA_PATH"; then
        echo "" >&2
        echo "In-place upgrade failed. Not uninstalling, because that would delete the" >&2
        echo "app's installed packages and settings. Fix the error above, or uninstall" >&2
        echo "by hand if you accept losing that data, then re-run." >&2
        exit 1
    fi
else
    ideviceinstaller install "$IPA_PATH"
fi

echo "Deploy Script Done"
