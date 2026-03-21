"""PyQt6 GUI for ScreenshotMacro."""

from __future__ import annotations

import sys

from loguru import logger
from pynput import keyboard, mouse
from PyQt6.QtCore import Qt, QTimer
from PyQt6.QtGui import QFont
from PyQt6.QtWidgets import (
    QApplication,
    QButtonGroup,
    QCheckBox,
    QDoubleSpinBox,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMainWindow,
    QMessageBox,
    QProgressBar,
    QPushButton,
    QRadioButton,
    QSpinBox,
    QVBoxLayout,
    QWidget,
)

from src.config import (
    ActionConfig,
    AreaConfig,
    ConfigManager,
    DelayConfig,
    get_config,
    save_config,
)
import subprocess

from src.macro_pyqt import MacroWorker

STYLESHEET = """
QMainWindow {
    background-color: #1e1e2e;
}
QWidget {
    background-color: #1e1e2e;
    color: #cdd6f4;
    font-size: 13px;
}
QGroupBox {
    background-color: #313244;
    border: 1px solid #45475a;
    border-radius: 8px;
    margin-top: 14px;
    padding: 16px 12px 12px 12px;
    font-weight: bold;
    font-size: 13px;
}
QGroupBox::title {
    subcontrol-origin: margin;
    left: 12px;
    padding: 0 6px;
    color: #89b4fa;
}
QLabel {
    background: transparent;
    color: #bac2de;
    font-size: 13px;
}
QSpinBox, QDoubleSpinBox, QLineEdit {
    background-color: #45475a;
    border: 1px solid #585b70;
    border-radius: 4px;
    padding: 4px 8px;
    color: #cdd6f4;
    min-height: 28px;
    selection-background-color: #89b4fa;
}
QSpinBox:focus, QDoubleSpinBox:focus, QLineEdit:focus {
    border: 1px solid #89b4fa;
}
QSpinBox::up-button, QDoubleSpinBox::up-button {
    subcontrol-origin: border;
    subcontrol-position: top right;
    width: 20px;
    border-left: 1px solid #585b70;
    border-bottom: 1px solid #585b70;
    border-top-right-radius: 4px;
    background: #585b70;
}
QSpinBox::down-button, QDoubleSpinBox::down-button {
    subcontrol-origin: border;
    subcontrol-position: bottom right;
    width: 20px;
    border-left: 1px solid #585b70;
    border-bottom-right-radius: 4px;
    background: #585b70;
}
QSpinBox::up-arrow, QDoubleSpinBox::up-arrow {
    width: 0; height: 0;
    border-left: 4px solid transparent;
    border-right: 4px solid transparent;
    border-bottom: 5px solid #cdd6f4;
}
QSpinBox::down-arrow, QDoubleSpinBox::down-arrow {
    width: 0; height: 0;
    border-left: 4px solid transparent;
    border-right: 4px solid transparent;
    border-top: 5px solid #cdd6f4;
}
QPushButton {
    background-color: #45475a;
    border: 1px solid #585b70;
    border-radius: 6px;
    padding: 6px 16px;
    color: #cdd6f4;
    min-height: 28px;
    font-weight: 500;
}
QPushButton:hover {
    background-color: #585b70;
    border-color: #89b4fa;
}
QPushButton:pressed {
    background-color: #313244;
}
QPushButton:disabled {
    background-color: #313244;
    color: #585b70;
    border-color: #45475a;
}
QPushButton#startBtn {
    background-color: #89b4fa;
    color: #1e1e2e;
    font-weight: bold;
    border: none;
}
QPushButton#startBtn:hover {
    background-color: #b4d0fb;
}
QPushButton#startBtn:pressed {
    background-color: #74a8f7;
}
QPushButton#startBtn:disabled {
    background-color: #45475a;
    color: #585b70;
}
QPushButton#cancelBtn {
    background-color: #f38ba8;
    color: #1e1e2e;
    font-weight: bold;
    border: none;
}
QPushButton#cancelBtn:hover {
    background-color: #f5a3b8;
}
QPushButton#cancelBtn:disabled {
    background-color: #45475a;
    color: #585b70;
}
QPushButton#saveBtn {
    background-color: #a6e3a1;
    color: #1e1e2e;
    font-weight: bold;
    border: none;
}
QPushButton#saveBtn:hover {
    background-color: #b8eab4;
}
QRadioButton, QCheckBox {
    background: transparent;
    spacing: 6px;
    color: #cdd6f4;
}
QRadioButton::indicator {
    width: 14px; height: 14px;
    border: 2px solid #585b70;
    border-radius: 9px;
    background: #45475a;
}
QRadioButton::indicator:checked {
    background: #89b4fa;
    border-color: #89b4fa;
}
QCheckBox::indicator {
    width: 16px; height: 16px;
    border: 2px solid #585b70;
    border-radius: 3px;
    background: #45475a;
}
QCheckBox::indicator:checked {
    background: #89b4fa;
    border-color: #89b4fa;
}
QProgressBar {
    background-color: #313244;
    border: 1px solid #45475a;
    border-radius: 6px;
    text-align: center;
    color: #cdd6f4;
    min-height: 22px;
    font-size: 12px;
}
QProgressBar::chunk {
    background-color: #89b4fa;
    border-radius: 5px;
}
QStatusBar {
    background-color: #181825;
    color: #6c7086;
    font-size: 12px;
}
"""


class ScreenshotGUI(QMainWindow):
    """Main GUI window for screenshot macro."""

    def __init__(self) -> None:
        super().__init__()
        self._config_manager = ConfigManager()
        self._config = self._config_manager.config

        self._init_window()
        self._init_state()
        self._setup_ui()
        self._load_config_to_ui()

    def _init_window(self) -> None:
        """Initialize window properties."""
        self.setWindowTitle("Screenshot Macro")
        self.setGeometry(200, 100, 520, 560)
        self.setWindowFlags(Qt.WindowType.WindowStaysOnTopHint)
        self.setMinimumWidth(400)
        self.statusBar().showMessage("Ready")

    def _init_state(self) -> None:
        """Initialize internal state variables."""
        self.worker: MacroWorker | None = None
        self.top_left: tuple[int, int] = self._config.gui.area.top_left
        self.bottom_right: tuple[int, int] = self._config.gui.area.bottom_right
        self.selecting_coordinates: str | bool = False
        self.drag_start: tuple[int, int] | None = None
        self.drag_end: tuple[int, int] | None = None
        self.mouse_position: tuple[int, int] | None = None
        self.mouse_listener: mouse.Listener | None = None
        self.key_capture_listener: keyboard.Listener | None = None
        self.capturing_key: bool = False

    def _setup_ui(self) -> None:
        """Set up the user interface."""
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        layout = QVBoxLayout(central_widget)
        layout.setSpacing(8)
        layout.setContentsMargins(16, 12, 16, 12)

        self._setup_area_controls(layout)
        self._setup_macro_controls(layout)
        self._setup_action_controls(layout)
        self._setup_progress(layout)
        self._setup_buttons(layout)

    def _setup_area_controls(self, layout: QVBoxLayout) -> None:
        """Set up screenshot area selection controls."""
        group = QGroupBox("Capture Area")
        g_layout = QVBoxLayout(group)
        g_layout.setSpacing(8)

        coords_layout = QHBoxLayout()
        coords_layout.setSpacing(12)

        tl_layout = QVBoxLayout()
        tl_label = QLabel("Top-Left")
        tl_label.setStyleSheet("color: #89b4fa; font-weight: bold; font-size: 11px;")
        tl_layout.addWidget(tl_label)
        tl_xy = QHBoxLayout()
        self.tl_x_input = QSpinBox()
        self.tl_x_input.setRange(0, 10000)
        self.tl_x_input.setValue(self.top_left[0])
        self.tl_x_input.setPrefix("X  ")
        self.tl_y_input = QSpinBox()
        self.tl_y_input.setRange(0, 10000)
        self.tl_y_input.setValue(self.top_left[1])
        self.tl_y_input.setPrefix("Y  ")
        tl_xy.addWidget(self.tl_x_input)
        tl_xy.addWidget(self.tl_y_input)
        tl_layout.addLayout(tl_xy)
        coords_layout.addLayout(tl_layout)

        br_layout = QVBoxLayout()
        br_label = QLabel("Bottom-Right")
        br_label.setStyleSheet("color: #89b4fa; font-weight: bold; font-size: 11px;")
        br_layout.addWidget(br_label)
        br_xy = QHBoxLayout()
        self.br_x_input = QSpinBox()
        self.br_x_input.setRange(0, 10000)
        self.br_x_input.setValue(self.bottom_right[0])
        self.br_x_input.setPrefix("X  ")
        self.br_y_input = QSpinBox()
        self.br_y_input.setRange(0, 10000)
        self.br_y_input.setValue(self.bottom_right[1])
        self.br_y_input.setPrefix("Y  ")
        br_xy.addWidget(self.br_x_input)
        br_xy.addWidget(self.br_y_input)
        br_layout.addLayout(br_xy)
        coords_layout.addLayout(br_layout)

        g_layout.addLayout(coords_layout)

        self.tl_x_input.valueChanged.connect(self._update_coords_from_input)
        self.tl_y_input.valueChanged.connect(self._update_coords_from_input)
        self.br_x_input.valueChanged.connect(self._update_coords_from_input)
        self.br_y_input.valueChanged.connect(self._update_coords_from_input)

        btn_layout = QHBoxLayout()
        btn_layout.setSpacing(6)
        self.select_area_btn = QPushButton("Drag Select")
        self.select_area_btn.clicked.connect(self._select_area_by_drag)
        self.set_top_left_btn = QPushButton("Pick Top-Left")
        self.set_top_left_btn.clicked.connect(self._set_top_left_coordinate)
        self.set_bottom_right_btn = QPushButton("Pick Bottom-Right")
        self.set_bottom_right_btn.clicked.connect(self._set_bottom_right_coordinate)
        btn_layout.addWidget(self.select_area_btn)
        btn_layout.addWidget(self.set_top_left_btn)
        btn_layout.addWidget(self.set_bottom_right_btn)
        g_layout.addLayout(btn_layout)

        layout.addWidget(group)

    def _setup_macro_controls(self, layout: QVBoxLayout) -> None:
        """Set up macro configuration controls."""
        group = QGroupBox("Macro Settings")
        g_layout = QVBoxLayout(group)
        g_layout.setSpacing(8)

        rep_layout = QHBoxLayout()
        rep_layout.addWidget(QLabel("Repetitions"))
        self.repetitions_input = QSpinBox()
        self.repetitions_input.setRange(1, 10000)
        self.repetitions_input.setValue(self._config.macro.repetitions)
        rep_layout.addWidget(self.repetitions_input)
        g_layout.addLayout(rep_layout)

        delay_layout = QHBoxLayout()
        delay_layout.addWidget(QLabel("Delay (s)"))
        self.delay_min_input = QDoubleSpinBox()
        self.delay_min_input.setRange(0.1, 60.0)
        self.delay_min_input.setValue(self._config.macro.delay.min)
        self.delay_min_input.setSingleStep(0.1)
        delay_layout.addWidget(self.delay_min_input)

        self.delay_max_label = QLabel("Max")
        delay_layout.addWidget(self.delay_max_label)
        self.delay_max_input = QDoubleSpinBox()
        self.delay_max_input.setRange(0.1, 60.0)
        self.delay_max_input.setValue(self._config.macro.delay.max)
        self.delay_max_input.setSingleStep(0.1)
        self.delay_max_input.setEnabled(False)
        delay_layout.addWidget(self.delay_max_input)
        g_layout.addLayout(delay_layout)

        self.random_delay_check = QCheckBox("Use Random Delay")
        self.random_delay_check.toggled.connect(self._toggle_random_delay)
        g_layout.addWidget(self.random_delay_check)

        layout.addWidget(group)

    def _setup_action_controls(self, layout: QVBoxLayout) -> None:
        """Set up action type controls."""
        group = QGroupBox("Action")
        g_layout = QVBoxLayout(group)
        g_layout.setSpacing(8)

        self.action_type_group = QButtonGroup()

        keyboard_layout = QHBoxLayout()
        self.keyboard_radio = QRadioButton("Keyboard")
        self.keyboard_radio.setChecked(True)
        self.action_type_group.addButton(self.keyboard_radio)
        keyboard_layout.addWidget(self.keyboard_radio)
        self.keyboard_input = QLineEdit()
        self.keyboard_input.setText(self._config.macro.action.key or "right")
        self.keyboard_input.setPlaceholderText("e.g. right, space, enter")
        keyboard_layout.addWidget(self.keyboard_input)
        self.capture_key_btn = QPushButton("Capture Key")
        self.capture_key_btn.clicked.connect(self._capture_keyboard_input)
        keyboard_layout.addWidget(self.capture_key_btn)
        g_layout.addLayout(keyboard_layout)

        mouse_layout = QHBoxLayout()
        self.mouse_radio = QRadioButton("Mouse Click")
        self.action_type_group.addButton(self.mouse_radio)
        mouse_layout.addWidget(self.mouse_radio)
        self.mouse_position_label = QLabel("Position: Current")
        mouse_layout.addWidget(self.mouse_position_label)
        self.set_mouse_position_btn = QPushButton("Set Position")
        self.set_mouse_position_btn.clicked.connect(self._set_mouse_position)
        self.set_mouse_position_btn.setEnabled(False)
        mouse_layout.addWidget(self.set_mouse_position_btn)
        self.reset_mouse_position_btn = QPushButton("Reset")
        self.reset_mouse_position_btn.clicked.connect(self._reset_mouse_position)
        self.reset_mouse_position_btn.setEnabled(False)
        mouse_layout.addWidget(self.reset_mouse_position_btn)
        g_layout.addLayout(mouse_layout)

        self.keyboard_radio.toggled.connect(self._toggle_action_type)
        self.mouse_radio.toggled.connect(self._toggle_action_type)

        layout.addWidget(group)

    def _setup_progress(self, layout: QVBoxLayout) -> None:
        """Set up progress bar."""
        self.progress_bar = QProgressBar()
        self.progress_bar.setRange(0, 100)
        self.progress_bar.setValue(0)
        self.progress_bar.setTextVisible(True)
        self.progress_bar.setFormat("%v / %m (%p%)")
        layout.addWidget(self.progress_bar)

    def _setup_buttons(self, layout: QVBoxLayout) -> None:
        """Set up control buttons."""
        button_layout = QHBoxLayout()
        button_layout.setSpacing(8)

        self.start_btn = QPushButton("Start Macro")
        self.start_btn.setObjectName("startBtn")
        self.start_btn.clicked.connect(self._start_macro)

        self.cancel_btn = QPushButton("Cancel")
        self.cancel_btn.setObjectName("cancelBtn")
        self.cancel_btn.clicked.connect(self._cancel_macro)
        self.cancel_btn.setEnabled(False)

        self.save_config_btn = QPushButton("Save Config")
        self.save_config_btn.setObjectName("saveBtn")
        self.save_config_btn.clicked.connect(self._save_config)

        self.open_folder_btn = QPushButton("Open Folder")
        self.open_folder_btn.clicked.connect(self._open_screenshots_folder)

        button_layout.addWidget(self.start_btn)
        button_layout.addWidget(self.cancel_btn)
        button_layout.addWidget(self.save_config_btn)
        button_layout.addWidget(self.open_folder_btn)

        layout.addLayout(button_layout)

    def _update_coords_from_input(self) -> None:
        """Update internal coordinates from spin box values."""
        self.top_left = (self.tl_x_input.value(), self.tl_y_input.value())
        self.bottom_right = (self.br_x_input.value(), self.br_y_input.value())

    def _sync_coord_inputs(self) -> None:
        """Sync spin box values from internal coordinates."""
        self.tl_x_input.setValue(self.top_left[0])
        self.tl_y_input.setValue(self.top_left[1])
        self.br_x_input.setValue(self.bottom_right[0])
        self.br_y_input.setValue(self.bottom_right[1])

    def _load_config_to_ui(self) -> None:
        """Load configuration values to UI elements."""
        self._sync_coord_inputs()
        self.repetitions_input.setValue(self._config.macro.repetitions)
        self.delay_min_input.setValue(self._config.macro.delay.min)
        self.delay_max_input.setValue(self._config.macro.delay.max)

        action = self._config.macro.action
        if action.type == "key":
            self.keyboard_radio.setChecked(True)
            self.keyboard_input.setText(action.key or "right")
        else:
            self.mouse_radio.setChecked(True)
            if action.position:
                self.mouse_position = action.position
                self.mouse_position_label.setText(f"Position: {self.mouse_position}")

    def _toggle_random_delay(self, checked: bool) -> None:
        """Toggle random delay input."""
        self.delay_max_input.setEnabled(checked)

    def _toggle_action_type(self) -> None:
        """Toggle between keyboard and mouse action types."""
        is_keyboard = self.keyboard_radio.isChecked()
        self.keyboard_input.setEnabled(is_keyboard)
        self.capture_key_btn.setEnabled(is_keyboard)
        self.set_mouse_position_btn.setEnabled(not is_keyboard)
        self.reset_mouse_position_btn.setEnabled(not is_keyboard)

    def _hide_for_selection(self) -> None:
        """Hide window by moving off-screen (keeps app active on macOS)."""
        self._saved_pos = self.pos()
        self.move(-10000, -10000)
        self.setWindowOpacity(0)

    def _stop_mouse_listener(self) -> None:
        """Stop and clean up mouse listener."""
        if self.mouse_listener:
            self.mouse_listener.stop()
            self.mouse_listener.join(timeout=1.0)
            self.mouse_listener = None

    def _stop_key_listener(self) -> None:
        """Stop and clean up keyboard listener."""
        if self.key_capture_listener:
            self.key_capture_listener.stop()
            self.key_capture_listener = None

    def _select_area_by_drag(self) -> None:
        """Start drag-based area selection."""
        self._hide_for_selection()
        self.selecting_coordinates = "drag"
        QTimer.singleShot(300, self._start_drag_selection)

    def _start_drag_selection(self) -> None:
        """Initialize drag selection listener."""
        self.drag_start = None
        self.drag_end = None

        def on_click(x: int, y: int, button: mouse.Button, pressed: bool) -> bool | None:
            if button == mouse.Button.left:
                if pressed:
                    self.drag_start = (int(x), int(y))
                else:
                    if self.drag_start:
                        self.drag_end = (int(x), int(y))
                        x1, y1 = self.drag_start
                        x2, y2 = self.drag_end
                        self.top_left = (min(x1, x2), min(y1, y2))
                        self.bottom_right = (max(x1, x2), max(y1, y2))
                        QTimer.singleShot(0, self._update_area_from_drag)
                        return False
            elif button == mouse.Button.right:
                QTimer.singleShot(0, self._cancel_selection)
                return False
            return None

        self.mouse_listener = mouse.Listener(on_click=on_click)
        self.mouse_listener.start()

    def _update_area_from_drag(self) -> None:
        """Update UI after drag selection."""
        self._sync_coord_inputs()
        self._stop_mouse_listener()
        self.selecting_coordinates = False
        self._restore_window()

    def _cancel_selection(self) -> None:
        """Cancel coordinate selection."""
        self._stop_mouse_listener()
        self.selecting_coordinates = False
        self._restore_window()

    def _restore_window(self) -> None:
        """Restore and focus the window."""
        if hasattr(self, "_saved_pos"):
            self.move(self._saved_pos)
        self.setWindowOpacity(1)
        self.showNormal()
        self.raise_()
        self.activateWindow()
        self.setFocus()
        QTimer.singleShot(100, self._ensure_focus)

    def _ensure_focus(self) -> None:
        """Ensure window has focus on macOS."""
        self.raise_()
        self.activateWindow()

    def _set_top_left_coordinate(self) -> None:
        """Start top-left coordinate selection."""
        self._hide_for_selection()
        self.selecting_coordinates = "top_left"
        QTimer.singleShot(300, self._start_coordinate_selection)

    def _set_bottom_right_coordinate(self) -> None:
        """Start bottom-right coordinate selection."""
        self._hide_for_selection()
        self.selecting_coordinates = "bottom_right"
        QTimer.singleShot(300, self._start_coordinate_selection)

    def _start_coordinate_selection(self) -> None:
        """Initialize single-point coordinate selection."""

        def on_click(x: int, y: int, button: mouse.Button, pressed: bool) -> bool | None:
            if button == mouse.Button.left and not pressed:
                QTimer.singleShot(0, lambda: self._update_coordinate_from_click(x, y))
                return False
            return None

        self.mouse_listener = mouse.Listener(on_click=on_click)
        self.mouse_listener.start()

    def _update_coordinate_from_click(self, x: int, y: int) -> None:
        """Update coordinate from click position."""
        if self.selecting_coordinates == "top_left":
            self.top_left = (int(x), int(y))
        elif self.selecting_coordinates == "bottom_right":
            self.bottom_right = (int(x), int(y))

        self._sync_coord_inputs()
        self._stop_mouse_listener()
        self.selecting_coordinates = False
        self._restore_window()

    def _set_mouse_position(self) -> None:
        """Start mouse position selection."""
        self._hide_for_selection()
        QTimer.singleShot(300, self._start_mouse_position_selection)

    def _start_mouse_position_selection(self) -> None:
        """Initialize mouse position selection."""

        def on_click(x: int, y: int, button: mouse.Button, pressed: bool) -> bool | None:
            if button == mouse.Button.left and not pressed:
                self.mouse_position = (int(x), int(y))
                QTimer.singleShot(0, self._update_mouse_position)
                return False
            return None

        self.mouse_listener = mouse.Listener(on_click=on_click)
        self.mouse_listener.start()

    def _update_mouse_position(self) -> None:
        """Update mouse position label."""
        if self.mouse_position:
            self.mouse_position_label.setText(f"Position: {self.mouse_position}")
        self._stop_mouse_listener()
        self._restore_window()

    def _reset_mouse_position(self) -> None:
        """Reset mouse position to current (no fixed position)."""
        self.mouse_position = None
        self.mouse_position_label.setText("Position: Current")

    def _capture_keyboard_input(self) -> None:
        """Start keyboard key capture."""
        self.capture_key_btn.setText("Press any key...")
        self.capture_key_btn.setEnabled(False)
        self.capturing_key = True

        def on_press(key: keyboard.Key | keyboard.KeyCode) -> bool:
            if self.capturing_key:
                try:
                    if hasattr(key, "char") and key.char:
                        key_name = key.char
                    else:
                        key_name = str(key).replace("Key.", "")
                except Exception:
                    key_name = str(key).replace("Key.", "")

                QTimer.singleShot(0, lambda: self._update_captured_key(key_name))
                return False
            return True

        QTimer.singleShot(100, lambda: self._start_key_capture_listener(on_press))

    def _start_key_capture_listener(self, on_press) -> None:
        """Start the key capture listener."""
        self.key_capture_listener = keyboard.Listener(on_press=on_press)
        self.key_capture_listener.start()

    def _update_captured_key(self, key_name: str) -> None:
        """Update the captured key in UI."""
        self.keyboard_input.setText(key_name)
        self.capture_key_btn.setText("Capture Key")
        self.capture_key_btn.setEnabled(True)
        self.capturing_key = False

        self._stop_key_listener()

    def _start_macro(self) -> None:
        """Start the macro execution."""
        if self.worker and self.worker.isRunning():
            return

        repetitions = self.repetitions_input.value()
        delay_min = self.delay_min_input.value()
        delay_max = (
            self.delay_max_input.value() if self.random_delay_check.isChecked() else delay_min
        )

        x1, y1 = self.top_left
        x2, y2 = self.bottom_right
        x = min(x1, x2)
        y = min(y1, y2)
        width = abs(x2 - x1)
        height = abs(y2 - y1)

        if width <= 0 or height <= 0:
            QMessageBox.warning(self, "Invalid Area", "Screenshot area has invalid dimensions.")
            return

        action_config = ActionConfig(
            type="key" if self.keyboard_radio.isChecked() else "click",
            key=self.keyboard_input.text() if self.keyboard_radio.isChecked() else None,
            position=(
                self.mouse_position if self.mouse_radio.isChecked() and self.mouse_position else None
            ),
        )

        logger.info(f"Starting macro: {repetitions} reps, delay {delay_min}-{delay_max}s")

        self.worker = MacroWorker(
            repetitions, delay_min, delay_max, x, y, width, height, action_config
        )
        self.worker.finished.connect(self._macro_finished)
        self.worker.progress.connect(self._update_progress)
        self.worker.error.connect(self._handle_error)
        self.worker.countdown.connect(self._update_countdown)
        self.worker.status_changed.connect(self._update_status)

        self.worker.start()

        self.start_btn.setEnabled(False)
        self.start_btn.setText("Running...")
        self.cancel_btn.setEnabled(True)

    def _cancel_macro(self) -> None:
        """Cancel the running macro."""
        if self.worker:
            self.worker.stop()
            logger.info("Macro cancelled by user")

    def _update_countdown(self, remaining: int) -> None:
        """Update countdown display."""
        self.start_btn.setText(f"Starting in {remaining}s...")

    def _update_status(self, status: str) -> None:
        """Update status bar."""
        messages = {
            "waiting": "Waiting to start...",
            "running": "Macro running",
        }
        self.statusBar().showMessage(messages.get(status, status))

    def _macro_finished(self) -> None:
        """Handle macro completion."""
        self.start_btn.setEnabled(True)
        self.start_btn.setText("Start Macro")
        self.cancel_btn.setEnabled(False)
        self.progress_bar.setValue(0)
        self.statusBar().showMessage("Completed")

    def _update_progress(self, count: int, total: int) -> None:
        """Update progress display."""
        self.progress_bar.setRange(0, total)
        self.progress_bar.setValue(count)
        self.start_btn.setText(f"Running... ({count}/{total})")
        self.statusBar().showMessage(f"Capturing: {count}/{total}")

    def _handle_error(self, error_msg: str) -> None:
        """Handle error from worker thread."""
        logger.error(f"Macro error: {error_msg}")
        QMessageBox.warning(self, "Macro Error", error_msg)

    def _open_screenshots_folder(self) -> None:
        """Open the screenshots directory in Finder."""
        directory = self._config.screenshot.directory
        directory.mkdir(parents=True, exist_ok=True)
        subprocess.run(["open", str(directory)])

    def _save_config(self) -> None:
        """Save current settings to config file."""
        self._config.gui.area = AreaConfig(
            top_left=self.top_left,
            bottom_right=self.bottom_right,
        )
        self._config.gui.window_size = f"{self.width()}x{self.height()}"

        self._config.macro.repetitions = self.repetitions_input.value()
        self._config.macro.delay = DelayConfig(
            min=self.delay_min_input.value(),
            max=self.delay_max_input.value(),
        )
        self._config.macro.action = ActionConfig(
            type="key" if self.keyboard_radio.isChecked() else "click",
            key=self.keyboard_input.text() if self.keyboard_radio.isChecked() else None,
            position=self.mouse_position if self.mouse_radio.isChecked() else None,
        )

        if save_config():
            logger.info("Config saved successfully")
            QMessageBox.information(self, "Config Saved", "Configuration saved successfully.")
        else:
            logger.error("Failed to save config")
            QMessageBox.warning(self, "Save Failed", "Failed to save configuration.")

    def _save_config_silent(self) -> None:
        """Save current settings to config file without UI feedback."""
        self._config.gui.area = AreaConfig(
            top_left=self.top_left,
            bottom_right=self.bottom_right,
        )
        self._config.gui.window_size = f"{self.width()}x{self.height()}"
        self._config.macro.repetitions = self.repetitions_input.value()
        self._config.macro.delay = DelayConfig(
            min=self.delay_min_input.value(),
            max=self.delay_max_input.value(),
        )
        self._config.macro.action = ActionConfig(
            type="key" if self.keyboard_radio.isChecked() else "click",
            key=self.keyboard_input.text() if self.keyboard_radio.isChecked() else None,
            position=self.mouse_position if self.mouse_radio.isChecked() else None,
        )
        if save_config():
            logger.info("Config auto-saved on exit")
        else:
            logger.error("Failed to auto-save config on exit")

    def keyPressEvent(self, event) -> None:
        """Handle key press events."""
        if self.capturing_key:
            return

        if event.key() == Qt.Key.Key_Escape:
            if self.selecting_coordinates:
                self._stop_mouse_listener()
                self.selecting_coordinates = False
                self._restore_window()
            elif not self.capturing_key:
                self.close()
        super().keyPressEvent(event)

    def closeEvent(self, event) -> None:
        """Clean up resources and auto-save config on close."""
        self._save_config_silent()
        self._stop_mouse_listener()
        self._stop_key_listener()
        if self.worker and self.worker.isRunning():
            self.worker.stop()
            self.worker.wait()
        super().closeEvent(event)


def run_gui() -> None:
    """Run the PyQt6 GUI application."""
    app = QApplication(sys.argv)
    app.setStyle("Fusion")
    app.setStyleSheet(STYLESHEET)
    app.setFont(QFont("SF Pro Text", 13))

    window = ScreenshotGUI()
    window.show()

    sys.exit(app.exec())


if __name__ == "__main__":
    run_gui()
