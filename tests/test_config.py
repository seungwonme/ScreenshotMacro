"""Tests for configuration management."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from src.config import (
    ActionConfig,
    AppConfig,
    AreaConfig,
    ConfigManager,
    DelayConfig,
    GuiConfig,
    MacroConfig,
    ScreenshotConfig,
)


class TestAreaConfig:
    def test_defaults(self):
        config = AreaConfig()
        assert config.top_left == (0, 45)
        assert config.bottom_right == (765, 1169)

    def test_round_trip(self):
        config = AreaConfig(top_left=(10, 20), bottom_right=(100, 200))
        restored = AreaConfig.from_dict(config.to_dict())
        assert restored.top_left == config.top_left
        assert restored.bottom_right == config.bottom_right

    def test_from_dict_with_defaults(self):
        config = AreaConfig.from_dict({})
        assert config.top_left == (0, 45)
        assert config.bottom_right == (765, 1169)


class TestDelayConfig:
    def test_defaults(self):
        config = DelayConfig()
        assert config.min == 1.0
        assert config.max == 3.0

    def test_min_clamp(self):
        config = DelayConfig(min=0.01, max=3.0)
        assert config.min == 0.1

    def test_max_less_than_min_corrected(self):
        config = DelayConfig(min=5.0, max=1.0)
        assert config.max == config.min == 5.0

    def test_round_trip(self):
        config = DelayConfig(min=2.0, max=5.0)
        restored = DelayConfig.from_dict(config.to_dict())
        assert restored.min == config.min
        assert restored.max == config.max


class TestActionConfig:
    def test_defaults(self):
        config = ActionConfig()
        assert config.type == "key"
        assert config.key == "right"
        assert config.position is None

    def test_key_type_round_trip(self):
        config = ActionConfig(type="key", key="left")
        restored = ActionConfig.from_dict(config.to_dict())
        assert restored.type == "key"
        assert restored.key == "left"

    def test_click_type_round_trip(self):
        config = ActionConfig(type="click", key=None, position=(100, 200))
        data = config.to_dict()
        restored = ActionConfig.from_dict(data)
        assert restored.type == "click"
        assert restored.position == (100, 200)

    def test_click_type_no_position(self):
        config = ActionConfig(type="click", key=None, position=None)
        data = config.to_dict()
        assert data["position"] is None

    def test_from_dict_defaults_to_key(self):
        config = ActionConfig.from_dict({})
        assert config.type == "key"
        assert config.key == "right"


class TestMacroConfig:
    def test_defaults(self):
        config = MacroConfig()
        assert config.repetitions == 300
        assert config.initial_wait == 5.0

    def test_initial_wait_clamp_low(self):
        config = MacroConfig(initial_wait=-3.0)
        assert config.initial_wait == 0.0

    def test_repetitions_clamp_low(self):
        config = MacroConfig(repetitions=0)
        assert config.repetitions == 1

    def test_repetitions_clamp_high(self):
        config = MacroConfig(repetitions=99999)
        assert config.repetitions == 10000

    def test_round_trip(self):
        config = MacroConfig(repetitions=50, initial_wait=3.0)
        restored = MacroConfig.from_dict(config.to_dict())
        assert restored.repetitions == config.repetitions
        assert restored.initial_wait == config.initial_wait


class TestScreenshotConfig:
    def test_defaults(self):
        config = ScreenshotConfig()
        assert config.format == "png"
        assert config.prefix == "screenshot"

    def test_string_directory_converted_to_path(self):
        config = ScreenshotConfig(directory="./test_dir")
        assert isinstance(config.directory, Path)

    def test_ensure_directory(self, tmp_path: Path):
        test_dir = tmp_path / "new_screenshots"
        config = ScreenshotConfig(directory=test_dir)
        config.ensure_directory()
        assert test_dir.exists()


class TestAppConfig:
    def test_round_trip(self):
        config = AppConfig()
        data = config.to_dict()
        restored = AppConfig.from_dict(data)
        assert restored.gui.window_size == config.gui.window_size
        assert restored.macro.repetitions == config.macro.repetitions
        assert restored.screenshot.format == config.screenshot.format
        assert restored.screenshot.prefix == config.screenshot.prefix

    def test_round_trip_custom_values(self):
        config = AppConfig(
            gui=GuiConfig(window_size="800x600"),
            macro=MacroConfig(repetitions=100, initial_wait=2.0),
        )
        data = config.to_dict()
        restored = AppConfig.from_dict(data)
        assert restored.gui.window_size == "800x600"
        assert restored.macro.repetitions == 100
        assert restored.macro.initial_wait == 2.0

    def test_from_empty_dict(self):
        config = AppConfig.from_dict({})
        assert config.gui.window_size == "900x500"
        assert config.macro.repetitions == 300


class TestConfigManager:
    def test_singleton(self):
        manager1 = ConfigManager()
        manager2 = ConfigManager()
        assert manager1 is manager2

    def test_load_from_file(self, tmp_config_file: Path):
        manager = ConfigManager()
        config = manager.load(tmp_config_file)
        assert config.macro.repetitions == 300
        assert config.macro.action.type == "key"
        assert config.macro.action.key == "right"

    def test_load_missing_file_uses_defaults(self, tmp_path: Path):
        manager = ConfigManager()
        config = manager.load(tmp_path / "nonexistent.json")
        assert config.macro.repetitions == 300

    def test_load_invalid_json(self, tmp_path: Path):
        bad_file = tmp_path / "bad.json"
        bad_file.write_text("not json", encoding="utf-8")
        manager = ConfigManager()
        config = manager.load(bad_file)
        assert config.macro.repetitions == 300  # defaults

    def test_save_and_reload(self, tmp_path: Path):
        config_path = tmp_path / "config.json"
        manager = ConfigManager()
        manager._config = AppConfig(
            macro=MacroConfig(repetitions=42)
        )
        assert manager.save(config_path) is True
        assert config_path.exists()

        data = json.loads(config_path.read_text(encoding="utf-8"))
        assert data["macro"]["default_repetitions"] == 42

    def test_save_no_config_returns_false(self):
        manager = ConfigManager()
        manager._config = None
        assert manager.save() is False

    def test_update(self):
        manager = ConfigManager()
        manager._config = AppConfig()
        manager.update(macro=MacroConfig(repetitions=99))
        assert manager.config.macro.repetitions == 99

    def test_reload(self, tmp_config_file: Path):
        manager = ConfigManager()
        manager.load(tmp_config_file)
        manager._config.macro.repetitions = 999
        reloaded = manager.reload()
        # After reload from the same default config path (not tmp),
        # it should return defaults since _config_path is reset
        assert reloaded is not None
