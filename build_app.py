"""Build macOS .app bundle using PyInstaller."""

import subprocess
import sys
import sysconfig
from pathlib import Path


def build():
    # Locate libpython dylib for PyInstaller
    libdir = Path(sysconfig.get_config_var("LIBDIR"))
    dylib = libdir / f"libpython{sysconfig.get_config_var('VERSION')}.dylib"

    cmd = [
        sys.executable, "-m", "PyInstaller",
        "--name", "ScreenshotMacro",
        "--windowed",
        "--onedir",
        "--noconfirm",
        "--add-data", "config.json:.",
        "--add-binary", f"{dylib}:.",
        "--hidden-import", "src.config",
        "--hidden-import", "src.gui_pyqt",
        "--hidden-import", "src.macro_pyqt",
        "--hidden-import", "src.utils",
        "--hidden-import", "src.find_duplicate_images",
        "--hidden-import", "pynput.keyboard._darwin",
        "--hidden-import", "pynput.mouse._darwin",
        "--collect-submodules", "pynput",
        "src/cli.py",
    ]

    print(f"Python lib: {dylib}")
    print(f"Exists: {dylib.exists()}")
    subprocess.run(cmd, check=True)
    print("\nBuild complete! App is at: dist/ScreenshotMacro.app")


if __name__ == "__main__":
    build()
