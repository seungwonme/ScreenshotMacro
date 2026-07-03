// smacro-gui: ScreenshotMacro SwiftUI GUI (위저드형).
// 상단 스텝 바(완료 시 초록 체크) + 단계별 탭:
//   1 대상 창(썸네일 그리드) -> 2 캡처 영역(드래그) -> 3 매크로 설정 -> 4 실행(테스트/진행)
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

struct TargetWindow: Identifiable, Hashable {
    let id: CGWindowID
    let pid: pid_t
    let appName: String
    let title: String

    var icon: NSImage? { NSRunningApplication(processIdentifier: pid)?.icon }
}

struct ContentView: View {
    // 설정 (UserDefaults 자동 저장 — Python 버전의 config.json 역할)
    @AppStorage("appName") private var savedAppName = ""
    @AppStorage("reps") private var reps = 100
    @AppStorage("actionType") private var actionType = "key"  // "key" | "click"
    @AppStorage("foregroundMode") private var foregroundMode = false
    @AppStorage("key") private var key = "right"
    @AppStorage("keyCode") private var keyCode = 124  // right
    @AppStorage("clickPointString") private var clickPointString = ""  // "x,y" (창 기준 포인트)
    @AppStorage("waitSeconds") private var waitSeconds = 5.0
    @AppStorage("randomDelay") private var randomDelay = true
    @AppStorage("delayMin") private var delayMin = 1.0
    @AppStorage("delayMax") private var delayMax = 3.0
    @AppStorage("fullWindow") private var fullWindow = true
    @AppStorage("areaString") private var areaString = ""  // "x,y,w,h" (창 기준 포인트)
    @AppStorage("outputBase") private var outputBase =
        NSString(string: "~/Pictures/ScreenshotMacro").expandingTildeInPath

    @State private var currentStep = 1
    @State private var targets: [TargetWindow] = []
    @State private var thumbs: [CGWindowID: CGImage] = [:]
    @State private var selected: TargetWindow?
    @State private var preview: CGImage?
    @State private var previewPointSize: CGSize = .zero
    @State private var dragCurrent: CGRect?
    @State private var lastFrame: CGImage?  // 실행/테스트 중 방금 저장된 컷
    @State private var testPassed = false
    @State private var status = ""
    @State private var progress = 0
    @State private var macroTask: Task<Void, Never>?
    @State private var lastSessionDir: URL?
    @State private var capturingKey = false
    @State private var keyMonitor: Any?

    private var running: Bool { macroTask != nil }

    private var area: CGRect? {
        let p = areaString.split(separator: ",").compactMap { Double($0) }
        guard p.count == 4, p[2] > 0, p[3] > 0 else { return nil }
        return CGRect(x: p[0], y: p[1], width: p[2], height: p[3])
    }

    private var clickPoint: CGPoint? {
        let p = clickPointString.split(separator: ",").compactMap { Double($0) }
        guard p.count == 2 else { return nil }
        return CGPoint(x: p[0], y: p[1])
    }

    private var actionLabel: String {
        actionType == "key" ? "\(key) 키" : "클릭 (\(clickPointString))"
    }

    private let stepTitles = ["대상 창", "캡처 영역", "매크로 설정", "실행"]

    private func stepComplete(_ i: Int) -> Bool {
        switch i {
        case 1: return selected != nil
        case 2: return preview != nil && (fullWindow || area != nil)
        case 3:
            let timingOK = reps >= 1 && (!randomDelay || delayMax >= max(0, delayMin))
                && !outputBase.isEmpty
            let actionOK = actionType == "key" || clickPoint != nil
            return timingOK && actionOK
        default: return testPassed
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            stepBar
                .padding(.vertical, 12)
            Divider()
            Group {
                switch currentStep {
                case 1: stepTargets
                case 2: stepArea
                case 3: stepSettings
                default: stepRun
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
                .padding(10)
        }
        .frame(minWidth: 800, minHeight: 600)
        .task { await refreshTargets() }
    }

    // MARK: - 상단 스텝 바

    private var stepBar: some View {
        HStack(spacing: 0) {
            ForEach(1...4, id: \.self) { i in
                Button {
                    currentStep = i
                } label: {
                    HStack(spacing: 6) {
                        if stepComplete(i) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.green)
                        } else {
                            Text("\(i)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(
                                    Circle().fill(
                                        currentStep == i
                                            ? Color.accentColor : Color.gray.opacity(0.4)))
                        }
                        Text(stepTitles[i - 1])
                            .fontWeight(currentStep == i ? .semibold : .regular)
                            .foregroundStyle(currentStep == i ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
                if i < 4 {
                    Rectangle()
                        .fill(stepComplete(i) ? Color.green.opacity(0.6) : Color.secondary.opacity(0.3))
                        .frame(width: 32, height: 2)
                        .padding(.horizontal, 8)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            if !status.isEmpty {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Spacer()
            if currentStep > 1 {
                Button("이전") { currentStep -= 1 }
            }
            if currentStep < 4 {
                Button("다음") { currentStep += 1 }
                    .buttonStyle(.borderedProminent)
                    .disabled(!stepComplete(currentStep))
            }
        }
    }

    // MARK: - Step 1: 대상 창 (썸네일 그리드)

    private var stepTargets: some View {
        VStack(spacing: 0) {
            HStack {
                Text("캡처할 창을 선택하세요. 가려진 창, 다른 데스크톱의 창도 그대로 보입니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await refreshTargets() }
                } label: {
                    Label("새로고침", systemImage: "arrow.clockwise")
                }
            }
            .padding(12)
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12
                ) {
                    ForEach(targets) { t in
                        targetCell(t)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .disabled(running)
    }

    private func targetCell(_ t: TargetWindow) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5))
                if let img = thumbs[t.id] {
                    Image(img, scale: 1, label: Text(t.appName))
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(height: 130)
            HStack(spacing: 6) {
                if let icon = t.icon {
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(t.appName).font(.caption.bold()).lineLimit(1)
                    Text(t.title.isEmpty ? "(제목 없음)" : t.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected == t ? Color.accentColor.opacity(0.12) : Color.clear))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    selected == t ? Color.accentColor : Color.secondary.opacity(0.25),
                    lineWidth: selected == t ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture { select(t) }
    }

    // MARK: - Step 2: 캡처 영역

    private var stepArea: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("", selection: $fullWindow) {
                    Text("창 전체").tag(true)
                    Text("영역 지정").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                if !fullWindow {
                    areaField("x", 0)
                    areaField("y", 1)
                    areaField("w", 2)
                    areaField("h", 3)
                }
                Spacer()
                Button {
                    Task { await capturePreview() }
                } label: {
                    Label("다시 캡처", systemImage: "camera")
                }
                .disabled(selected == nil)
            }
            .padding(12)
            if preview != nil {
                previewEditor
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            } else {
                ContentUnavailableView(
                    "미리보기 없음", systemImage: "macwindow",
                    description: Text("1단계에서 대상 창을 먼저 선택하세요"))
            }
        }
        .disabled(running)
    }

    private var previewEditor: some View {
        GeometryReader { geo in
            if let preview {
                let fit = fittedRect(image: preview, in: geo.size)
                ZStack(alignment: .topLeading) {
                    Image(preview, scale: 1, label: Text("preview"))
                        .resizable()
                        .frame(width: fit.width, height: fit.height)
                        .offset(x: fit.minX, y: fit.minY)
                    if !fullWindow, let rect = selectionRect(in: fit) {
                        // 선택 밖은 어둡게 — 어디가 찍히는지 즉시 보이게
                        Path { p in
                            p.addRect(CGRect(origin: .zero, size: geo.size))
                            p.addRect(rect)
                        }
                        .fill(.black.opacity(0.45), style: FillStyle(eoFill: true))
                        Rectangle()
                            .stroke(.orange, lineWidth: 2)
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .contentShape(Rectangle())
                .gesture(dragGesture(fit: fit))
            }
        }
    }

    private func areaField(_ label: String, _ index: Int) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(
                label,
                text: Binding(
                    get: {
                        let p = areaString.split(separator: ",").map(String.init)
                        return p.count == 4 ? p[index] : ""
                    },
                    set: { newValue in
                        var p = areaString.split(separator: ",").map(String.init)
                        if p.count != 4 { p = ["0", "0", "0", "0"] }
                        p[index] = newValue
                        areaString = p.joined(separator: ",")
                    })
            )
            .font(.caption.monospaced())
            .frame(width: 52)
        }
    }

    // MARK: - Step 3: 매크로 설정

    private var stepSettings: some View {
        Form {
            Section("페이지 넘김 동작 (캡처 후 매번 실행)") {
                Picker("", selection: $actionType) {
                    Text("키 입력").tag("key")
                    Text("마우스 클릭").tag("click")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if actionType == "key" {
                    LabeledContent("보낼 키") {
                        HStack(spacing: 6) {
                            Text(key)
                                .font(.body.monospaced())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary))
                            Menu("자주 쓰는 키") {
                                ForEach(keyCodes.keys.sorted(), id: \.self) { name in
                                    Button(name) {
                                        key = name
                                        keyCode = Int(keyCodes[name]!)
                                        testPassed = false
                                    }
                                }
                            }
                            .frame(width: 110)
                            Button(capturingKey ? "키를 누르세요... (esc 취소)" : "키 캡처") {
                                capturingKey ? stopKeyCapture() : startKeyCapture()
                            }
                            .tint(capturingKey ? .orange : nil)
                        }
                    }
                } else {
                    clickPositionPicker
                }
                Toggle("전면 모드 (호환)", isOn: $foregroundMode)
                Text(
                    foregroundMode
                        ? "대상 앱을 전면에 두고 하드웨어 입력과 같은 경로(HID)로 전송합니다. 모든 앱에서 동작하지만 도는 동안 맥으로 다른 작업은 못 합니다."
                        : "백그라운드 모드: 대상 앱에만 이벤트를 보내 도는 동안 다른 작업이 가능합니다. Discord 등 일부 앱이 입력을 무시하면 전면 모드를 켜세요."
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            Section("타이밍") {
                LabeledContent("반복 횟수") {
                    HStack(spacing: 4) {
                        TextField("", value: $reps, format: .number)
                            .frame(width: 64)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $reps, in: 1...10000, step: 10).labelsHidden()
                        Text("회").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("시작 대기") {
                    HStack(spacing: 4) {
                        TextField("", value: $waitSeconds, format: .number)
                            .frame(width: 64)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $waitSeconds, in: 0...60, step: 1).labelsHidden()
                        Text("초").foregroundStyle(.secondary)
                    }
                }
                Toggle("캡처 간 딜레이 랜덤 (사람처럼 불규칙하게)", isOn: $randomDelay)
                LabeledContent(randomDelay ? "딜레이 범위" : "딜레이") {
                    HStack(spacing: 4) {
                        TextField("", value: $delayMin, format: .number)
                            .frame(width: 56)
                            .multilineTextAlignment(.trailing)
                        if randomDelay {
                            Text("~").foregroundStyle(.secondary)
                            TextField("", value: $delayMax, format: .number)
                                .frame(width: 56)
                                .multilineTextAlignment(.trailing)
                        }
                        Text("초").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("예상 소요") {
                    Text(etaText(from: reps)).foregroundStyle(.secondary)
                }
            }
            Section("저장 위치") {
                HStack {
                    TextField("", text: $outputBase).font(.caption.monospaced())
                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: outputBase))
                    } label: {
                        Image(systemName: "folder")
                    }
                }
                Text("실행할 때마다 01, 02, ... 세션 폴더가 자동 생성됩니다")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .disabled(running)
    }

    /// 클릭 위치 지정: 미니 미리보기를 클릭하면 창 기준 좌표로 저장
    private var clickPositionPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let preview {
                Text(
                    clickPoint == nil
                        ? "아래 미리보기에서 클릭할 위치를 누르세요 (예: '다음' 버튼)"
                        : "클릭 위치: \(clickPointString) (창 기준 포인트) — 다시 누르면 변경"
                )
                .font(.caption)
                .foregroundStyle(clickPoint == nil ? .orange : .secondary)
                GeometryReader { geo in
                    let fit = fittedRect(image: preview, in: geo.size)
                    ZStack(alignment: .topLeading) {
                        Image(preview, scale: 1, label: Text("click-preview"))
                            .resizable()
                            .frame(width: fit.width, height: fit.height)
                            .offset(x: fit.minX, y: fit.minY)
                        if let marker = clickMarker(in: fit) {
                            Image(systemName: "scope")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.red)
                                .shadow(color: .white, radius: 2)
                                .position(marker)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard fit.contains(location), previewPointSize.width > 0 else { return }
                        let sx = previewPointSize.width / fit.width
                        let sy = previewPointSize.height / fit.height
                        clickPointString = String(
                            format: "%.0f,%.0f",
                            (location.x - fit.minX) * sx, (location.y - fit.minY) * sy)
                        testPassed = false
                    }
                }
                .frame(height: 200)
            } else {
                Text("1단계에서 대상 창을 먼저 선택하면 여기서 클릭 위치를 지정할 수 있습니다")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func clickMarker(in fit: CGRect) -> CGPoint? {
        guard let clickPoint, previewPointSize.width > 0 else { return nil }
        return CGPoint(
            x: fit.minX + clickPoint.x * fit.width / previewPointSize.width,
            y: fit.minY + clickPoint.y * fit.height / previewPointSize.height)
    }

    // MARK: - Step 4: 실행

    private var stepRun: some View {
        VStack(spacing: 12) {
            // 설정 요약
            HStack(spacing: 14) {
                summaryItem("macwindow", selected?.appName ?? "창 미선택")
                summaryItem(
                    "crop", fullWindow ? "창 전체" : (area != nil ? areaString : "영역 미지정"))
                summaryItem("repeat", "\(reps)회 · \(actionLabel)")
                if foregroundMode {
                    summaryItem("macwindow.on.rectangle", "전면 모드")
                }
                summaryItem("clock", "약 \(etaText(from: reps))")
            }
            .padding(.top, 12)

            if running {
                ProgressView(value: Double(progress), total: Double(max(reps, 1)))
                    .padding(.horizontal, 16)
                HStack {
                    Text("\(progress)/\(reps) — 남은 시간 약 \(etaText(from: reps - progress))")
                        .font(.callout)
                    Button("중지", role: .destructive) { macroTask?.cancel() }
                }
            } else {
                HStack(spacing: 10) {
                    Button {
                        testOnce()
                    } label: {
                        Label("테스트 1회", systemImage: "checkmark.seal")
                    }
                    .disabled(selected == nil)
                    .help("캡처 1장 + 키 1회로 설정을 확인합니다 (파일 저장 안 함)")
                    Button {
                        startMacro()
                    } label: {
                        Label("매크로 시작", systemImage: "play.fill")
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(selected == nil)
                    if let dir = lastSessionDir {
                        Button {
                            NSWorkspace.shared.open(dir)
                        } label: {
                            Label("결과 폴더", systemImage: "folder")
                        }
                    }
                }
            }

            // 실시간/테스트 캡처 미리보기
            Group {
                if let lastFrame {
                    VStack(spacing: 4) {
                        Image(lastFrame, scale: 1, label: Text("live"))
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(.separator, lineWidth: 1))
                        Text(running ? "방금 저장된 컷 (실시간)" : "테스트 캡처 결과")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    ContentUnavailableView(
                        "테스트 1회로 설정을 확인하세요", systemImage: "checkmark.seal",
                        description: Text("캡처 1장과 키 1회를 보내 결과를 여기서 보여줍니다.\n확인 후 매크로를 시작하면 도는 동안 다른 작업을 하셔도 됩니다."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func summaryItem(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    // MARK: - 좌표 계산

    /// 이미지가 scaledToFit으로 표시될 사각형 (컨테이너 좌표)
    private func fittedRect(image: CGImage, in container: CGSize) -> CGRect {
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        let scale = min(container.width / iw, container.height / ih)
        let w = iw * scale, h = ih * scale
        return CGRect(
            x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
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
                let sx = previewPointSize.width / fit.width
                let sy = previewPointSize.height / fit.height
                let x = (r.minX - fit.minX) * sx
                let y = (r.minY - fit.minY) * sy
                areaString = String(
                    format: "%.0f,%.0f,%.0f,%.0f", x, y, r.width * sx, r.height * sy)
                fullWindow = false
                testPassed = false
                status = "영역 지정 완료 — 4단계에서 '테스트 1회'로 확인하세요"
            }
    }

    // MARK: - Actions

    // MARK: - 키 캡처 (아무 키나 등록, Python의 key capture 대응)

    private func startKeyCapture() {
        capturingKey = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            defer { DispatchQueue.main.async { stopKeyCapture() } }
            if event.keyCode != 53 {  // esc는 취소
                keyCode = Int(event.keyCode)
                key = keyDisplayName(for: event)
                testPassed = false
            }
            return nil  // 이벤트 소비 (앱 단축키로 새지 않게)
        }
    }

    private func stopKeyCapture() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
        capturingKey = false
    }

    private func keyDisplayName(for event: NSEvent) -> String {
        if let known = keyCodes.first(where: { $0.value == CGKeyCode(event.keyCode) })?.key {
            return known
        }
        let chars = event.charactersIgnoringModifiers ?? ""
        return chars.isEmpty || chars.unicodeScalars.contains(where: { $0.value < 0x20 })
            ? "code \(event.keyCode)" : chars
    }

    private func refreshTargets() async {
        do {
            try checkScreenRecording()
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            let me = ProcessInfo.processInfo.processIdentifier
            let windows = content.windows.filter { w in
                guard let app = w.owningApplication else { return false }
                // windowLayer 0 = 일반 앱 창 (Dock 배경·월페이퍼·오버레이는 다른 레이어)
                // activationPolicy .regular = 도크에 뜨는 앱 (스크린샷 헬퍼 등 제외)
                return app.processID != me && w.isOnScreen && w.windowLayer == 0
                    && w.frame.width > 50 && w.frame.height > 50
                    && !app.applicationName.isEmpty
                    && NSRunningApplication(processIdentifier: app.processID)?
                        .activationPolicy == .regular
            }
            targets = windows.map {
                TargetWindow(
                    id: $0.windowID, pid: $0.owningApplication!.processID,
                    appName: $0.owningApplication!.applicationName, title: $0.title ?? "")
            }
            .sorted { ($0.appName, $0.title) < ($1.appName, $1.title) }
            if selected == nil, let prev = targets.first(where: { $0.appName == savedAppName }) {
                selected = prev
                Task { await capturePreview() }
            }
            // 썸네일은 뒤에서 순차 로드 (그리드가 먼저 뜨고 채워짐)
            for w in windows {
                thumbs[w.windowID] = try? await captureThumbnail(window: w)
            }
        } catch {
            status = "오류: \(error)"
        }
    }

    private func select(_ t: TargetWindow) {
        selected = t
        savedAppName = t.appName
        testPassed = false
        Task {
            await capturePreview()
            currentStep = 2
        }
    }

    private func capturePreview() async {
        guard let selected else { return }
        do {
            let window = try await findWindow(selected)
            preview = try await captureImage(window: window)
            previewPointSize = window.frame.size
            status = "\(selected.appName) — \(Int(window.frame.width))x\(Int(window.frame.height))pt"
        } catch {
            status = "오류: \(error)"
        }
    }

    private func findWindow(_ t: TargetWindow) async throws -> SCWindow {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        if let w = content.windows.first(where: { $0.windowID == t.id }) { return w }
        return try await frontWindow(ofPid: t.pid)  // 창이 닫혔으면 같은 앱의 최대 창으로 폴백
    }

    private func testOnce() {
        guard let selected else { return }
        macroTask = Task {
            defer { macroTask = nil }
            do {
                try checkScreenRecording()
                try checkAccessibility()
                let window = try await findWindow(selected)
                lastFrame = try await captureImage(
                    window: window, area: fullWindow ? nil : area)
                let method = try performAction(window: window, pid: selected.pid)
                testPassed = true
                status = "테스트 OK — 캡처 1장 + \(actionLabel) 전송(방식: \(method)). 대상 앱이 실제로 반응했는지 확인하세요"
            } catch {
                testPassed = false
                status = "테스트 실패: \(error)"
            }
        }
    }

    /// 설정된 페이지 넘김 동작(키 또는 클릭)을 대상 앱에 전송. 사용된 방식 문자열 반환.
    @discardableResult
    private func performAction(window: SCWindow, pid: pid_t) throws -> String {
        if foregroundMode {
            ensureFrontmost(pid: pid)
            if actionType == "click" {
                guard let clickPoint else { throw die("클릭 위치가 지정되지 않았습니다 (3단계)") }
                try sendClickGlobal(at: clickPoint, window: window)
                return "전면 클릭"
            }
            try sendKeyGlobal(code: CGKeyCode(keyCode))
            return "전면 키 입력"
        }
        if actionType == "click" {
            guard let clickPoint else { throw die("클릭 위치가 지정되지 않았습니다 (3단계)") }
            return try sendClick(at: clickPoint, window: window, toPid: pid)
        } else {
            try sendKey(code: CGKeyCode(keyCode), toPid: pid)
            return "키 입력"
        }
    }

    private func startMacro() {
        guard let selected else { return }
        let repsNow = reps
        let waitNow = max(0, waitSeconds)
        let dMin = max(0, delayMin)
        let dMax = randomDelay ? max(dMin, delayMax) : dMin
        let areaNow = fullWindow ? nil : area
        let baseNow = outputBase

        macroTask = Task {
            defer { macroTask = nil }
            do {
                try checkScreenRecording()
                try checkAccessibility()
                let sessionDir = try nextSessionDir(base: baseNow)
                lastSessionDir = sessionDir
                progress = 0
                lastFrame = nil

                for s in stride(from: Int(waitNow), through: 1, by: -1) {
                    if Task.isCancelled { break }
                    status = "\(s)초 후 시작 — 대상 창을 첫 페이지로 준비하세요"
                    try await Task.sleep(for: .seconds(1))
                }
                for i in 1...repsNow {
                    if Task.isCancelled { break }
                    let window = try await findWindow(selected)
                    let image = try await captureImage(window: window, area: areaNow)
                    try savePNG(
                        image,
                        to: sessionDir.appendingPathComponent(
                            String(format: "screenshot_%03d.png", i)))
                    try performAction(window: window, pid: selected.pid)
                    lastFrame = image
                    progress = i
                    status = "진행 중 — 다른 작업을 하셔도 됩니다"
                    if i < repsNow {
                        try await Task.sleep(for: .seconds(Double.random(in: dMin...dMax)))
                    }
                }
                if Task.isCancelled {
                    status = "중지됨 — \(progress)장 저장: \(sessionDir.path)"
                } else {
                    status = "완료 — \(progress)장 저장: \(sessionDir.path)"
                    NSSound(named: "Glass")?.play()
                    NSWorkspace.shared.open(sessionDir)
                }
            } catch is CancellationError {
                status = "중지됨 (\(progress)장 저장됨)"
            } catch {
                status = "오류 (\(progress)장까지 저장됨): \(error)"
                NSSound(named: "Basso")?.play()
            }
        }
    }

    private func etaText(from remaining: Int) -> String {
        let dMin = max(0, delayMin)
        let avg = (randomDelay ? (dMin + max(dMin, delayMax)) / 2 : dMin) + 0.4  // +캡처 시간
        let total = Int(Double(max(0, remaining)) * avg)
        return total >= 60 ? "\(total / 60)분 \(total % 60)초" : "\(total)초"
    }
}
