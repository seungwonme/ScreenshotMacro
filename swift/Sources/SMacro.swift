// smacro-proto: ScreenshotMacro Swift 프로토타입.
// 검증 대상 2가지 — (1) 포커스를 뺏지 않는 특정 윈도우 캡처(ScreenCaptureKit),
// (2) 특정 앱에만 키 이벤트 전송(CGEventPostToPid). GUI는 검증 후 별도.
//
// 필요 권한:
//   - 화면 기록(Screen Recording): list / capture / macro
//   - 손쉬운 사용(Accessibility): send-key / macro

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

// spartan: 프로토타입에 필요한 키만. 확장 시 keyname -> keycode 테이블 보강.
let keyCodes: [String: CGKeyCode] = [
    "right": 124, "left": 123, "down": 125, "up": 126,
    "space": 49, "return": 36, "pagedown": 121, "pageup": 116,
]

struct CLIError: Error, CustomStringConvertible {
    let description: String
}

func die(_ message: String) -> CLIError { CLIError(description: message) }

// MARK: - Window lookup / capture

func frontWindow(ofPid pid: pid_t) async throws -> SCWindow {
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

func capture(window: SCWindow, to url: URL, area: CGRect? = nil) async throws {
    let filter = SCContentFilter(desktopIndependentWindow: window)
    let config = SCStreamConfiguration()
    let scale = CGFloat(filter.pointPixelScale)
    config.width = Int(window.frame.width * scale)
    config.height = Int(window.frame.height * scale)
    config.showsCursor = false
    var image = try await SCScreenshotManager.captureImage(
        contentFilter: filter, configuration: config)
    if let area {
        // 창 좌상단 기준 포인트 좌표 -> 픽셀로 환산해 크롭 (창을 옮겨도 유지됨)
        let pixelRect = CGRect(
            x: area.origin.x * scale, y: area.origin.y * scale,
            width: area.width * scale, height: area.height * scale)
        guard let cropped = image.cropping(to: pixelRect) else {
            throw die("--area가 창 범위를 벗어납니다 (창 크기: \(Int(window.frame.width))x\(Int(window.frame.height))pt)")
        }
        image = cropped
    }
    guard
        let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw die("PNG 생성 실패: \(url.path)") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw die("PNG 저장 실패: \(url.path)") }
}

// MARK: - Key injection

func sendKey(_ name: String, toPid pid: pid_t) throws {
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

// MARK: - Permissions

func checkScreenRecording() throws {
    if !CGPreflightScreenCaptureAccess() {
        CGRequestScreenCaptureAccess()
        throw die("화면 기록 권한이 없습니다. 시스템 설정 > 개인정보 보호 및 보안 > 화면 기록에서 이 터미널을 허용하세요.")
    }
}

func checkAccessibility() throws {
    if !AXIsProcessTrusted() {
        throw die("손쉬운 사용 권한이 없습니다. 시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서 이 터미널을 허용하세요.")
    }
}

// MARK: - Arg parsing

func flagValue(_ args: [String], _ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func resolveTarget(_ args: [String]) throws -> pid_t {
    if let raw = flagValue(args, "--pid") {
        guard let pid = pid_t(raw) else { throw die("--pid 값이 숫자가 아닙니다: \(raw)") }
        return pid
    }
    if let name = flagValue(args, "--app") {
        func rank(_ a: NSRunningApplication) -> Int {
            // 정확 일치 > 도크에 뜨는 일반 앱 > 나머지 (헬퍼 프로세스 오선택 방지)
            let exact = (a.localizedName ?? "").caseInsensitiveCompare(name) == .orderedSame
            return (exact ? 0 : 2) + (a.activationPolicy == .regular ? 0 : 1)
        }
        let apps = NSWorkspace.shared.runningApplications
            .filter { ($0.localizedName ?? "").localizedCaseInsensitiveContains(name) }
            .sorted { rank($0) < rank($1) }
        guard let app = apps.first else {
            throw die("실행 중인 앱에서 '\(name)'을 찾을 수 없습니다 (list로 확인)")
        }
        if apps.count > 1 {
            print("주의: '\(name)' 일치 앱 \(apps.count)개 중 '\(app.localizedName ?? "?")' 선택")
        }
        return app.processIdentifier
    }
    throw die("--app <이름> 또는 --pid <숫자>가 필요합니다 (list 명령으로 확인)")
}

func parseArea(_ args: [String]) throws -> CGRect? {
    guard let raw = flagValue(args, "--area") else { return nil }
    let parts = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard parts.count == 4, parts[2] > 0, parts[3] > 0 else {
        throw die("--area 형식: x,y,w,h (창 좌상단 기준 포인트, 예: 100,110,350,180)")
    }
    return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
}

// Python 버전의 screenshots/01, 02, ... 세션 디렉토리 규칙과 동일
func nextSessionDir(base: String) throws -> URL {
    let fm = FileManager.default
    try fm.createDirectory(atPath: base, withIntermediateDirectories: true)
    let existing = (try? fm.contentsOfDirectory(atPath: base)) ?? []
    let next = (existing.compactMap { Int($0) }.max() ?? 0) + 1
    let dir = URL(fileURLWithPath: base).appendingPathComponent(String(format: "%02d", next))
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

let usage = """
    smacro-proto — ScreenshotMacro Swift 프로토타입

    대상 지정: --app <앱 이름 일부> 또는 --pid <숫자> (list로 확인)

    사용법:
      smacro-proto list                                   캡처 가능한 윈도우 목록 (pid, 앱, 제목)
      smacro-proto capture --app <이름> [--out <path>] [--area x,y,w,h]
                                                          해당 앱의 최대 윈도우를 PNG로 캡처
                                                          --area: 창 좌상단 기준 포인트 영역만 크롭
      smacro-proto send-key --app <이름> --key <name>     해당 앱에만 키 이벤트 전송 (포커스 불필요)
      smacro-proto macro --app <이름> [--reps N] [--key right] [--area x,y,w,h]
                         [--wait S] [--delay-min S] [--delay-max S] [--out <dir>]
                                                          캡처+키 전송 반복 (백그라운드 동작)
                                                          --out 생략 시 captures/01, 02, ... 자동 생성
    """

// MARK: - Main

@main
struct SMacro {
    static func main() async {
        do {
            try await run()
        } catch {
            FileHandle.standardError.write(Data("오류: \(error)\n".utf8))
            exit(1)
        }
    }

    static func run() async throws {
        // CLI(비 앱 번들)에서는 window server 연결이 자동 초기화되지 않아
        // SCContentFilter 생성 시 CGS_REQUIRE_INIT assert로 크래시한다. CG API 선호출로 초기화.
        _ = CGMainDisplayID()
        let args = Array(CommandLine.arguments.dropFirst())
        switch args.first {
        case "list":
            try checkScreenRecording()
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            for window in content.windows
            where window.frame.width > 50 && window.frame.height > 50 {
                let app = window.owningApplication
                print(
                    "pid=\(app?.processID ?? 0)\t\(app?.applicationName ?? "?")\t\(window.title ?? "")"
                )
            }

        case "capture":
            let pid = try resolveTarget(args)
            let area = try parseArea(args)
            try checkScreenRecording()
            let out = flagValue(args, "--out") ?? "capture_\(pid).png"
            let window = try await frontWindow(ofPid: pid)
            try await capture(window: window, to: URL(fileURLWithPath: out), area: area)
            print("저장: \(out) (\(window.owningApplication?.applicationName ?? "?") — \(window.title ?? ""))")

        case "send-key":
            let pid = try resolveTarget(args)
            try checkAccessibility()
            let key = flagValue(args, "--key") ?? "right"
            try sendKey(key, toPid: pid)
            print("키 '\(key)' 전송 완료 -> pid \(pid)")

        case "macro":
            let pid = try resolveTarget(args)
            let area = try parseArea(args)
            try checkScreenRecording()
            try checkAccessibility()
            let reps = Int(flagValue(args, "--reps") ?? "10") ?? 10
            let key = flagValue(args, "--key") ?? "right"
            let wait = Double(flagValue(args, "--wait") ?? "3") ?? 3
            let delayMin = Double(flagValue(args, "--delay-min") ?? "1") ?? 1
            let delayMax = Double(flagValue(args, "--delay-max") ?? "1") ?? 1
            let sessionDir: URL
            if let out = flagValue(args, "--out") {
                sessionDir = URL(fileURLWithPath: out)
                try FileManager.default.createDirectory(
                    at: sessionDir, withIntermediateDirectories: true)
            } else {
                sessionDir = try nextSessionDir(base: "captures")
            }

            print("\(wait)초 후 시작 (pid \(pid), \(reps)회, 키 '\(key)') -> \(sessionDir.path)/")
            try await Task.sleep(for: .seconds(wait))
            for i in 1...reps {
                let window = try await frontWindow(ofPid: pid)  // 매 회 조회: 창 이동/리사이즈 대응
                let out = sessionDir.appendingPathComponent(
                    String(format: "screenshot_%03d.png", i))
                try await capture(window: window, to: out, area: area)
                try sendKey(key, toPid: pid)
                print("[\(i)/\(reps)] \(out.lastPathComponent)")
                if i < reps {
                    try await Task.sleep(for: .seconds(Double.random(in: delayMin...max(delayMin, delayMax))))
                }
            }
            print("완료: \(sessionDir.path)/")

        default:
            print(usage)
        }
    }
}
