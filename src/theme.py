"""Theme palettes and stylesheet builder for the PyQt6 GUI.

Both themes share one stylesheet template; only the color palette differs, so
the dark and light variants can never drift apart.
"""

from __future__ import annotations

# Catppuccin Mocha (dark)
DARK_PALETTE = {
    "base": "#1e1e2e",
    "mantle": "#181825",
    "surface0": "#313244",
    "surface1": "#45475a",
    "surface2": "#585b70",
    "text": "#cdd6f4",
    "subtext": "#bac2de",
    "overlay": "#6c7086",
    "accent": "#89b4fa",
    "accent_hover": "#b4d0fb",
    "accent_pressed": "#74a8f7",
    "red": "#f38ba8",
    "red_hover": "#f5a3b8",
    "green": "#a6e3a1",
    "green_hover": "#b8eab4",
    "on_accent": "#1e1e2e",
}

# Catppuccin Latte (light)
LIGHT_PALETTE = {
    "base": "#eff1f5",
    "mantle": "#e6e9ef",
    "surface0": "#ccd0da",
    "surface1": "#bcc0cc",
    "surface2": "#acb0be",
    "text": "#4c4f69",
    "subtext": "#5c5f77",
    "overlay": "#8c8fa1",
    "accent": "#1e66f5",
    "accent_hover": "#4c82f7",
    "accent_pressed": "#1552d8",
    "red": "#d20f39",
    "red_hover": "#e24960",
    "green": "#40a02b",
    "green_hover": "#56b342",
    "on_accent": "#eff1f5",
}


def build_stylesheet(p: dict) -> str:
    """Build the GUI stylesheet from a color palette."""
    return f"""
QMainWindow {{
    background-color: {p['base']};
}}
QWidget {{
    background-color: {p['base']};
    color: {p['text']};
    font-size: 13px;
}}
QGroupBox {{
    background-color: {p['surface0']};
    border: 1px solid {p['surface1']};
    border-radius: 8px;
    margin-top: 14px;
    padding: 16px 12px 12px 12px;
    font-weight: bold;
    font-size: 13px;
}}
QGroupBox::title {{
    subcontrol-origin: margin;
    left: 12px;
    padding: 0 6px;
    color: {p['accent']};
}}
QLabel {{
    background: transparent;
    color: {p['subtext']};
    font-size: 13px;
}}
QSpinBox, QDoubleSpinBox, QLineEdit {{
    background-color: {p['surface1']};
    border: 1px solid {p['surface2']};
    border-radius: 4px;
    padding: 4px 8px;
    color: {p['text']};
    min-height: 28px;
    selection-background-color: {p['accent']};
}}
QSpinBox:focus, QDoubleSpinBox:focus, QLineEdit:focus {{
    border: 1px solid {p['accent']};
}}
QSpinBox::up-button, QDoubleSpinBox::up-button {{
    subcontrol-origin: border;
    subcontrol-position: top right;
    width: 20px;
    border-left: 1px solid {p['surface2']};
    border-bottom: 1px solid {p['surface2']};
    border-top-right-radius: 4px;
    background: {p['surface2']};
}}
QSpinBox::down-button, QDoubleSpinBox::down-button {{
    subcontrol-origin: border;
    subcontrol-position: bottom right;
    width: 20px;
    border-left: 1px solid {p['surface2']};
    border-bottom-right-radius: 4px;
    background: {p['surface2']};
}}
QSpinBox::up-arrow, QDoubleSpinBox::up-arrow {{
    width: 0; height: 0;
    border-left: 4px solid transparent;
    border-right: 4px solid transparent;
    border-bottom: 5px solid {p['text']};
}}
QSpinBox::down-arrow, QDoubleSpinBox::down-arrow {{
    width: 0; height: 0;
    border-left: 4px solid transparent;
    border-right: 4px solid transparent;
    border-top: 5px solid {p['text']};
}}
QPushButton {{
    background-color: {p['surface1']};
    border: 1px solid {p['surface2']};
    border-radius: 6px;
    padding: 6px 16px;
    color: {p['text']};
    min-height: 28px;
    font-weight: 500;
}}
QPushButton:hover {{
    background-color: {p['surface2']};
    border-color: {p['accent']};
}}
QPushButton:pressed {{
    background-color: {p['surface0']};
}}
QPushButton:disabled {{
    background-color: {p['surface0']};
    color: {p['overlay']};
    border-color: {p['surface1']};
}}
QPushButton#startBtn {{
    background-color: {p['accent']};
    color: {p['on_accent']};
    font-weight: bold;
    border: none;
}}
QPushButton#startBtn:hover {{
    background-color: {p['accent_hover']};
}}
QPushButton#startBtn:pressed {{
    background-color: {p['accent_pressed']};
}}
QPushButton#startBtn:disabled {{
    background-color: {p['surface1']};
    color: {p['overlay']};
}}
QPushButton#cancelBtn {{
    background-color: {p['red']};
    color: {p['on_accent']};
    font-weight: bold;
    border: none;
}}
QPushButton#cancelBtn:hover {{
    background-color: {p['red_hover']};
}}
QPushButton#cancelBtn:disabled {{
    background-color: {p['surface1']};
    color: {p['overlay']};
}}
QPushButton#saveBtn {{
    background-color: {p['green']};
    color: {p['on_accent']};
    font-weight: bold;
    border: none;
}}
QPushButton#saveBtn:hover {{
    background-color: {p['green_hover']};
}}
QRadioButton, QCheckBox {{
    background: transparent;
    spacing: 6px;
    color: {p['text']};
}}
QRadioButton::indicator {{
    width: 14px; height: 14px;
    border: 2px solid {p['surface2']};
    border-radius: 9px;
    background: {p['surface1']};
}}
QRadioButton::indicator:checked {{
    background: {p['accent']};
    border-color: {p['accent']};
}}
QCheckBox::indicator {{
    width: 16px; height: 16px;
    border: 2px solid {p['surface2']};
    border-radius: 3px;
    background: {p['surface1']};
}}
QCheckBox::indicator:checked {{
    background: {p['accent']};
    border-color: {p['accent']};
}}
QProgressBar {{
    background-color: {p['surface0']};
    border: 1px solid {p['surface1']};
    border-radius: 6px;
    text-align: center;
    color: {p['text']};
    min-height: 22px;
    font-size: 12px;
}}
QProgressBar::chunk {{
    background-color: {p['accent']};
    border-radius: 5px;
}}
QStatusBar {{
    background-color: {p['mantle']};
    color: {p['overlay']};
    font-size: 12px;
}}
"""


DARK_STYLESHEET = build_stylesheet(DARK_PALETTE)
LIGHT_STYLESHEET = build_stylesheet(LIGHT_PALETTE)


def stylesheet_for(theme: str) -> str:
    """Return the stylesheet for the named theme ('dark' or 'light')."""
    return LIGHT_STYLESHEET if theme == "light" else DARK_STYLESHEET
