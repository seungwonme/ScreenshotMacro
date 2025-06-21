# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ScreenshotMacro is a macOS-specific Python automation tool for screenshot capture and processing. The tool provides automated screenshot capturing with keyboard automation, manual capture via keypress events, and utilities for cleanup and duplicate detection.

## Development Commands

### Installation and Setup
```bash
# Install package and dependencies
pip install -e .

# Run the application in different modes
screenshot-macro run    # Macro mode: Automated capture with delays
screenshot-macro self   # Self mode: Manual capture via right arrow key
screenshot-macro clean  # Clean mode: Remove all screenshots

# Find duplicate images
python find_duplicate_images.py -d ./screenshots -t 0
```

### Code Quality (when configured)
```bash
# Format code with Black
black . --line-length 88

# Run linting
flake8 --max-line-length=100
pylint src/

# Sort imports
isort .
```

## Architecture

### Core Components

1. **Entry Points**
   - `main.py`: CLI argument parsing and mode selection
   - `find_duplicate_images.py`: Standalone duplicate detection using perceptual hashing

2. **Mode Implementations** (in `src/`)
   - `macro.py`: MacroMode class - automated capture with configurable delays
   - `self.py`: SelfMode class - manual capture triggered by right arrow key
   - `utils.py`: Shared utilities including screenshot capture and PDF conversion

3. **Platform Integration**
   - Uses macOS native `screencapture` command for screenshots
   - Requires screen recording permissions in System Preferences
   - GUI built with tkinter for cross-platform compatibility

### Key Dependencies
- `pyautogui`: GUI automation and keyboard simulation
- `pynput`: Keyboard event monitoring
- `imagehash`: Perceptual hashing for duplicate detection
- `Pillow`: Image processing and PDF generation

### Configuration
- Runtime settings in `config.json` (window size, capture area, delays)
- Project configuration in `pyproject.toml`
- Code style enforced via `.flake8`, `.pylintrc`, `.isort.cfg`

## Important Notes

1. **macOS Only**: The project relies on `screencapture` command exclusive to macOS
2. **Permissions**: Requires screen recording permissions for Python interpreter
3. **Screenshot Storage**: All captures saved to `screenshots/` directory
4. **No Test Suite**: Currently no tests implemented despite pytest configuration
