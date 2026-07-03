// SMacroCore: CLI(smacro-proto)와 GUI(smacro-gui)가 공유하는 캡처·키 전송 로직.
//
// 필요 권한:
//   - 화면 기록(Screen Recording): 윈도우 목록·캡처
//   - 손쉬운 사용(Accessibility): 키 전송

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

// spartan: 필요한 키만. 확장 시 keyname -> keycode 테이블 보강.
public let keyCodes: [String: CGKeyCode] = [
    "right": 124, "left": 123, "down": 125, "up": 126,
    "space": 49, "return": 36, "pagedown": 121, "pageup": 116,
]

public struct CoreError: Error, CustomStringConvertible {
    public let description: String
}

public func die(_ message: String) -> CoreError { CoreError(description: message) }

/// CLI(비 앱 번들)에서는 window server 연결이 자동 초기화되지 않아
/// SCContentFilter 생성 시 CGS_REQUIRE_INIT assert로 크래시한다. CG API 선호출로 초기화.
public func initWindowServerConnection() {
    _ = CGMainDisplayID()
}

// MARK: - Window lookup / capture

public func frontWindow(ofPid pid: pid_t) async throws -> SCWindow {
    let content = try await SCShareableContent.excludingDesktopWindows(
        false, onScreenWindowsOnly: true)
    let windows = content.windows.filter {
        $0.owningApplication?.processID == pid && $0.isOnScreen
            && $0.frame.width > 50 && $0.frame.height > 50
    }
    guard let window = windows.max(by: {
        $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
    }) else {
        throw die("pid \(pid)의 캡처 가능한 윈도우가 없습니다 (최소화 상태는 캡처 불가)")
    }
    return window
}

/// 윈도우를 캡처해 CGImage로 반환. area는 창 좌상단 기준 포인트 좌표 크롭.
public func captureImage(window: SCWindow, area: CGRect? = nil) async throws -> CGImage {
    let filter = SCContentFilter(desktopIndependentWindow: window)
    let config = SCStreamConfiguration()
    let scale = CGFloat(filter.pointPixelScale)
    config.width = Int(window.frame.width * scale)
    config.height = Int(window.frame.height * scale)
    config.showsCursor = false
    let image = try await SCScreenshotManager.captureImage(
        contentFilter: filter, configuration: config)
    guard let area else { return image }
    let pixelRect = CGRect(
        x: area.origin.x * scale, y: area.origin.y * scale,
        width: area.width * scale, height: area.height * scale)
    guard let cropped = image.cropping(to: pixelRect) else {
        throw die("--area가 창 범위를 벗어납니다 (창 크기: \(Int(window.frame.width))x\(Int(window.frame.height))pt)")
    }
    return cropped
}

/// 창 목록용 저해상도 썸네일 (가려진 창·다른 데스크톱의 창도 내용이 보임)
public func captureThumbnail(window: SCWindow, maxWidth: Int = 320) async throws -> CGImage {
    let filter = SCContentFilter(desktopIndependentWindow: window)
    let config = SCStreamConfiguration()
    let aspect = window.frame.height / max(window.frame.width, 1)
    config.width = maxWidth
    config.height = max(1, Int(CGFloat(maxWidth) * aspect))
    config.showsCursor = false
    return try await SCScreenshotManager.captureImage(
        contentFilter: filter, configuration: config)
}

public func savePNG(_ image: CGImage, to url: URL) throws {
    guard
        let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw die("PNG 생성 실패: \(url.path)") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw die("PNG 저장 실패: \(url.path)") }
}

// MARK: - Key injection

public func sendKey(_ name: String, toPid pid: pid_t) throws {
    guard let code = keyCodes[name] else {
        throw die("모르는 키 '\(name)' (지원: \(keyCodes.keys.sorted().joined(separator: ", ")))")
    }
    let source = CGEventSource(stateID: .hidSystemState)
    guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
    else { throw die("CGEvent 생성 실패") }
    down.postToPid(pid)
    usleep(20_000)  // down/up 무간격 연타 시 대상 앱에서 이벤트가 드롭될 수 있음
    up.postToPid(pid)
    usleep(50_000)  // 프로세스 즉시 종료 시 마지막 이벤트가 flush 전에 유실되는 것 방지
}

/// 창 좌상단 기준 포인트 좌표를 현재 창 위치의 화면 좌표로 환산해 좌클릭 전송.
/// postToPid라 대상 앱이 백그라운드여도 동작하고, 창이 이동해도 상대 좌표가 유지된다.
public func sendClick(at windowPoint: CGPoint, window: SCWindow, toPid pid: pid_t) throws {
    let global = CGPoint(
        x: window.frame.origin.x + windowPoint.x,
        y: window.frame.origin.y + windowPoint.y)
    let source = CGEventSource(stateID: .hidSystemState)
    guard
        let down = CGEvent(
            mouseEventSource: source, mouseType: .leftMouseDown,
            mouseCursorPosition: global, mouseButton: .left),
        let up = CGEvent(
            mouseEventSource: source, mouseType: .leftMouseUp,
            mouseCursorPosition: global, mouseButton: .left)
    else { throw die("CGEvent 생성 실패") }
    down.setIntegerValueField(.mouseEventClickState, value: 1)
    up.setIntegerValueField(.mouseEventClickState, value: 1)
    down.postToPid(pid)
    usleep(20_000)
    up.postToPid(pid)
    usleep(50_000)  // 키와 동일: 종료 직전 이벤트 flush 유실 방지
}

// MARK: - Permissions

public func checkScreenRecording() throws {
    if !CGPreflightScreenCaptureAccess() {
        CGRequestScreenCaptureAccess()
        throw die("화면 기록 권한이 없습니다. 시스템 설정 > 개인정보 보호 및 보안 > 화면 기록에서 이 앱을 허용하세요.")
    }
}

public func checkAccessibility() throws {
    if !AXIsProcessTrusted() {
        throw die("손쉬운 사용 권한이 없습니다. 시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서 이 앱을 허용하세요.")
    }
}

// MARK: - App / session helpers

/// 이름 부분 일치로 실행 중인 앱 pid를 찾는다. 정확 일치 > 도크 앱 > 나머지 순으로 선택.
public func resolveApp(named name: String) throws -> NSRunningApplication {
    func rank(_ a: NSRunningApplication) -> Int {
        let exact = (a.localizedName ?? "").caseInsensitiveCompare(name) == .orderedSame
        return (exact ? 0 : 2) + (a.activationPolicy == .regular ? 0 : 1)
    }
    let apps = NSWorkspace.shared.runningApplications
        .filter { ($0.localizedName ?? "").localizedCaseInsensitiveContains(name) }
        .sorted { rank($0) < rank($1) }
    guard let app = apps.first else {
        throw die("실행 중인 앱에서 '\(name)'을 찾을 수 없습니다")
    }
    return app
}

// Python 버전의 screenshots/01, 02, ... 세션 디렉토리 규칙과 동일
public func nextSessionDir(base: String) throws -> URL {
    let fm = FileManager.default
    try fm.createDirectory(atPath: base, withIntermediateDirectories: true)
    let existing = (try? fm.contentsOfDirectory(atPath: base)) ?? []
    let next = (existing.compactMap { Int($0) }.max() ?? 0) + 1
    let dir = URL(fileURLWithPath: base).appendingPathComponent(String(format: "%02d", next))
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
