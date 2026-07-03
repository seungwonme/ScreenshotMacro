// smacro-proto: ScreenshotMacro Swift CLI. 로직은 SMacroCore 공유.

import AppKit
import CoreGraphics
import Foundation
import SMacroCore
import ScreenCaptureKit

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
        let app = try resolveApp(named: name)
        if (app.localizedName ?? "").caseInsensitiveCompare(name) != .orderedSame {
            print("주의: '\(name)' -> '\(app.localizedName ?? "?")' 선택")
        }
        return app.processIdentifier
    }
    throw die("--app <이름> 또는 --pid <숫자>가 필요합니다 (list 명령으로 확인)")
}

func parseArea(_ args: [String]) throws -> CGRect? {
    guard let raw = flagValue(args, "--area") else { return nil }
    let parts = raw.split(separator: ",").compactMap {
        Double($0.trimmingCharacters(in: .whitespaces))
    }
    guard parts.count == 4, parts[2] > 0, parts[3] > 0 else {
        throw die("--area 형식: x,y,w,h (창 좌상단 기준 포인트, 예: 100,110,350,180)")
    }
    return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
}

let usage = """
    smacro-proto — ScreenshotMacro Swift CLI

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
        initWindowServerConnection()
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
            let image = try await captureImage(window: window, area: area)
            try savePNG(image, to: URL(fileURLWithPath: out))
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
                let image = try await captureImage(window: window, area: area)
                try savePNG(image, to: out)
                try sendKey(key, toPid: pid)
                print("[\(i)/\(reps)] \(out.lastPathComponent)")
                if i < reps {
                    try await Task.sleep(
                        for: .seconds(Double.random(in: delayMin...max(delayMin, delayMax))))
                }
            }
            print("완료: \(sessionDir.path)/")

        default:
            print(usage)
        }
    }
}
