#!/usr/bin/env bash
set -euo pipefail

REPOSITORY="${REPOSITORY:-leoisadev1/better-monitor}"
INSTALL_DIR="/Applications"
OPEN_APP=1

usage() {
    cat <<USAGE
Usage: install-latest.sh [--user] [--system] [--no-open]

Downloads the latest Better Monitor GitHub release, installs the app, removes
quarantine from that installed app bundle, and opens it.

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

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

api_url="https://api.github.com/repos/$REPOSITORY/releases/latest"
zip_url="$(
    /usr/bin/python3 - "$api_url" <<'PY'
import json
import sys
import urllib.request

with urllib.request.urlopen(sys.argv[1]) as response:
    release = json.load(response)

for asset in release.get("assets", []):
    name = asset.get("name", "")
    if name.startswith("Better-Monitor-") and name.endswith(".zip"):
        print(asset["browser_download_url"])
        raise SystemExit(0)

raise SystemExit("No Better-Monitor release zip found")
PY
)"

zip_path="$work_dir/Better-Monitor.zip"
curl -fL "$zip_url" -o "$zip_path"
ditto -x -k "$zip_path" "$work_dir"

source_app="$work_dir/Better Monitor.app"
target_app="$INSTALL_DIR/Better Monitor.app"

if [[ ! -d "$source_app" ]]; then
    echo "Release zip did not contain Better Monitor.app" >&2
    exit 1
fi

if [[ "$INSTALL_DIR" == "$HOME/"* || "$INSTALL_DIR" == "$HOME" ]]; then
    mkdir -p "$INSTALL_DIR"
    rm -rf "$target_app"
    ditto "$source_app" "$target_app"
    xattr -dr com.apple.quarantine "$target_app" 2>/dev/null || true
else
    if [[ -w "$INSTALL_DIR" ]]; then
        rm -rf "$target_app"
        ditto "$source_app" "$target_app"
        xattr -dr com.apple.quarantine "$target_app" 2>/dev/null || true
    else
        sudo rm -rf "$target_app"
        sudo ditto "$source_app" "$target_app"
        sudo xattr -dr com.apple.quarantine "$target_app" 2>/dev/null || true
    fi
fi

codesign --verify --deep --strict --verbose=2 "$target_app"

if [[ "$OPEN_APP" -eq 1 ]]; then
    open "$target_app"
fi

echo "Installed $target_app"
