#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/container_path.sh"

DEVICE_HOST="localhost"
DEVICE_PORT="2222"

if [ -z "$1" ]; then
    echo "Usage: $0 <path-to-local-package-dir>"
    echo "  The dir must contain manifest.json (and optionally Theme/, Playlist/),"
    echo "  matching the layout PackageManager expects on-device."
    exit 1
fi

LOCAL_PACKAGE_DIR="$1"
MANIFEST_PATH="$LOCAL_PACKAGE_DIR/manifest.json"

if [ ! -f "$MANIFEST_PATH" ]; then
    echo "No manifest.json found at $MANIFEST_PATH" >&2
    exit 1
fi

PACKAGE_ID="$(python3 -c "import json; print(json.load(open('$MANIFEST_PATH'))['packageId'])")"

if [ -z "$PACKAGE_ID" ]; then
    echo "Could not read packageId from $MANIFEST_PATH" >&2
    exit 1
fi

resolve_container_path

REMOTE_PACKAGE_DIR="$CONTAINER_PATH/Documents/AmbientDisplay/Packages/$PACKAGE_ID"

echo "Pushing '$PACKAGE_ID' -> $REMOTE_PACKAGE_DIR"

AMBIENT_DIR="$CONTAINER_PATH/Documents/AmbientDisplay"

ssh -p "$DEVICE_PORT" "root@$DEVICE_HOST" \
    "mkdir -p '$REMOTE_PACKAGE_DIR' && chown -R mobile:mobile '$AMBIENT_DIR'"

rsync -avz --delete -e "ssh -p $DEVICE_PORT" \
    "$LOCAL_PACKAGE_DIR/" "root@$DEVICE_HOST:$REMOTE_PACKAGE_DIR/"

echo "Done. Relaunch the app to pick up the new/updated package."