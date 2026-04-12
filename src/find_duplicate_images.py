from __future__ import annotations

from collections import defaultdict
from pathlib import Path

import imagehash
from loguru import logger
from PIL import Image


def calculate_image_hash(image_path: Path) -> imagehash.ImageHash | None:
    """
    이미지의 perceptual hash를 계산합니다.
    이 해시는 이미지가 비슷하면 비슷한 값을 가집니다.

    Args:
        image_path: 이미지 파일 경로

    Returns:
        이미지 해시 또는 에러 발생 시 None
    """
    try:
        return imagehash.average_hash(Image.open(image_path))
    except Exception as e:
        logger.error("이미지 처리 중 오류 발생 {}: {}", image_path, e)
        return None


def _collect_image_hashes(
    directory_path: Path, image_extensions: set[str]
) -> dict[imagehash.ImageHash, list[Path]]:
    """이미지 파일들의 해시를 수집합니다."""
    hash_dict = defaultdict(list)

    for image_path in directory_path.rglob("*"):
        if image_path.suffix.lower() in image_extensions:
            image_hash = calculate_image_hash(image_path)
            if image_hash:
                hash_dict[image_hash].append(image_path)

    return hash_dict


def _group_similar_hashes(
    hash_dict: dict[imagehash.ImageHash, list[Path]], hash_threshold: int
) -> dict[imagehash.ImageHash, list[Path]]:
    """유사한 해시들을 그룹화합니다."""
    processed_hashes = set()
    combined_dict = defaultdict(list)

    for hash1, files1 in hash_dict.items():
        if hash1 in processed_hashes:
            continue

        processed_hashes.add(hash1)
        similar_group = files1.copy()

        for hash2, files2 in hash_dict.items():
            if hash2 in processed_hashes:
                continue

            # 해시 간의 차이가 임계값 이하인지 확인
            if hash1 != hash2 and hash1 - hash2 <= hash_threshold:
                similar_group.extend(files2)
                processed_hashes.add(hash2)

        if len(similar_group) > 1:
            combined_dict[hash1] = similar_group

    return combined_dict


def find_duplicate_images(
    directory: str, hash_threshold: int = 0
) -> dict[imagehash.ImageHash, list[Path]]:
    """
    주어진 디렉토리에서 중복/유사한 이미지를 찾습니다.

    Args:
        directory: 검색할 디렉토리 경로
        hash_threshold: 유사성 임계값 (0은 정확히 동일한 이미지만 찾음)

    Returns:
        해시값을 키로, 유사한 이미지 파일 경로 리스트를 값으로 하는 딕셔너리
    """
    directory_path = Path(directory)
    if not directory_path.exists():
        logger.error("디렉토리가 존재하지 않습니다: {}", directory)
        return {}

    logger.info("검색 디렉토리: {}", directory)

    # 지원하는 이미지 확장자
    image_extensions: set[str] = {".png", ".jpg", ".jpeg", ".gif", ".bmp"}

    # 모든 이미지 파일의 해시 수집
    hash_dict = _collect_image_hashes(directory_path, image_extensions)

    # 유사 해시 처리 (threshold가 0보다 큰 경우)
    if hash_threshold > 0:
        return _group_similar_hashes(hash_dict, hash_threshold)

    # 중복된 이미지만 남기기
    return {k: v for k, v in hash_dict.items() if len(v) > 1}


def display_duplicate_groups(
    duplicates: dict[imagehash.ImageHash, list[Path]],
) -> None:
    """
    발견된 유사/중복 이미지 그룹을 표시합니다.
    파일명을 기준으로 오름차순 정렬하여 보여줍니다.

    Args:
        duplicates: 해시값을 키로, 중복된 이미지 경로 리스트를 값으로 하는 딕셔너리
    """
    if not duplicates:
        logger.info("유사한 이미지를 찾지 못했습니다.")
        return

    total_groups = len(duplicates)
    total_files = sum(len(files) for files in duplicates.values())

    logger.info(
        "총 {}개 그룹에서 {}개의 유사/중복 이미지를 발견했습니다.", total_groups, total_files
    )

    for i, (hash_value, file_list) in enumerate(duplicates.items(), 1):
        logger.info("\n유사한 이미지 그룹 #{} (해시: {}):", i, hash_value)

        # 파일명 순으로 정렬
        # 파일명에서 숫자 부분을 정수로 변환하여 자연스러운 정렬을 수행
        def extract_number(file_path):
            filename = file_path.name
            # "screenshot_123.png"와 같은 이름에서 숫자 부분을 추출
            try:
                # 파일명에서 숫자 부분 추출 (screenshot_123.png -> 123)
                number_part = filename.split("_")[-1].split(".")[0]
                return int(number_part)
            except (IndexError, ValueError):
                # 숫자 추출에 실패하면 파일명 그대로 반환
                return filename

        # 추출된 숫자를 기준으로 파일 경로 정렬
        sorted_files = sorted(file_list, key=extract_number)

        for file_path in sorted_files:
            logger.info("- {}", file_path)
