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
stop_event = threading.Event()  # 매크로 중단을 위한 이벤트 객체

# 스크린샷 폴더 생성
if not os.path.exists("screenshot"):
    os.makedirs("screenshot")


def set_top_left():
    root.withdraw()  # GUI 창 숨기기

    def on_click(x, y, button, pressed):
        if pressed:
            global top_left
            top_left = (x, y)
            lbl_top_left.config(text=f"좌측 상단: {top_left}")
            listener.stop()
            root.deiconify()  # GUI 창 다시 표시
            return False

    listener = mouse.Listener(on_click=on_click)
    listener.start()


def set_bottom_right():
    root.withdraw()

    def on_click(x, y, button, pressed):
        if pressed:
            global bottom_right
            bottom_right = (x, y)
            lbl_bottom_right.config(text=f"우측 하단: {bottom_right}")
            listener.stop()
            root.deiconify()
            return False

    listener = mouse.Listener(on_click=on_click)
    listener.start()


def take_screenshot(file_path, x, y, width, height):
    command = ["screencapture", "-x", "-R{},{},{},{}".format(x, y, width, height), file_path]
    subprocess.run(command)


def get_next_pdf_filename():
    index = 1
    while True:
        pdf_filename = f"{index}.pdf"
        if not os.path.exists(pdf_filename):
            return pdf_filename
        index += 1


def start_macro():
    global stop_event
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

    # 지연 시간 입력 받기
    try:
        delay = float(entry_delay.get())
        if delay < 0:
            raise ValueError
    except ValueError:
        messagebox.showerror("오류", "유효한 지연 시간을 입력해주세요.")
        return

    # 영역 계산
    x1, y1 = top_left
    x2, y2 = bottom_right
    x = int(min(x1, x2))
    y = int(min(y1, y2))
    width = int(abs(x2 - x1))
    height = int(abs(y2 - y1))
    region = (x, y, width, height)

    # stop_event 초기화
    stop_event.clear()

    # 준비 시간
    time.sleep(5)

    # 매크로 실행 스레드 시작
    threading.Thread(target=run_macro, args=(repetitions, region, delay, stop_event)).start()


def run_macro(repetitions, region, delay, stop_event):
    images = []
    x, y, width, height = region

    # 새로운 PDF 파일 이름 생성
    pdf_filename = get_next_pdf_filename()

    for count in range(1, repetitions + 1):
        if stop_event.is_set():
            print("매크로가 중단되었습니다.")
            break

        # 지연 시간 설정
        time.sleep(delay)

        if stop_event.is_set():
            print("매크로가 중단되었습니다.")
            break

        # 스크린샷 캡처
        filename = f"screenshot/screenshot_{count}.png"
        take_screenshot(filename, x, y, width, height)
        print(f"스크린샷 {filename} 저장 완료.")

        # 이미지 로드 및 리스트에 추가
        image = Image.open(filename).convert("RGB")
        images.append(image)

        # 오른쪽 방향키 누르기
        pyautogui.press("right")
        print("오른쪽 방향키 누름.")

    # 캡처한 이미지가 있을 경우 PDF로 저장
    if images:
        images[0].save(pdf_filename, save_all=True, append_images=images[1:])
        print(f"PDF 파일 {pdf_filename} 저장 완료.")

        # 개별 이미지 파일 삭제
        for count in range(1, len(images) + 1):
            os.remove(f"screenshot/screenshot_{count}.png")
        print("개별 스크린샷 파일 삭제 완료.")

    if stop_event.is_set():
        messagebox.showinfo("취소", "매크로 실행이 취소되었습니다.")
    else:
        messagebox.showinfo("완료", f"매크로 실행이 완료되었습니다. 결과 파일: {pdf_filename}")


def cancel_macro():
    stop_event.set()
    print("매크로 중단 요청됨.")


def on_esc_press(event):
    root.destroy()


# GUI 구성
root = tk.Tk()
root.title("스크린샷 매크로")

# 창의 크기 설정
root.geometry("400x400")

# 창을 화면의 중앙에 배치
root.update_idletasks()
width = root.winfo_width()
height = root.winfo_height()
x = (root.winfo_screenwidth() // 2) - (width // 2)
y = root.winfo_screenheight() // 2
root.geometry(f"{width}x{height}+{x}+{y}")

# 창을 항상 위로 설정
root.attributes("-topmost", True)

# Esc 키에 종료 기능 바인딩
root.bind("<Escape>", on_esc_press)

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

# 지연 시간 입력란 추가
lbl_delay = tk.Label(root, text="지연 시간(초):")
lbl_delay.pack(pady=5)

entry_delay = tk.Entry(root)
entry_delay.insert(0, "1")  # 기본값 1초 설정
entry_delay.pack(pady=5)

btn_start = tk.Button(root, text="매크로 시작", command=start_macro)
btn_start.pack(pady=10)

# 취소 버튼 추가
btn_cancel = tk.Button(root, text="매크로 중단", command=cancel_macro)
btn_cancel.pack(pady=10)

root.mainloop()
