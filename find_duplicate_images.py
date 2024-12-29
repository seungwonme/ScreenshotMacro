import os
from pathlib import Path
from PIL import Image
import imagehash
from collections import defaultdict


def calculate_image_hash(image_path):
    """
    이미지의 perceptual hash를 계산합니다.
    이 해시는 이미지가 비슷하면 비슷한 값을 가집니다.
    """
    try:
        return imagehash.average_hash(Image.open(image_path))
    except Exception as e:
        print(f"Error processing {image_path}: {e}")
        return None


def find_duplicate_images(directory):
    """
    주어진 디렉토리에서 중복/유사한 이미지를 찾습니다.
    """
    hash_dict = defaultdict(list)

    # 지원하는 이미지 확장자

    image_extensions = {".png", ".jpg", ".jpeg", ".gif", ".bmp"}

    # 모든 이미지 파일 검사
    for image_path in Path(directory).rglob("*"):
        if image_path.suffix.lower() in image_extensions:
            image_hash = calculate_image_hash(image_path)
            if image_hash:
                hash_dict[image_hash].append(image_path)

    # 중복된 이미지 출력
    for hash_value, file_list in hash_dict.items():
        if len(file_list) > 1:
            print("\n유사한 이미지 그룹:")
            for file_path in file_list:
                print(f"- {file_path}")


if __name__ == "__main__":
    # 현재 디렉토리에서 실행
    current_dir = os.getcwd() + "/screenshots/"
    print(f"검색 디렉토리: {current_dir}")
    find_duplicate_images(current_dir)
