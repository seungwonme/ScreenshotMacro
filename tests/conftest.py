"""Shared test fixtures for ScreenshotMacro."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from src.config import AppConfig, ConfigManager


@pytest.fixture
def tmp_config_file(tmp_path: Path) -> Path:
    """Create a temporary config.json with default values."""
    config_data = {
        "gui": {
            "window_size": "900x500",
            "default_area": {"top_left": [0, 45], "bottom_right": [765, 1169]},
        },
        "macro": {
            "default_repetitions": 300,
            "default_delay": {"min": 1.0, "max": 3.0},
            "action": {"type": "key", "key": "right"},
            "initial_wait": 5.0,
        },
        "screenshot": {
            "directory": str(tmp_path / "screenshots"),
            "format": "png",
            "prefix": "screenshot",
        },
    }
    config_path = tmp_path / "config.json"
    config_path.write_text(json.dumps(config_data, indent=2), encoding="utf-8")
    return config_path


@pytest.fixture
def tmp_screenshots_dir(tmp_path: Path) -> Path:
    """Create a temporary screenshots directory."""
    screenshots_dir = tmp_path / "screenshots"
    screenshots_dir.mkdir()
    return screenshots_dir


@pytest.fixture(autouse=True)
def reset_config_manager():
    """Reset ConfigManager singleton between tests."""
    yield
    ConfigManager._instance = None
    ConfigManager._config = None


@pytest.fixture
def default_config() -> AppConfig:
    """Create a default AppConfig for testing."""
    return AppConfig()
