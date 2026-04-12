# AGENTS.md

## Project Overview

macOS 전용 스크린샷 자동화 도구. PyQt6 GUI에서 영역 지정 후 반복 캡처 + 키/마우스 액션 자동 실행.

## Architecture

- `src/config.py`: Dataclass 기반 설정 (`AppConfig` > `GuiConfig`, `MacroConfig`, `ScreenshotConfig`). 싱글톤 `ConfigManager`가 `config.json` 읽기/쓰기 담당.
- `src/cli.py`: Typer CLI. `run`, `clean`, `list`, `stats`, `config`, `find-duplicates` 명령어. loguru 로깅.
- `src/gui_pyqt.py`: PyQt6 메인 윈도우. 좌표 선택(드래그/클릭), 매크로 설정, 키 캡처. Catppuccin Mocha 테마. 종료 시 설정 자동 저장.
- `src/macro_pyqt.py`: `MacroWorker(QThread)`. 초기 대기 → 반복 루프(딜레이 → 스크린샷 → 액션). 세션 디렉토리 자동 생성.
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
