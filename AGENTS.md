# AGENTS.md

## Project Overview

macOS 전용 스크린샷 자동화 도구. PyQt6 GUI에서 영역 지정 후 반복 캡처 + 키/마우스 액션 자동 실행.

## Architecture

- `src/config.py`: Dataclass 기반 설정 (`AppConfig` > `GuiConfig`, `MacroConfig`, `ScreenshotConfig`). 싱글톤 `ConfigManager`가 `config.json` 읽기/쓰기 담당.
- `src/cli.py`: Typer CLI. `run`, `macro`(헤드리스), `clean`, `list`, `stats`, `config`, `find-duplicates` 명령어 (+ `run`의 deprecated 별칭 `self`). loguru 로깅.
- `src/gui_pyqt.py`: PyQt6 메인 윈도우. 좌표 선택(드래그/클릭), 매크로 설정, 키 캡처. 다크/라이트 테마 토글, 세션 경로 표시, 완료 후 폴더 자동 열기, 에러는 상태바에 비차단 표시. 종료 시 설정 자동 저장.
- `src/theme.py`: 다크(Catppuccin Mocha)/라이트(Latte) 팔레트와 스타일시트 빌더. 두 테마가 한 템플릿을 공유.
- `src/macro_pyqt.py`: `MacroWorker(QThread)`. 초기 대기 → 반복 루프(딜레이 → 스크린샷 → 액션). 세션 디렉토리 자동 생성, 연속 실패 시 중단, `session_started` 시그널로 경로 통지.
- `src/utils.py`: `take_screenshot()` (macOS `screencapture` 래퍼), `get_next_count()`, `get_next_session_dir()`, `clean_screenshots()`, `list_screenshots()`.
- `src/find_duplicate_images.py`: `imagehash` 기반 퍼셉추얼 해싱으로 중복 이미지 탐지.

## Key Patterns

- `ActionConfig(type="click", position=None)`은 유효한 상태 ("현재 커서 위치에서 클릭")
- 스크린샷은 `screenshots/{세션번호}/` 하위에 저장 (세션 디렉토리 자동 생성)
- PyInstaller 번들 모드에서 `_get_base_dir()`이 `.app` 번들 외부 경로를 반환

## Dev Commands

```bash
uv sync                              # 의존성 설치
uv run python -m src.cli run         # GUI 실행
uv run python -m src.cli -v run      # 디버그 모드
uv run pytest                        # 테스트
```

## Change Log

- 2026-03-24: `gui_pyqt.py`에 Start Delay 입력 추가, `macro_pyqt.py`에서 명시적 `initial_wait` 우선 사용
- 2026-03-24: `ActionConfig(type="click", position=None)` 유효 상태로 허용
- 2026-04-12: ConfigManager 도입, CLI/GUI 전면 리팩토링, loguru 통합, dev 의존성 분리
- 2026-06-06: 전체 유지보수 — 버그 10건 수정(설정 일부 손상 시 전체 리셋 방지·잘못된 `action.type` 정규화·`closeEvent` 무한 대기 해소·빈 키 입력 방어·스크린샷 실패 시 페이지 건너뜀 방지·연속 실패 시 중단·중복 그룹화 single-linkage·정렬 키 타입 안정화·상대 경로 직렬화·`reload` 경로 추적), 데드코드 제거(`ConfigManager.update`, `take_screenshot` 도달 불가 분기, `get_next_count` 호출), 린트/포맷 정리, 회귀 테스트 +10(78→87), 의존성 전체 최신화(typer 0.26·pillow 12·pyqt6 6.11 등)
- 2026-06-06: 편의성 개선 — ① CLI 헤드리스 매크로(`macro` 명령, GUI 없이 자동화) ② 에러 알림을 모달에서 상태바로 ③ 세션 저장 경로 GUI 표시 ④ 완료 후 폴더 자동 열기 ⑤ 다크/라이트 테마 토글(`src/theme.py`, config `gui.theme` 저장) ⑥ 시스템 폰트 사용(SF Pro Text fallback 경고 제거). 테스트 87→94
- 2026-06-06: GUI 버그 수정 — ① 드래그/좌표/키 캡처가 모두 안 되던 근본 원인: pynput listener 스레드에서 `QTimer.singleShot`이 발화하지 않음(이벤트 루프 없음). `pyqtSignal`로 메인 스레드에 위임(`_drag_selected`/`_coordinate_picked`/`_mouse_position_picked`/`_key_captured`/`_selection_cancelled`). ② 좌표 동기화 시 `valueChanged` 재진입으로 좌표가 절반만 반영 → `_sync_coord_inputs`에서 `blockSignals`. ③ 창 높이(560 고정)가 콘텐츠보다 작아 테마 버튼 등 하단이 잘림 → `adjustSize()`로 콘텐츠에 맞춤
