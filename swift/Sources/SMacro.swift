// smacro-proto: ScreenshotMacro Swift 프로토타입.
// 검증 대상 2가지 — (1) 포커스를 뺏지 않는 특정 윈도우 캡처(ScreenCaptureKit),
// (2) 특정 앱에만 키 이벤트 전송(CGEventPostToPid). GUI는 검증 후 별도.
//
// 필요 권한:
//   - 화면 기록(Screen Recording): list / capture / macro
//   - 손쉬운 사용(Accessibility): send-key / macro

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

func capture(window: SCWindow, to url: URL) async throws {
    let filter = SCContentFilter(desktopIndependentWindow: window)
    let config = SCStreamConfiguration()
    let scale = CGFloat(filter.pointPixelScale)
    config.width = Int(window.frame.width * scale)
    config.height = Int(window.frame.height * scale)
    config.showsCursor = false
    let image = try await SCScreenshotManager.captureImage(
        contentFilter: filter, configuration: config)
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

func requirePid(_ args: [String]) throws -> pid_t {
    guard let raw = flagValue(args, "--pid"), let pid = pid_t(raw) else {
        throw die("--pid <숫자>가 필요합니다 (list 명령으로 확인)")
    }
    return pid
}

let usage = """
    smacro-proto — ScreenshotMacro Swift 프로토타입

    사용법:
      smacro-proto list                                   캡처 가능한 윈도우 목록 (pid, 앱, 제목)
      smacro-proto capture --pid <pid> [--out <path>]     해당 앱의 최대 윈도우를 PNG로 캡처
      smacro-proto send-key --pid <pid> --key <name>      해당 앱에만 키 이벤트 전송 (포커스 불필요)
      smacro-proto macro --pid <pid> [--reps N] [--key right]
                         [--wait S] [--delay-min S] [--delay-max S] [--out <dir>]
                                                          캡처+키 전송 반복 (백그라운드 동작)
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
            try checkScreenRecording()
            let pid = try requirePid(args)
            let out = flagValue(args, "--out") ?? "capture_\(pid).png"
            let window = try await frontWindow(ofPid: pid)
            try await capture(window: window, to: URL(fileURLWithPath: out))
            print("저장: \(out) (\(window.owningApplication?.applicationName ?? "?") — \(window.title ?? ""))")

        case "send-key":
            try checkAccessibility()
            let pid = try requirePid(args)
            let key = flagValue(args, "--key") ?? "right"
            try sendKey(key, toPid: pid)
            print("키 '\(key)' 전송 완료 -> pid \(pid)")

        case "macro":
            try checkScreenRecording()
            try checkAccessibility()
            let pid = try requirePid(args)
            let reps = Int(flagValue(args, "--reps") ?? "10") ?? 10
            let key = flagValue(args, "--key") ?? "right"
            let wait = Double(flagValue(args, "--wait") ?? "3") ?? 3
            let delayMin = Double(flagValue(args, "--delay-min") ?? "1") ?? 1
            let delayMax = Double(flagValue(args, "--delay-max") ?? "1") ?? 1
            let outDir = flagValue(args, "--out") ?? "captures"
            try FileManager.default.createDirectory(
                atPath: outDir, withIntermediateDirectories: true)

            print("\(wait)초 후 시작 (pid \(pid), \(reps)회, 키 '\(key)')")
            try await Task.sleep(for: .seconds(wait))
            for i in 1...reps {
                let window = try await frontWindow(ofPid: pid)  // 매 회 조회: 창 이동/리사이즈 대응
                let out = URL(fileURLWithPath: outDir).appendingPathComponent(
                    String(format: "screenshot_%03d.png", i))
                try await capture(window: window, to: out)
                try sendKey(key, toPid: pid)
                print("[\(i)/\(reps)] \(out.lastPathComponent)")
                if i < reps {
                    try await Task.sleep(for: .seconds(Double.random(in: delayMin...max(delayMin, delayMax))))
                }
            }
            print("완료: \(outDir)/")

        default:
            print(usage)
        }
    }
}
