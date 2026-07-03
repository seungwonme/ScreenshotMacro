# smacro-proto — Swift 프로토타입

Python 버전이 구조적으로 못 하는 것을 검증하는 CLI 프로토타입입니다:

1. **포커스를 뺏지 않는 윈도우 캡처** — ScreenCaptureKit으로 특정 앱의 윈도우만 캡처 (다른 창에 가려져 있어도 캡처됨)
2. **특정 앱에만 키 전송** — `CGEventPostToPid`로 대상 앱에 직접 키 이벤트 전달 (포커스 불필요)

둘이 합쳐지면: **매크로가 도는 동안 맥으로 다른 작업을 할 수 있습니다.**

## 필요 권한 (시스템 설정 > 개인정보 보호 및 보안)

- **화면 기록**: `list` / `capture` / `macro` — 실행하는 터미널 앱에 부여
- **손쉬운 사용**: `send-key` / `macro` — 실행하는 터미널 앱에 부여

## 사용법

```bash
cd swift
swift build

# 1. 캡처 가능한 윈도우 목록에서 대상 pid 확인
swift run smacro-proto list

# 2. 단건 캡처 검증 (대상 앱을 다른 창으로 가려도 캡처되는지 확인)
swift run smacro-proto capture --pid <pid> --out /tmp/test.png

# 3. 키 전송 검증 (대상 앱이 포커스 없어도 반응하는지 확인)
swift run smacro-proto send-key --pid <pid> --key right

# 4. 전체 매크로 (캡처 + 키 전송 반복, 백그라운드 동작)
swift run smacro-proto macro --pid <pid> --reps 20 --key right \
  --wait 3 --delay-min 0.5 --delay-max 2 --out captures
```

지원 키: `right` `left` `up` `down` `space` `return` `pageup` `pagedown`

## 한계 (프로토타입)

- 최소화된 윈도우는 캡처 불가 (ScreenCaptureKit 제약 — 가려진 창은 가능)
- 앱별 최대 크기 윈도우 하나만 대상
- 검증 완료 후 GUI(SwiftUI)와 세션 디렉토리·중복 탐지(Vision FeaturePrint)를 이식할 예정
