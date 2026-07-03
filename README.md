# Screenshot Macro for macOS

macOS 전용 스크린샷 자동화 도구. 지정한 영역을 반복 캡처하면서 키보드/마우스 액션을 자동 실행합니다.

## Features

- **Macro Mode**: 지정 영역을 반복 캡처하며 키 입력 또는 마우스 클릭을 자동 실행 (시작 딜레이, 랜덤 딜레이 지원)
- **Headless Mode**: GUI 없이 `config.json`의 캡처 영역으로 매크로 실행 (자동화/스크립트용)
- **Duplicate Detection**: 퍼셉추얼 해시 기반 중복 이미지 탐지
- **Session Management**: 캡처 세션별 디렉토리 자동 생성 (`screenshots/01/`, `screenshots/02/`, ...)
- **Config Persistence**: GUI에서 설정 변경 시 `config.json`에 자동 저장
- **Dark/Light Theme**: Catppuccin Mocha(다크) / Latte(라이트) 테마 토글

## Requirements

- **macOS** (`screencapture` 명령어 필요)
- **Python 3.11+**
- **uv** (패키지 매니저)

## Installation

```bash
git clone https://github.com/seungwonme/ScreenshotMacro.git
cd ScreenshotMacro
uv sync
```

## Usage

```bash
# GUI 실행
uv run python -m src.cli run

# Headless 매크로 실행 (config.json의 캡처 영역 사용)
uv run python -m src.cli macro
uv run python -m src.cli macro -n 100 -k right -w 3  # 반복/키/시작 대기 오버라이드
uv run python -m src.cli macro --delay-min 0.5 --delay-max 2.0

# 스크린샷 정리
uv run python -m src.cli clean
uv run python -m src.cli clean -f  # 확인 없이 삭제

# 유틸리티
uv run python -m src.cli list             # 캡처된 스크린샷 목록
uv run python -m src.cli stats            # 통계
uv run python -m src.cli config           # 현재 설정 표시
uv run python -m src.cli find-duplicates  # 중복 이미지 탐지

# 디버그 로깅
uv run python -m src.cli -v run
```

### GUI 사용법

1. **Capture Area 설정**: 좌표 직접 입력, Drag Select, 또는 Pick Top-Left / Pick Bottom-Right 클릭
2. **Macro Settings 설정**:
   - **Repetitions**: 캡처 반복 횟수
   - **Start Delay (s)**: 매크로 시작 전 대기 시간
   - **Delay (s)**: 각 캡처 사이 딜레이 (Use Random Delay로 범위 지정 가능)
3. **Action 설정**: Keyboard (키 입력) 또는 Mouse Click (고정 좌표 또는 현재 커서 위치)
4. **Start Macro**로 실행, **Cancel**로 중지
5. Options 영역의 테마 버튼으로 다크/라이트 전환 (설정에 저장됨)

## Project Structure

```
screenshotMacro/
├── src/
│   ├── cli.py              # Typer 기반 CLI (run / macro / clean / list / stats / config / find-duplicates)
│   ├── config.py           # Dataclass 기반 설정 관리 (싱글톤 ConfigManager)
│   ├── gui_pyqt.py         # PyQt6 GUI
│   ├── theme.py            # 다크/라이트 테마 팔레트 + 스타일시트 빌더
│   ├── macro_pyqt.py       # QThread 기반 매크로 워커
│   ├── utils.py            # screencapture 래퍼, 파일 관리
│   └── find_duplicate_images.py  # 퍼셉추얼 해시 중복 탐지
├── tests/                  # pytest 테스트 (config / utils / macro worker / duplicates / cli)
├── config.json             # 런타임 설정
├── build_app.py            # PyInstaller 빌드 스크립트
├── ScreenshotMacro.spec    # PyInstaller 번들 스펙
└── pyproject.toml
```

## Development

```bash
# 테스트 실행
uv run pytest

# macOS .app 번들 빌드 (PyInstaller)
uv run python build_app.py
```

## Notes

- macOS 시스템 환경설정에서 Python에 화면 녹화 권한 필요
- 스크린샷은 `screenshots/` 하위 세션 디렉토리에 저장
- GUI 종료 시 현재 설정이 `config.json`에 자동 저장
