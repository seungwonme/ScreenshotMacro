#!/bin/zsh
# smacro-proto 엔드투엔드 검증 (화면 기록 + 손쉬운 사용 권한이 있는 터미널에서 실행)
# 검증: (1) 포커스 없는 윈도우 캡처 (2) 포커스 없는 앱으로의 키 전송
set -u
export SWIFT_BACKTRACE=enable=no  # 크래시 시 대화형 백트레이서가 스크립트를 멈추지 않게

cd "$(dirname "$0")/.." || exit 1
BIN=./.build/debug/smacro-proto
PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

echo "== 1. 빌드"
swift build -q || { echo "빌드 실패"; exit 1; }
ok "swift build"

echo "== 2. 윈도우 목록 (화면 기록 권한)"
if $BIN list > /tmp/smacro-list.txt 2>&1; then
  ok "list ($(wc -l < /tmp/smacro-list.txt | tr -d ' ')개 윈도우)"
else
  bad "list — $(cat /tmp/smacro-list.txt)"; echo "화면 기록 권한 없이는 진행 불가"; exit 1
fi

echo "== 3. TextEdit 준비 (테스트 대상, 새 문서)"
osascript -e 'tell application "TextEdit"
  activate
  make new document
end tell' > /dev/null || { bad "TextEdit 문서 생성 (자동화 권한 확인)"; exit 1; }
TE_PID=$(pgrep -x TextEdit | head -1)
ok "TextEdit pid=$TE_PID"

# 터미널을 다시 전면으로 -> TextEdit은 백그라운드가 됨
sleep 1
TERM_APP=$(osascript -e 'tell application "System Events" to get name of first process whose unix id is '"$PPID" 2>/dev/null)
open -a "${TERM_APP:-Ghostty}" 2>/dev/null; sleep 1

echo "== 4. 포커스 없는 윈도우 캡처"
if $BIN capture --pid "$TE_PID" --out /tmp/smacro-capture.png; then
  DIMS=$(sips -g pixelWidth -g pixelHeight /tmp/smacro-capture.png 2>/dev/null | awk '/pixel/ {printf "%s ", $2}')
  ok "백그라운드 캡처 -> /tmp/smacro-capture.png (${DIMS}px)"
else
  bad "capture"
fi

echo "== 4b. 영역 크롭 캡처 (--area 10,10,200,100 -> 2:1 비율)"
if $BIN capture --pid "$TE_PID" --area "10,10,200,100" --out /tmp/smacro-area.png; then
  W=$(sips -g pixelWidth /tmp/smacro-area.png 2>/dev/null | awk '/pixelWidth/ {print $2}')
  H=$(sips -g pixelHeight /tmp/smacro-area.png 2>/dev/null | awk '/pixelHeight/ {print $2}')
  if [ "${W:-0}" -eq $(( ${H:-1} * 2 )) ]; then
    ok "영역 크롭 (${W}x${H}px)"
  else
    bad "영역 크롭 비율 이상 (${W}x${H}px, 기대 2:1)"
  fi
else
  bad "영역 크롭 캡처"
fi

echo "== 5. 포커스 없는 키 전송 (space x5 -> TextEdit)"
KEYFAIL=0
for i in 1 2 3 4 5; do
  $BIN send-key --pid "$TE_PID" --key space || KEYFAIL=1
  sleep 0.2
done
sleep 0.5
# macOS 26 TextEdit에서 'length of text of document 1'은 -1728로 실패 -> count characters 사용
LEN=$(osascript -e 'tell application "TextEdit" to count characters of document 1' 2>&1)
if [ "$KEYFAIL" -eq 0 ] && [ "$LEN" = "5" ]; then
  ok "백그라운드 키 전송 (문서에 공백 5자 입력 확인)"
else
  bad "키 전송 — 문서 글자 수: $LEN (기대: 5). 손쉬운 사용 권한 확인"
fi

echo "== 6. 정리 (TextEdit 문서 저장 없이 닫기)"
osascript -e 'tell application "TextEdit" to close document 1 saving no' > /dev/null 2>&1

echo ""
echo "결과: PASS $PASS / FAIL $FAIL"
[ "$FAIL" -eq 0 ] && echo "-> 핵심 가설 검증 완료: 매크로 중 다른 작업 가능" || echo "-> 실패 항목 위 로그 참조"
exit "$FAIL"
