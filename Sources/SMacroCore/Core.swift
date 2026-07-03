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
    try sendKey(code: code, toPid: pid)
}

/// 키코드 직접 전송 (GUI 키 캡처로 임의 키 지원)
public func sendKey(code: CGKeyCode, toPid pid: pid_t) throws {
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
/// 백그라운드 창의 컨트롤은 합성 첫 클릭을 무시하는 경우가 많아(acceptsFirstMouse)
/// 1) 해당 좌표의 AX 요소에 AXPress (포커스 불필요, 버튼류에 확실)
/// 2) 실패 시 CGEvent postToPid (mouseMoved로 hover 갱신 후 down/up)
/// 순서로 시도한다. 반환값은 실제 사용된 방식 ("AXPress" | "CGEvent").
@discardableResult
public func sendClick(at windowPoint: CGPoint, window: SCWindow, toPid pid: pid_t) throws -> String {
    let global = CGPoint(
        x: window.frame.origin.x + windowPoint.x,
        y: window.frame.origin.y + windowPoint.y)

    if axPress(at: global, pid: pid) { return "AXPress" }

    let source = CGEventSource(stateID: .hidSystemState)
    guard
        let moved = CGEvent(
            mouseEventSource: source, mouseType: .mouseMoved,
            mouseCursorPosition: global, mouseButton: .left),
        let down = CGEvent(
            mouseEventSource: source, mouseType: .leftMouseDown,
            mouseCursorPosition: global, mouseButton: .left),
        let up = CGEvent(
            mouseEventSource: source, mouseType: .leftMouseUp,
            mouseCursorPosition: global, mouseButton: .left)
    else { throw die("CGEvent 생성 실패") }
    down.setIntegerValueField(.mouseEventClickState, value: 1)
    up.setIntegerValueField(.mouseEventClickState, value: 1)
    moved.postToPid(pid)
    usleep(20_000)
    down.postToPid(pid)
    usleep(20_000)
    up.postToPid(pid)
    usleep(50_000)  // 키와 동일: 종료 직전 이벤트 flush 유실 방지
    return "CGEvent"
}

/// 화면 좌표에 있는 대상 앱의 AX 요소를 찾아 AXPress. 성공 여부 반환.
private func axPress(at global: CGPoint, pid: pid_t) -> Bool {
    let appEl = AXUIElementCreateApplication(pid)
    // Electron/Chromium은 보조기술이 요청하기 전까지 AX 트리를 비워둠 -> 수동 활성화.
    // (Discord 등에서 요소가 안 잡히는 원인. 활성화 직후 트리 구축에 잠깐 걸림)
    AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    AXUIElementSetAttributeValue(appEl, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    usleep(80_000)

    var el: AXUIElement?
    guard
        AXUIElementCopyElementAtPosition(appEl, Float(global.x), Float(global.y), &el)
            == .success, let found = el
    else { return false }

    // 좌표의 요소가 press 미지원이면 부모로 올라가며 탐색 (버튼 안의 텍스트/아이콘 케이스)
    var cur = found
    for _ in 0..<6 {
        var actions: CFArray?
        if AXUIElementCopyActionNames(cur, &actions) == .success,
            let list = actions as? [String], list.contains(kAXPressAction),
            AXUIElementPerformAction(cur, kAXPressAction as CFString) == .success {
            return true
        }
        var parentRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(cur, kAXParentAttribute as CFString, &parentRef)
                == .success,
            let parent = parentRef, CFGetTypeID(parent) == AXUIElementGetTypeID()
        else { break }
        cur = unsafeDowncast(parent as AnyObject, to: AXUIElement.self)
    }
    return false
}

// MARK: - 전면 모드 (전역 HID 이벤트 — 하드웨어 입력과 같은 경로, 포커스된 앱이 받음)

/// 합성 이벤트를 무시하는 앱(Electron 등)용. 대상 앱을 전면에 두고 사용해야 한다.
public func sendKeyGlobal(_ name: String) throws {
    guard let code = keyCodes[name] else {
        throw die("모르는 키 '\(name)' (지원: \(keyCodes.keys.sorted().joined(separator: ", ")))")
    }
    try sendKeyGlobal(code: code)
}

public func sendKeyGlobal(code: CGKeyCode) throws {
    let source = CGEventSource(stateID: .hidSystemState)
    guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
    else { throw die("CGEvent 생성 실패") }
    down.post(tap: .cghidEventTap)
    usleep(20_000)
    up.post(tap: .cghidEventTap)
    usleep(30_000)
}

/// 전역 클릭 — 실제 커서가 이동하며, 그 좌표의 전면 창이 클릭된다.
public func sendClickGlobal(at windowPoint: CGPoint, window: SCWindow) throws {
    let global = CGPoint(
        x: window.frame.origin.x + windowPoint.x,
        y: window.frame.origin.y + windowPoint.y)
    let source = CGEventSource(stateID: .hidSystemState)
    guard
        let moved = CGEvent(
            mouseEventSource: source, mouseType: .mouseMoved,
            mouseCursorPosition: global, mouseButton: .left),
        let down = CGEvent(
            mouseEventSource: source, mouseType: .leftMouseDown,
            mouseCursorPosition: global, mouseButton: .left),
        let up = CGEvent(
            mouseEventSource: source, mouseType: .leftMouseUp,
            mouseCursorPosition: global, mouseButton: .left)
    else { throw die("CGEvent 생성 실패") }
    down.setIntegerValueField(.mouseEventClickState, value: 1)
    up.setIntegerValueField(.mouseEventClickState, value: 1)
    moved.post(tap: .cghidEventTap)
    usleep(30_000)
    down.post(tap: .cghidEventTap)
    usleep(30_000)
    up.post(tap: .cghidEventTap)
    usleep(30_000)
}

/// 대상 앱이 전면이 아니면 전면으로 올리고 잠깐 대기 (전면 모드용)
public func ensureFrontmost(pid: pid_t) {
    guard let app = NSRunningApplication(processIdentifier: pid), !app.isActive else { return }
    app.activate()
    usleep(300_000)
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

// MARK: - 중복 이미지 탐지 (Python imagehash.average_hash 8x8과 동일 알고리즘)

/// 8x8 그레이스케일 평균 해시. 해밍 거리 0 = 사실상 동일 이미지.
public func averageHash(_ image: CGImage) -> UInt64? {
    let side = 8
    guard
        let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
    else { return nil }
    ctx.interpolationQuality = .medium
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    guard let data = ctx.data else { return nil }
    let px = data.bindMemory(to: UInt8.self, capacity: side * side)
    var sum = 0
    for i in 0..<64 { sum += Int(px[i]) }
    let avg = sum / 64
    var hash: UInt64 = 0
    for i in 0..<64 where Int(px[i]) > avg { hash |= (1 << UInt64(i)) }
    return hash
}

public func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int { (a ^ b).nonzeroBitCount }

public func loadImage(at url: URL) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
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
