import tkinter as tk
from tkinter import messagebox
import pyautogui
import time
from pynput import mouse
import threading
import os
from PIL import Image
import subprocess
import random

# === GUI Setup ===
root = tk.Tk()
root.title("Screenshot Macro")
root.geometry("800x400")

# === Global Variables ===
# Web size
# top_left = (450, 0)
# bottom_right = (1230, 1050)
top_left = (0, 0)
bottom_right = (root.winfo_screenwidth() // 2 - 6, root.winfo_screenheight())
stop_event = threading.Event()  # Used to stop the macro

# === Screenshot Directory Setup ===
if not os.path.exists("screenshots"):
    os.makedirs("screenshots")


# === Functions ===
def set_top_left():
    """Set the top-left corner for the screenshot region."""
    root.withdraw()  # Hide the window

    def on_click(x, y, button, pressed):
        if pressed:
            global top_left
            top_left = (x, y)
            lbl_top_left.config(text=f"Top-Left: {top_left}")
            listener.stop()
            root.deiconify()  # Show window again
            return False

    listener = mouse.Listener(on_click=on_click)
    listener.start()


def set_bottom_right():
    """Set the bottom-right corner for the screenshot region."""
    root.withdraw()

    def on_click(x, y, button, pressed):
        if pressed:
            global bottom_right
            bottom_right = (x, y)
            lbl_bottom_right.config(text=f"Bottom-Right: {bottom_right}")
            listener.stop()
            root.deiconify()
            return False

    listener = mouse.Listener(on_click=on_click)
    listener.start()


def take_screenshot(file_path, x, y, width, height):
    """Take a screenshot with the specified region using screencapture."""
    command = ["screencapture", "-x", "-R{},{},{},{}".format(x, y, width, height), file_path]
    subprocess.run(command)


def get_next_pdf_filename():
    """Find the next available PDF filename to avoid overwriting."""
    index = 1
    while True:
        pdf_filename = f"{index}.pdf"
        if not os.path.exists(pdf_filename):
            return pdf_filename
        index += 1


def toggle_random_delay():
    """Enable/Disable the maximum delay field based on the checkbox."""
    if random_delay_var.get():
        lbl_delay_min.config(text="Min (s)")
        entry_delay_max.config(state="normal")  # Enable max delay
    else:
        lbl_delay_min.config(text="Delay (s)")
        entry_delay_max.config(state="disabled")  # Disable max delay


def start_macro():
    """Start the macro process with the given settings."""
    global stop_event
    if top_left is None or bottom_right is None:
        messagebox.showerror("Error", "Please set both the top-left and bottom-right corners.")
        return

    # Get the number of repetitions
    try:
        repetitions = int(entry_repetitions.get())
        if repetitions <= 0:
            raise ValueError
    except ValueError:
        messagebox.showerror("Error", "Please enter a valid number of repetitions.")
        return

    # Get delay times
    try:
        min_delay = float(entry_delay_min.get())
        if min_delay < 0:
            raise ValueError
        if random_delay_var.get():
            max_delay = float(entry_delay_max.get())
            if max_delay < min_delay:
                raise ValueError
        else:
            max_delay = min_delay  # Use fixed delay if random delay is not enabled
    except ValueError:
        messagebox.showerror("Error", "Please enter valid delay times.")
        return

    # Calculate screenshot region
    x1, y1 = top_left
    x2, y2 = bottom_right
    x = int(min(x1, x2))
    y = int(min(y1, y2))
    width = int(abs(x2 - x1))
    height = int(abs(y2 - y1))
    region = (x, y, width, height)

    # Reset stop event and update UI
    stop_event.clear()
    btn_start.config(state="disabled", text="매크로 실행 중...")
    btn_cancel.config(state="normal")
    root.update()

    # Ready time
    time.sleep(5)

    # Start macro in a new thread
    threading.Thread(target=run_macro, args=(repetitions, region, min_delay, max_delay, stop_event)).start()


def get_next_count():
    """Find the next available screenshot count."""
    index = 1
    while True:
        filename = f"screenshots/screenshot_{index}.png"
        if not os.path.exists(filename):
            return index
        index += 1


def run_macro(repetitions, region, min_delay, max_delay, stop_event):
    """Run the macro logic in a separate thread."""
    x, y, width, height = region
    pdf_filename = get_next_pdf_filename()
    start_count = get_next_count()

    for count in range(start_count, start_count + repetitions):
        if stop_event.is_set():
            print("Macro stopped.")
            break

        # Set delay time
        if min_delay == max_delay:
            delay = min_delay
        else:
            delay = random.uniform(min_delay, max_delay)

        print(f"Waiting for {delay} seconds.")
        time.sleep(delay)

        if stop_event.is_set():
            print("Macro stopped.")
            return

        # Take screenshot
        filename = f"screenshots/screenshot_{count}.png"
        take_screenshot(filename, x, y, width, height)
        print(f"Took screenshot {filename}.")

        # Press right arrow key
        pyautogui.press("right")

    # Reset buttons when done
    btn_start.config(state="normal", text="Start Macro")
    btn_cancel.config(state="disabled")


def convert_images_to_pdf():
    """Convert all images in the 'screenshots' folder to a single PDF."""
    image_folder = "screenshots"
    images = []

    # Load all images
    for file_name in sorted(os.listdir(image_folder)):
        if file_name.endswith(".png"):
            image_path = os.path.join(image_folder, file_name)
            img = Image.open(image_path).convert("RGB")
            images.append(img)

    if not images:
        print("No images found.")
        return

    # Save images as PDF
    output_pdf = get_next_pdf_filename()
    images[0].save(output_pdf, save_all=True, append_images=images[1:])
    print(f"PDF saved as {output_pdf}.")

    # Delete all images
    for file_name in os.listdir(image_folder):
        if file_name.endswith(".png"):
            os.remove(os.path.join(image_folder, file_name))
    print("All images deleted.")


def cancel_macro():
    """Cancel the currently running macro."""
    stop_event.set()
    btn_start.config(state="normal", text="Start Macro")
    btn_cancel.config(state="disabled")


def on_esc_press(event):
    root.destroy()


# === GUI Setup ===

# Position window to the top-right corner of the screen
root.update_idletasks()
width = root.winfo_width()
height = root.winfo_height()
x = root.winfo_screenwidth() - width
y = 0
root.geometry(f"{width}x{height}+{x}+{y}")
root.attributes("-topmost", True)

# Bind the ESC key to close the window
root.bind("<Escape>", on_esc_press)

# === GUI Components ===

lbl_top_left = tk.Label(root, text=f"Top-Left: {top_left}")
lbl_top_left.pack(pady=5)

btn_set_top_left = tk.Button(root, text="Set Top-Left", command=set_top_left)
btn_set_top_left.pack(pady=5)

lbl_bottom_right = tk.Label(root, text=f"Bottom-Right: {bottom_right}")
lbl_bottom_right.pack(pady=5)

btn_set_bottom_right = tk.Button(root, text="Set Bottom-Right", command=set_bottom_right)
btn_set_bottom_right.pack(pady=5)

lbl_repetitions = tk.Label(root, text="Repetitions:")
lbl_repetitions.pack(pady=5)

entry_repetitions = tk.Entry(root)
entry_repetitions.insert(0, "300")  # Set default value to 10
entry_repetitions.pack(pady=5)

# Delay Settings (min/max)
delay_frame = tk.Frame(root)
delay_frame.pack(pady=5)

# Minimum Delay
lbl_delay_min = tk.Label(delay_frame, text="Delay (s)")
lbl_delay_min.pack(side=tk.LEFT, padx=5)

entry_delay_min = tk.Entry(delay_frame)
entry_delay_min.insert(0, "1.5")
entry_delay_min.pack(side=tk.LEFT, padx=5)

# Maximum Delay
lbl_delay_max = tk.Label(delay_frame, text="Max (s)")
lbl_delay_max.pack(side=tk.LEFT, padx=5)

entry_delay_max = tk.Entry(delay_frame)
entry_delay_max.pack(side=tk.LEFT, padx=5)
entry_delay_max.insert(0, "3")
entry_delay_max.config(state="disabled")  # Initially disabled

# Random delay checkbox
random_delay_var = tk.BooleanVar()
chk_random_delay = tk.Checkbutton(root, text="Use Random Delay", variable=random_delay_var, command=toggle_random_delay)
chk_random_delay.pack(pady=5)
random_delay_var.set(False)

# Buttons for macro controls
btn_frame = tk.Frame(root)
btn_frame.pack(pady=5)

btn_start = tk.Button(btn_frame, text="Start Macro", command=start_macro, width=10, height=2)
btn_start.pack(side=tk.LEFT, pady=10, padx=5)

btn_cancel = tk.Button(btn_frame, text="Cancel Macro", command=cancel_macro, state="disabled", width=10, height=2)
btn_cancel.pack(side=tk.LEFT, pady=10, padx=5)

bnt_convert = tk.Button(root, text="Convert to PDF", command=convert_images_to_pdf)
bnt_convert.pack(pady=5)

root.mainloop()
