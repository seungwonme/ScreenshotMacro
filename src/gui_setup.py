import tkinter as tk
from src.utils import set_top_left, set_bottom_right
from src.constants import GuiConfig


def on_esc_press(event, root):
    root.quit()
    root.destroy()


def setup_common_gui(root):
    root.top_left = GuiConfig.DEFAULT_TOP_LEFT
    root.bottom_right = GuiConfig.DEFAULT_BOTTOM_RIGHT

    root.bind("<Escape>", lambda event: on_esc_press(event, root))

    lbl_top_left = tk.Label(root, text=f"Top-Left: {root.top_left}")
    lbl_top_left.pack(pady=5)

    btn_set_top_left = tk.Button(root, text="Set Top-Left", command=lambda: set_top_left(root, lbl_top_left))
    btn_set_top_left.pack(pady=5)

    lbl_bottom_right = tk.Label(root, text=f"Bottom-Right: {root.bottom_right}")
    lbl_bottom_right.pack(pady=5)

    btn_set_bottom_right = tk.Button(
        root, text="Set Bottom-Right", command=lambda: set_bottom_right(root, lbl_bottom_right)
    )
    btn_set_bottom_right.pack(pady=5)
