# setup.py
from setuptools import find_packages, setup

setup(
    name="ScreenshotMacro",
    version="1.0.0",
    description="A Python application for automating screenshots and macros.",
    author="Seungwon An",
    author_email="seungwonan.me@gmail.com",
    url="https://github.com/seungwonme/ScreenshotMacro",  # 프로젝트 URL로 변경하세요
    packages=find_packages(),
    entry_points={
        "console_scripts": [
            "screenshot-macro=src.cli:main",
        ],
    },
    install_requires=[
        "Pillow",
        "pyautogui",
        "pynput",
        "keyboard",
        "typer[all]>=0.9.0",
        "imagehash>=4.3.2",
        # 필요에 따라 requirements.txt에 있는 다른 의존성을 추가하세요
    ],
    classifiers=[
        "Programming Language :: Python :: 3",
        "Operating System :: OS Independent",
    ],
    python_requires=">=3.6",
)
