# Screenshot Macro for macOS

macOS 전용 스크린샷 자동화 도구 (Swift). 대상 앱의 윈도우를 반복 캡처하면서 키 입력 또는 마우스 클릭을 자동 실행합니다.

핵심 특징: **매크로가 도는 동안 다른 작업을 할 수 있습니다.** ScreenCaptureKit으로 대상 창을 백그라운드(다른 창에 가려진 상태 포함)에서 캡처하고, `CGEventPostToPid`로 그 앱에만 키/클릭을 보내기 때문에 포커스를 뺏지 않습니다.

## Features

- **위저드 GUI**: 대상 창 선택(썸네일) -> 캡처 영역 드래그 지정 -> 매크로 설정 -> 테스트 후 실행
- **백그라운드 매크로**: 대상 창이 가려져 있어도 캡처, 키/클릭은 대상 앱에만 전송
- **전면 모드 (호환)**: 합성 입력을 무시하는 앱(Electron 등)용. HID 전역 이벤트로 하드웨어 입력과 동일 경로
- **액션**: 키 입력(키 캡처로 아무 키나 등록) 또는 마우스 클릭(미리보기에서 위치 지정, 창 기준 좌표)
- **영역 캡처**: 창 기준 상대 좌표 크롭 - 창을 옮겨도 좌표 유지
- **세션 관리**: 실행마다 `01/`, `02/`, ... 세션 디렉토리 자동 생성
- **중복 정리**: 파일 바이트 SHA256로 완전 동일 캡처를 그룹핑. GUI '중복 정리' 시트에서 미리보기 + 체크박스(전체 선택 기본 ON, 그룹당 1장 유지)로 확인 후 휴지통 삭제, CLI는 `--delete`
- **Headless CLI**: GUI 없이 스크립트/자동화에서 사용 가능

## Requirements

- macOS 14+ (ScreenCaptureKit)
- Swift 툴체인 (Xcode 또는 Command Line Tools)
- 권한: **화면 기록**(캡처), **손쉬운 사용**(키/클릭 전송) - 실행하는 터미널 앱에 부여

## Installation

```bash
git clone https://github.com/seungwonme/ScreenshotMacro.git
cd ScreenshotMacro
swift build
```

## GUI

```bash
swift run smacro-gui
```

1. **대상 창** - 모든 창이 실제 썸네일로 표시됩니다 (가려진 창, 다른 데스크톱 포함). 클릭하면 자동으로 미리보기 캡처.
2. **캡처 영역** - 창 전체 또는 미리보기 위 드래그로 영역 지정 (선택 밖은 딤 처리, 숫자 필드 동기화).
3. **매크로 설정** - 동작(키 캡처로 임의 키 / 미리보기 클릭으로 클릭 위치), 반복/시작 대기/랜덤 딜레이, 전면 모드 토글.
4. **실행** - **테스트 1회**(캡처 1장 + 액션 1회)로 확인 후 시작. 진행 바 + 남은 시간 + 방금 저장된 컷 실시간 표시. 완료 시 알림음 + 폴더 자동 열기.

상단 스텝 바에 단계별 완료가 초록 체크로 표시되고, 설정은 자동 저장됩니다(UserDefaults).

## CLI

```bash
# 대상 지정: --app <앱 이름 일부> 또는 --pid <숫자>
swift run smacro-proto list                                   # 캡처 가능한 윈도우 목록
swift run smacro-proto capture --app 미리보기 --out /tmp/t.png  # 단건 캡처 (가려져 있어도 OK)
swift run smacro-proto send-key --app 미리보기 --key right      # 키 전송 (포커스 불필요)

# 전체 매크로: 캡처 + 키 전송 반복, 도는 동안 다른 작업 가능
# --out 생략 시 captures/01, 02, ... 세션 디렉토리 자동 생성
# --area x,y,w,h: 창 좌상단 기준 포인트 좌표로 본문만 크롭
swift run smacro-proto macro --app 미리보기 --reps 300 --key right \
  --area 100,110,350,180 --wait 5 --delay-min 1 --delay-max 3
```

지원 키(CLI): `right` `left` `up` `down` `space` `return` `pageup` `pagedown` - GUI에서는 키 캡처로 아무 키나 등록 가능

### 유틸리티

```bash
# 기본 디렉토리 ./captures, --dir로 변경
swift run smacro-proto captures                         # 세션별 캡처 현황
swift run smacro-proto stats                            # 전체 통계
swift run smacro-proto clean [-f]                       # 캡처 전체 휴지통 이동 (-f: 확인 생략)
swift run smacro-proto find-duplicates [--delete] [-f] # 중복 캡처 탐지 (--delete: 그룹당 1장만 남기고 휴지통)
```

## Project Structure

```
ScreenshotMacro/
├── Package.swift
├── Sources/
│   ├── SMacroCore/Core.swift     # 공유 로직: 캡처, 키/클릭 전송, 권한, 세션 디렉토리, 해시
│   ├── smacro-gui/App.swift      # SwiftUI 위저드 GUI
│   └── smacro-proto/SMacro.swift # CLI (list/capture/send-key/macro/유틸리티)
├── scripts/
│   └── validate-swift-proto.sh   # 엔드투엔드 검증 (백그라운드 캡처·키 전송 자동 판정)
└── captures/                     # 캡처 출력 (세션별 번호 디렉토리, gitignore)
```

## Notes

- 최소화된 윈도우는 캡처할 수 없습니다 (가려진 창은 가능 - ScreenCaptureKit 제약)
- 백그라운드 클릭은 좌표의 AX 요소에 AXPress를 먼저 시도하고(Electron은 AX 트리 강제 활성화), 실패 시 CGEvent로 폴백합니다. 그래도 반응이 없는 앱은 전면 모드를 사용하세요
- 권한은 프로세스 계보 기준입니다. `swift run`으로 실행하면 터미널 앱의 화면 기록/손쉬운 사용 권한을 상속합니다
- 구 Python(PyQt6) 버전은 git 히스토리에서 확인할 수 있습니다 (2026-07 Swift 전환)
