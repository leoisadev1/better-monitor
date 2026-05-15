#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Better Monitor"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
INSTALL_DIR="/Applications"
OPEN_APP=1

usage() {
    cat <<USAGE
Usage: scripts/install-better-monitor.sh [--user] [--system] [--no-open]

Builds Better Monitor, installs the app bundle, removes quarantine from that
installed bundle, verifies the ad-hoc signature, and opens the app.

Options:
  --user      Install to ~/Applications without sudo.
  --system    Install to /Applications. This is the default.
  --no-open   Install but do not launch the app.
  -h, --help  Show this help.
USAGE
}

while (($#)); do
    case "$1" in
    --user)
        INSTALL_DIR="$HOME/Applications"
        ;;
    --system)
        INSTALL_DIR="/Applications"
        ;;
    --no-open)
        OPEN_APP=0
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 64
        ;;
    esac
    shift
done

"$ROOT_DIR/scripts/package-better-monitor.sh" >/dev/null

TARGET_APP="$INSTALL_DIR/$APP_NAME.app"

if [[ "$INSTALL_DIR" == "$HOME/"* || "$INSTALL_DIR" == "$HOME" ]]; then
    mkdir -p "$INSTALL_DIR"
    rm -rf "$TARGET_APP"
    ditto "$APP_DIR" "$TARGET_APP"
    xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
else
    if [[ ! -d "$INSTALL_DIR" ]]; then
        echo "Install directory does not exist: $INSTALL_DIR" >&2
        exit 1
    fi
    if [[ -w "$INSTALL_DIR" ]]; then
        rm -rf "$TARGET_APP"
        ditto "$APP_DIR" "$TARGET_APP"
        xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
    else
        sudo rm -rf "$TARGET_APP"
        sudo ditto "$APP_DIR" "$TARGET_APP"
        sudo xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
    fi
fi

codesign --verify --deep --strict --verbose=2 "$TARGET_APP"

if [[ "$OPEN_APP" -eq 1 ]]; then
    open "$TARGET_APP"
fi

echo "Installed $TARGET_APP"
