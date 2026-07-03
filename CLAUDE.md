# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ScreenshotMacro is a macOS-specific Python automation tool for screenshot capture and processing. The tool provides automated screenshot capturing with keyboard automation and utilities for cleanup and duplicate detection.

## Development Commands

### Installation and Setup
```bash
# Install dependencies with uv
uv sync

# Run the application (GUI-based)
uv run python -m src.cli run     # Launch GUI for macro mode
uv run python -m src.cli macro   # Run macro headless (no GUI) using the config's capture area
uv run python -m src.cli clean   # Remove all screenshots
uv run python -m src.cli config  # Display current configuration

# Utility commands
uv run python -m src.cli find-duplicates  # Find duplicate images
uv run python -m src.cli list             # List captured screenshots
uv run python -m src.cli stats            # Show capture statistics

# Verbose mode (debug logging)
uv run python -m src.cli -v run
```

## Architecture

### Project Structure
```
screenshotMacro/
├── src/
│   ├── __init__.py
│   ├── cli.py              # CLI entry point (typer-based)
│   ├── config.py           # Unified configuration management
│   ├── gui_pyqt.py         # PyQt6 GUI implementation
│   ├── theme.py            # GUI theme palettes (dark/light) + stylesheet builder
│   ├── macro_pyqt.py       # Screenshot macro worker thread
│   ├── utils.py            # Utility functions (screenshot, cleanup)
│   └── find_duplicate_images.py  # Image duplicate detection
├── tests/                  # pytest suite (config, utils, macro worker, duplicates)
├── build_app.py            # PyInstaller build script
├── ScreenshotMacro.spec    # PyInstaller bundle spec
├── config.json             # Runtime configuration
├── pyproject.toml          # Project configuration
└── screenshots/            # Screenshot output (numbered session subdirs)
```

### Core Components

1. **Configuration (`src/config.py`)**
   - Dataclass-based configuration with validation
   - Singleton `ConfigManager` for centralized config access
   - Auto-loading from `config.json` with defaults fallback

2. **CLI (`src/cli.py`)**
   - Typer-based CLI with rich output
   - Loguru logging integration
   - Commands: run, macro (headless), clean, list, stats, config, find-duplicates (plus a deprecated `self` alias for `run`)

3. **GUI (`src/gui_pyqt.py`)**
   - PyQt6 main window with area selection
   - Coordinate capture via mouse click/drag
   - Keyboard key capture for action binding
   - Dark/light theme toggle (palettes in `src/theme.py`), session-path display, auto-open-on-finish
   - Errors surface in the status bar (non-blocking)

4. **Macro Worker (`src/macro_pyqt.py`)**
   - QThread-based background execution
   - Progress signals for UI updates
   - Error handling with signals

5. **Utilities (`src/utils.py`)**
   - `take_screenshot()`: macOS screencapture wrapper with error handling
   - `get_next_count()`: File index calculation
   - `clean_screenshots()`: Bulk file deletion
   - `list_screenshots()`: Directory listing with sorting

### Key Dependencies
- `typer[all]`: CLI framework with rich support
- `loguru`: Structured logging
- `pyqt6`: GUI framework
- `pyautogui`: GUI automation
- `pynput`: Keyboard/mouse event monitoring
- `imagehash`: Perceptual hashing for duplicate detection
- `pillow`: Image processing

### Configuration (`config.json`)
```json
{
  "gui": {
    "window_size": "900x500",
    "default_area": {
      "top_left": [0, 45],
      "bottom_right": [765, 1169]
    }
  },
  "macro": {
    "default_repetitions": 300,
    "default_delay": { "min": 1.0, "max": 3.0 },
    "action": { "type": "key", "key": "right" },
    "initial_wait": 5.0
  },
  "screenshot": {
    "directory": "./screenshots",
    "format": "png",
    "prefix": "screenshot"
  }
}
```

## Important Notes

1. **macOS Only**: Requires `screencapture` command (macOS native)
2. **Permissions**: Screen recording permission required for Python
3. **Screenshot Storage**: Each run saves into a new numbered session subdirectory (`screenshots/01/`, `screenshots/02/`, ...) created by `get_next_session_dir()`; the base directory is configurable
4. **Logging**: Uses loguru - enable debug with `-v` flag
5. **Tests**: pytest 테스트 존재 (`tests/test_config.py`, `tests/test_utils.py`, `tests/test_macro_worker.py`, `tests/test_find_duplicates.py`)
