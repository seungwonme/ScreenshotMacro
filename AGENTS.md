# AGENTS.md

## Project Overview

macOS 전용 스크린샷 자동화 도구 (Swift). 대상 앱 윈도우를 백그라운드에서 반복 캡처하며 키/클릭 액션을 자동 실행한다. 핵심 가치는 "매크로가 도는 동안 다른 작업 가능" - ScreenCaptureKit 윈도우 캡처 + `CGEventPostToPid` 앱 타겟 이벤트로 포커스를 뺏지 않는다.

## Architecture

SwiftPM 패키지, 타깃 3개:

- `Sources/SMacroCore/Core.swift`: CLI/GUI 공유 로직.
  - 캡처: `frontWindow(ofPid:)`(앱의 최대 윈도우), `captureImage(window:area:)`(area는 창 기준 포인트 크롭), `captureThumbnail`, `savePNG`
  - 입력: `sendKey(code:toPid:)`/`sendClick(at:window:toPid:)`(백그라운드), `sendKeyGlobal`/`sendClickGlobal`(전면 모드, HID 전역), `ensureFrontmost`
  - 클릭은 AXPress 우선(Electron은 `AXManualAccessibility`로 AX 트리 강제 활성화, press 지원 조상 6단계 탐색) -> CGEvent 폴백. 반환값이 사용된 방식("AXPress"/"CGEvent")
  - 유틸: `nextSessionDir`(01, 02, ... 자동 번호), `fileHash`(파일 바이트 SHA256, 완전 동일 캡처만 탐지 - aHash는 문서/전자책처럼 레이아웃 균일한 캡처에서 오탐 심해 폐기), `collectPNGs`/`duplicateGroups`(중복 그룹핑, CLI·GUI 공용), `fileThumbnail`(축소 썸네일 디코드), `resolveApp`(이름 부분 일치, 정확 일치 > 도크 앱 랭킹)
- `Sources/smacro-gui/App.swift`: SwiftUI 위저드 GUI. 스텝 4개(대상 창 썸네일 그리드 -> 영역 드래그 -> 매크로 설정 -> 실행), 상단 스텝 바 초록 체크, 테스트 1회, 진행 바 + 실시간 컷. 매크로 종료 후 '끝나면 중복 자동 정리' 토글(기본 ON, `pruneDuplicates`)이 세션의 동일 프레임을 정리. 실행 단계의 '중복 정리' 버튼 -> 중복 미리보기 시트(체크박스, 전체 선택 기본 ON, 그룹당 1장 유지, 휴지통 삭제). 설정은 `@AppStorage`(UserDefaults).
- `Sources/smacro-proto/SMacro.swift`: CLI. `list`(윈도우) / `capture` / `send-key` / `macro` / `captures`(세션 현황) / `stats` / `clean`(휴지통) / `find-duplicates`(`--delete`로 그룹당 1장 남기고 휴지통).

## macOS 함정 (이 프로젝트에서 실측 확인된 것)

- **CLI에서 SCContentFilter 크래시**: 비 앱 번들 프로세스는 CGS 미초기화로 `CGS_REQUIRE_INIT` abort. 실행 초기에 `CGMainDisplayID()` 선호출 필수 (`initWindowServerConnection()`).
- **postToPid 이벤트 유실**: post 직후 프로세스 종료 시 flush 전에 유실. down/up 사이 20ms + 종료 전 50ms 대기.
- **백그라운드 클릭 무시**: 비활성 창 컨트롤은 합성 첫 클릭을 무시(acceptsFirstMouse). AXPress 경로가 해법. Electron(Discord 등)은 AX 트리가 기본 비활성 -> `AXManualAccessibility` 켜야 요소가 잡힘. 그래도 안 되면 전면 모드.
- **TCC 권한은 프로세스 계보 기준**: 터미널에 화면 기록/손쉬운 사용을 부여하면 `swift run` 자식이 상속. 백그라운드 에이전트(claude 등)에는 별도 부여 필요.

## Dev Commands

```bash
swift build                       # 전체 빌드 (GUI + CLI)
swift run smacro-gui              # GUI 실행
swift run smacro-proto <command>  # CLI
scripts/validate-swift-proto.sh   # E2E 검증 (권한 있는 터미널에서, TextEdit로 자동 판정)
```

## Change Log

- 2026-07-03: **Swift 전환 완료, Python(PyQt6) 코드 제거.** 구현 이력은 git 히스토리와 PR #1(Python 최종 안정화)·#2(Swift 전환) 참조.
  - Python 대비 상회: 백그라운드 캡처/입력(멀티태스킹 가능), 창 썸네일 선택, 창 기준 좌표(창 이동에 안전), 테스트 1회, 전면 호환 모드, clean이 휴지통 이동(복구 가능)
  - Python 대비 제외: "현재 커서 위치 클릭"(백그라운드 모델에서 무의미), 수동 테마 토글(시스템 추종)
