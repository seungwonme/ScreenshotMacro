// smacro-gui: ScreenshotMacro SwiftUI GUI.
// 대상 앱 선택 -> 미리보기 캡처 -> 미리보기 위 드래그로 영역 지정 -> 매크로 실행.
// 매크로가 도는 동안 대상 앱이 백그라운드여도 캡처·키 전송이 동작한다.

import AppKit
import SMacroCore
import ScreenCaptureKit
import SwiftUI

@main
struct SMacroApp: App {
    init() {
        initWindowServerConnection()
        // swift run(터미널 실행)에서는 앱 번들이 아니라 도크/포커스가 없음 -> 일반 앱으로 승격
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("Screenshot Macro") {
            ContentView()
        }
    }
}

struct ContentView: View {
    // 설정 (UserDefaults 자동 저장 — Python 버전의 config.json 역할)
    @AppStorage("appName") private var appName = ""
    @AppStorage("reps") private var reps = 100
    @AppStorage("key") private var key = "right"
    @AppStorage("waitSeconds") private var waitSeconds = 5.0
    @AppStorage("delayMin") private var delayMin = 1.0
    @AppStorage("delayMax") private var delayMax = 3.0
    @AppStorage("areaString") private var areaString = ""  // "x,y,w,h" (창 기준 포인트)
    @AppStorage("outputBase") private var outputBase =
        NSString(string: "~/Pictures/ScreenshotMacro").expandingTildeInPath

    @State private var runningApps: [String] = []
    @State private var preview: CGImage?
    @State private var previewPointSize: CGSize = .zero  // 미리보기 창의 포인트 크기
    @State private var dragCurrent: CGRect?  // 미리보기 표시 좌표계의 드래그 사각형
    @State private var status = "대상 앱을 선택하고 미리보기로 영역을 지정하세요"
    @State private var progress = 0
    @State private var macroTask: Task<Void, Never>?
    @State private var lastSessionDir: URL?

    private var running: Bool { macroTask != nil }

    private var area: CGRect? {
        let p = areaString.split(separator: ",").compactMap { Double($0) }
        guard p.count == 4, p[2] > 0, p[3] > 0 else { return nil }
        return CGRect(x: p[0], y: p[1], width: p[2], height: p[3])
    }

    var body: some View {
        HSplitView {
            settingsPane
                .frame(minWidth: 300, maxWidth: 360)
            previewPane
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 480)
        .onAppear(perform: refreshApps)
    }

    // MARK: - 좌측: 설정

    private var settingsPane: some View {
        Form {
            Section("대상 앱") {
                Picker("앱", selection: $appName) {
                    Text("선택...").tag("")
                    ForEach(runningApps, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    Button("새로고침") { refreshApps() }
                    Button("미리보기 캡처") { Task { await capturePreview() } }
                        .disabled(appName.isEmpty)
                }
            }

            Section("영역 (창 기준, 비우면 창 전체)") {
                TextField("x,y,w,h", text: $areaString)
                    .font(.body.monospaced())
                Button("영역 초기화") { areaString = "" }
                    .disabled(areaString.isEmpty)
            }

            Section("매크로") {
                Stepper("반복: \(reps)회", value: $reps, in: 1...10000, step: 10)
                Picker("키", selection: $key) {
                    ForEach(keyCodes.keys.sorted(), id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    Text("시작 대기")
                    TextField("", value: $waitSeconds, format: .number).frame(width: 50)
                    Text("초")
                }
                HStack {
                    Text("딜레이")
                    TextField("", value: $delayMin, format: .number).frame(width: 50)
                    Text("~")
                    TextField("", value: $delayMax, format: .number).frame(width: 50)
                    Text("초")
                }
            }

            Section("저장 위치") {
                TextField("", text: $outputBase).font(.caption.monospaced())
            }

            Section {
                if running {
                    Button("중지 (\(progress)/\(reps))", role: .destructive) {
                        macroTask?.cancel()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Button("매크로 시작") { startMacro() }
                        .keyboardShortcut(.defaultAction)
                        .frame(maxWidth: .infinity)
                        .disabled(appName.isEmpty)
                }
                if let dir = lastSessionDir {
                    Button("결과 폴더 열기") { NSWorkspace.shared.open(dir) }
                        .frame(maxWidth: .infinity)
                }
            }

            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .formStyle(.grouped)
    }

    // MARK: - 우측: 미리보기 + 드래그 영역 선택

    private var previewPane: some View {
        Group {
            if let preview {
                GeometryReader { geo in
                    let fit = fittedRect(image: preview, in: geo.size)
                    ZStack(alignment: .topLeading) {
                        Image(preview, scale: 1, label: Text("preview"))
                            .resizable()
                            .frame(width: fit.width, height: fit.height)
                            .offset(x: fit.minX, y: fit.minY)
                        if let rect = selectionRect(in: fit) {
                            Rectangle()
                                .stroke(.orange, lineWidth: 2)
                                .background(Rectangle().fill(.orange.opacity(0.15)))
                                .frame(width: rect.width, height: rect.height)
                                .offset(x: rect.minX, y: rect.minY)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .gesture(dragGesture(fit: fit))
                }
                .padding(8)
            } else {
                ContentUnavailableView(
                    "미리보기 없음", systemImage: "photo",
                    description: Text("대상 앱을 고르고 '미리보기 캡처'를 누르면\n여기서 드래그로 캡처 영역을 지정할 수 있습니다"))
            }
        }
    }

    /// 이미지가 scaledToFit으로 표시될 사각형 (컨테이너 좌표)
    private func fittedRect(image: CGImage, in container: CGSize) -> CGRect {
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        let scale = min(container.width / iw, container.height / ih)
        let w = iw * scale, h = ih * scale
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }

    /// 저장된 area(창 포인트 좌표)를 미리보기 표시 좌표로 환산
    private func selectionRect(in fit: CGRect) -> CGRect? {
        if let drag = dragCurrent { return drag }
        guard let area, previewPointSize.width > 0 else { return nil }
        let sx = fit.width / previewPointSize.width
        let sy = fit.height / previewPointSize.height
        return CGRect(
            x: fit.minX + area.minX * sx, y: fit.minY + area.minY * sy,
            width: area.width * sx, height: area.height * sy)
    }

    private func dragGesture(fit: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                let r = CGRect(
                    x: min(v.startLocation.x, v.location.x),
                    y: min(v.startLocation.y, v.location.y),
                    width: abs(v.location.x - v.startLocation.x),
                    height: abs(v.location.y - v.startLocation.y)
                ).intersection(fit)
                dragCurrent = r.isNull ? nil : r
            }
            .onEnded { _ in
                defer { dragCurrent = nil }
                guard let r = dragCurrent, previewPointSize.width > 0,
                    r.width > 4, r.height > 4
                else { return }
                // 표시 좌표 -> 창 포인트 좌표
                let sx = previewPointSize.width / fit.width
                let sy = previewPointSize.height / fit.height
                let x = (r.minX - fit.minX) * sx
                let y = (r.minY - fit.minY) * sy
                areaString = String(
                    format: "%.0f,%.0f,%.0f,%.0f", x, y, r.width * sx, r.height * sy)
                status = "영역 지정: \(areaString) (창 기준 포인트)"
            }
    }

    // MARK: - Actions

    private func refreshApps() {
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { $0.localizedName }
            .sorted()
    }

    private func capturePreview() async {
        do {
            try checkScreenRecording()
            let app = try resolveApp(named: appName)
            let window = try await frontWindow(ofPid: app.processIdentifier)
            preview = try await captureImage(window: window)
            previewPointSize = window.frame.size
            status = "미리보기: \(Int(window.frame.width))x\(Int(window.frame.height))pt — 드래그로 영역 지정"
        } catch {
            status = "오류: \(error)"
        }
    }

    private func startMacro() {
        let repsNow = reps
        let keyNow = key
        let waitNow = waitSeconds
        let dMin = delayMin
        let dMax = max(delayMin, delayMax)
        let areaNow = area
        let baseNow = outputBase
        let appNow = appName

        macroTask = Task {
            defer { macroTask = nil }
            do {
                try checkScreenRecording()
                try checkAccessibility()
                let app = try resolveApp(named: appNow)
                let pid = app.processIdentifier
                let sessionDir = try nextSessionDir(base: baseNow)
                lastSessionDir = sessionDir
                progress = 0

                status = "\(Int(waitNow))초 후 시작 -> \(sessionDir.path)"
                try await Task.sleep(for: .seconds(waitNow))
                for i in 1...repsNow {
                    if Task.isCancelled { break }
                    let window = try await frontWindow(ofPid: pid)
                    let image = try await captureImage(window: window, area: areaNow)
                    try savePNG(
                        image,
                        to: sessionDir.appendingPathComponent(
                            String(format: "screenshot_%03d.png", i)))
                    try sendKey(keyNow, toPid: pid)
                    progress = i
                    status = "진행 중 \(i)/\(repsNow) — 다른 작업을 하셔도 됩니다"
                    if i < repsNow {
                        try await Task.sleep(for: .seconds(Double.random(in: dMin...dMax)))
                    }
                }
                status = Task.isCancelled
                    ? "중지됨 (\(progress)/\(repsNow)) -> \(sessionDir.path)"
                    : "완료: \(repsNow)장 -> \(sessionDir.path)"
                if !Task.isCancelled { NSWorkspace.shared.open(sessionDir) }
            } catch is CancellationError {
                status = "중지됨 (\(progress)장 저장됨)"
            } catch {
                status = "오류: \(error)"
            }
        }
    }
}
