import tkinter as tk
from tkinter import messagebox
import pyautogui
import time
from pynput import mouse
import threading
import os
from PIL import Image
import subprocess 

# 전역 변수 설정
top_left = None
bottom_right = None

def set_top_left():
    messagebox.showinfo("좌측 상단 설정", "캡처할 영역의 좌측 상단 모서리에 마우스를 이동한 후 클릭하세요.")
    root.withdraw()  # GUI 창 숨기기

    def on_click(x, y, button, pressed):
        if pressed:
            global top_left
            top_left = (x, y)
            lbl_top_left.config(text=f"좌측 상단: {top_left}")
            listener.stop()
            root.deiconify()  # GUI 창 다시 표시
            return False

    # 마우스 클릭을 감지하는 리스너 시작
    listener = mouse.Listener(on_click=on_click)
    listener.start()

def set_bottom_right():
    messagebox.showinfo("우측 하단 설정", "캡처할 영역의 우측 하단 모서리에 마우스를 이동한 후 클릭하세요.")
    root.withdraw()  # GUI 창 숨기기

    def on_click(x, y, button, pressed):
        if pressed:
            global bottom_right
            bottom_right = (x, y)
            lbl_bottom_right.config(text=f"우측 하단: {bottom_right}")
            listener.stop()
            root.deiconify()  # GUI 창 다시 표시
            return False

    # 마우스 클릭을 감지하는 리스너 시작
    listener = mouse.Listener(on_click=on_click)
    listener.start()

def take_screenshot(file_path, x, y, width, height):
    # screencapture 명령어를 사용하여 스크린샷 캡처
    command = ['screencapture', '-x', '-R{},{},{},{}'.format(x, y, width, height), file_path]
    subprocess.run(command)

def start_macro():
    if top_left is None or bottom_right is None:
        messagebox.showerror("오류", "좌측 상단과 우측 하단 모서리를 모두 설정해주세요.")
        return
    try:
        repetitions = int(entry_repetitions.get())
        if repetitions <= 0:
            raise ValueError
    except ValueError:
        messagebox.showerror("오류", "유효한 반복 횟수를 입력해주세요.")
        return

    # 영역 계산 (좌표를 정수로 변환)
    x1, y1 = top_left
    x2, y2 = bottom_right
    x = int(min(x1, x2))
    y = int(min(y1, y2))
    width = int(abs(x2 - x1))
    height = int(abs(y2 - y1))
    region = (x, y, width, height)

    # 매크로 실행을 위한 새로운 스레드 시작
    threading.Thread(target=run_macro, args=(repetitions, region)).start()

def run_macro(repetitions, region):
    images = []
    x, y, width, height = region
    for count in range(1, repetitions + 1):
        # 지연 시간 설정 (필요에 따라 조정 가능)
        time.sleep(2)

        # 스크린샷 캡처
        filename = f"screenshot_{count}.png"
        take_screenshot(filename, x, y, width, height)
        print(f"스크린샷 {filename} 저장 완료.")

        # 캡처한 이미지를 리스트에 추가
        image = Image.open(filename).convert('RGB')  # PDF 저장을 위해 RGB로 변환
        images.append(image)

        # 오른쪽 방향키 누르기
        pyautogui.press("right")
        print("오른쪽 방향키 누름.")

    # 캡처한 이미지를 PDF로 저장
    if images:
        pdf_filename = "output.pdf"
        images[0].save(pdf_filename, save_all=True, append_images=images[1:])
        print(f"PDF 파일 {pdf_filename} 저장 완료.")

        # 필요에 따라 개별 이미지 파일 삭제
        for count in range(1, repetitions + 1):
            os.remove(f"screenshot_{count}.png")
        print("개별 스크린샷 파일 삭제 완료.")

    messagebox.showinfo("완료", "매크로 실행이 완료되었습니다.")

# GUI 구성
root = tk.Tk()
root.title("스크린샷 매크로")

lbl_top_left = tk.Label(root, text="좌측 상단: 설정되지 않음")
lbl_top_left.pack(pady=5)

btn_set_top_left = tk.Button(root, text="좌측 상단 설정", command=set_top_left)
btn_set_top_left.pack(pady=5)

lbl_bottom_right = tk.Label(root, text="우측 하단: 설정되지 않음")
lbl_bottom_right.pack(pady=5)

btn_set_bottom_right = tk.Button(root, text="우측 하단 설정", command=set_bottom_right)
btn_set_bottom_right.pack(pady=5)

lbl_repetitions = tk.Label(root, text="반복 횟수:")
lbl_repetitions.pack(pady=5)

entry_repetitions = tk.Entry(root)
entry_repetitions.pack(pady=5)

btn_start = tk.Button(root, text="매크로 시작", command=start_macro)
btn_start.pack(pady=20)

root.mainloop()
