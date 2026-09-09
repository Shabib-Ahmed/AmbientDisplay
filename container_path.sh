# Not meant to be run directly — source this from other scripts.
# Provides resolve_container_path(), which sets $CONTAINER_PATH or exits
# with an error if the app isn't installed / has no container.

BUNDLE_ID="${BUNDLE_ID:-com.causeifeltlikeit.AmbientDisplay}"

resolve_container_path() {
    local raw
    raw="$(ideviceinstaller list -b "$BUNDLE_ID" -a Container 2>/dev/null | tail -n +2)"

    # ideviceinstaller prints a quoted path on its own line, e.g.:
    #   "/private/var/mobile/Containers/Data/Application/<UUID>"
    CONTAINER_PATH="$(echo "$raw" | tr -d '\r' | sed 's/^"//;s/"$//' | xargs)"

    if [ -z "$CONTAINER_PATH" ]; then
        echo "Could not resolve a container path for $BUNDLE_ID." >&2
        echo "Is the app installed? Try running deploy.sh first." >&2
        exit 1
    fi
}
