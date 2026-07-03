"""Tests for MacroWorker thread."""

from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import patch

import pytest
from PyQt6.QtCore import QCoreApplication

from src.config import ConfigManager
from src.macro_pyqt import MAX_CONSECUTIVE_FAILURES, MacroWorker


@pytest.fixture(autouse=True)
def qapp():
    """Ensure QCoreApplication exists for signal testing."""
    app = QCoreApplication.instance()
    if app is None:
        app = QCoreApplication([])
    yield app


@pytest.fixture
def setup_config(tmp_path: Path, reset_config_manager):
    """Set up ConfigManager with a temp config."""
    config_data = {
        "gui": {
            "window_size": "900x500",
            "default_area": {"top_left": [0, 45], "bottom_right": [765, 1169]},
        },
        "macro": {
            "default_repetitions": 300,
            "default_delay": {"min": 1.0, "max": 3.0},
            "action": {"type": "key", "key": "right"},
            "initial_wait": 0.0,
        },
        "screenshot": {
            "directory": str(tmp_path / "screenshots"),
            "format": "png",
            "prefix": "screenshot",
        },
    }
    config_path = tmp_path / "config.json"
    config_path.write_text(json.dumps(config_data), encoding="utf-8")
    manager = ConfigManager()
    manager.load(config_path)
    return manager


class TestMacroWorkerInit:
    def test_default_action_config(self, setup_config):
        worker = MacroWorker(
            repetitions=1,
            delay_min=0.1,
            delay_max=0.1,
            x=0,
            y=0,
            width=100,
            height=100,
        )
        assert worker.action_config.type == "key"
        assert worker.action_config.key == "right"
        assert worker.initial_wait == 0.0
        assert worker.should_stop is False

    def test_custom_action_config(self, setup_config):
        action = {"type": "click", "position": [100, 200]}
        worker = MacroWorker(
            repetitions=5,
            delay_min=0.5,
            delay_max=1.0,
            x=0,
            y=0,
            width=100,
            height=100,
            action_config=action,
        )
        assert worker.action_config == action
        assert worker.repetitions == 5

    def test_custom_initial_wait_overrides_config(self, setup_config):
        worker = MacroWorker(
            repetitions=1,
            delay_min=0.1,
            delay_max=0.1,
            x=0,
            y=0,
            width=100,
            height=100,
            initial_wait=2.5,
        )
        assert worker.initial_wait == 2.5


class TestMacroWorkerStop:
    def test_stop_sets_flag(self, setup_config):
        worker = MacroWorker(
            repetitions=1,
            delay_min=0.1,
            delay_max=0.1,
            x=0,
            y=0,
            width=100,
            height=100,
        )
        assert worker.should_stop is False
        worker.stop()
        assert worker.should_stop is True


class TestMacroWorkerSignals:
    @patch("src.macro_pyqt.take_screenshot")
    @patch("src.macro_pyqt.pyautogui")
    @patch("src.macro_pyqt.time.sleep", return_value=None)
    def test_countdown_uses_explicit_initial_wait(
        self,
        mock_sleep,
        mock_pyautogui,
        mock_screenshot,
        setup_config,
        tmp_path,
    ):
        mock_screenshot.return_value = tmp_path / "test.png"

        worker = MacroWorker(
            repetitions=1,
            delay_min=0.0,
            delay_max=0.0,
            x=0,
            y=0,
            width=100,
            height=100,
            initial_wait=2.5,
        )

        countdown_calls = []
        status_changes = []
        worker.countdown.connect(countdown_calls.append)
        worker.status_changed.connect(status_changes.append)

        worker.run()

        assert countdown_calls == [2, 1]
        assert status_changes[:2] == ["waiting", "running"]

    @patch("src.macro_pyqt.take_screenshot")
    @patch("src.macro_pyqt.pyautogui")
    @patch("src.macro_pyqt.time.sleep", return_value=None)
    def test_progress_signal_emitted(
        self, mock_sleep, mock_pyautogui, mock_screenshot, setup_config, tmp_path
    ):
        mock_screenshot.return_value = tmp_path / "test.png"

        worker = MacroWorker(
            repetitions=2,
            delay_min=0.0,
            delay_max=0.0,
            x=0,
            y=0,
            width=100,
            height=100,
        )

        progress_calls = []
        worker.progress.connect(lambda current, total: progress_calls.append((current, total)))

        finished_called = []
        worker.finished.connect(lambda: finished_called.append(True))

        worker.run()

        assert len(progress_calls) == 2
        assert progress_calls[0] == (1, 2)
        assert progress_calls[1] == (2, 2)
        assert len(finished_called) == 1

    @patch("src.macro_pyqt.take_screenshot")
    @patch("src.macro_pyqt.pyautogui")
    @patch("src.macro_pyqt.time.sleep", return_value=None)
    def test_stop_halts_execution(
        self, mock_sleep, mock_pyautogui, mock_screenshot, setup_config, tmp_path
    ):
        mock_screenshot.return_value = tmp_path / "test.png"

        worker = MacroWorker(
            repetitions=100,
            delay_min=0.0,
            delay_max=0.0,
            x=0,
            y=0,
            width=100,
            height=100,
        )

        progress_calls = []
        worker.progress.connect(lambda current, total: progress_calls.append((current, total)))

        # Stop after first iteration
        def stop_after_first(current, total):
            if current >= 1:
                worker.stop()

        worker.progress.connect(stop_after_first)

        worker.run()

        # Should have stopped early (not all 100 iterations)
        assert len(progress_calls) < 100

    @patch("src.macro_pyqt.take_screenshot", side_effect=Exception("Fatal error"))
    @patch("src.macro_pyqt.pyautogui")
    @patch("src.macro_pyqt.time.sleep", return_value=None)
    def test_error_signal_on_fatal_failure(
        self, mock_sleep, mock_pyautogui, mock_screenshot, setup_config
    ):
        worker = MacroWorker(
            repetitions=1,
            delay_min=0.0,
            delay_max=0.0,
            x=0,
            y=0,
            width=100,
            height=100,
        )

        error_messages = []
        worker.error.connect(lambda msg: error_messages.append(msg))

        finished_called = []
        worker.finished.connect(lambda: finished_called.append(True))

        worker.run()

        # Should still emit finished even on error
        assert len(finished_called) == 1

    @patch("src.macro_pyqt.take_screenshot")
    @patch("src.macro_pyqt.pyautogui")
    @patch("src.macro_pyqt.time.sleep", return_value=None)
    def test_screenshot_error_emits_error_signal(
        self, mock_sleep, mock_pyautogui, mock_screenshot, setup_config
    ):
        from src.utils import ScreenshotError

        mock_screenshot.side_effect = ScreenshotError("Capture failed")

        worker = MacroWorker(
            repetitions=2,
            delay_min=0.0,
            delay_max=0.0,
            x=0,
            y=0,
            width=100,
            height=100,
        )

        error_messages = []
        worker.error.connect(lambda msg: error_messages.append(msg))

        worker.run()

        # Each iteration should emit an error for the screenshot failure
        assert len(error_messages) == 2
        assert "Capture failed" in error_messages[0]

    @patch("src.macro_pyqt.take_screenshot")
    @patch("src.macro_pyqt.pyautogui")
    @patch("src.macro_pyqt.time.sleep", return_value=None)
    def test_action_skipped_on_screenshot_failure(
        self, mock_sleep, mock_pyautogui, mock_screenshot, setup_config
    ):
        from src.utils import ScreenshotError

        mock_screenshot.side_effect = ScreenshotError("Capture failed")

        worker = MacroWorker(
            repetitions=1,
            delay_min=0.0,
            delay_max=0.0,
            x=0,
            y=0,
            width=100,
            height=100,
        )
        worker.run()

        # A failed capture must not advance the page (no key press / click).
        mock_pyautogui.press.assert_not_called()
        mock_pyautogui.click.assert_not_called()

    @patch("src.macro_pyqt.take_screenshot")
    @patch("src.macro_pyqt.pyautogui")
    @patch("src.macro_pyqt.time.sleep", return_value=None)
    def test_aborts_after_consecutive_failures(
        self, mock_sleep, mock_pyautogui, mock_screenshot, setup_config
    ):
        from src.utils import ScreenshotError

        mock_screenshot.side_effect = ScreenshotError("Capture failed")

        worker = MacroWorker(
            repetitions=100,
            delay_min=0.0,
            delay_max=0.0,
            x=0,
            y=0,
            width=100,
            height=100,
        )

        error_messages = []
        worker.error.connect(error_messages.append)
        progress_calls = []
        worker.progress.connect(lambda current, total: progress_calls.append(current))

        worker.run()

        # Persistent failures abort after the consecutive-failure limit instead
        # of flooding error signals for all 100 repetitions.
        assert len(error_messages) == MAX_CONSECUTIVE_FAILURES
        assert len(progress_calls) < 100

    @patch("src.macro_pyqt.take_screenshot")
    @patch("src.macro_pyqt.pyautogui")
    @patch("src.macro_pyqt.time.sleep", return_value=None)
    def test_session_started_emitted(
        self, mock_sleep, mock_pyautogui, mock_screenshot, setup_config, tmp_path
    ):
        mock_screenshot.return_value = tmp_path / "test.png"

        worker = MacroWorker(
            repetitions=1,
            delay_min=0.0,
            delay_max=0.0,
            x=0,
            y=0,
            width=100,
            height=100,
        )

        sessions = []
        worker.session_started.connect(sessions.append)
        worker.run()

        # The session directory path is announced exactly once for the run.
        assert len(sessions) == 1
        assert sessions[0]
