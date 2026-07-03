"""Unified configuration management for ScreenshotMacro."""

from __future__ import annotations

import json
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal

from loguru import logger


def _get_base_dir() -> Path:
    """Get the writable base directory for the application.

    In frozen (PyInstaller) mode, resolves to the directory containing the .app bundle.
    In normal mode, resolves to the project root.
    """
    if getattr(sys, "frozen", False):
        exe = Path(sys.executable).resolve()
        # macOS .app bundle: .app/Contents/MacOS/executable
        if exe.parent.name == "MacOS" and exe.parent.parent.name == "Contents":
            return exe.parent.parent.parent.parent
        return exe.parent
    return Path(__file__).resolve().parent.parent


@dataclass
class AreaConfig:
    """Screenshot area configuration."""

    top_left: tuple[int, int] = (0, 45)
    bottom_right: tuple[int, int] = (765, 1169)

    def to_dict(self) -> dict:
        return {
            "top_left": list(self.top_left),
            "bottom_right": list(self.bottom_right),
        }

    @classmethod
    def from_dict(cls, data: dict) -> AreaConfig:
        return cls(
            top_left=tuple(data.get("top_left", (0, 45))),
            bottom_right=tuple(data.get("bottom_right", (765, 1169))),
        )


@dataclass
class DelayConfig:
    """Delay configuration."""

    min: float = 1.0
    max: float = 3.0

    def __post_init__(self) -> None:
        if self.min < 0.1:
            self.min = 0.1
        if self.max < self.min:
            self.max = self.min

    def to_dict(self) -> dict:
        return {"min": self.min, "max": self.max}

    @classmethod
    def from_dict(cls, data: dict) -> DelayConfig:
        return cls(
            min=data.get("min", 1.0),
            max=data.get("max", 3.0),
        )


@dataclass
class ActionConfig:
    """Action configuration (keyboard or mouse click).

    For click actions, ``position=None`` means "click at the current cursor
    position" instead of a fixed coordinate.
    """

    type: Literal["key", "click"] = "key"
    key: str | None = "right"
    position: tuple[int, int] | None = None

    def __post_init__(self) -> None:
        if self.type not in ("key", "click"):
            raise ValueError(f"ActionConfig: invalid type '{self.type}', expected 'key' or 'click'")
        if self.type == "key" and not self.key:
            raise ValueError("ActionConfig: type='key' requires a non-empty key value")

    def to_dict(self) -> dict:
        result = {"type": self.type}
        if self.type == "key":
            result["key"] = self.key
        else:
            result["position"] = list(self.position) if self.position else None
        return result

    @classmethod
    def from_dict(cls, data: dict) -> ActionConfig:
        """Build an ActionConfig from raw config data, normalizing bad values.

        Unknown action types fall back to 'key' and an empty key falls back to
        'right' so that a single malformed field never raises during load() and
        wipes the rest of the user's configuration.
        """
        action_type = data.get("type", "key")
        if action_type not in ("key", "click"):
            logger.warning("Unknown action type '%s', falling back to 'key'", action_type)
            action_type = "key"

        if action_type == "key":
            return cls(type="key", key=data.get("key") or "right", position=None)
        return cls(
            type="click",
            key=None,
            position=tuple(data["position"]) if data.get("position") else None,
        )


@dataclass
class MacroConfig:
    """Macro execution configuration."""

    repetitions: int = 300
    delay: DelayConfig = field(default_factory=DelayConfig)
    action: ActionConfig = field(default_factory=ActionConfig)
    initial_wait: float = 5.0

    def __post_init__(self) -> None:
        if self.repetitions < 1:
            self.repetitions = 1
        if self.repetitions > 10000:
            self.repetitions = 10000
        if self.initial_wait < 0:
            self.initial_wait = 0.0

    def to_dict(self) -> dict:
        return {
            "default_repetitions": self.repetitions,
            "default_delay": self.delay.to_dict(),
            "action": self.action.to_dict(),
            "initial_wait": self.initial_wait,
        }

    @classmethod
    def from_dict(cls, data: dict) -> MacroConfig:
        return cls(
            repetitions=data.get("default_repetitions", 300),
            delay=DelayConfig.from_dict(data.get("default_delay", {})),
            action=ActionConfig.from_dict(data.get("action", {})),
            initial_wait=data.get("initial_wait", 5.0),
        )


@dataclass
class ScreenshotConfig:
    """Screenshot storage configuration."""

    directory: Path = field(default_factory=lambda: Path("./screenshots"))
    format: str = "png"
    prefix: str = "screenshot"

    def __post_init__(self) -> None:
        if isinstance(self.directory, str):
            self.directory = Path(self.directory)
        if not self.directory.is_absolute():
            self.directory = _get_base_dir() / self.directory

    def to_dict(self) -> dict:
        # Serialize directories inside the project/base dir as relative paths so
        # a committed config.json stays portable across machines and checkouts.
        base = _get_base_dir()
        try:
            directory = f"./{self.directory.relative_to(base)}"
        except ValueError:
            directory = str(self.directory)
        return {
            "directory": directory,
            "format": self.format,
            "prefix": self.prefix,
        }

    @classmethod
    def from_dict(cls, data: dict) -> ScreenshotConfig:
        return cls(
            directory=Path(data.get("directory", "./screenshots")),
            format=data.get("format", "png"),
            prefix=data.get("prefix", "screenshot"),
        )

    def ensure_directory(self) -> None:
        """Create screenshot directory if it doesn't exist."""
        self.directory.mkdir(parents=True, exist_ok=True)


@dataclass
class GuiConfig:
    """GUI window configuration."""

    window_size: str = "900x500"
    area: AreaConfig = field(default_factory=AreaConfig)
    theme: str = "dark"

    def __post_init__(self) -> None:
        if self.theme not in ("dark", "light"):
            self.theme = "dark"

    def to_dict(self) -> dict:
        return {
            "window_size": self.window_size,
            "default_area": self.area.to_dict(),
            "theme": self.theme,
        }

    @classmethod
    def from_dict(cls, data: dict) -> GuiConfig:
        return cls(
            window_size=data.get("window_size", "900x500"),
            area=AreaConfig.from_dict(data.get("default_area", {})),
            theme=data.get("theme", "dark"),
        )


@dataclass
class AppConfig:
    """Application configuration."""

    gui: GuiConfig = field(default_factory=GuiConfig)
    macro: MacroConfig = field(default_factory=MacroConfig)
    screenshot: ScreenshotConfig = field(default_factory=ScreenshotConfig)

    def to_dict(self) -> dict:
        return {
            "gui": self.gui.to_dict(),
            "macro": self.macro.to_dict(),
            "screenshot": self.screenshot.to_dict(),
        }

    @classmethod
    def from_dict(cls, data: dict) -> AppConfig:
        return cls(
            gui=GuiConfig.from_dict(data.get("gui", {})),
            macro=MacroConfig.from_dict(data.get("macro", {})),
            screenshot=ScreenshotConfig.from_dict(data.get("screenshot", {})),
        )


class ConfigManager:
    """Singleton configuration manager."""

    _instance: ConfigManager | None = None
    _config: AppConfig | None = None

    def __new__(cls) -> ConfigManager:
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._config_path = _get_base_dir() / "config.json"
        return cls._instance

    @property
    def config(self) -> AppConfig:
        if self._config is None:
            self._config = self.load()
        return self._config

    def load(self, path: Path | None = None) -> AppConfig:
        """Load configuration from JSON file."""
        config_path = path or self._config_path

        if not config_path.exists():
            # Frozen app: try bundled config as fallback
            if getattr(sys, "frozen", False):
                bundled = Path(getattr(sys, "_MEIPASS", "")) / "config.json"
                if bundled.exists():
                    config_path = bundled
                    logger.info(f"Using bundled config: {config_path}")
                else:
                    logger.warning(f"Config not found: {config_path}, using defaults")
                    self._config = AppConfig()
                    return self._config
            else:
                logger.warning(f"Config file not found: {config_path}, using defaults")
                self._config = AppConfig()
                return self._config

        try:
            with open(config_path, encoding="utf-8") as f:
                data = json.load(f)
            self._config = AppConfig.from_dict(data)
            # Remember the path we actually loaded so reload() re-reads it.
            self._config_path = config_path
            logger.info(f"Config loaded from {config_path}")
            return self._config
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON in config file: {e}")
            self._config = AppConfig()
            return self._config
        except Exception as e:
            logger.error(f"Failed to load config: {e}")
            self._config = AppConfig()
            return self._config

    def save(self, path: Path | None = None) -> bool:
        """Save configuration to JSON file."""
        config_path = path or self._config_path

        if self._config is None:
            logger.warning("No config to save")
            return False

        try:
            with open(config_path, "w", encoding="utf-8") as f:
                json.dump(self._config.to_dict(), f, indent=2, ensure_ascii=False)
            logger.info(f"Config saved to {config_path}")
            return True
        except Exception as e:
            logger.error(f"Failed to save config: {e}")
            return False

    def reload(self) -> AppConfig:
        """Force reload configuration from file."""
        self._config = None
        return self.load()


def get_config() -> AppConfig:
    """Get the application configuration."""
    return ConfigManager().config


def save_config() -> bool:
    """Save the current configuration."""
    return ConfigManager().save()
