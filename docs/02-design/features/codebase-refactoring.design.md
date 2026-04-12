# Design: ScreenshotMacro Codebase Refactoring

> Plan Reference: `docs/01-plan/features/codebase-refactoring.plan.md`

## 1. Implementation Order

```
Phase 1: Critical Fixes
  1-1. config.py - config path 수정 + default 통일
  1-2. pyproject.toml - dependency 정리
  1-3. (commit checkpoint)

Phase 2: Consistency Refactoring
  2-1. find_duplicate_images.py - loguru 전환 + modern type hints
  2-2. gui_pyqt.py - ESC 중복 처리 제거
  2-3. (commit checkpoint)

Phase 3: UX Improvements
  3-1. macro_pyqt.py - countdown signal 추가
  3-2. gui_pyqt.py - QProgressBar + QStatusBar + countdown 연결
  3-3. (commit checkpoint)
```

## 2. Phase 1: Critical Fixes

### 2.1 `src/config.py` - Config Path + Default 통일

**File**: `src/config.py`

#### Change 1: Project root 기반 config path (L199)

```python
# Before (L199)
_config_path: Path = Path("config.json")

# After
_config_path: Path = Path(__file__).resolve().parent.parent / "config.json"
```

**Rationale**: `Path("config.json")`은 CWD에 의존하므로, `uv run python -m src.cli run`을 프로젝트 루트 외에서 실행하면 config를 찾지 못함. `__file__` 기반으로 변경하면 실행 위치에 무관하게 동작.

#### Change 2: AreaConfig default 값 통일 (L17)

```python
# Before (L17)
top_left: tuple[int, int] = (0, 43)

# After
top_left: tuple[int, int] = (0, 45)
```

**Rationale**: `config.json`의 `top_left: [0, 45]`와 맞춤.

### 2.2 `pyproject.toml` - Dependency 정리

**File**: `pyproject.toml`

#### Change 1: pre-commit을 dev dependency로 이동

```toml
# Before (L7-16)
dependencies = [
    ...
    "pre-commit>=4.3.0",
    ...
]

# After
dependencies = [
    "imagehash>=4.3.2",
    "loguru>=0.7.0",
    "pillow>=11.3.0",
    "pyautogui>=0.9.54",
    "pynput>=1.8.1",
    "pyqt6>=6.8.0",
    "typer[all]>=0.16.0",
]

[dependency-groups]
dev = [
    "pre-commit>=4.3.0",
]
```

#### Change 2: black/isort target-version 수정

```toml
# Before
[tool.black]
target-version = ['py313']

[tool.isort]
py_version = 313

# After
[tool.black]
target-version = ['py311']

[tool.isort]
py_version = 311
```

## 3. Phase 2: Consistency Refactoring

### 3.1 `src/find_duplicate_images.py` - 전면 리팩토링

**File**: `src/find_duplicate_images.py`
**변경 범위**: 전체 파일

#### Change 1: Import 현대화

```python
# Before
import argparse
import logging
import os
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Optional, Set

import imagehash
from PIL import Image

# After
from __future__ import annotations

from collections import defaultdict
from pathlib import Path

import imagehash
from loguru import logger
from PIL import Image
```

- `argparse`, `logging`, `os` 제거
- `typing` 모듈 제거 (Python 3.11+ native 사용)
- `loguru` 추가

#### Change 2: Type hints 현대화

| Before | After |
|--------|-------|
| `Dict[K, V]` | `dict[K, V]` |
| `List[T]` | `list[T]` |
| `Optional[T]` | `T \| None` |
| `Set[T]` | `set[T]` |

#### Change 3: logging -> loguru 전환

모든 함수에서 `logger` 파라미터 제거. 모듈 레벨 `loguru.logger` 사용.

```python
# Before
def calculate_image_hash(image_path: Path, logger: logging.Logger) -> Optional[imagehash.ImageHash]:

# After
def calculate_image_hash(image_path: Path) -> imagehash.ImageHash | None:
```

영향받는 함수 시그니처:
- `calculate_image_hash(image_path, logger)` -> `calculate_image_hash(image_path)`
- `_collect_image_hashes(directory_path, image_extensions, logger)` -> `_collect_image_hashes(directory_path, image_extensions)`
- `find_duplicate_images(directory, hash_threshold, logger)` -> `find_duplicate_images(directory, hash_threshold)`
- `display_duplicate_groups(duplicates, logger)` -> `display_duplicate_groups(duplicates)`
- `setup_logger()` -> 삭제

#### Change 4: 독립 main/argparse 제거

```python
# 삭제할 코드
def setup_logger() -> logging.Logger: ...
def main(): ...
if __name__ == "__main__": ...
```

CLI에서만 호출되므로 독립 실행 불필요.

#### Change 5: cli.py 호출부 업데이트

**File**: `src/cli.py`

```python
# Before (L15-17)
from src.find_duplicate_images import display_duplicate_groups
from src.find_duplicate_images import find_duplicate_images as find_dupes
from src.find_duplicate_images import setup_logger

# After
from src.find_duplicate_images import display_duplicate_groups
from src.find_duplicate_images import find_duplicate_images as find_dupes
```

```python
# Before (L112-114) - find_duplicates command
dup_logger = setup_logger()
duplicates = find_dupes(directory, threshold, dup_logger)
display_duplicate_groups(duplicates, dup_logger)

# After
duplicates = find_dupes(directory, threshold)
display_duplicate_groups(duplicates)
```

### 3.2 `src/gui_pyqt.py` - ESC 중복 처리 제거

**File**: `src/gui_pyqt.py`

#### Change 1: QShortcut 제거 (L9-10, L83-86)

```python
# 삭제 (L10)
from PyQt6.QtGui import QKeySequence, QShortcut

# 변경
from PyQt6.QtGui import ...  # QKeySequence, QShortcut 제거 (사용처 없으면 import 자체 삭제)
```

```python
# 삭제 (L83-86)
def _setup_shortcuts(self) -> None:
    """Set up keyboard shortcuts."""
    self.escape_shortcut = QShortcut(QKeySequence("Escape"), self)
    self.escape_shortcut.activated.connect(self.close)
```

```python
# 삭제 (_init_window에서 _setup_shortcuts 호출 제거)
# L50
self._setup_shortcuts()  # 삭제
```

#### Change 2: _capture_keyboard_input에서 escape_shortcut 참조 제거 (L381-382, L412-413)

```python
# Before (L381-382)
if hasattr(self, "escape_shortcut"):
    self.escape_shortcut.setEnabled(False)

# After: 삭제 (escape_shortcut이 더 이상 존재하지 않음)
```

```python
# Before (L412-413)
if hasattr(self, "escape_shortcut"):
    self.escape_shortcut.setEnabled(True)

# After: 삭제
```

#### Change 3: keyPressEvent가 유일한 ESC 핸들러 (L509-521)

기존 `keyPressEvent`가 이미 ESC를 처리하므로 변경 불필요. 단, key capture 중 ESC 방지 로직은 유지.

```python
def keyPressEvent(self, event) -> None:
    if self.capturing_key:
        return
    if event.key() == Qt.Key.Key_Escape:
        if self.selecting_coordinates:
            self._stop_mouse_listener()
            self.selecting_coordinates = False
            self._restore_window()
        else:
            self.close()
    super().keyPressEvent(event)
```

## 4. Phase 3: UX Improvements

### 4.1 `src/macro_pyqt.py` - Countdown Signal 추가

**File**: `src/macro_pyqt.py`

#### Change 1: countdown signal 추가 (L23)

```python
class MacroWorker(QThread):
    finished = pyqtSignal()
    progress = pyqtSignal(int, int)      # current, total
    error = pyqtSignal(str)
    countdown = pyqtSignal(int)           # NEW: remaining seconds
    status_changed = pyqtSignal(str)      # NEW: status text
```

#### Change 2: run()에서 countdown emit (L58-61)

```python
# Before
initial_wait = self._config.macro.initial_wait
logger.info(f"Starting macro with {initial_wait}s initial wait")
time.sleep(initial_wait)

# After
initial_wait = self._config.macro.initial_wait
self.status_changed.emit("waiting")
for remaining in range(int(initial_wait), 0, -1):
    if self.should_stop:
        return
    self.countdown.emit(remaining)
    time.sleep(1)
# Handle fractional seconds
fraction = initial_wait - int(initial_wait)
if fraction > 0 and not self.should_stop:
    time.sleep(fraction)
self.status_changed.emit("running")
```

### 4.2 `src/gui_pyqt.py` - Progress Bar + Status Bar

**File**: `src/gui_pyqt.py`

#### Change 1: QProgressBar import 추가

```python
from PyQt6.QtWidgets import (
    ...
    QProgressBar,    # NEW
    QStatusBar,      # NEW (QMainWindow에 내장이지만 명시적 import)
    ...
)
```

#### Change 2: _setup_ui에 progress bar 추가

`_setup_buttons` 이후에 추가:

```python
def _setup_progress(self, layout: QVBoxLayout) -> None:
    """Set up progress bar."""
    self.progress_bar = QProgressBar()
    self.progress_bar.setRange(0, 100)
    self.progress_bar.setValue(0)
    self.progress_bar.setTextVisible(True)
    self.progress_bar.setFormat("%v / %m (%p%)")
    layout.addWidget(self.progress_bar)
```

#### Change 3: Status bar 활성화

```python
def _init_window(self) -> None:
    ...
    self.statusBar().showMessage("Ready")
```

#### Change 4: Signal 연결 업데이트 (_start_macro)

```python
self.worker.countdown.connect(self._update_countdown)
self.worker.status_changed.connect(self._update_status)
```

#### Change 5: 새 슬롯 메서드 추가

```python
def _update_countdown(self, remaining: int) -> None:
    """Update countdown display."""
    self.start_btn.setText(f"Starting in {remaining}s...")

def _update_status(self, status: str) -> None:
    """Update status bar."""
    messages = {
        "waiting": "Waiting to start...",
        "running": "Macro running",
    }
    self.statusBar().showMessage(messages.get(status, status))
```

#### Change 6: _update_progress 수정

```python
# Before
def _update_progress(self, count: int, total: int) -> None:
    self.start_btn.setText(f"Running... ({count}/{total})")

# After
def _update_progress(self, count: int, total: int) -> None:
    self.progress_bar.setRange(0, total)
    self.progress_bar.setValue(count)
    self.start_btn.setText(f"Running... ({count}/{total})")
    self.statusBar().showMessage(f"Capturing: {count}/{total}")
```

#### Change 7: _macro_finished 수정

```python
# After
def _macro_finished(self) -> None:
    self.start_btn.setEnabled(True)
    self.start_btn.setText("Start Macro")
    self.cancel_btn.setEnabled(False)
    self.progress_bar.setValue(0)
    self.statusBar().showMessage("Completed")
```

## 5. File Change Summary

| File | Phase | Changes |
|------|-------|---------|
| `src/config.py` | 1 | config path 수정, default 통일 (2곳) |
| `pyproject.toml` | 1 | pre-commit 이동, version 수정 (3곳) |
| `src/find_duplicate_images.py` | 2 | 전면 리팩토링 (loguru, modern types, main 제거) |
| `src/cli.py` | 2 | import/호출부 업데이트 (3곳) |
| `src/gui_pyqt.py` | 2+3 | ESC 중복 제거 + progress bar + status bar |
| `src/macro_pyqt.py` | 3 | countdown/status signal 추가 |
| `config.json` | - | 변경 없음 |

## 6. Dependency Impact

- 새로운 외부 dependency 없음
- 모든 변경은 기존 dependency 범위 내

## 7. Verification Checklist

각 Phase 완료 후 수동 검증:

### Phase 1
- [ ] `cd /tmp && uv run --project /path/to/project python -m src.cli config` -> config 정상 로드
- [ ] config.py default와 config.json 값 일치 확인
- [ ] `uv sync` 정상 완료

### Phase 2
- [ ] `uv run python -m src.cli find-duplicates` 정상 동작
- [ ] loguru 형식으로 로그 출력 확인
- [ ] ESC 키로 GUI 창 닫힘 확인
- [ ] Key capture 모드에서 ESC 방지 동작 확인

### Phase 3
- [ ] Start Macro 클릭 시 카운트다운 표시
- [ ] 매크로 실행 중 progress bar 업데이트
- [ ] status bar에 상태 메시지 표시
- [ ] Cancel 시 정상 중단 + UI 복원
