"""Macro worker thread for screenshot automation."""

from __future__ import annotations

import random
import time

import pyautogui
from loguru import logger
from PyQt6.QtCore import QThread, pyqtSignal

from src.config import ActionConfig, get_config
from src.utils import ScreenshotError, get_next_session_dir, take_screenshot

# Abort the macro after this many consecutive screenshot failures (e.g. revoked
# screen-recording permission) instead of flooding error signals indefinitely.
MAX_CONSECUTIVE_FAILURES = 3


class MacroWorker(QThread):
    """Worker thread for executing screenshot macro."""

    finished = pyqtSignal()
    progress = pyqtSignal(int, int)  # current, total
    error = pyqtSignal(str)
    countdown = pyqtSignal(int)  # remaining seconds
    status_changed = pyqtSignal(str)  # status text
    session_started = pyqtSignal(str)  # session directory path

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
        initial_wait: float | None = None,
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
        self.initial_wait = max(
            0.0,
            initial_wait if initial_wait is not None else self._config.macro.initial_wait,
        )

    def stop(self) -> None:
        """Request the thread to stop."""
        self.should_stop = True
        logger.info("Macro stop requested")

    def _interruptible_sleep(self, duration: float) -> None:
        """Sleep in short chunks so a stop request takes effect promptly.

        A single long ``time.sleep`` would keep the worker (and a GUI waiting on
        it during close) blocked for up to the full delay; chunking lets
        ``should_stop`` cut the wait short.
        """
        step = 0.1
        elapsed = 0.0
        while elapsed < duration and not self.should_stop:
            time.sleep(min(step, duration - elapsed))
            elapsed += step

    def _run_initial_wait(self) -> bool:
        """Run the initial countdown. Returns False if stopped during the wait."""
        initial_wait = self.initial_wait
        logger.info(f"Starting macro with {initial_wait}s initial wait")
        self.status_changed.emit("waiting")
        for remaining in range(int(initial_wait), 0, -1):
            if self.should_stop:
                return False
            self.countdown.emit(remaining)
            time.sleep(1)
        fraction = initial_wait - int(initial_wait)
        if fraction > 0 and not self.should_stop:
            time.sleep(fraction)
        return not self.should_stop

    def run(self) -> None:
        """Execute the macro loop."""
        try:
            if not self._run_initial_wait():
                return
            self.status_changed.emit("running")

            screenshot_config = self._config.screenshot
            screenshot_config.ensure_directory()

            session_dir = get_next_session_dir(screenshot_config.directory)
            session_dir.mkdir(parents=True, exist_ok=True)
            logger.info(f"Session directory: {session_dir}")
            self.session_started.emit(str(session_dir))

            directory = session_dir
            prefix = screenshot_config.prefix
            extension = screenshot_config.format
            # Each run uses a fresh numbered session directory, so file
            # numbering always starts at 1.
            count = 1
            consecutive_failures = 0

            logger.info(
                f"Starting {self.repetitions} repetitions "
                f"(delay: {self.delay_min}-{self.delay_max}s)"
            )

            for i in range(self.repetitions):
                if self.should_stop:
                    logger.info(f"Macro stopped at iteration {i}")
                    break

                delay = random.uniform(self.delay_min, self.delay_max)
                self._interruptible_sleep(delay)

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
                    consecutive_failures = 0
                    # Only advance (key press / click) after a successful capture
                    # so a transient failure never silently skips a page.
                    self._execute_action()
                except ScreenshotError as e:
                    consecutive_failures += 1
                    logger.error(f"Screenshot failed at iteration {i}: {e}")
                    self.error.emit(str(e))
                    if consecutive_failures >= MAX_CONSECUTIVE_FAILURES:
                        logger.error(
                            f"Aborting macro after {consecutive_failures} "
                            "consecutive screenshot failures"
                        )
                        break

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
            else:
                logger.warning(f"Unknown action type '{action_type}'; no action performed")
        except Exception as e:
            logger.error(f"Action execution failed: {e}")
