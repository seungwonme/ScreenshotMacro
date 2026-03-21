"""Macro worker thread for screenshot automation."""

from __future__ import annotations

import random
import time
import pyautogui
from loguru import logger
from PyQt6.QtCore import QThread, pyqtSignal

from src.config import get_config
from src.utils import ScreenshotError, get_next_count, get_next_session_dir, take_screenshot

from src.config import ActionConfig


class MacroWorker(QThread):
    """Worker thread for executing screenshot macro."""

    finished = pyqtSignal()
    progress = pyqtSignal(int, int)  # current, total
    error = pyqtSignal(str)
    countdown = pyqtSignal(int)  # remaining seconds
    status_changed = pyqtSignal(str)  # status text

    def __init__(
        self,
        repetitions: int,
        delay_min: float,
        delay_max: float,
        x: int,
        y: int,
        width: int,
        height: int,
        action_config: ActionConfig | None = None,
    ) -> None:
        super().__init__()
        self.repetitions = repetitions
        self.delay_min = delay_min
        self.delay_max = delay_max
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.action_config = action_config or ActionConfig(type="key", key="right")
        self.should_stop = False

        self._config = get_config()

    def stop(self) -> None:
        """Request the thread to stop."""
        self.should_stop = True
        logger.info("Macro stop requested")

    def run(self) -> None:
        """Execute the macro loop."""
        try:
            initial_wait = self._config.macro.initial_wait
            logger.info(f"Starting macro with {initial_wait}s initial wait")
            self.status_changed.emit("waiting")
            for remaining in range(int(initial_wait), 0, -1):
                if self.should_stop:
                    return
                self.countdown.emit(remaining)
                time.sleep(1)
            fraction = initial_wait - int(initial_wait)
            if fraction > 0 and not self.should_stop:
                time.sleep(fraction)
            self.status_changed.emit("running")

            screenshot_config = self._config.screenshot
            screenshot_config.ensure_directory()

            session_dir = get_next_session_dir(screenshot_config.directory)
            session_dir.mkdir(parents=True, exist_ok=True)
            logger.info(f"Session directory: {session_dir}")

            directory = session_dir
            prefix = screenshot_config.prefix
            extension = screenshot_config.format
            count = get_next_count(directory, prefix, extension)

            logger.info(
                f"Starting {self.repetitions} repetitions "
                f"(delay: {self.delay_min}-{self.delay_max}s)"
            )

            for i in range(self.repetitions):
                if self.should_stop:
                    logger.info(f"Macro stopped at iteration {i}")
                    break

                delay = random.uniform(self.delay_min, self.delay_max)
                time.sleep(delay)

                if self.should_stop:
                    break

                filename = directory / f"{prefix}_{count}.{extension}"

                try:
                    take_screenshot(
                        filename,
                        self.x,
                        self.y,
                        self.width,
                        self.height,
                    )
                    count += 1
                except ScreenshotError as e:
                    logger.error(f"Screenshot failed at iteration {i}: {e}")
                    self.error.emit(str(e))

                self._execute_action()
                self.progress.emit(i + 1, self.repetitions)

            logger.info("Macro completed")

        except Exception as e:
            logger.exception(f"Macro execution error: {e}")
            self.error.emit(str(e))
        finally:
            self.finished.emit()

    def _execute_action(self) -> None:
        """Execute the configured action (key press or mouse click)."""
        action_type = self.action_config.type

        try:
            if action_type == "key":
                key = self.action_config.key or "right"
                pyautogui.press(key)
                logger.debug(f"Pressed key: {key}")
            elif action_type == "click":
                position = self.action_config.position
                if position and len(position) == 2:
                    pyautogui.click(position[0], position[1])
                    logger.debug(f"Clicked at: {position}")
                else:
                    pyautogui.click()
                    logger.debug("Clicked at current position")
        except Exception as e:
            logger.error(f"Action execution failed: {e}")
