"""Utility functions for ScreenshotMacro."""

from __future__ import annotations

import subprocess
from pathlib import Path
from typing import TYPE_CHECKING

from loguru import logger

if TYPE_CHECKING:
    from src.config import ScreenshotConfig


class ScreenshotError(Exception):
    """Exception raised when screenshot capture fails."""


def take_screenshot(
    file_path: str | Path,
    x: int,
    y: int,
    width: int,
    height: int,
) -> Path:
    """Capture a screenshot of the specified region.

    Args:
        file_path: Path to save the screenshot.
        x: X coordinate of the region's top-left corner.
        y: Y coordinate of the region's top-left corner.
        width: Width of the region.
        height: Height of the region.

    Returns:
        Path to the saved screenshot.

    Raises:
        ScreenshotError: If the screenshot capture fails.
        ValueError: If coordinates or dimensions are invalid.
    """
    if width <= 0 or height <= 0:
        raise ValueError(f"Invalid dimensions: width={width}, height={height}")

    if x < 0 or y < 0:
        raise ValueError(f"Invalid coordinates: x={x}, y={y}")

    file_path = Path(file_path)
    file_path.parent.mkdir(parents=True, exist_ok=True)

    command = ["screencapture", "-x", f"-R{x},{y},{width},{height}", str(file_path)]

    try:
        # check=True raises CalledProcessError for any non-zero exit code, which
        # is handled below; no explicit returncode check is needed.
        subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=True,
            timeout=10,
        )

        if not file_path.exists():
            raise ScreenshotError(f"Screenshot file was not created: {file_path}")

        logger.debug(f"Screenshot saved: {file_path}")
        return file_path

    except subprocess.TimeoutExpired as e:
        raise ScreenshotError("Screenshot capture timed out") from e
    except subprocess.CalledProcessError as e:
        raise ScreenshotError(f"Screenshot capture failed: {e.stderr}") from e
    except FileNotFoundError as e:
        raise ScreenshotError("screencapture command not found. This tool requires macOS.") from e


def get_next_count(
    directory: str | Path,
    prefix: str = "screenshot",
    extension: str = "png",
) -> int:
    """Get the next available file index in the directory.

    Args:
        directory: Directory to check for existing files.
        prefix: File name prefix.
        extension: File extension (without dot).

    Returns:
        The next available index number.
    """
    directory = Path(directory)

    if not directory.exists():
        return 1

    existing_indices: list[int] = []
    pattern = f"{prefix}_*.{extension}"

    for file in directory.glob(pattern):
        try:
            stem = file.stem
            index_str = stem.replace(f"{prefix}_", "")
            index = int(index_str)
            existing_indices.append(index)
        except (ValueError, IndexError):
            continue

    return max(existing_indices, default=0) + 1


def get_next_session_dir(base_directory: str | Path) -> Path:
    """Get the next available numbered session directory.

    Scans for existing directories named with zero-padded numbers (01, 02, ...)
    and returns the path to the next one.

    Args:
        base_directory: Base screenshots directory.

    Returns:
        Path to the next session directory (e.g., screenshots/01).
    """
    base_directory = Path(base_directory)

    if not base_directory.exists():
        return base_directory / "01"

    existing_indices: list[int] = []
    for entry in base_directory.iterdir():
        if entry.is_dir():
            try:
                index = int(entry.name)
                existing_indices.append(index)
            except ValueError:
                continue

    next_index = max(existing_indices, default=0) + 1
    return base_directory / f"{next_index:02d}"


def clean_screenshots(config: ScreenshotConfig | None = None) -> int:
    """Remove all screenshot files from the screenshots directory.

    Args:
        config: Screenshot configuration. If None, uses default path.

    Returns:
        Number of files deleted.
    """
    if config is None:
        from src.config import get_config

        config = get_config().screenshot

    screenshots_dir = config.directory

    if not screenshots_dir.exists():
        logger.warning(f"Screenshots directory does not exist: {screenshots_dir}")
        return 0

    png_files = list(screenshots_dir.glob("**/*.png"))
    jpg_files = list(screenshots_dir.glob("**/*.jpg"))
    jpeg_files = list(screenshots_dir.glob("**/*.jpeg"))
    all_files = png_files + jpg_files + jpeg_files

    if not all_files:
        logger.info("No screenshot files to clean")
        return 0

    deleted_count = 0
    for file in all_files:
        try:
            file.unlink()
            deleted_count += 1
        except OSError as e:
            logger.error(f"Failed to delete {file}: {e}")

    # Remove empty session directories
    for entry in sorted(screenshots_dir.iterdir(), reverse=True):
        if entry.is_dir() and not any(entry.iterdir()):
            try:
                entry.rmdir()
            except OSError:
                pass

    logger.info(f"Cleaned {deleted_count} screenshot(s)")
    return deleted_count


def list_screenshots(config: ScreenshotConfig | None = None) -> list[Path]:
    """List all screenshot files in the screenshots directory.

    Args:
        config: Screenshot configuration. If None, uses default path.

    Returns:
        List of screenshot file paths sorted by modification time (newest first).
    """
    if config is None:
        from src.config import get_config

        config = get_config().screenshot

    screenshots_dir = config.directory

    if not screenshots_dir.exists():
        return []

    extensions = {".png", ".jpg", ".jpeg"}
    screenshots = [
        f for f in screenshots_dir.rglob("*") if f.is_file() and f.suffix.lower() in extensions
    ]

    return sorted(screenshots, key=lambda x: x.stat().st_mtime, reverse=True)
