import argparse
from tkinter import Tk
import src.constants as const
from src.macro import ScreenshotMacro
from src.self import ScreenshotSelf
from src.gui_setup import setup_common_gui
from src.utils import clean_screenshots


def main():
    parser = argparse.ArgumentParser(
        description="Choose the mode of operation: run, self, or clean."
    )
    parser.add_argument(
        "mode",
        choices=["run", "self", "clean"],
        help=(
            "Mode of operation: 'run' for automation, 'self' for screenshot self,"
            " 'clean' to delete all screenshots."
        ),
    )
    args = parser.parse_args()

    if args.mode == "clean":
        clean_screenshots()
        return

    root = Tk()
    root.geometry(const.GuiConfig.WINDOW_SIZE)
    root.attributes("-topmost", True)

    setup_common_gui(root)

    if args.mode == "run":
        ScreenshotMacro(root).setup()
    elif args.mode == "self":
        ScreenshotSelf(root).setup()

    root.mainloop()


if __name__ == "__main__":
    main()
