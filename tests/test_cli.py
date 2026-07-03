"""Tests for the CLI commands."""

from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import patch

from typer.testing import CliRunner

from src.cli import app
from src.config import ConfigManager

runner = CliRunner()


def _write_config(tmp_path: Path, top_left, bottom_right) -> Path:
    config_data = {
        "gui": {
            "window_size": "900x500",
            "default_area": {"top_left": list(top_left), "bottom_right": list(bottom_right)},
        },
        "macro": {
            "default_repetitions": 2,
            "default_delay": {"min": 0.1, "max": 0.1},
            "action": {"type": "key", "key": "right"},
            "initial_wait": 0.0,
        },
        "screenshot": {
            "directory": str(tmp_path / "screenshots"),
            "format": "png",
            "prefix": "screenshot",
        },
    }
    path = tmp_path / "config.json"
    path.write_text(json.dumps(config_data), encoding="utf-8")
    return path


class TestMacroCommand:
    @patch("src.macro_pyqt.take_screenshot")
    @patch("src.macro_pyqt.pyautogui")
    @patch("src.macro_pyqt.time.sleep", return_value=None)
    def test_headless_macro_runs(self, mock_sleep, mock_pyautogui, mock_screenshot, tmp_path):
        mock_screenshot.return_value = tmp_path / "x.png"
        ConfigManager().load(_write_config(tmp_path, (0, 0), (100, 100)))

        result = runner.invoke(
            app, ["macro", "-n", "3", "--delay-min", "0", "--delay-max", "0", "-w", "0"]
        )

        assert result.exit_code == 0
        assert mock_screenshot.call_count == 3

    def test_macro_invalid_area_exits(self, tmp_path):
        ConfigManager().load(_write_config(tmp_path, (50, 50), (50, 50)))

        result = runner.invoke(app, ["macro"])

        assert result.exit_code == 1


class TestConfigCommand:
    def test_config_command_runs(self, tmp_path):
        ConfigManager().load(_write_config(tmp_path, (0, 0), (100, 100)))

        result = runner.invoke(app, ["config"])

        assert result.exit_code == 0
        assert "Current Configuration" in result.stdout
