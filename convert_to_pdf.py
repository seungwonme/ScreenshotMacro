from PIL import Image
import os


def convert_images_to_pdf():
    image_folder = "screenshot"
    images = []

    # 스크린샷 폴더 내의 이미지 파일을 불러옴
    for file_name in sorted(os.listdir(image_folder)):
        if file_name.endswith(".png"):
            image_path = os.path.join(image_folder, file_name)
            img = Image.open(image_path).convert("RGB")
            images.append(img)

    # 이미지가 존재할 경우 PDF로 변환
    if images:
        output_pdf = "output.pdf"
        images[0].save(output_pdf, save_all=True, append_images=images[1:])
        print(f"PDF 파일 {output_pdf} 생성 완료.")


if __name__ == "__main__":
    convert_images_to_pdf()
