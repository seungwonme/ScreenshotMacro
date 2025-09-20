import os
import random
import time

import pyautogui
from PyQt6.QtCore import QThread, pyqtSignal

from src.constants import Paths
from src.utils import get_next_count, take_screenshot


class MacroWorker(QThread):
    """매크로 실행 워커 스레드"""

    finished = pyqtSignal()
    progress = pyqtSignal(int, int)  # current, total

    def __init__(self, repetitions, delay_min, delay_max, x, y, width, height, action_config=None):
        super().__init__()
        self.repetitions = repetitions
        self.delay_min = delay_min
        self.delay_max = delay_max
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.action_config = action_config or {"type": "key", "key": "right"}
        self.should_stop = False

    def stop(self):
        """스레드 중단"""
        self.should_stop = True

    def run(self):
        """매크로 실행"""
        try:
            # 5초 대기
            time.sleep(5)

            screenshot_directory = Paths.SCREENSHOTS_DIR
            count = get_next_count(screenshot_directory, "screenshot", "png")

            for i in range(self.repetitions):
                if self.should_stop:
                    break

                # 딜레이 계산
                delay = random.uniform(self.delay_min, self.delay_max)
                time.sleep(delay)

                if self.should_stop:
                    break

                # 스크린샷 저장
                if not os.path.exists(screenshot_directory):
                    os.makedirs(screenshot_directory)

                filename = f"{screenshot_directory}/screenshot_{count}.png"
                take_screenshot(filename, self.x, self.y, self.width, self.height)

                # 액션 실행
                action_type = self.action_config.get("type", "key")
                if action_type == "key":
                    key = self.action_config.get("key", "right")
                    pyautogui.press(key)
                elif action_type == "click":
                    position = self.action_config.get("position")
                    if position and len(position) == 2:
                        pyautogui.click(position[0], position[1])
                    else:
                        pyautogui.click()

                count += 1

                # 진행률 업데이트
                self.progress.emit(i + 1, self.repetitions)

        except Exception as e:
            print(f"매크로 실행 중 오류: {e}")
        finally:
            self.finished.emit()
