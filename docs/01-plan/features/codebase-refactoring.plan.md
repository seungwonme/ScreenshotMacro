# Plan: ScreenshotMacro Codebase Refactoring

## 1. Overview

| Item | Description |
|------|-------------|
| Feature | 코드베이스 전반 개선 및 리팩토링 |
| Priority | High |
| Complexity | Medium |
| Estimated Scope | 6개 Python 파일 + pyproject.toml + config.json |

## 2. Current State Analysis

### 2.1 Architecture Summary

```
src/
  cli.py              (226L) - Typer CLI 엔트리포인트
  config.py           (275L) - Dataclass 기반 설정 관리 (NEW, untracked)
  gui_pyqt.py         (545L) - PyQt6 GUI
  macro_pyqt.py       (132L) - QThread 매크로 워커
  utils.py            (182L) - 유틸리티 (screencapture 래퍼)
  find_duplicate_images.py (198L) - 중복 이미지 탐지
  __init__.py          (0L) - 빈 파일
```

Total: ~1,558 LOC

### 2.2 Recent Refactoring (Uncommitted)

- `setup.py` 삭제 -> `pyproject.toml` 전환
- `src/constants.py` 삭제 -> `src/config.py` (dataclass 기반) 신규 생성
- tkinter -> PyQt6 전환 완료
- CLI: argparse -> typer 전환 완료

## 3. Identified Issues

### 3.1 Critical (기능 영향)

| # | Issue | Location | Impact |
|---|-------|----------|--------|
| C-1 | config path가 상대경로(`Path("config.json")`)로 CWD에 의존 | `config.py:199` | 다른 디렉토리에서 실행 시 config 로드 실패 |
| C-2 | `src/config.py`가 git untracked 상태 | git status | 커밋하지 않으면 다른 환경에서 import 실패 |
| C-3 | `src/constants.py` 삭제, `setup.py` 삭제가 미커밋 | git status | 기존 코드와 충돌 가능 |

### 3.2 Medium (일관성/유지보수)

| # | Issue | Location | Impact |
|---|-------|----------|--------|
| M-1 | `find_duplicate_images.py`가 `logging` 모듈 사용, 나머지는 `loguru` | `find_duplicate_images.py` | 로그 출력 형식 불일치 |
| M-2 | `find_duplicate_images.py`가 구식 type hints (`Dict`, `List`, `Optional`, `Set`) 사용 | `find_duplicate_images.py` | 코드 스타일 불일치 (나머지는 Python 3.11+ 스타일) |
| M-3 | config.json `top_left: [0, 45]` vs config.py default `(0, 43)` | `config.json`, `config.py:17` | default 값 불일치 |
| M-4 | `pre-commit`이 main dependencies에 포함 | `pyproject.toml:11` | dev dependency여야 함 |
| M-5 | `pyproject.toml` black/isort 설정의 target-version이 `py313`이지만 requires-python은 `>=3.11` | `pyproject.toml:22,40` | 린터 설정 불일치 |
| M-6 | ESC 처리가 QShortcut과 keyPressEvent에서 중복 | `gui_pyqt.py:86,514` | 불필요한 중복 로직 |

### 3.3 Low (개선 기회)

| # | Issue | Location | Impact |
|---|-------|----------|--------|
| L-1 | `find_duplicate_images.py`에 별도 `main()` + `argparse` 존재 (CLI에서도 호출 가능) | `find_duplicate_images.py:173` | 불필요한 중복 CLI 엔트리포인트 |
| L-2 | GUI에 progress bar 미구현 (텍스트로만 진행률 표시) | `gui_pyqt.py:476` | UX 개선 여지 |
| L-3 | initial_wait 동안 GUI에 상태 표시 없음 | `macro_pyqt.py:61` | 사용자가 대기 시간 인지 불가 |
| L-4 | `__init__.py`가 빈 파일 | `src/__init__.py` | namespace package로 충분 |

## 4. Improvement Plan

### Phase 1: Critical Fixes (기능 정상 동작 보장)

#### 1-1. Config path를 프로젝트 루트 기준으로 해석

```python
# Before
_config_path: Path = Path("config.json")

# After
_config_path: Path = Path(__file__).parent.parent / "config.json"
```

#### 1-2. config.json과 config.py default 값 통일

- `config.py` AreaConfig default를 `(0, 45)`로 변경 (config.json 기준)

#### 1-3. 전체 변경사항 git commit

- `src/config.py` 추가
- `src/constants.py`, `setup.py` 삭제 반영

### Phase 2: Consistency Refactoring (일관성 확보)

#### 2-1. `find_duplicate_images.py` 현대화

- `logging` -> `loguru` 전환
- `Dict`, `List`, `Optional`, `Set` -> `dict`, `list`, `set`, `| None` 전환
- 독립 `main()` / `argparse` 제거 (CLI에서만 호출)
- Korean 코멘트 유지 (기존 스타일 존중)

#### 2-2. `pyproject.toml` 정리

- `pre-commit`을 dev dependency group으로 이동
- black/isort target-version을 `py311`로 통일

#### 2-3. GUI ESC 중복 처리 제거

- `QShortcut` 제거, `keyPressEvent`에서 통합 처리

### Phase 3: UX Improvements (사용성 개선)

#### 3-1. GUI Progress Bar 추가

- `QProgressBar` 위젯 추가
- MacroWorker의 progress signal 연결

#### 3-2. Initial Wait 카운트다운 표시

- MacroWorker에서 initial_wait signal 추가
- GUI에서 "Starting in N seconds..." 표시

#### 3-3. Status Bar 추가

- `QStatusBar`에 현재 상태 표시 (대기/실행중/완료/에러)

## 5. Implementation Priority

```
Phase 1 (Critical)     ████████████████████  Must Do
Phase 2 (Consistency)  ████████████████████  Should Do
Phase 3 (UX)           ████████████████░░░░  Nice to Have
```

## 6. Risk Assessment

| Risk | Mitigation |
|------|------------|
| PyQt6 GUI 변경 시 기존 동작 깨짐 | Phase별 테스트 실행 (수동) |
| loguru 전환 시 find_duplicate_images 독립 실행 불가 | loguru를 dependency에 이미 포함, 문제 없음 |
| config path 변경 시 다른 환경 호환성 | `__file__` 기반이므로 어디서든 동작 |

## 7. Out of Scope

- 테스트 코드 작성 (pytest 설정은 있으나 테스트 미구현)
- CI/CD 파이프라인
- 새로운 기능 추가
- GUI 디자인 리디자인
