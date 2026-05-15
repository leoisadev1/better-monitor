#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Better Monitor"
APP_VERSION="${APP_VERSION:-$(cat "$ROOT_DIR/VERSION")}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
REPOSITORY="${GITHUB_REPOSITORY:-leoisadev1/better-monitor}"
TAG_NAME="${TAG_NAME:-v$APP_VERSION}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
ZIP_PATH="$DIST_DIR/Better-Monitor-$APP_VERSION.zip"
APPCAST_PATH="$DIST_DIR/appcast.xml"
RELEASE_NOTES_PATH="$DIST_DIR/release-notes.md"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://github.com/$REPOSITORY/releases/latest/download/appcast.xml}"

find_sparkle_tool() {
    local tool="$1"
    find "$ROOT_DIR/.build" -path "*/Sparkle/bin/$tool" -type f -perm -111 2>/dev/null | head -1
}

cd "$ROOT_DIR"

APP_VERSION="$APP_VERSION" \
BUILD_NUMBER="$BUILD_NUMBER" \
SPARKLE_FEED_URL="$SPARKLE_FEED_URL" \
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}" \
    "$ROOT_DIR/scripts/package-better-monitor.sh" >/dev/null

rm -f "$ZIP_PATH" "$APPCAST_PATH" "$RELEASE_NOTES_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

{
    echo "# Better Monitor $APP_VERSION"
    echo
    echo "Built from commit ${GITHUB_SHA:-$(git rev-parse --short HEAD 2>/dev/null || echo local)}."
    echo
    echo "Download the zip, unzip it, and move Better Monitor.app to Applications."
} > "$RELEASE_NOTES_PATH"

signature_attributes=""
sign_update="$(find_sparkle_tool sign_update || true)"
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" && -n "$sign_update" ]]; then
    private_key_file="$(mktemp)"
    trap 'rm -f "$private_key_file"' EXIT
    printf '%s' "$SPARKLE_PRIVATE_KEY" > "$private_key_file"
    signature_attributes="$("$sign_update" -f "$private_key_file" "$ZIP_PATH")"
elif [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" && -n "$sign_update" ]]; then
    signature_attributes="$("$sign_update" -f "$SPARKLE_PRIVATE_KEY_FILE" "$ZIP_PATH")"
else
    echo "warning: Sparkle signing key or sign_update tool missing; appcast will not be usable by Sparkle." >&2
fi

download_url="https://github.com/$REPOSITORY/releases/download/$TAG_NAME/$(basename "$ZIP_PATH")"
pub_date="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

cat > "$APPCAST_PATH" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Better Monitor Updates</title>
    <link>https://github.com/$REPOSITORY</link>
    <description>Better Monitor release feed</description>
    <item>
      <title>Better Monitor $APP_VERSION</title>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$APP_VERSION</sparkle:shortVersionString>
      <pubDate>$pub_date</pubDate>
      <enclosure url="$download_url" type="application/zip" $signature_attributes />
    </item>
  </channel>
</rss>
XML

echo "$ZIP_PATH"
echo "$APPCAST_PATH"
echo "$RELEASE_NOTES_PATH"
