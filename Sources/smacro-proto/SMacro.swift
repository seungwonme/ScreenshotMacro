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

    유틸리티 (기본 디렉토리: ./captures, --dir로 변경):
      smacro-proto captures [--dir D]                     세션별 캡처 현황
      smacro-proto stats [--dir D]                        전체 통계
      smacro-proto clean [--dir D] [-f]                   캡처 전체 삭제(휴지통, -f는 확인 생략)
      smacro-proto find-duplicates [--dir D] [--threshold N]
                                                          중복 이미지 탐지 (기본 N=0: 완전 동일)
    """

// MARK: - 유틸리티 명령

func collectPNGs(in dir: String) throws -> [URL] {
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

func fmtSize(_ bytes: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}

func runList(dir: String) throws {
    let files = try collectPNGs(in: dir)
    guard !files.isEmpty else { return print("캡처 없음: \(dir)") }
    let bySession = Dictionary(grouping: files) { $0.deletingLastPathComponent().lastPathComponent }
    for (session, items) in bySession.sorted(by: { $0.key < $1.key }) {
        let size = items.compactMap {
            try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize
        }.reduce(0, +)
        print("\(dir)/\(session)\t\(items.count)장\t\(fmtSize(size))")
    }
    print("합계: \(files.count)장")
}

func runStats(dir: String) throws {
    let files = try collectPNGs(in: dir)
    guard !files.isEmpty else { return print("캡처 없음: \(dir)") }
    var total = 0
    var dates: [Date] = []
    for f in files {
        let v = try? f.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        total += v?.fileSize ?? 0
        if let d = v?.contentModificationDate { dates.append(d) }
    }
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
    print("총 스크린샷: \(files.count)장")
    print("총 용량: \(fmtSize(total)) (평균 \(fmtSize(files.isEmpty ? 0 : total / files.count)))")
    if let oldest = dates.min(), let newest = dates.max() {
        print("기간: \(fmt.string(from: oldest)) ~ \(fmt.string(from: newest))")
    }
}

func runClean(dir: String, force: Bool) throws {
    let files = try collectPNGs(in: dir)
    guard !files.isEmpty else { return print("캡처 없음: \(dir)") }
    if !force {
        print("\(dir)의 캡처 \(files.count)장을 휴지통으로 이동합니다. 계속할까요? [y/N] ", terminator: "")
        guard readLine()?.lowercased() == "y" else { return print("취소됨") }
    }
    // 세션 디렉토리 단위로 휴지통 이동 (복구 가능)
    let sessions = Set(files.map { $0.deletingLastPathComponent() })
    for session in sessions.sorted(by: { $0.path < $1.path }) {
        try FileManager.default.trashItem(at: session, resultingItemURL: nil)
    }
    print("완료: \(files.count)장 (\(sessions.count)개 세션) 휴지통으로 이동")
}

func runFindDuplicates(dir: String, threshold: Int) throws {
    let files = try collectPNGs(in: dir)
    guard !files.isEmpty else { return print("캡처 없음: \(dir)") }
    let dupGroups = duplicateGroups(in: files, threshold: threshold)
    guard !dupGroups.isEmpty else {
        return print("중복 없음 (\(files.count)장 검사, 임계값 \(threshold))")
    }
    for (n, g) in dupGroups.enumerated() {
        print("\n유사 그룹 #\(n + 1):")
        for url in g { print("  \(url.path)") }
    }
    print("\n\(dupGroups.count)개 그룹, 중복 \(dupGroups.map { $0.count - 1 }.reduce(0, +))장")
}

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

        case "captures":
            try runList(dir: flagValue(args, "--dir") ?? "captures")

        case "stats":
            try runStats(dir: flagValue(args, "--dir") ?? "captures")

        case "clean":
            try runClean(
                dir: flagValue(args, "--dir") ?? "captures", force: args.contains("-f"))

        case "find-duplicates":
            try runFindDuplicates(
                dir: flagValue(args, "--dir") ?? "captures",
                threshold: Int(flagValue(args, "--threshold") ?? "0") ?? 0)

        default:
            print(usage)
        }
    }
}
