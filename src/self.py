import tkinter as tk
from src.constants import Paths
import os
import keyboard
import time
from src.utils import take_screenshot, convert_images_to_pdf, get_next_count


class ScreenshotSelf:
    def __init__(self, root):
        self.root = root
        self.screenshot_directory = Paths.SCREENSHOTS_DIR
        self.listener = None  # To store the key listener handler
        self.count = get_next_count(self.screenshot_directory, "screenshot", "png")

    def setup(self):
        self.setup_gui()

    def setup_gui(self):
        self.delay_frame = tk.Frame(self.root)
        self.delay_frame.pack(pady=5)

        tk.Label(self.delay_frame, text="Delay (s)").pack(side=tk.LEFT, padx=5)
        self.entry_delay = tk.Entry(self.delay_frame)
        self.entry_delay.insert(0, "1")
        self.entry_delay.pack(side=tk.LEFT, padx=5)

        self.button_frame = tk.Frame(self.root)
        # Start Key Listener Button
        btn_start_key_listener = tk.Button(
            self.button_frame, text="Start Listener", command=self.start_key_listener
        )
        btn_start_key_listener.pack(side=tk.LEFT, pady=10)

        # Stop Key Listener Button
        btn_stop_key_listener = tk.Button(
            self.button_frame, text="Stop Listener", command=self.stop_key_listener
        )
        btn_stop_key_listener.pack(side=tk.LEFT, pady=10)

        self.button_frame.pack(pady=10)

        # Convert to PDF Button
        btn_convert_to_pdf = tk.Button(
            self.root, text="Convert to PDF", command=convert_images_to_pdf
        )
        btn_convert_to_pdf.pack(pady=10)

    def start_key_listener(self):
        self.count = get_next_count(self.screenshot_directory, "screenshot", "png")
        if self.listener is None:
            # Start the key listener and store the handler
            self.listener = keyboard.on_press_key("down", self.on_down_arrow_press)
            print("Started listening for the down arrow key.")
        else:
            print("Key listener is already running.")

    def stop_key_listener(self):
        if self.listener is not None:
            # Unhook the key listener
            keyboard.unhook(self.listener)
            self.listener = None
            print("Stopped listening for the down arrow key.")
        else:
            print("Key listener is not running.")

    def on_down_arrow_press(self, event):
        time.sleep(float(self.entry_delay.get()))
        self.take_screenshot()
        keyboard.press_and_release("enter")

    def take_screenshot(self):
        """Take a screenshot when the right arrow key is pressed."""
        x1, y1 = self.root.top_left
        x2, y2 = self.root.bottom_right
        x = int(min(x1, x2))
        y = int(min(y1, y2))
        width = int(abs(x2 - x1))
        height = int(abs(y2 - y1))

        if not os.path.exists(self.screenshot_directory):
            os.makedirs(self.screenshot_directory)

        filename = self.screenshot_directory + f"/screenshot_{self.count}.png"
        take_screenshot(filename, x, y, width, height)
        print(f"Screenshot saved as {filename}")
        self.count += 1
