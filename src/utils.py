import os
import subprocess
from pathlib import Path


def take_screenshot(file_path, x, y, width, height):
    """주어진 영역의 스크린샷을 저장합니다."""
    command = ["screencapture", "-x", f"-R{x},{y},{width},{height}", file_path]
    subprocess.run(command)


def get_next_count(directory, prefix, extension):
    """다음 저장할 파일의 인덱스를 반환합니다."""
    index = 1
    while os.path.exists(os.path.join(directory, f"{prefix}_{index}.{extension}")):
        index += 1
    return index


def clean_screenshots():
    """스크린샷 디렉토리의 모든 PNG 파일을 삭제합니다."""
    screenshots_dir = Path("./screenshots")
    if not screenshots_dir.exists():
        print("Screenshots directory does not exist.")
        return

    png_files = list(screenshots_dir.glob("*.png"))
    if not png_files:
        print("No PNG files to clean.")
        return

    for png_file in png_files:
        png_file.unlink()

    print(f"Cleaned {len(png_files)} screenshot(s) successfully.")
