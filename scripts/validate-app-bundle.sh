#!/bin/bash
# .app 번들이 실행 파일, 아이콘, Info.plist, SwiftPM resource bundle, 서명을 포함하는지 검증한다.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="ScreenshotMacro"
DEST="${1:-$(mktemp -d)}"
CLEANUP=0
if [[ $# -eq 0 ]]; then
    CLEANUP=1
fi

cleanup() {
    if [[ "$CLEANUP" -eq 1 && -n "$DEST" ]]; then
        /bin/rm -rf -- "$DEST"
    fi
}
trap cleanup EXIT

scripts/build-app.sh "$DEST"

APP="$DEST/$APP_NAME.app"
PLIST="$APP/Contents/Info.plist"
ICON="$APP/Contents/Resources/AppIcon.icns"

test -x "$APP/Contents/MacOS/$APP_NAME"
plutil -lint "$PLIST" >/dev/null
[[ "$(plutil -extract CFBundleIconFile raw -o - "$PLIST")" == "AppIcon" ]]
test -s "$ICON"
file "$ICON" | grep -q "Mac OS X icon"
find "$APP/Contents/Resources" -maxdepth 1 -type d -name "*.bundle" -print -quit | grep -q .
codesign --verify "$APP"

echo "OK: app bundle smoke passed ($APP)"
