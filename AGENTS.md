# Project Notes

- 2026-03-24: `src/gui_pyqt.py`에 `Start Delay (s)` 입력을 추가하고 시작 직전/저장 시 `macro.initial_wait`를 반영하도록 수정했다. `src/macro_pyqt.py`는 명시적으로 전달된 `initial_wait`를 우선 사용하며, `tests/test_config.py`와 `tests/test_macro_worker.py`에 관련 회귀 테스트를 추가했다.
- 2026-03-24: `src/config.py`에서 `ActionConfig(type="click", position=None)`을 유효한 상태로 허용하도록 정리했다. GUI의 `Mouse Click > Position: Current` 상태와 `MacroWorker`의 현재 커서 클릭 동작에 맞춘 변경이다.
