# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

## Claude Code 전용 참고

- 이 세션(백그라운드 에이전트)에는 화면 기록/손쉬운 사용 TCC 권한이 없다. 캡처·입력 전송의 실기기 검증은 `scripts/validate-swift-proto.sh`를 사용자 터미널에서 실행하게 안내한다 (TextEdit로 캡처·키 전송을 자동 판정).
- 빌드 검증은 권한 없이 가능: `swift build` + `swift test` + CLI 인자 오류 경로 실행. E2E는 pre-push 훅이 권한 있는 터미널에서 자동 실행하므로 사용자에게 따로 시키지 않는다.
- GUI 상태 저장은 UserDefaults라 `defaults read` 도메인은 실행 방식(swift run)에 따라 다름 - 코드의 `@AppStorage` 키를 기준으로 볼 것.
