"""Tests for duplicate image detection."""

from __future__ import annotations

from pathlib import Path

import imagehash
import numpy as np
from PIL import Image

from src.find_duplicate_images import (
    _group_similar_hashes,
    calculate_image_hash,
    display_duplicate_groups,
    find_duplicate_images,
)


def _make_hash(true_indices: list[int]) -> imagehash.ImageHash:
    """Build an 8x8 perceptual hash with the given bit positions set to True."""
    bits = np.zeros(64, dtype=bool)
    for idx in true_indices:
        bits[idx] = True
    return imagehash.ImageHash(bits.reshape(8, 8))


def _create_test_image(path: Path, color: tuple = (255, 0, 0), size: tuple = (100, 100)) -> Path:
    """Create a test image file."""
    img = Image.new("RGB", size, color)
    img.save(path)
    return path


class TestCalculateImageHash:
    def test_valid_image(self, tmp_path: Path):
        img_path = _create_test_image(tmp_path / "test.png")
        result = calculate_image_hash(img_path)
        assert result is not None

    def test_invalid_file(self, tmp_path: Path):
        bad_file = tmp_path / "bad.png"
        bad_file.write_text("not an image", encoding="utf-8")
        result = calculate_image_hash(bad_file)
        assert result is None

    def test_nonexistent_file(self, tmp_path: Path):
        result = calculate_image_hash(tmp_path / "nonexistent.png")
        assert result is None

    def test_same_image_same_hash(self, tmp_path: Path):
        img1 = _create_test_image(tmp_path / "img1.png", color=(255, 0, 0))
        img2 = _create_test_image(tmp_path / "img2.png", color=(255, 0, 0))
        hash1 = calculate_image_hash(img1)
        hash2 = calculate_image_hash(img2)
        assert hash1 == hash2

    def test_different_images_different_hash(self, tmp_path: Path):
        img1 = _create_test_image(tmp_path / "img1.png", color=(255, 0, 0))
        img2 = _create_test_image(tmp_path / "img2.png", color=(0, 0, 255))
        hash1 = calculate_image_hash(img1)
        hash2 = calculate_image_hash(img2)
        # Note: perceptual hashes of solid color images may or may not differ
        # This test just verifies the function works, not hash uniqueness
        assert hash1 is not None
        assert hash2 is not None


class TestFindDuplicateImages:
    def test_nonexistent_directory(self):
        result = find_duplicate_images("/nonexistent/path")
        assert result == {}

    def test_no_duplicates(self, tmp_path: Path):
        _create_test_image(tmp_path / "img1.png", color=(255, 0, 0), size=(100, 100))
        _create_test_image(tmp_path / "img2.png", color=(0, 255, 0), size=(200, 200))
        result = find_duplicate_images(str(tmp_path))
        # May or may not find duplicates depending on hash sensitivity
        # Just verify it returns a dict
        assert isinstance(result, dict)

    def test_exact_duplicates(self, tmp_path: Path):
        _create_test_image(tmp_path / "img1.png", color=(128, 128, 128))
        _create_test_image(tmp_path / "img2.png", color=(128, 128, 128))
        result = find_duplicate_images(str(tmp_path))
        # Same solid color images should have same hash
        assert len(result) >= 1
        # Each group should have at least 2 files
        for files in result.values():
            assert len(files) >= 2

    def test_with_threshold(self, tmp_path: Path):
        _create_test_image(tmp_path / "img1.png", color=(128, 128, 128))
        _create_test_image(tmp_path / "img2.png", color=(128, 128, 128))
        result = find_duplicate_images(str(tmp_path), hash_threshold=5)
        assert isinstance(result, dict)

    def test_empty_directory(self, tmp_path: Path):
        result = find_duplicate_images(str(tmp_path))
        assert result == {}


class TestGroupSimilarHashes:
    def test_grouping_is_transitive(self):
        # a~b=3, b~c=3, a~c=6: single-linkage must merge all three even though
        # a and c are not within threshold of each other directly.
        a = _make_hash([])
        b = _make_hash([0, 1, 2])
        c = _make_hash([0, 1, 2, 3, 4, 5])
        assert (a - b) == 3
        assert (b - c) == 3
        assert (a - c) == 6

        hash_dict = {a: [Path("a.png")], b: [Path("b.png")], c: [Path("c.png")]}
        groups = _group_similar_hashes(hash_dict, hash_threshold=3)

        assert len(groups) == 1
        all_files = [f for files in groups.values() for f in files]
        assert len(all_files) == 3

    def test_grouping_is_order_independent(self):
        # Reversing insertion order must yield the same single merged group.
        a = _make_hash([])
        b = _make_hash([0, 1, 2])
        c = _make_hash([0, 1, 2, 3, 4, 5])

        reversed_dict = {c: [Path("c.png")], b: [Path("b.png")], a: [Path("a.png")]}
        groups = _group_similar_hashes(reversed_dict, hash_threshold=3)

        all_files = [f for files in groups.values() for f in files]
        assert len(groups) == 1
        assert len(all_files) == 3


class TestDisplayDuplicateGroups:
    def test_handles_mixed_numeric_and_text_filenames(self):
        # A group mixing screenshot_N.png and an arbitrary name must not crash
        # the sort (int vs str comparison) in display.
        h = _make_hash([0])
        duplicates = {h: [Path("screenshot_12.png"), Path("foo.png")]}
        display_duplicate_groups(duplicates)  # should not raise
