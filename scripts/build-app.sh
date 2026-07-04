#!/bin/bash
# ScreenshotMacro.app 번들 빌드 + 설치
# 사용: scripts/build-app.sh [설치 폴더, 기본 ~/Applications]
#
# - release 빌드한 smacro-gui 바이너리를 .app 번들로 감싼다
# - Apple Development 인증서가 있으면 그걸로 서명 (재빌드해도 화면 기록/손쉬운 사용
#   TCC 권한 유지). 없으면 ad-hoc 서명 (재빌드마다 권한 재승인 필요)
# - 이전에 `swift run smacro-gui`로 쓰던 설정(UserDefaults 도메인 smacro-gui)이 있으면
#   앱 도메인으로 1회 이관한다
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="ScreenshotMacro"
BUNDLE_ID="com.seungwonme.ScreenshotMacro"
DEST="${1:-$HOME/Applications}"

echo "▸ release 빌드"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/smacro-gui"

APP="$DEST/$APP_NAME.app"
mkdir -p "$DEST"
# 빈 변수 사고 방지: 기대한 경로 모양일 때만 기존 번들 제거
if [[ "$APP" == *"/$APP_NAME.app" && -d "$APP" ]]; then
    /bin/rm -rf -- "$APP"
fi
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>Screenshot Macro</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" > /dev/null

IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development/{print $2; exit}')
if [[ -n "${IDENTITY}" ]]; then
    echo "▸ 서명: $IDENTITY"
    codesign --force --sign "$IDENTITY" "$APP"
else
    echo "▸ 서명: ad-hoc (재빌드 시 TCC 권한 재승인 필요)"
    codesign --force --sign - "$APP"
fi
codesign --verify "$APP"

# swift run 시절 설정 이관 (앱 도메인이 비어 있을 때 1회)
if defaults read smacro-gui > /dev/null 2>&1 \
    && ! defaults read "$BUNDLE_ID" > /dev/null 2>&1; then
    echo "▸ 기존 설정 이관 (smacro-gui -> $BUNDLE_ID)"
    defaults export smacro-gui - | defaults import "$BUNDLE_ID" -
fi

echo "완료: $APP"
