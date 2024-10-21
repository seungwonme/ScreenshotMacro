from dataclasses import dataclass


@dataclass
class GuiConfig:
    WINDOW_SIZE: str = "800x400"
    DEFAULT_REPETITIONS: int = 300
    DEFAULT_DELAY_MIN: float = 1.0
    DEFAULT_DELAY_MAX: float = 3.0
    DEFAULT_TOP_LEFT: tuple = (0, 0)
    DEFAULT_BOTTOM_RIGHT: tuple = (834, 1050)


@dataclass
class Paths:
    SCREENSHOTS_DIR: str = "screenshots"
    SCREENSHOT_PREFIX: str = "screenshot"
    OUTPUT_DIR: str = "outputs"


@dataclass
class KeyBindings:
    SCREENSHOT_KEY: str = "right"
    EXIT_KEY: str = "escape"
