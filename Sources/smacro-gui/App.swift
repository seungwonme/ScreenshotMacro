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
        // 단일 창: Cmd+N 다중 창이 뜨면 RunState/HUD 싱글턴이 충돌한다
        Window("Screenshot Macro", id: "main") {
            ContentView()
        }
    }
}

/// 영역 드래그의 종류: 새로 그리기 / 기존 선택 이동 / 핸들 리사이즈
enum AreaDragMode {
    case create
    case move(CGRect)
    case resize(CGRect, x: RectEdge?, y: RectEdge?)
}

enum RectEdge { case min, max }

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
    @AppStorage("dedupOnFinish") private var dedupOnFinish = true
    @AppStorage("fullWindow") private var fullWindow = true
    @AppStorage("areaString") private var areaString = ""  // "x,y,w,h" (창 기준 포인트)
    @AppStorage("outputBase") private var outputBase =
        NSString(string: "~/Pictures/ScreenshotMacro").expandingTildeInPath
    @AppStorage("openFinderOnFinish") private var openFinderOnFinish = true
    @AppStorage("targetSizeString") private var targetSizeString = ""  // area/clickPoint가 기준한 창 크기 "w,h"

    @State private var currentStep = 1
    @State private var targets: [TargetWindow] = []
    @State private var thumbs: [CGWindowID: CGImage?] = [:]  // 값 nil = 캡처 실패, 키 없음 = 로드 중
    @State private var selected: TargetWindow?
    @State private var preview: CGImage?
    @State private var previewPointSize: CGSize = .zero
    @State private var dragCurrent: CGRect?
    @State private var dragMode: AreaDragMode?
    // 제스처 취소(onEnded 미호출) 시에도 자동 리셋되는 유일한 수단 — onChange로 잔존 상태 정리
    @GestureState private var dragActive = false
    @State private var lastFrame: CGImage?  // 실행/테스트 중 방금 저장된 컷
    @State private var testPassed = false
    @State private var status = ""
    @State private var macroTask: Task<Void, Never>?
    @State private var lastSessionDir: URL?
    @State private var capturingKey = false
    @State private var keyMonitor: Any?
    @State private var nudgeMonitor: Any?  // 2단계 방향키 영역 이동
    @State private var refreshing = false
    @State private var screenPermissionDenied = false
    @State private var windowFallbackNote: String?  // 원래 창을 잃고 같은 앱 다른 창으로 폴백했을 때 안내

    /// 실행 진행 상태 (progress/reps/countdown/error) - HUD와 공유하는 단일 소스
    @ObservedObject private var runState = RunState.shared

    // 중복 정리 시트
    @State private var showDuplicates = false

    private var running: Bool { macroTask != nil }

    private var area: CGRect? { CGRect(storageString: areaString) }

    private var clickPoint: CGPoint? { CGPoint(storageString: clickPointString) }

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

    /// 스텝 바 이동 가능 조건: 뒤로는 자유, 앞으로는 사이 단계가 모두 완료돼야 (푸터 '다음'과 동일 규칙)
    private func stepReachable(_ i: Int) -> Bool {
        i <= currentStep || (currentStep..<i).allSatisfy(stepComplete)
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
        .sheet(isPresented: $showDuplicates) {
            DuplicatesSheetView(initialDir: latestSessionDir())
        }
        // 동작 결과에 영향을 주는 설정이 바뀌면 테스트 통과를 무효화 (스텝 바 초록 체크의 신뢰 유지).
        // 저장 값 기준이라 어떤 편집 경로(드래그, 수동 입력, 키 캡처)든 자동으로 걸린다.
        .onChange(of: actionType) { testPassed = false }
        .onChange(of: foregroundMode) { testPassed = false }
        .onChange(of: fullWindow) { testPassed = false }
        .onChange(of: areaString) { testPassed = false }
        .onChange(of: clickPointString) { testPassed = false }
        .onChange(of: keyCode) { testPassed = false }
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
                .disabled(running || !stepReachable(i))
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
                    .disabled(running)  // 실행 중 이동하면 중지 버튼이 화면에서 사라짐
            }
            if currentStep < 4 {
                Button("다음") { currentStep += 1 }
                    .buttonStyle(.borderedProminent)
                    .disabled(running || !stepComplete(currentStep))
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
                .keyboardShortcut("r", modifiers: .command)
            }
            .padding(12)
            if screenPermissionDenied {
                ContentUnavailableView {
                    Label("화면 기록 권한이 필요합니다", systemImage: "video.slash")
                } description: {
                    Text(
                        "창 목록과 캡처에 화면 기록 권한이 필요합니다.\n허용한 뒤에는 실행한 앱(터미널 등)을 완전히 종료했다가 다시 실행해야 반영됩니다."
                    )
                } actions: {
                    Button("시스템 설정 열기") {
                        NSWorkspace.shared.open(
                            URL(
                                string:
                                    "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                            )!)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("다시 확인") { Task { await refreshTargets() } }
                }
            } else {
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
        }
        .disabled(running)
    }

    private func targetCell(_ t: TargetWindow) -> some View {
        Button {
            select(t)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5))
                    switch thumbs[t.id] {
                    case .some(.some(let img)):
                        Image(img, scale: 1, label: Text(t.appName))
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    case .some(.none):
                        // 캡처 실패: 영구 스피너 대신 플레이스홀더 (로딩 중과 구분)
                        Image(systemName: "macwindow")
                            .font(.system(size: 28))
                            .foregroundStyle(.tertiary)
                    case .none:
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
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(t.appName) \(t.title.isEmpty ? "(제목 없음)" : t.title)")
        .accessibilityAddTraits(selected == t ? .isSelected : [])
    }

    // MARK: - Step 2: 캡처 영역

    private var stepArea: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("캡처 범위", selection: $fullWindow) {
                    Text("창 전체").tag(true)
                    Text("영역 지정").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
                if !fullWindow {
                    areaField("x", 0)
                    areaField("y", 1)
                    areaField("w", 2)
                    areaField("h", 3)
                    if area != nil {
                        Button {
                            centerArea()
                        } label: {
                            Image(systemName: "rectangle.center.inset.filled")
                        }
                        .help("영역을 창 중앙으로 정렬")
                        Button {
                            resizeArea(step: 10)
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                        }
                        .help("영역 키우기 (⇧])")
                        .keyboardShortcut("]", modifiers: .shift)
                        Button {
                            resizeArea(step: -10)
                        } label: {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                        }
                        .help("영역 줄이기 (⇧[)")
                        .keyboardShortcut("[", modifiers: .shift)
                    }
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
        .onAppear { startNudgeMonitor() }
        .onDisappear { stopNudgeMonitor() }
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
                    if !fullWindow || dragCurrent != nil, let rect = selectionRect(in: fit) {
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
                        // 리사이즈 핸들 (모서리 4 + 변 중앙 4)
                        ForEach(0..<handlePoints(of: rect).count, id: \.self) { i in
                            Rectangle()
                                .fill(.white)
                                .frame(width: 7, height: 7)
                                .overlay(Rectangle().stroke(.orange, lineWidth: 1))
                                .position(handlePoints(of: rect)[i])
                        }
                        // 크기 라벨 (창 기준 포인트)
                        if fit.width > 0 {
                            let sx = previewPointSize.width / fit.width
                            let sy = previewPointSize.height / fit.height
                            Text(
                                "\(Int((rect.width * sx).rounded()))×\(Int((rect.height * sy).rounded()))pt"
                            )
                            .font(.caption.monospaced())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.7), in: Capsule())
                            .foregroundStyle(.white)
                            .position(
                                x: min(max(rect.midX, 40), geo.size.width - 40),
                                y: min(rect.maxY + 16, geo.size.height - 12))
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .contentShape(Rectangle())
                .gesture(dragGesture(fit: fit))
                .onChange(of: dragActive) { _, active in
                    // 제스처가 취소돼 onEnded가 안 불려도 잔존 상태를 정리 (정상 종료 뒤엔 no-op)
                    if !active {
                        dragCurrent = nil
                        dragMode = nil
                    }
                }
                .onTapGesture(count: 2) { location in
                    // 선택이 프리뷰 전체를 덮으면 새로 그릴 자리가 없다 — 더블클릭으로 해제.
                    // 핸들 근처 미세 조정 시도(4pt 미만 드래그 2회)가 해제로 오인되지 않게
                    // 선택 내부 더블클릭은 무시하되, 전체를 덮었을 때는 어디든 허용.
                    guard !fullWindow, let r = selectionRect(in: fit) else { return }
                    let coversAll = r.insetBy(dx: -1, dy: -1).contains(fit)
                    guard coversAll || !r.insetBy(dx: -12, dy: -12).contains(location) else {
                        return
                    }
                    areaString = ""
                    dragCurrent = nil
                    dragMode = nil
                    status = "선택 해제 — 드래그로 새 영역을 지정하세요"
                }
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
                Picker("동작 종류", selection: $actionType) {
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
                        TextField("반복 횟수", value: $reps, format: .number)
                            .labelsHidden()
                            .frame(width: 64)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $reps, in: 1...10000, step: 10).labelsHidden()
                        Text("회").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("시작 대기") {
                    HStack(spacing: 4) {
                        TextField("시작 대기(초)", value: $waitSeconds, format: .number)
                            .labelsHidden()
                            .frame(width: 64)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $waitSeconds, in: 0...60, step: 1).labelsHidden()
                        Text("초").foregroundStyle(.secondary)
                    }
                }
                Toggle("캡처 간 딜레이 랜덤 (사람처럼 불규칙하게)", isOn: $randomDelay)
                LabeledContent(randomDelay ? "딜레이 범위" : "딜레이") {
                    HStack(spacing: 4) {
                        TextField("최소 딜레이(초)", value: $delayMin, format: .number)
                            .labelsHidden()
                            .frame(width: 56)
                            .multilineTextAlignment(.trailing)
                        if randomDelay {
                            Text("~").foregroundStyle(.secondary)
                            TextField("최대 딜레이(초)", value: $delayMax, format: .number)
                                .labelsHidden()
                                .frame(width: 56)
                                .multilineTextAlignment(.trailing)
                        }
                        Text("초").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("예상 소요") {
                    Text(etaText(from: reps)).foregroundStyle(.secondary)
                }
                Toggle("끝나면 중복(로딩 중 등 동일 프레임) 자동 정리", isOn: $dedupOnFinish)
                if dedupOnFinish {
                    Text("완전히 같은 프레임의 첫 장만 남기고 나머지는 휴지통으로 이동합니다")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            Section("저장 위치") {
                HStack {
                    TextField("저장 위치", text: $outputBase)
                        .labelsHidden()
                        .font(.caption.monospaced())
                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: outputBase))
                    } label: {
                        Image(systemName: "folder")
                    }
                    .accessibilityLabel("저장 폴더 열기")
                }
                Text("실행할 때마다 01, 02, ... 세션 폴더가 자동 생성됩니다")
                    .font(.caption).foregroundStyle(.tertiary)
                Toggle("완료되면 결과 폴더 열기", isOn: $openFinderOnFinish)
                if openFinderOnFinish {
                    Text("다른 작업 중 포커스를 뺏기기 싫으면 끄세요 (완료음은 항상 울립니다)")
                        .font(.caption).foregroundStyle(.tertiary)
                }
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
                        clickPointString = CGPoint(
                            x: (location.x - fit.minX) * sx, y: (location.y - fit.minY) * sy
                        ).storageString
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
                ProgressView(
                    value: Double(runState.progress), total: Double(max(runState.reps, 1))
                )
                .padding(.horizontal, 16)
                HStack {
                    Text(
                        "\(runState.progress)/\(runState.reps) — 남은 시간 약 \(etaText(from: runState.reps - runState.progress))"
                    )
                    .font(.callout)
                    Button("중지", role: .destructive) { macroTask?.cancel() }
                        .keyboardShortcut(.cancelAction)
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
                    Button {
                        showDuplicates = true
                    } label: {
                        Label("중복 정리", systemImage: "square.on.square.dashed")
                    }
                    .help("방금 매크로를 돌린 세션 폴더의 중복 캡처를 미리보기로 확인하고 삭제합니다")
                }
            }

            // 카운트다운 / 실시간·테스트 캡처 미리보기
            Group {
                if let countdown = runState.countdown {
                    VStack(spacing: 14) {
                        Text("\(countdown)")
                            .font(.system(size: 120, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.snappy, value: countdown)
                            .foregroundStyle(.tint)
                        Text("곧 시작합니다 — 대상 창을 첫 페이지로 준비하세요")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let lastFrame {
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

    /// 핸들 위치: 모서리 4 + 변 중앙 4
    private func handlePoints(of r: CGRect) -> [CGPoint] {
        [
            CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY),
            CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.midY),
            CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.minX, y: r.maxY),
            CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY),
        ]
    }

    /// 드래그 시작점이 기존 선택의 핸들/내부/외부 중 어디인지 판정
    private func hitTest(_ p: CGPoint, fit: CGRect) -> AreaDragMode {
        // Shift+드래그 = 기존 선택 무시하고 항상 새로 그리기
        if NSEvent.modifierFlags.contains(.shift) { return .create }
        guard !fullWindow, let r = selectionRect(in: fit) else { return .create }
        // 작은 선택에서도 내부 move 존이 남도록 톨러런스를 축별로 줄인다
        let tolX = min(10, r.width / 3)
        let tolY = min(10, r.height / 3)
        let dxMin = abs(p.x - r.minX), dxMax = abs(p.x - r.maxX)
        let dyMin = abs(p.y - r.minY), dyMax = abs(p.y - r.maxY)
        let ex: RectEdge? = min(dxMin, dxMax) <= tolX ? (dxMin <= dxMax ? .min : .max) : nil
        let ey: RectEdge? = min(dyMin, dyMax) <= tolY ? (dyMin <= dyMax ? .min : .max) : nil
        let insideX = p.x > r.minX - tolX && p.x < r.maxX + tolX
        let insideY = p.y > r.minY - tolY && p.y < r.maxY + tolY
        if (ex != nil || ey != nil), insideX, insideY { return .resize(r, x: ex, y: ey) }
        if r.contains(p) { return .move(r) }
        return .create
    }

    private func clampPoint(_ p: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(p.x, rect.minX), rect.maxX),
            y: min(max(p.y, rect.minY), rect.maxY))
    }

    /// 영역을 크기 유지한 채 창 중앙으로.
    /// 창 frame이 아니라 캡처 이미지의 실제 불투명 콘텐츠 기준 — 일부 앱(Chrome 등)은
    /// frame보다 좁게 렌더링해 이미지 오른쪽/아래가 투명 패딩이라 frame 중앙이 어긋난다.
    private func centerArea() {
        guard let a = area, previewPointSize != .zero, let img = preview else { return }
        let ptPerPx = previewPointSize.width / CGFloat(img.width)
        let c = opaqueContentRect(of: img)
        let content = CGRect(
            x: c.minX * ptPerPx, y: c.minY * ptPerPx,
            width: c.width * ptPerPx, height: c.height * ptPerPx)
        areaString = CGRect(
            x: max(0, content.minX + (content.width - a.width) / 2),
            y: max(0, content.minY + (content.height - a.height) / 2),
            width: a.width, height: a.height
        ).storageString
        status = "영역을 창 중앙으로 정렬했습니다 — 방향키로 미세 이동 (⇧: 10pt)"
    }

    /// 방향키로 영역 이동 (1pt, ⇧=10pt) — 2단계에서만, 텍스트 필드 편집 중엔 개입 안 함
    private func startNudgeMonitor() {
        guard nudgeMonitor == nil else { return }
        nudgeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !fullWindow, !running, let a = area, previewPointSize != .zero,
                // 필드 편집 중 커서 이동(field editor는 NSTextView)을 방향키가 뺏지 않게
                !(NSApp.keyWindow?.firstResponder is NSTextView)
            else { return event }
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            var dx: CGFloat = 0, dy: CGFloat = 0
            switch event.keyCode {
            case 123: dx = -step  // ←
            case 124: dx = step  // →
            case 125: dy = step  // ↓
            case 126: dy = -step  // ↑
            default: return event
            }
            var r = a.offsetBy(dx: dx, dy: dy)
            r.origin.x = min(max(0, r.origin.x), max(0, previewPointSize.width - r.width))
            r.origin.y = min(max(0, r.origin.y), max(0, previewPointSize.height - r.height))
            areaString = r.storageString
            return nil  // 소비 (스크롤 등으로 새지 않게)
        }
    }

    private func stopNudgeMonitor() {
        if let m = nudgeMonitor {
            NSEvent.removeMonitor(m)
            nudgeMonitor = nil
        }
    }

    /// 중심 고정으로 사방 step(창 포인트)만큼 키우기/줄이기 — 창 경계 클램프
    private func resizeArea(step: CGFloat) {
        guard let a = area, previewPointSize != .zero else { return }
        let r = a.insetBy(dx: -step, dy: -step)
            .intersection(CGRect(origin: .zero, size: previewPointSize))
        guard !r.isNull, r.width >= 1, r.height >= 1 else { return }
        areaString = r.storageString
    }

    private func dragGesture(fit: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($dragActive) { _, state, _ in state = true }
            .onChanged { v in
                if dragMode == nil { dragMode = hitTest(v.startLocation, fit: fit) }
                let t = CGSize(
                    width: v.location.x - v.startLocation.x,
                    height: v.location.y - v.startLocation.y)
                var r: CGRect
                switch dragMode! {
                case .create:
                    // fit 안으로 클램프 — 이미지 밖 드래그로 교집합이 비어 옛 선택이 깜빡이지 않게
                    let a = clampPoint(v.startLocation, to: fit)
                    let b = clampPoint(v.location, to: fit)
                    r = CGRect(
                        x: min(a.x, b.x), y: min(a.y, b.y),
                        width: abs(b.x - a.x), height: abs(b.y - a.y))
                    // 레터박스 여백만 오가는 드래그는 0-크기 sliver — 표시하지 않음
                    if r.width < 1 || r.height < 1 { return }
                case .move(let orig):
                    r = orig.offsetBy(dx: t.width, dy: t.height)
                    // 선택이 fit보다 커도 min/max가 역전되지 않게 상한을 하한 이상으로
                    r.origin.x = min(max(r.origin.x, fit.minX), max(fit.minX, fit.maxX - r.width))
                    r.origin.y = min(max(r.origin.y, fit.minY), max(fit.minY, fit.maxY - r.height))
                case .resize(let orig, let ex, let ey):
                    r = orig
                    if ex == .min {
                        r.origin.x += t.width
                        r.size.width -= t.width
                    } else if ex == .max {
                        r.size.width += t.width
                    }
                    if ey == .min {
                        r.origin.y += t.height
                        r.size.height -= t.height
                    } else if ey == .max {
                        r.size.height += t.height
                    }
                    r = r.standardized  // 반대편을 넘어가면 뒤집기
                }
                r = r.intersection(fit)
                if !r.isNull { dragCurrent = r }
            }
            .onEnded { _ in
                let mode = dragMode
                defer {
                    dragCurrent = nil
                    dragMode = nil
                }
                guard let r = dragCurrent, previewPointSize.width > 0 else { return }
                // 새로 그리기만 실수 방지 최소 크기 적용 — 이동/리사이즈는 그대로 커밋
                if case .create = mode ?? .create, r.width <= 4 || r.height <= 4 { return }
                let sx = previewPointSize.width / fit.width
                let sy = previewPointSize.height / fit.height
                let w = max(1, r.width * sx)
                let h = max(1, r.height * sy)
                areaString = CGRect(
                    // 창 max 변에서 0으로 접힌 리사이즈가 창 밖 좌표로 커밋되지 않게 origin도 클램프
                    x: min((r.minX - fit.minX) * sx, previewPointSize.width - w),
                    y: min((r.minY - fit.minY) * sy, previewPointSize.height - h),
                    width: w, height: h
                ).storageString
                fullWindow = false
                status = "영역 지정 완료 — 드래그로 이동, 핸들로 크기 조절, ⇧드래그로 새로 그리기"
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
        // Cmd+R 연타로 두 루프가 썸네일 상태를 겹쳐 쓰는 것 방지
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        // 권한이 없으면 시스템 프롬프트 요청(최초 1회) 후 전용 빈 상태 뷰로 안내
        guard screenRecordingGranted(requestIfNeeded: true) else {
            screenPermissionDenied = true
            return
        }
        screenPermissionDenied = false
        do {
            let me = ProcessInfo.processInfo.processIdentifier
            let windows = try await captureTargets(dockAppsOnly: true, excludePid: me)
            targets = windows.compactMap { w in
                guard let app = w.owningApplication else { return nil }
                return TargetWindow(
                    id: w.windowID, pid: app.processID,
                    appName: app.applicationName, title: w.title ?? "")
            }
            .sorted { ($0.appName, $0.title) < ($1.appName, $1.title) }
            if selected == nil, let prev = targets.first(where: { $0.appName == savedAppName }) {
                selected = prev
                Task { await capturePreview() }
            }
            // 썸네일은 뒤에서 순차 로드 (그리드가 먼저 뜨고 채워짐). 실패는 nil 값으로 기록.
            for w in windows {
                thumbs.updateValue(try? await captureThumbnail(window: w), forKey: w.windowID)
            }
        } catch {
            status = "오류: \(error)"
        }
    }

    private func select(_ t: TargetWindow) {
        // 다른 앱을 선택하면 이전 앱 창 기준의 영역/클릭 좌표는 무효 (크기가 같아도 다른 UI)
        if t.appName != savedAppName {
            areaString = ""
            clickPointString = ""
            targetSizeString = ""
        }
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
            let sizeInfo =
                "\(selected.appName) — \(Int(window.frame.width))x\(Int(window.frame.height))pt"
            status = windowFallbackNote.map { "\($0). \(sizeInfo)" } ?? sizeInfo
            invalidateStaleCoordinates(for: window.frame.size)
        } catch {
            status = "오류: \(error)"
        }
    }

    /// 저장된 영역/클릭 좌표는 특정 창 크기 기준이다. 다른 크기의 창(다른 앱, 리사이즈된 창)에
    /// 이전 좌표를 조용히 재사용하면 엉뚱한 위치를 클릭하므로 초기화하고 알린다.
    private func invalidateStaleCoordinates(for size: CGSize) {
        let sizeNow = CGPoint(x: size.width, y: size.height).storageString
        defer { targetSizeString = sizeNow }
        guard !targetSizeString.isEmpty, targetSizeString != sizeNow,
            !areaString.isEmpty || !clickPointString.isEmpty
        else { return }
        areaString = ""
        clickPointString = ""
        status = "창 크기가 달라져 이전 캡처 영역/클릭 위치를 초기화했습니다. 다시 지정하세요"
    }

    private func findWindow(_ t: TargetWindow) async throws -> SCWindow {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        if let w = content.windows.first(where: { $0.windowID == t.id }) {
            windowFallbackNote = nil
            return w
        }
        // 창이 닫혔으면 같은 앱의 최대 창으로 폴백 - 조용히 엉뚱한 창을 찍지 않게 상태에 표시
        let fallback = try await frontWindow(ofPid: t.pid)
        windowFallbackNote =
            "주의: 원래 창을 찾지 못해 '\(fallback.title ?? t.appName)' 창으로 전환됨"
        return fallback
    }

    private func testOnce() {
        guard let selected else { return }
        macroTask = Task {
            defer { macroTask = nil }
            do {
                try checkScreenRecording()
                try checkAccessibility(promptUser: true)
                windowFallbackNote = nil
                let window = try await findWindow(selected)
                if let note = windowFallbackNote {
                    // 다른 창으로 테스트를 통과시키면 잘못된 창에 매크로를 돌리게 됨
                    testPassed = false
                    status = "테스트 중단 — \(note). 1단계에서 창을 다시 선택하세요"
                    return
                }
                lastFrame = try await captureImage(
                    window: window, area: fullWindow ? nil : area)
                let method = try Self.sendConfiguredAction(
                    foreground: foregroundMode, actionType: actionType,
                    keyCode: CGKeyCode(keyCode), clickPoint: clickPoint,
                    window: window, pid: selected.pid)
                testPassed = true
                status = "테스트 OK — 캡처 1장 + \(actionLabel) 전송(방식: \(method)). 대상 앱이 실제로 반응했는지 확인하세요"
            } catch {
                testPassed = false
                status = "테스트 실패: \(error)"
            }
        }
    }

    /// 페이지 넘김 동작(키 또는 클릭) 전송. usleep 블로킹 구간이 있어 매크로 루프에서는
    /// detached로 호출한다 (메인에서 돌리면 그 구간 동안 중지 버튼이 무반응).
    private nonisolated static func sendConfiguredAction(
        foreground: Bool, actionType: String, keyCode: CGKeyCode, clickPoint: CGPoint?,
        window: SCWindow, pid: pid_t
    ) throws -> String {
        if foreground {
            ensureFrontmost(pid: pid)
            if actionType == "click" {
                guard let clickPoint else { throw die("클릭 위치가 지정되지 않았습니다 (3단계)") }
                try sendClickGlobal(at: clickPoint, window: window)
                return "전면 클릭"
            }
            try sendKeyGlobal(code: keyCode)
            return "전면 키 입력"
        }
        if actionType == "click" {
            guard let clickPoint else { throw die("클릭 위치가 지정되지 않았습니다 (3단계)") }
            return try sendClick(at: clickPoint, window: window, toPid: pid)
        }
        try sendKey(code: keyCode, toPid: pid)
        return "키 입력"
    }

    private func startMacro() {
        guard let selected else { return }
        // TextField는 Stepper(1...10000)와 달리 0 이하 입력을 막지 않음 - 1...N 범위 크래시 방지
        let repsNow = max(1, reps)
        let waitNow = max(0, waitSeconds)
        let dMin = max(0, delayMin)
        let dMax = randomDelay ? max(dMin, delayMax) : dMin
        let areaNow = fullWindow ? nil : area
        let baseNow = outputBase
        let dedupNow = dedupOnFinish
        let fgNow = foregroundMode
        let actionNow = actionType
        let keyCodeNow = CGKeyCode(keyCode)
        let clickNow = clickPoint
        let pidNow = selected.pid
        runState.error = nil

        let task = Task {
            defer {
                macroTask = nil
                runState.stop = nil
                runState.countdown = nil
                // 오류로 끝났으면 HUD를 오류 상태로 남긴다 - 다른 Space에서 일하던 사용자가
                // 'HUD가 사라짐'만으로는 정상 완료와 실패를 구분할 수 없기 때문
                if runState.error == nil { FloatingHUD.hide() }
            }
            do {
                try checkScreenRecording()
                try checkAccessibility(promptUser: true)
                let sessionDir = try nextSessionDir(base: baseNow)
                lastSessionDir = sessionDir
                lastFrame = nil
                windowFallbackNote = nil
                runState.progress = 0
                runState.reps = repsNow
                FloatingHUD.show()

                for s in stride(from: Int(waitNow), through: 1, by: -1) {
                    if Task.isCancelled { break }
                    runState.countdown = s
                    status = "\(s)초 후 시작 — 대상 창을 첫 페이지로 준비하세요"
                    do { try await Task.sleep(for: .seconds(1)) } catch is CancellationError { break }
                }
                runState.countdown = nil
                for i in 1...repsNow {
                    if Task.isCancelled { break }
                    let window = try await findWindow(selected)
                    // 저장된 영역/클릭 좌표는 미리보기 시점의 창 기준이다. 다른 창(폴백)이나
                    // 다른 크기(리사이즈)에 적용하면 조용히 엉뚱한 위치를 찍으므로 중단한다.
                    if areaNow != nil || actionNow == "click" {
                        if let note = windowFallbackNote {
                            throw die("\(note). 저장된 좌표를 다른 창에 적용할 수 없어 중단합니다")
                        }
                        let sizeNow = CGPoint(x: window.frame.width, y: window.frame.height)
                            .storageString
                        if !targetSizeString.isEmpty, sizeNow != targetSizeString {
                            throw die(
                                "창 크기(\(sizeNow)pt)가 좌표를 지정한 시점(\(targetSizeString)pt)과 다릅니다. 2단계에서 다시 지정하세요")
                        }
                    }
                    let image = try await captureImage(window: window, area: areaNow)
                    let dest = sessionDir.appendingPathComponent(
                        String(format: "screenshot_%03d.png", i))
                    // PNG 인코딩/디스크 쓰기와 usleep 블로킹 전송은 메인 밖에서 (중지 버튼 반응 유지).
                    // 전면 모드의 앱 활성화(activate)는 AppKit 관례대로 메인에서 수행 -
                    // 전면 모드는 어차피 다른 작업이 불가능해 메인 블로킹이 문제되지 않는다.
                    if fgNow {
                        try await Task.detached(priority: .userInitiated) {
                            try savePNG(image, to: dest)
                        }.value
                        _ = try Self.sendConfiguredAction(
                            foreground: true, actionType: actionNow, keyCode: keyCodeNow,
                            clickPoint: clickNow, window: window, pid: pidNow)
                    } else {
                        try await Task.detached(priority: .userInitiated) {
                            try savePNG(image, to: dest)
                            _ = try Self.sendConfiguredAction(
                                foreground: false, actionType: actionNow, keyCode: keyCodeNow,
                                clickPoint: clickNow, window: window, pid: pidNow)
                        }.value
                    }
                    lastFrame = image
                    runState.progress = i
                    status = windowFallbackNote ?? "진행 중 — 다른 작업을 하셔도 됩니다"
                    if i < repsNow {
                        // 중지가 이 대기 중 걸려도 CancellationError로 catch에 빠지지 않고
                        // 아래 자동 중복 정리/세션 경로 status까지 정상 수행 (main의 #4와 동일 취지)
                        do {
                            try await Task.sleep(for: .seconds(Double.random(in: dMin...dMax)))
                        } catch is CancellationError { break }
                    }
                }
                let removed = dedupNow ? pruneDuplicates(in: sessionDir) : 0
                let kept = runState.progress - removed
                let dedupNote = removed > 0 ? " (중복 \(removed)장 휴지통 이동, \(kept)장 유지)" : ""
                if Task.isCancelled {
                    status = "중지됨 — \(runState.progress)장 저장\(dedupNote): \(sessionDir.path)"
                } else {
                    status = "완료 — \(runState.progress)장 저장\(dedupNote): \(sessionDir.path)"
                    NSSound(named: "Glass")?.play()
                    if openFinderOnFinish { NSWorkspace.shared.open(sessionDir) }
                }
            } catch is CancellationError {
                status = "중지됨 (\(runState.progress)장 저장됨)"
            } catch {
                let msg = "오류 (\(runState.progress)장까지 저장됨): \(error)"
                status = msg
                runState.error = msg
                NSSound(named: "Basso")?.play()
            }
        }
        macroTask = task
        runState.stop = { task.cancel() }  // 뷰 전체가 아니라 task만 캡처
    }

    /// 세션 폴더에서 바이트 완전 동일한(로딩 중 등으로 같은) 프레임의 첫 장만 남기고
    /// 나머지를 휴지통으로 이동. 반환은 이동한 장수. 실패는 무시하고 진행.
    private func pruneDuplicates(in dir: URL) -> Int {
        let fm = FileManager.default
        let files =
            (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "png" } ?? []
        var removed = 0
        for group in duplicateGroups(in: files) {
            for url in group.dropFirst() where (try? fm.trashItem(at: url, resultingItemURL: nil)) != nil {
                removed += 1
            }
        }
        return removed
    }

    private func etaText(from remaining: Int) -> String {
        let dMin = max(0, delayMin)
        let avg = (randomDelay ? (dMin + max(dMin, delayMax)) / 2 : dMin) + 0.4  // +캡처 시간
        let total = Int(Double(max(0, remaining)) * avg)
        return total >= 60 ? "\(total / 60)분 \(total % 60)초" : "\(total)초"
    }

    // MARK: - 중복 정리 시트 (본체는 DuplicatesSheet.swift)

    /// 중복 정리가 스캔할 폴더: 이번 실행의 세션 폴더가 있으면 그걸, 없으면(앱 재실행 등)
    /// outputBase 아래 가장 최근(최고 번호) 세션 폴더, 그것도 없으면 base 자체.
    private func latestSessionDir() -> URL {
        if let lastSessionDir { return lastSessionDir }
        let base = URL(fileURLWithPath: outputBase)
        let subs =
            (try? FileManager.default.contentsOfDirectory(
                at: base, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        let sessions = subs.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                && Int($0.lastPathComponent) != nil
        }
        return sessions.max { (Int($0.lastPathComponent) ?? 0) < (Int($1.lastPathComponent) ?? 0) }
            ?? base
    }
}

// MARK: - 플로팅 HUD (모든 Space·전체화면 위에 뜨는 실행 중 미니 패널)

/// 실행 중 상태의 단일 소스 - 메인 창(ContentView)과 플로팅 HUD가 함께 관찰한다
final class RunState: ObservableObject {
    static let shared = RunState()
    @Published var progress = 0
    @Published var reps = 0
    @Published var countdown: Int?
    @Published var error: String?  // 설정되면 defer가 HUD를 닫지 않고 오류 상태로 남긴다
    var stop: (() -> Void)?
}

struct HUDView: View {
    @ObservedObject var state = RunState.shared

    var body: some View {
        HStack(spacing: 10) {
            if let error = state.error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
                Text(error)
                    .font(.caption).lineLimit(1).truncationMode(.tail)
                    .help(error)
                Button {
                    state.error = nil
                    FloatingHUD.hide()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("오류 닫기")
            } else {
                Image(systemName: "camera.fill").font(.caption).foregroundStyle(.secondary)
                if let s = state.countdown {
                    Text("\(s)초 후 시작")
                        .font(.caption.monospacedDigit())
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ProgressView(value: Double(state.progress), total: Double(max(state.reps, 1)))
                        .frame(width: 110)
                    Text("\(state.progress)/\(state.reps)")
                        .font(.caption.monospacedDigit())
                }
                Button {
                    state.stop?()
                } label: {
                    Image(systemName: "stop.fill").foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("매크로 중지")
                .accessibilityLabel("매크로 중지")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
    }
}

@MainActor
enum FloatingHUD {
    static var panel: NSPanel?

    static func show() {
        guard panel == nil else { return }
        let host = NSHostingView(rootView: HUDView())
        host.frame = NSRect(x: 0, y: 0, width: 280, height: 34)
        let p = NSPanel(
            contentRect: host.frame,
            styleMask: [.nonactivatingPanel, .utilityWindow, .titled, .fullSizeContentView],
            backing: .buffered, defer: false)
        p.contentView = host
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.level = .floating
        // 모든 Space에 따라다니고 전체화면 Space 위에도 표시
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = true
        p.hidesOnDeactivate = false
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.maxX - 300, y: f.maxY - 54))
        }
        p.orderFrontRegardless()
        panel = p
    }

    static func hide() {
        panel?.close()
        panel = nil
    }
}
