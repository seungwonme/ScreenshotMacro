# smacro — Swift 버전 (GUI + CLI)

Python 버전이 구조적으로 못 하는 것을 검증하는 CLI 프로토타입입니다:

1. **포커스를 뺏지 않는 윈도우 캡처** — ScreenCaptureKit으로 특정 앱의 윈도우만 캡처 (다른 창에 가려져 있어도 캡처됨)
2. **특정 앱에만 키 전송** — `CGEventPostToPid`로 대상 앱에 직접 키 이벤트 전달 (포커스 불필요)

둘이 합쳐지면: **매크로가 도는 동안 맥으로 다른 작업을 할 수 있습니다.**

## 필요 권한 (시스템 설정 > 개인정보 보호 및 보안)

- **화면 기록**: `list` / `capture` / `macro` — 실행하는 터미널 앱에 부여
- **손쉬운 사용**: `send-key` / `macro` — 실행하는 터미널 앱에 부여

## GUI

```bash
cd swift
swift run smacro-gui
```

1. 대상 앱 선택 -> **미리보기 캡처**
2. 미리보기 위에서 드래그로 캡처 영역 지정 (비우면 창 전체)
3. 반복/키/딜레이 설정 후 **매크로 시작** — 도는 동안 다른 작업 가능
4. 완료되면 세션 폴더가 자동으로 열림. 설정은 자동 저장(UserDefaults)

터미널(권한 부여된 앱)에서 실행하면 화면 기록/손쉬운 사용 권한을 그대로 상속한다.

## CLI

```bash
cd swift
swift build

# 대상 지정은 --app <앱 이름 일부> (또는 --pid <숫자>)
swift run smacro-proto list                                   # 캡처 가능한 윈도우 목록
swift run smacro-proto capture --app 미리보기 --out /tmp/t.png  # 단건 캡처 (가려져 있어도 OK)
swift run smacro-proto send-key --app 미리보기 --key right      # 키 전송 (포커스 불필요)

# 전체 매크로: 캡처 + 키 전송 반복, 도는 동안 다른 작업 가능
# --out 생략 시 captures/01, 02, ... 세션 디렉토리 자동 생성
# --area x,y,w,h: 창 좌상단 기준 포인트 좌표로 본문만 크롭 (구버전의 영역 지정 대응,
#                 화면 좌표가 아니라 창 기준이므로 창을 옮겨도 좌표가 안 깨짐)
swift run smacro-proto macro --app 미리보기 --reps 300 --key right \
  --area 100,110,350,180 --wait 5 --delay-min 1 --delay-max 3
```

엔드투엔드 자동 검증: `../scripts/validate-swift-proto.sh` (2026-07-03 macOS 26.5.1에서 PASS 5/0)

지원 키: `right` `left` `up` `down` `space` `return` `pageup` `pagedown`
(GUI에서는 "키 캡처"로 아무 키나 등록 가능)

### 유틸리티 (기본 디렉토리 ./captures, --dir로 변경)

```bash
swift run smacro-proto captures                    # 세션별 캡처 현황
swift run smacro-proto stats                       # 전체 통계
swift run smacro-proto clean [-f]                  # 캡처 전체 휴지통 이동 (-f: 확인 생략)
swift run smacro-proto find-duplicates [--threshold 5]  # 중복 이미지 탐지 (기본 0=완전 동일)
```

## 한계 (프로토타입)

- 최소화된 윈도우는 캡처 불가 (ScreenCaptureKit 제약 — 가려진 창은 가능)
- 앱별 최대 크기 윈도우 하나만 대상
- 검증 완료 후 GUI(SwiftUI)와 중복 탐지(Vision FeaturePrint)를 이식할 예정
