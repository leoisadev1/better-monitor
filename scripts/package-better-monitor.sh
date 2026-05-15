#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Better Monitor"
BUNDLE_ID="dev.leo.better-monitor"
APP_VERSION="${APP_VERSION:-$(cat "$ROOT_DIR/VERSION" 2>/dev/null || echo "0.1.0")}"
BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://github.com/leoisadev1/better-monitor/releases/latest/download/appcast.xml}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-jUMCVlXWl00ED/J8vVlEWsh/Lc/V43ldHQJgJQ2fy2o=}"
BUILD_DIR="$ROOT_DIR/.build/release"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
EXECUTABLE="$BUILD_DIR/better-monitor"
APP_ICON="$ROOT_DIR/Resources/AppIcon.icns"

cd "$ROOT_DIR"

swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"
cp "$EXECUTABLE" "$MACOS_DIR/$APP_NAME"
chmod 755 "$MACOS_DIR/$APP_NAME"
if [[ -f "$APP_ICON" ]]; then
    cp "$APP_ICON" "$RESOURCES_DIR/AppIcon.icns"
fi

if command -v install_name_tool >/dev/null 2>&1; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_NAME" 2>/dev/null || true
fi

while IFS= read -r framework; do
    framework_name="$(basename "$framework")"
    rm -rf "$FRAMEWORKS_DIR/$framework_name"
    ditto "$framework" "$FRAMEWORKS_DIR/$framework_name"
done < <(find -L "$BUILD_DIR" -maxdepth 4 -type d -name "Sparkle.framework" 2>/dev/null)

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
    <key>SUEnableInstallerLauncherService</key>
    <true/>
    <key>SUFeedURL</key>
    <string>$SPARKLE_FEED_URL</string>
PLIST

if [[ -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    cat >> "$CONTENTS_DIR/Info.plist" <<PLIST
    <key>SUPublicEDKey</key>
    <string>$SPARKLE_PUBLIC_ED_KEY</string>
PLIST
fi

cat >> "$CONTENTS_DIR/Info.plist" <<PLIST
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

echo "$APP_DIR"
