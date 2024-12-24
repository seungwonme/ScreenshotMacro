import tkinter as tk
import threading
import time
import random
import os
import pyautogui
from src.constants import Paths
from src.utils import take_screenshot, get_next_count


class ScreenshotMacro:
    def __init__(self, root):
        self.root = root
        self.stop_event = threading.Event()
        self.screenshot_directory = Paths.SCREENSHOTS_DIR

    def setup(self):
        self.setup_gui()

    def setup_gui(self):
        tk.Label(self.root, text="Repetitions:").pack(pady=5)
        self.entry_repetitions = tk.Entry(self.root)
        self.entry_repetitions.insert(0, "300")
        self.entry_repetitions.pack(pady=5)

        self.delay_frame = tk.Frame(self.root)
        self.delay_frame.pack(pady=5)

        tk.Label(self.delay_frame, text="Delay (s)").pack(side=tk.LEFT, padx=5)
        self.entry_delay_min = tk.Entry(self.delay_frame)
        self.entry_delay_min.insert(0, "1")
        self.entry_delay_min.pack(side=tk.LEFT, padx=5)

        self.lbl_delay_max = tk.Label(self.delay_frame, text="Max (s)")
        self.lbl_delay_max.pack(side=tk.LEFT, padx=5)

        self.entry_delay_max = tk.Entry(self.delay_frame)
        self.entry_delay_max.pack(side=tk.LEFT, padx=5)
        self.entry_delay_max.insert(0, "3")
        self.entry_delay_max.config(state="disabled")

        self.random_delay_var = tk.BooleanVar()
        tk.Checkbutton(
            self.root,
            text="Use Random Delay",
            variable=self.random_delay_var,
            command=self.toggle_random_delay,
        ).pack(pady=5)

        btn_frame = tk.Frame(self.root)
        btn_frame.pack(pady=5)

        self.btn_start = tk.Button(btn_frame, text="Start Macro", command=self.start_macro, width=10, height=2)
        self.btn_start.pack(side=tk.LEFT, pady=10, padx=5)
        self.btn_cancel = tk.Button(
            btn_frame,
            text="Cancel Macro",
            command=self.cancel_macro,
            state="disabled",
            width=10,
            height=2,
        )
        self.btn_cancel.pack(side=tk.LEFT, pady=10, padx=5)

    def toggle_random_delay(self):
        if self.random_delay_var.get():
            self.entry_delay_max.config(state="normal")
        else:
            self.entry_delay_max.config(state="disabled")

    def start_macro(self):
        self.stop_event.clear()

        # Retrieve values from Tkinter variables and widgets
        try:
            repetitions = int(self.entry_repetitions.get())
            delay_min = float(self.entry_delay_min.get())
            random_delay = self.random_delay_var.get()
            if random_delay:
                delay_max = float(self.entry_delay_max.get())
            else:
                delay_max = delay_min
        except ValueError:
            print("Invalid input. Please enter valid numbers.")
            return

        self.btn_start.config(state="disabled", text="Running...")
        self.btn_cancel.config(state="normal")

        x1, y1 = self.root.top_left
        x2, y2 = self.root.bottom_right
        x = int(min(x1, x2))
        y = int(min(y1, y2))
        width = int(abs(x2 - x1))
        height = int(abs(y2 - y1))

        threading.Thread(
            target=self.run_macro,
            args=(repetitions, delay_min, delay_max, random_delay, x, y, width, height),
            daemon=True,
        ).start()

    def run_macro(self, repetitions, delay_min, delay_max, random_delay, x, y, width, height):

        time.sleep(5)

        count = get_next_count(self.screenshot_directory, "screenshot", "png")

        for _ in range(repetitions):
            if self.stop_event.is_set():
                break

            # Calculate delay
            delay = random.uniform(delay_min, delay_max) if random_delay else delay_min

            time.sleep(delay)
            # print(f"Waiting for {delay} seconds...")

            if self.stop_event.is_set():
                break

            if not os.path.exists(self.screenshot_directory):
                os.makedirs(self.screenshot_directory)

            filename = self.screenshot_directory + f"/screenshot_{count}.png"
            take_screenshot(filename, x, y, width, height)
            print(f"Screenshot saved as {filename}")

            pyautogui.press("right")
            count += 1

        # Schedule GUI updates in the main thread
        self.root.after(0, self.macro_finished)

    def macro_finished(self):
        self.btn_start.config(state="normal", text="Start Macro")
        self.btn_cancel.config(state="disabled")

    def cancel_macro(self):
        self.stop_event.set()
        self.btn_start.config(state="normal", text="Start Macro")
        self.btn_cancel.config(state="disabled")
