import os
import subprocess
from PIL import Image
from pynput import mouse


def take_screenshot(file_path, x, y, width, height):
    """주어진 영역의 스크린샷을 저장합니다."""
    command = ["screencapture", "-x", f"-R{x},{y},{width},{height}", file_path]
    subprocess.run(command)


def get_next_count(directory, prefix, extension):
    """다음 저장할 파일의 인덱스를 반환합니다."""
    index = 1
    if extension == 'pdf':
        while os.path.exists(os.path.join(directory, f"{index}.{extension}")):
            index += 1
    else:
        while os.path.exists(os.path.join(directory, f"{prefix}_{index}.{extension}")):
            index += 1
    return index


def set_top_left(root, lbl_top_left):
    """스크린샷 영역의 좌상단 좌표를 설정합니다."""

    def on_click(x, y, button, pressed):
        if pressed:
            root.top_left = (x, y)
            lbl_top_left.config(text=f"Top-Left: {root.top_left}")
            root.deiconify()
            listener.stop()
            return False

    root.withdraw()
    listener = mouse.Listener(on_click=on_click)
    listener.start()


def set_bottom_right(root, lbl_bottom_right):
    """스크린샷 영역의 우하단 좌표를 설정합니다."""

    def on_click(x, y, button, pressed):
        if pressed:
            root.bottom_right = (x, y)
            lbl_bottom_right.config(text=f"Bottom-Right: {root.bottom_right}")
            root.deiconify()
            listener.stop()
            return False

    root.withdraw()
    listener = mouse.Listener(on_click=on_click)
    listener.start()


def clean_screenshots():
    """스크린샷 디렉토리의 모든 PNG 파일을 삭제합니다."""
    folder = "screenshots"
    if not os.path.exists(folder):
        print("Screenshots directory does not exist.")
        return
    deleted_files = 0
    for file_name in os.listdir(folder):
        if file_name.endswith(".png"):
            os.remove(os.path.join(folder, file_name))
            deleted_files += 1
    print(f"Deleted {deleted_files} screenshot(s).")


def convert_images_to_pdf():
    """스크린샷 이미지를 PDF로 변환합니다."""
    image_folder = "screenshots"
    images = []
    for file_name in sorted(os.listdir(image_folder)):
        if file_name.endswith(".png"):
            image_path = os.path.join(image_folder, file_name)
            img = Image.open(image_path).convert("RGB")
            images.append(img)
    if not images:
        print("No images found.")
        return
    output_pdf = f"{get_next_count('.', '', 'pdf')}.pdf"
    images[0].save(output_pdf, save_all=True, append_images=images[1:])
    print(f"PDF saved as {output_pdf}.")

    clean_screenshots()
