// SMacroCore: CLI(smacro-proto)와 GUI(smacro-gui)가 공유하는 캡처·키 전송 로직.
//
// 필요 권한:
//   - 화면 기록(Screen Recording): 윈도우 목록·캡처
//   - 손쉬운 사용(Accessibility): 키 전송

import AppKit
import CoreGraphics
import CryptoKit
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

/// 이보다 작은 창은 캡처 대상에서 제외 (툴팁·팝업류)
public let minCaptureSize: CGFloat = 50

/// 캡처 대상 창 목록 - '어떤 창이 대상인가' 정책의 단일 지점 (CLI list / GUI 그리드 / frontWindow 공용).
/// dockAppsOnly: 도크에 뜨는 일반 앱 창만 (windowLayer 0, activationPolicy .regular).
public func captureTargets(dockAppsOnly: Bool = false, excludePid: pid_t? = nil) async throws
    -> [SCWindow]
{
    let content = try await SCShareableContent.excludingDesktopWindows(
        false, onScreenWindowsOnly: true)
    // 창마다 NSRunningApplication을 새로 만들지 않게 도크 앱 pid를 한 번만 수집
    let regularPids: Set<pid_t> =
        dockAppsOnly
        ? Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .map(\.processIdentifier))
        : []
    return content.windows.filter { w in
        guard let app = w.owningApplication,
            w.frame.width > minCaptureSize, w.frame.height > minCaptureSize,
            app.processID != (excludePid ?? -1)
        else { return false }
        if dockAppsOnly {
            guard w.windowLayer == 0, !app.applicationName.isEmpty,
                regularPids.contains(app.processID)
            else { return false }
        }
        return true
    }
}

public func frontWindow(ofPid pid: pid_t) async throws -> SCWindow {
    let windows = try await captureTargets().filter {
        $0.owningApplication?.processID == pid
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
        throw die("지정한 캡처 영역이 창 범위를 벗어납니다 (창 크기: \(Int(window.frame.width))x\(Int(window.frame.height))pt)")
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

    let ev = try makeClickEvents(at: global)
    ev.moved.postToPid(pid)
    usleep(20_000)
    ev.down.postToPid(pid)
    usleep(20_000)
    ev.up.postToPid(pid)
    usleep(50_000)  // 키와 동일: 종료 직전 이벤트 flush 유실 방지
    return "CGEvent"
}

/// moved/down/up 좌클릭 이벤트 3종 생성 (백그라운드 postToPid / 전면 post 공용)
private func makeClickEvents(at global: CGPoint) throws -> (moved: CGEvent, down: CGEvent, up: CGEvent) {
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
    return (moved, down, up)
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
    let ev = try makeClickEvents(at: global)
    ev.moved.post(tap: .cghidEventTap)
    usleep(30_000)
    ev.down.post(tap: .cghidEventTap)
    usleep(30_000)
    ev.up.post(tap: .cghidEventTap)
    usleep(30_000)
}

/// 대상 앱이 전면이 아니면 전면으로 올리고 잠깐 대기 (전면 모드용)
public func ensureFrontmost(pid: pid_t) {
    guard let app = NSRunningApplication(processIdentifier: pid), !app.isActive else { return }
    app.activate()
    usleep(300_000)
}

// MARK: - Permissions

/// 화면 기록 권한 보유 여부. requestIfNeeded: 미보유 시 macOS 시스템 프롬프트 요청(최초 1회만 뜸).
public func screenRecordingGranted(requestIfNeeded: Bool = false) -> Bool {
    if CGPreflightScreenCaptureAccess() { return true }
    if requestIfNeeded { CGRequestScreenCaptureAccess() }
    return false
}

public func checkScreenRecording() throws {
    if !screenRecordingGranted(requestIfNeeded: true) {
        throw die("화면 기록 권한이 없습니다. 시스템 설정 > 개인정보 보호 및 보안 > 화면 기록에서 이 앱을 허용하세요.")
    }
}

/// promptUser: 권한이 없으면 macOS 시스템 프롬프트를 띄우고 설정 목록에 앱을 등록 (GUI용)
public func checkAccessibility(promptUser: Bool = false) throws {
    let trusted =
        promptUser
        ? AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        : AXIsProcessTrusted()
    if !trusted {
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

// MARK: - 중복 캡처 탐지 (파일 바이트 SHA256 - 완전 동일 캡처만)

/// 파일 내용 전체의 SHA256. 값이 같으면 바이트까지 동일한 파일이다.
/// aHash(8x8 지문)는 여백/레이아웃이 균일한 문서·전자책 캡처에서 서로 다른 페이지도
/// 같은 해시로 뭉쳐 오탐이 심해, 스크롤이 안 넘어가 같은 화면을 두 번 찍은 진짜 중복만
/// 잡도록 바이트 해시로 대체했다.
public func fileHash(at url: URL) -> String? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

/// dir(하위 폴더 포함) 안의 모든 PNG를 경로순으로 수집.
public func collectPNGs(in dir: String) throws -> [URL] {
    let base = URL(fileURLWithPath: dir)
    guard FileManager.default.fileExists(atPath: base.path) else {
        throw die("디렉토리가 없습니다: \(dir)")
    }
    let files = FileManager.default.enumerator(
        at: base, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])?
        .compactMap { $0 as? URL }
        .filter { $0.pathExtension.lowercased() == "png" } ?? []
    return files.sorted { $0.path < $1.path }
}

/// PNG 목록을 파일 바이트 SHA256로 그룹핑. 2장 이상 동일한 그룹만 반환하며,
/// 각 그룹은 경로순, 그룹들도 첫 원소 경로순으로 정렬한다. CLI/GUI 공용.
public func duplicateGroups(in files: [URL]) -> [[URL]] {
    var byHash: [String: [URL]] = [:]
    for f in files {
        guard let h = fileHash(at: f) else { continue }
        byHash[h, default: []].append(f)
    }
    return byHash.values
        .filter { $0.count > 1 }
        .map { $0.sorted { $0.path < $1.path } }
        .sorted { $0[0].path < $1[0].path }
}

// MARK: - 안티 패턴 매칭 (로딩 화면 등 '이렇게 생긴 캡처는 불필요' 기준 이미지)

/// 안티 패턴 기준 이미지 보관 폴더. 캡처 베이스와 분리해 clean/stats/find-duplicates
/// 집계에 섞이지 않는다. 없으면 생성.
public func antiPatternsDir() throws -> URL {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ScreenshotMacro/antipatterns")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// 등록된 안티 패턴 기준 이미지 목록 (경로순)
public func antiPatterns() throws -> [URL] {
    try collectPNGs(in: antiPatternsDir().path)
}

/// 비교용 그레이스케일 64x80 지문. 종횡비는 무시하고 고정 크기로 리샘플 (양쪽 동일 조건 비교).
public func grayFingerprint(at url: URL, width: Int = 64, height: Int = 80) -> [UInt8]? {
    guard let image = fileThumbnail(at: url, maxPixel: 256),
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue)
    else { return nil }
    ctx.interpolationQuality = .medium
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let data = ctx.data else { return nil }
    let count = width * height
    return Array(UnsafeBufferPointer(start: data.bindMemory(to: UInt8.self, capacity: count), count: count))
}

/// 두 지문의 8x8 블록별 RMS 픽셀 차 중 최댓값 (0=동일, 255=최대). 길이 불일치는 매칭 불가로 무한대.
/// 전역 평균 RMS는 저대비 패턴(흰 배경 + 연회색 아이콘)에서 여백 많은 실제 페이지와
/// 구분이 안 된다 — 텍스트처럼 국소에 몰린 차이를 블록 최댓값으로 증폭해야 갈린다.
func maxBlockRMS(_ a: [UInt8], _ b: [UInt8], width: Int = 64, height: Int = 80, block: Int = 8) -> Double {
    guard a.count == b.count, a.count == width * height else { return .infinity }
    var worst = 0.0
    for by in stride(from: 0, to: height, by: block) {
        for bx in stride(from: 0, to: width, by: block) {
            var sum = 0.0
            for y in by..<min(by + block, height) {
                for x in bx..<min(bx + block, width) {
                    let d = Double(a[y * width + x]) - Double(b[y * width + x])
                    sum += d * d
                }
            }
            worst = max(worst, (sum / Double(block * block)).squareRoot())
        }
    }
    return worst
}

/// 안티 패턴 판정 임계값. 실측(전자책 캡처 4개 세션 ~700장, 로딩 화면 2종):
/// 같은 로딩 화면의 재등장은 0, 가장 비슷한 실제 페이지(간지·속표지)는 8.6·38.2 — 4는 2배+ 마진.
public let antiPatternRMSThreshold: Double = 4

/// files 중 안티 패턴 기준 이미지와 거의 같은 프레임 목록 (입력 순서 유지).
/// 중복 dedup(완전 동일 해시)과 달리 전부 삭제 대상 — 남길 한 장이 없다.
public func antiPatternMatches(
    in files: [URL], patterns: [URL], threshold: Double = antiPatternRMSThreshold
) -> [URL] {
    let prints = patterns.compactMap { grayFingerprint(at: $0) }
    guard !prints.isEmpty else { return [] }
    return files.filter { f in
        guard let fp = grayFingerprint(at: f) else { return false }
        return prints.contains { maxBlockRMS($0, fp) < threshold }
    }
}

/// 파일에서 최대 변 길이 maxPixel의 축소 썸네일 생성 (원본 풀해상도 디코드를 피해 메모리 절약).
public func fileThumbnail(at url: URL, maxPixel: Int = 400) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        kCGImageSourceCreateThumbnailWithTransform: true,
    ]
    return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
}

/// 이미지에서 불투명 콘텐츠가 차지하는 영역 (픽셀 좌표, 좌상단 원점).
/// 일부 앱(Chrome 등)은 창 frame보다 좁게 렌더링해 SCK 캡처 오른쪽/아래가 투명 패딩으로
/// 남는다 - '보이는 콘텐츠' 기준 정렬용. 다운샘플 스캔이라 오차는 ±(원본폭/256)px.
public func opaqueContentRect(of image: CGImage) -> CGRect {
    let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    let sw = min(256, image.width)
    let sh = max(1, image.height * sw / max(1, image.width))
    guard
        let ctx = CGContext(
            data: nil, width: sw, height: sh, bitsPerComponent: 8, bytesPerRow: sw * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return full }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: sw, height: sh))
    guard let data = ctx.data else { return full }
    let px = data.bindMemory(to: UInt8.self, capacity: sw * sh * 4)
    var minX = sw, maxX = -1, minY = sh, maxY = -1
    for y in 0..<sh {
        for x in 0..<sw where px[(y * sw + x) * 4 + 3] > 10 {
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
        }
    }
    guard maxX >= 0 else { return full }  // 전부 투명이면 전체 반환 (0-크기 방지)
    let s = CGFloat(image.width) / CGFloat(sw)
    return CGRect(
        x: CGFloat(minX) * s, y: CGFloat(minY) * s,
        width: CGFloat(maxX - minX + 1) * s, height: CGFloat(maxY - minY + 1) * s)
}

// MARK: - "x,y[,w,h]" 문자열 직렬화 (GUI @AppStorage 저장용 - 파싱/기록 지점 공용)

extension CGRect {
    public init?(storageString s: String) {
        let p = s.split(separator: ",").compactMap { Double($0) }
        guard p.count == 4, p[2] > 0, p[3] > 0 else { return nil }
        self.init(x: p[0], y: p[1], width: p[2], height: p[3])
    }
    public var storageString: String {
        String(format: "%.0f,%.0f,%.0f,%.0f", minX, minY, width, height)
    }
}

extension CGPoint {
    public init?(storageString s: String) {
        let p = s.split(separator: ",").compactMap { Double($0) }
        guard p.count == 2 else { return nil }
        self.init(x: p[0], y: p[1])
    }
    public var storageString: String { String(format: "%.0f,%.0f", x, y) }
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
