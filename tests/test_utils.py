"""Tests for utility functions."""

from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from src.config import ScreenshotConfig
from src.utils import (
    ScreenshotError,
    clean_screenshots,
    get_next_count,
    get_next_session_dir,
    list_screenshots,
    take_screenshot,
)


class TestGetNextCount:
    def test_empty_directory(self, tmp_path: Path):
        assert get_next_count(tmp_path) == 1

    def test_nonexistent_directory(self, tmp_path: Path):
        assert get_next_count(tmp_path / "nonexistent") == 1

    def test_sequential_files(self, tmp_path: Path):
        for i in range(1, 4):
            (tmp_path / f"screenshot_{i}.png").touch()
        assert get_next_count(tmp_path) == 4

    def test_gap_in_numbering(self, tmp_path: Path):
        for i in [1, 2, 5]:
            (tmp_path / f"screenshot_{i}.png").touch()
        assert get_next_count(tmp_path) == 6

    def test_custom_prefix(self, tmp_path: Path):
        (tmp_path / "capture_1.png").touch()
        (tmp_path / "capture_2.png").touch()
        assert get_next_count(tmp_path, prefix="capture") == 3

    def test_custom_extension(self, tmp_path: Path):
        (tmp_path / "screenshot_1.jpg").touch()
        assert get_next_count(tmp_path, extension="jpg") == 2

    def test_non_numeric_files_ignored(self, tmp_path: Path):
        (tmp_path / "screenshot_abc.png").touch()
        (tmp_path / "screenshot_1.png").touch()
        assert get_next_count(tmp_path) == 2


class TestGetNextSessionDir:
    def test_nonexistent_base(self, tmp_path: Path):
        result = get_next_session_dir(tmp_path / "nonexistent")
        assert result == tmp_path / "nonexistent" / "01"

    def test_empty_directory(self, tmp_path: Path):
        result = get_next_session_dir(tmp_path)
        assert result == tmp_path / "01"

    def test_existing_sessions(self, tmp_path: Path):
        (tmp_path / "01").mkdir()
        (tmp_path / "02").mkdir()
        result = get_next_session_dir(tmp_path)
        assert result == tmp_path / "03"

    def test_gap_in_session_numbers(self, tmp_path: Path):
        (tmp_path / "01").mkdir()
        (tmp_path / "05").mkdir()
        result = get_next_session_dir(tmp_path)
        assert result == tmp_path / "06"

    def test_non_numeric_dirs_ignored(self, tmp_path: Path):
        (tmp_path / "01").mkdir()
        (tmp_path / "temp").mkdir()
        result = get_next_session_dir(tmp_path)
        assert result == tmp_path / "02"


class TestTakeScreenshot:
    def test_invalid_dimensions_width(self, tmp_path: Path):
        with pytest.raises(ValueError, match="Invalid dimensions"):
            take_screenshot(tmp_path / "test.png", 0, 0, 0, 100)

    def test_invalid_dimensions_height(self, tmp_path: Path):
        with pytest.raises(ValueError, match="Invalid dimensions"):
            take_screenshot(tmp_path / "test.png", 0, 0, 100, -1)

    def test_invalid_coordinates(self, tmp_path: Path):
        with pytest.raises(ValueError, match="Invalid coordinates"):
            take_screenshot(tmp_path / "test.png", -1, 0, 100, 100)

    @patch("src.utils.subprocess.run")
    def test_successful_screenshot(self, mock_run: MagicMock, tmp_path: Path):
        output_file = tmp_path / "test.png"
        mock_run.return_value = MagicMock(returncode=0, stderr="")
        # Simulate file creation
        output_file.touch()

        result = take_screenshot(output_file, 0, 0, 100, 100)
        assert result == output_file
        mock_run.assert_called_once()

    @patch("src.utils.subprocess.run")
    def test_file_not_created(self, mock_run: MagicMock, tmp_path: Path):
        output_file = tmp_path / "missing.png"
        mock_run.return_value = MagicMock(returncode=0, stderr="")
        # Don't create the file

        with pytest.raises(ScreenshotError, match="not created"):
            take_screenshot(output_file, 0, 0, 100, 100)

    @patch("src.utils.subprocess.run", side_effect=FileNotFoundError)
    def test_screencapture_not_found(self, mock_run: MagicMock, tmp_path: Path):
        with pytest.raises(ScreenshotError, match="requires macOS"):
            take_screenshot(tmp_path / "test.png", 0, 0, 100, 100)


class TestCleanScreenshots:
    def test_clean_with_files(self, tmp_path: Path):
        screenshots_dir = tmp_path / "screenshots"
        screenshots_dir.mkdir()
        for i in range(3):
            (screenshots_dir / f"screenshot_{i}.png").touch()

        config = ScreenshotConfig(directory=screenshots_dir)
        deleted = clean_screenshots(config)
        assert deleted == 3
        assert not list(screenshots_dir.glob("*.png"))

    def test_clean_with_session_dirs(self, tmp_path: Path):
        screenshots_dir = tmp_path / "screenshots"
        session = screenshots_dir / "01"
        session.mkdir(parents=True)
        (session / "screenshot_1.png").touch()

        config = ScreenshotConfig(directory=screenshots_dir)
        deleted = clean_screenshots(config)
        assert deleted == 1
        # Empty session dir should be removed
        assert not session.exists()

    def test_clean_nonexistent_directory(self, tmp_path: Path):
        config = ScreenshotConfig(directory=tmp_path / "nonexistent")
        deleted = clean_screenshots(config)
        assert deleted == 0

    def test_clean_empty_directory(self, tmp_path: Path):
        screenshots_dir = tmp_path / "screenshots"
        screenshots_dir.mkdir()
        config = ScreenshotConfig(directory=screenshots_dir)
        deleted = clean_screenshots(config)
        assert deleted == 0

    def test_clean_mixed_extensions(self, tmp_path: Path):
        screenshots_dir = tmp_path / "screenshots"
        screenshots_dir.mkdir()
        (screenshots_dir / "image.png").touch()
        (screenshots_dir / "image.jpg").touch()
        (screenshots_dir / "image.jpeg").touch()
        (screenshots_dir / "readme.txt").touch()  # should not be deleted

        config = ScreenshotConfig(directory=screenshots_dir)
        deleted = clean_screenshots(config)
        assert deleted == 3
        assert (screenshots_dir / "readme.txt").exists()


class TestListScreenshots:
    def test_list_empty_directory(self, tmp_path: Path):
        screenshots_dir = tmp_path / "screenshots"
        screenshots_dir.mkdir()
        config = ScreenshotConfig(directory=screenshots_dir)
        result = list_screenshots(config)
        assert result == []

    def test_list_nonexistent_directory(self, tmp_path: Path):
        config = ScreenshotConfig(directory=tmp_path / "nonexistent")
        result = list_screenshots(config)
        assert result == []

    def test_list_with_files(self, tmp_path: Path):
        screenshots_dir = tmp_path / "screenshots"
        screenshots_dir.mkdir()
        for name in ["a.png", "b.jpg", "c.jpeg"]:
            (screenshots_dir / name).touch()

        config = ScreenshotConfig(directory=screenshots_dir)
        result = list_screenshots(config)
        assert len(result) == 3

    def test_list_ignores_non_image_files(self, tmp_path: Path):
        screenshots_dir = tmp_path / "screenshots"
        screenshots_dir.mkdir()
        (screenshots_dir / "image.png").touch()
        (screenshots_dir / "readme.txt").touch()

        config = ScreenshotConfig(directory=screenshots_dir)
        result = list_screenshots(config)
        assert len(result) == 1

    def test_list_includes_subdirectories(self, tmp_path: Path):
        screenshots_dir = tmp_path / "screenshots"
        session = screenshots_dir / "01"
        session.mkdir(parents=True)
        (session / "screenshot_1.png").touch()

        config = ScreenshotConfig(directory=screenshots_dir)
        result = list_screenshots(config)
        assert len(result) == 1
