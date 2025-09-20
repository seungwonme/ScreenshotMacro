import json
import sys
from pathlib import Path

from pynput import keyboard, mouse
from PyQt6.QtCore import Qt, QTimer
from PyQt6.QtGui import QKeySequence, QShortcut
from PyQt6.QtWidgets import (
    QApplication,
    QButtonGroup,
    QCheckBox,
    QDoubleSpinBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMainWindow,
    QPushButton,
    QRadioButton,
    QSpinBox,
    QVBoxLayout,
    QWidget,
)

from src.macro_pyqt import MacroWorker


class ScreenshotGUI(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Screenshot Macro")
        self.setGeometry(200, 100, 900, 500)
        self.setWindowFlags(Qt.WindowType.WindowStaysOnTopHint)

        # 메인 위젯
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        layout = QVBoxLayout(central_widget)

        # 영역 설정
        self.setup_area_controls(layout)

        # 매크로 설정
        self.setup_macro_controls(layout)

        # 액션 타입 설정
        self.setup_action_controls(layout)

        # 버튼
        self.setup_buttons(layout)

        # ESC 키 단축키 설정
        self.escape_shortcut = QShortcut(QKeySequence("Escape"), self)
        self.escape_shortcut.activated.connect(self.close)

        # 워커 스레드
        self.worker = None

        # 좌표 설정용 변수
        self.top_left = (0, 43)
        self.bottom_right = (765, 1169)
        self.selecting_coordinates = False
        self.drag_start = None
        self.drag_end = None

        # 설정 로드
        self.load_config()

        # 키보드 캡처 리스너
        self.key_capture_listener = None
        self.capturing_key = False

    def setup_area_controls(self, layout):
        """스크린샷 영역 설정 UI"""
        area_group = QWidget()
        area_layout = QVBoxLayout(area_group)

        # 좌표 표시
        self.top_left_label = QLabel("Top-Left: (0, 43)")
        self.bottom_right_label = QLabel("Bottom-Right: (765, 1169)")

        area_layout.addWidget(self.top_left_label)
        area_layout.addWidget(self.bottom_right_label)

        # 좌표 설정 버튼
        coord_layout = QHBoxLayout()

        # 드래그로 영역 선택 버튼
        self.select_area_btn = QPushButton("Select Area (Drag)")
        self.select_area_btn.clicked.connect(self.select_area_by_drag)

        # 개별 좌표 설정 버튼
        self.set_top_left_btn = QPushButton("Set Top-Left")
        self.set_top_left_btn.clicked.connect(self.set_top_left_coordinate)

        self.set_bottom_right_btn = QPushButton("Set Bottom-Right")
        self.set_bottom_right_btn.clicked.connect(self.set_bottom_right_coordinate)

        coord_layout.addWidget(self.select_area_btn)
        coord_layout.addWidget(self.set_top_left_btn)
        coord_layout.addWidget(self.set_bottom_right_btn)

        area_layout.addLayout(coord_layout)
        layout.addWidget(area_group)

    def setup_macro_controls(self, layout):
        """매크로 설정 UI"""
        macro_group = QWidget()
        macro_layout = QVBoxLayout(macro_group)

        # 반복 횟수
        rep_layout = QHBoxLayout()
        rep_layout.addWidget(QLabel("Repetitions:"))
        self.repetitions_input = QSpinBox()
        self.repetitions_input.setRange(1, 10000)
        self.repetitions_input.setValue(300)
        rep_layout.addWidget(self.repetitions_input)
        macro_layout.addLayout(rep_layout)

        # 딜레이 설정
        delay_layout = QHBoxLayout()
        delay_layout.addWidget(QLabel("Delay (s):"))
        self.delay_min_input = QDoubleSpinBox()
        self.delay_min_input.setRange(0.1, 60.0)
        self.delay_min_input.setValue(1.0)
        self.delay_min_input.setSingleStep(0.1)
        delay_layout.addWidget(self.delay_min_input)

        delay_layout.addWidget(QLabel("Max (s):"))
        self.delay_max_input = QDoubleSpinBox()
        self.delay_max_input.setRange(0.1, 60.0)
        self.delay_max_input.setValue(3.0)
        self.delay_max_input.setSingleStep(0.1)
        self.delay_max_input.setEnabled(False)
        delay_layout.addWidget(self.delay_max_input)

        macro_layout.addLayout(delay_layout)

        # 랜덤 딜레이 체크박스
        self.random_delay_check = QCheckBox("Use Random Delay")
        self.random_delay_check.toggled.connect(self.toggle_random_delay)
        macro_layout.addWidget(self.random_delay_check)

        layout.addWidget(macro_group)

    def setup_action_controls(self, layout):
        """액션 타입 설정 UI"""
        action_group = QWidget()
        action_layout = QVBoxLayout(action_group)

        action_layout.addWidget(QLabel("Action Type:"))

        # 라디오 버튼 그룹
        self.action_type_group = QButtonGroup()

        # 키보드 입력 옵션
        keyboard_layout = QHBoxLayout()
        self.keyboard_radio = QRadioButton("Keyboard")
        self.keyboard_radio.setChecked(True)
        self.action_type_group.addButton(self.keyboard_radio)
        keyboard_layout.addWidget(self.keyboard_radio)

        self.keyboard_input = QLineEdit()
        self.keyboard_input.setText("right")
        self.keyboard_input.setPlaceholderText("Enter key name (e.g., right, space, enter)")
        keyboard_layout.addWidget(self.keyboard_input)

        self.capture_key_btn = QPushButton("Capture Key")
        self.capture_key_btn.clicked.connect(self.capture_keyboard_input)
        keyboard_layout.addWidget(self.capture_key_btn)

        action_layout.addLayout(keyboard_layout)

        # 마우스 클릭 옵션
        mouse_layout = QHBoxLayout()
        self.mouse_radio = QRadioButton("Mouse Click")
        self.action_type_group.addButton(self.mouse_radio)
        mouse_layout.addWidget(self.mouse_radio)

        self.mouse_position_label = QLabel("Position: Current")
        mouse_layout.addWidget(self.mouse_position_label)

        self.set_mouse_position_btn = QPushButton("Set Position")
        self.set_mouse_position_btn.clicked.connect(self.set_mouse_position)
        self.set_mouse_position_btn.setEnabled(False)
        mouse_layout.addWidget(self.set_mouse_position_btn)

        action_layout.addLayout(mouse_layout)

        # 라디오 버튼 토글 이벤트
        self.keyboard_radio.toggled.connect(self.toggle_action_type)
        self.mouse_radio.toggled.connect(self.toggle_action_type)

        layout.addWidget(action_group)

    def toggle_action_type(self):
        """액션 타입 토글"""
        is_keyboard = self.keyboard_radio.isChecked()
        self.keyboard_input.setEnabled(is_keyboard)
        self.capture_key_btn.setEnabled(is_keyboard)
        self.set_mouse_position_btn.setEnabled(not is_keyboard)

    def setup_buttons(self, layout):
        """버튼 UI"""
        button_layout = QHBoxLayout()

        self.start_btn = QPushButton("Start Macro")
        self.start_btn.clicked.connect(self.start_macro)

        self.cancel_btn = QPushButton("Cancel Macro")
        self.cancel_btn.clicked.connect(self.cancel_macro)
        self.cancel_btn.setEnabled(False)

        self.save_config_btn = QPushButton("Save Config")
        self.save_config_btn.clicked.connect(self.save_config)

        button_layout.addWidget(self.start_btn)
        button_layout.addWidget(self.cancel_btn)
        button_layout.addWidget(self.save_config_btn)

        layout.addLayout(button_layout)

    def toggle_random_delay(self, checked):
        """랜덤 딜레이 토글"""
        self.delay_max_input.setEnabled(checked)

    def select_area_by_drag(self):
        """드래그로 영역 선택"""
        self.hide()
        self.selecting_coordinates = "drag"
        QTimer.singleShot(300, self.start_drag_selection)

    def start_drag_selection(self):
        """드래그 선택 시작"""
        self.drag_start = None
        self.drag_end = None

        def on_move(x, y):
            pass  # 마우스 이동 중에는 아무것도 하지 않음

        def on_click(x, y, button, pressed):
            if button == mouse.Button.left:
                if pressed:
                    # 드래그 시작
                    self.drag_start = (int(x), int(y))
                else:
                    # 드래그 종료
                    if self.drag_start:
                        self.drag_end = (int(x), int(y))
                        # 좌표 정렬 (top-left, bottom-right 순서로)
                        x1, y1 = self.drag_start
                        x2, y2 = self.drag_end
                        self.top_left = (min(x1, x2), min(y1, y2))
                        self.bottom_right = (max(x1, x2), max(y1, y2))

                        # UI 업데이트를 메인 스레드에서 실행
                        QTimer.singleShot(0, self.update_area_from_drag)
                        return False  # 리스너 중지
            elif button == mouse.Button.right:
                # 우클릭으로 취소
                QTimer.singleShot(0, self.cancel_selection)
                return False

        self.mouse_listener = mouse.Listener(on_move=on_move, on_click=on_click)
        self.mouse_listener.start()

    def update_area_from_drag(self):
        """드래그 선택 결과 업데이트"""
        self.top_left_label.setText(f"Top-Left: {self.top_left}")
        self.bottom_right_label.setText(f"Bottom-Right: {self.bottom_right}")

        if hasattr(self, "mouse_listener"):
            self.mouse_listener.stop()
        self.selecting_coordinates = False

        self.show()
        self.raise_()
        self.activateWindow()

    def cancel_selection(self):
        """선택 취소"""
        if hasattr(self, "mouse_listener"):
            self.mouse_listener.stop()
        self.selecting_coordinates = False
        self.show()
        self.raise_()
        self.activateWindow()

    def start_macro(self):
        """매크로 시작"""
        if self.worker and self.worker.isRunning():
            return

        # 설정값 가져오기
        repetitions = self.repetitions_input.value()
        delay_min = self.delay_min_input.value()
        delay_max = (
            self.delay_max_input.value() if self.random_delay_check.isChecked() else delay_min
        )

        # 좌표 계산
        x1, y1 = self.top_left
        x2, y2 = self.bottom_right
        x = min(x1, x2)
        y = min(y1, y2)
        width = abs(x2 - x1)
        height = abs(y2 - y1)

        # 액션 설정
        action_config = {
            "type": "key" if self.keyboard_radio.isChecked() else "click",
            "key": self.keyboard_input.text() if self.keyboard_radio.isChecked() else None,
            "position": (
                self.mouse_position
                if hasattr(self, "mouse_position") and self.mouse_radio.isChecked()
                else None
            ),
        }

        # 워커 스레드 시작
        self.worker = MacroWorker(
            repetitions, delay_min, delay_max, x, y, width, height, action_config
        )
        self.worker.finished.connect(self.macro_finished)
        self.worker.progress.connect(self.update_progress)

        self.worker.start()

        # UI 상태 변경
        self.start_btn.setEnabled(False)
        self.start_btn.setText("Running...")
        self.cancel_btn.setEnabled(True)

    def cancel_macro(self):
        """매크로 취소"""
        if self.worker:
            self.worker.stop()

    def macro_finished(self):
        """매크로 완료"""
        self.start_btn.setEnabled(True)
        self.start_btn.setText("Start Macro")
        self.cancel_btn.setEnabled(False)

    def update_progress(self, count, total):
        """진행률 업데이트"""
        self.start_btn.setText(f"Running... ({count}/{total})")

    def set_top_left_coordinate(self):
        """Top-Left 좌표 설정"""
        self.hide()
        self.selecting_coordinates = "top_left"
        QTimer.singleShot(300, self.start_coordinate_selection)

    def set_bottom_right_coordinate(self):
        """Bottom-Right 좌표 설정"""
        self.hide()
        self.selecting_coordinates = "bottom_right"
        QTimer.singleShot(300, self.start_coordinate_selection)

    def start_coordinate_selection(self):
        """좌표 선택 시작"""

        def on_click(x, y, button, pressed):
            if pressed and button == mouse.Button.left:
                # 좌표 업데이트를 메인 스레드에서 실행
                QTimer.singleShot(0, lambda: self.update_coordinate_from_click(x, y))
                return False  # 리스너 중지

        self.mouse_listener = mouse.Listener(on_click=on_click)
        self.mouse_listener.start()

    def update_coordinate_from_click(self, x, y):
        """좌표 업데이트 및 UI 복원"""
        if self.selecting_coordinates == "top_left":
            self.top_left = (int(x), int(y))
            self.top_left_label.setText(f"Top-Left: {self.top_left}")
        elif self.selecting_coordinates == "bottom_right":
            self.bottom_right = (int(x), int(y))
            self.bottom_right_label.setText(f"Bottom-Right: {self.bottom_right}")

        # 리스너 정리 및 UI 복원
        if hasattr(self, "mouse_listener"):
            self.mouse_listener.stop()
        self.selecting_coordinates = False

        self.show()
        self.raise_()
        self.activateWindow()

    def set_mouse_position(self):
        """마우스 클릭 위치 설정"""
        self.hide()
        QTimer.singleShot(300, self.start_mouse_position_selection)

    def start_mouse_position_selection(self):
        """마우스 위치 선택 시작"""

        def on_click(x, y, button, pressed):
            if pressed and button == mouse.Button.left:
                self.mouse_position = (int(x), int(y))
                QTimer.singleShot(0, self.update_mouse_position)
                return False

        self.mouse_listener = mouse.Listener(on_click=on_click)
        self.mouse_listener.start()

    def update_mouse_position(self):
        """마우스 위치 업데이트"""
        if hasattr(self, "mouse_position"):
            self.mouse_position_label.setText(f"Position: {self.mouse_position}")

        if hasattr(self, "mouse_listener"):
            self.mouse_listener.stop()

        self.show()
        self.raise_()
        self.activateWindow()

    def capture_keyboard_input(self):
        """키보드 입력 캡처"""
        self.capture_key_btn.setText("Press any key...")
        self.capture_key_btn.setEnabled(False)
        self.capturing_key = True

        # 일시적으로 ESC 단축키 비활성화
        if hasattr(self, "escape_shortcut"):
            self.escape_shortcut.setEnabled(False)

        def on_press(key):
            if self.capturing_key:
                # 키 이름 추출
                try:
                    if hasattr(key, "char") and key.char:
                        key_name = key.char
                    else:
                        key_name = str(key).replace("Key.", "")
                except:
                    key_name = str(key).replace("Key.", "")

                # UI 업데이트를 메인 스레드에서 실행
                QTimer.singleShot(0, lambda: self.update_captured_key(key_name))
                return False  # 리스너 중지

        # 키보드 리스너를 짧은 지연 후 시작
        QTimer.singleShot(100, lambda: self.start_key_capture_listener(on_press))

    def start_key_capture_listener(self, on_press):
        """키 캡처 리스너 시작"""
        self.key_capture_listener = keyboard.Listener(on_press=on_press)
        self.key_capture_listener.start()

    def update_captured_key(self, key_name):
        """캡처된 키 업데이트"""
        self.keyboard_input.setText(key_name)
        self.capture_key_btn.setText("Capture Key")
        self.capture_key_btn.setEnabled(True)
        self.capturing_key = False

        # ESC 단축키 다시 활성화
        if hasattr(self, "escape_shortcut"):
            self.escape_shortcut.setEnabled(True)

        if hasattr(self, "key_capture_listener"):
            self.key_capture_listener.stop()

    def keyPressEvent(self, event):
        """키 이벤트 처리"""
        # 키 캡처 중에는 키 이벤트 무시
        if self.capturing_key:
            return

        if event.key() == Qt.Key.Key_Escape:
            if self.selecting_coordinates:
                # ESC로 좌표 선택 취소
                if hasattr(self, "mouse_listener"):
                    self.mouse_listener.stop()
                self.selecting_coordinates = False
                self.show()
            elif not self.capturing_key:
                # ESC로 프로그램 종료 (키 캡처 중이 아닐 때만)
                self.close()
        super().keyPressEvent(event)

    def load_config(self):
        """설정 파일 로드"""
        config_path = Path("config.json")
        if config_path.exists():
            try:
                with open(config_path, "r", encoding="utf-8") as f:
                    config = json.load(f)

                # GUI 설정 로드
                gui_config = config.get("gui", {})
                default_area = gui_config.get("default_area", {})
                if "top_left" in default_area:
                    self.top_left = tuple(default_area["top_left"])
                    self.top_left_label.setText(f"Top-Left: {self.top_left}")
                if "bottom_right" in default_area:
                    self.bottom_right = tuple(default_area["bottom_right"])
                    self.bottom_right_label.setText(f"Bottom-Right: {self.bottom_right}")

                # 매크로 설정 로드
                macro_config = config.get("macro", {})
                self.repetitions_input.setValue(macro_config.get("default_repetitions", 300))

                delay_config = macro_config.get("default_delay", {})
                self.delay_min_input.setValue(delay_config.get("min", 1.0))
                self.delay_max_input.setValue(delay_config.get("max", 3.0))

                # 액션 설정 로드
                action_config = macro_config.get("action", {})
                action_type = action_config.get("type", "key")
                if action_type == "key":
                    self.keyboard_radio.setChecked(True)
                    self.keyboard_input.setText(action_config.get("key", "right"))
                else:
                    self.mouse_radio.setChecked(True)
                    position = action_config.get("position")
                    if position:
                        self.mouse_position = tuple(position)
                        self.mouse_position_label.setText(f"Position: {self.mouse_position}")

            except Exception as e:
                print(f"Failed to load config: {e}")

    def save_config(self):
        """설정 파일 저장"""
        config = {
            "gui": {
                "window_size": f"{self.width()}x{self.height()}",
                "default_area": {
                    "top_left": list(self.top_left),
                    "bottom_right": list(self.bottom_right),
                },
            },
            "macro": {
                "default_repetitions": self.repetitions_input.value(),
                "default_delay": {
                    "min": self.delay_min_input.value(),
                    "max": self.delay_max_input.value(),
                },
                "action": {
                    "type": "key" if self.keyboard_radio.isChecked() else "click",
                    "key": self.keyboard_input.text() if self.keyboard_radio.isChecked() else None,
                    "position": (
                        list(self.mouse_position)
                        if hasattr(self, "mouse_position") and self.mouse_radio.isChecked()
                        else None
                    ),
                },
            },
            "screenshot": {"directory": "./screenshots", "format": "png"},
        }

        config_path = Path("config.json")
        try:
            with open(config_path, "w", encoding="utf-8") as f:
                json.dump(config, f, indent=2, ensure_ascii=False)
            print("Config saved successfully")
        except Exception as e:
            print(f"Failed to save config: {e}")


def run_gui():
    """PyQt6 GUI 실행"""
    app = QApplication(sys.argv)

    # 어플리케이션 스타일 설정
    app.setStyle("Fusion")

    window = ScreenshotGUI()
    window.show()

    sys.exit(app.exec())


if __name__ == "__main__":
    run_gui()
