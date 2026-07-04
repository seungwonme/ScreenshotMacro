// smacro-gui: 중복 캡처 정리 시트. 바이트 완전 동일(SHA256) 그룹을 미리보기로 보여주고
// 그룹당 첫 장만 남기고 선택분을 휴지통으로 이동한다. ContentView 위저드와 독립.

import AppKit
import SMacroCore
import SwiftUI

struct DuplicatesSheetView: View {
    let initialDir: URL

    @Environment(\.dismiss) private var dismiss
    @State private var scanDir: URL?
    @State private var groups: [[URL]] = []
    @State private var selected: Set<URL> = []  // 삭제할 파일들 (전체 선택이 기본)
    @State private var thumbs: [URL: CGImage] = [:]
    @State private var statusText = ""
    @State private var scanError: String?
    @State private var scanning = false

    /// 각 그룹에서 첫 장(유지)을 뺀 나머지 = 삭제 가능한 중복들
    private var deletable: [URL] { groups.flatMap { $0.dropFirst() } }

    private var allSelected: Bool {
        !deletable.isEmpty && selected.count == deletable.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("중복 캡처 정리").font(.headline)
                    Text(scanDir?.path ?? "")
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button { pickFolder() } label: {
                    Label("폴더 선택", systemImage: "folder")
                }
            }
            .padding(12)
            Divider()

            if scanning {
                ProgressView("중복 스캔 중...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groups.isEmpty {
                Group {
                    if let scanError {
                        ContentUnavailableView(
                            "폴더를 읽을 수 없음", systemImage: "exclamationmark.triangle",
                            description: Text(scanError))
                    } else {
                        ContentUnavailableView(
                            "중복 없음", systemImage: "checkmark.circle",
                            description: Text("이 폴더에는 바이트가 완전히 동일한 중복 캡처가 없습니다."))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 10) {
                    Button(allSelected ? "전체 해제" : "전체 선택") { toggleSelectAll() }
                    Text(
                        "\(groups.count)개 그룹 · 중복 \(deletable.count)장 · 선택 \(selected.count)장"
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(groups.enumerated()), id: \.offset) { idx, group in
                            groupRow(idx: idx, group: group)
                        }
                    }
                    .padding(12)
                }
            }

            Divider()
            HStack {
                if !statusText.isEmpty {
                    Text(statusText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("닫기") { dismiss() }
                Button(role: .destructive) {
                    deleteSelected()
                } label: {
                    Label("선택 \(selected.count)장 삭제", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty)
            }
            .padding(12)
        }
        // 메인 창 최소 높이(600)보다 작게 - 시트가 부모 창을 넘지 않게
        .frame(width: 760, height: 560)
        .task { await scan(initialDir) }
    }

    private func groupRow(idx: Int, group: [URL]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("동일 그룹 #\(idx + 1) · \(group.count)장").font(.subheadline.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(group.enumerated()), id: \.offset) { i, url in
                        thumbCell(url: url, isKeep: i == 0)
                    }
                }
            }
        }
    }

    private func thumbCell(url: URL, isKeep: Bool) -> some View {
        let isSelected = selected.contains(url)
        return Button {
            guard !isKeep else { return }  // 유지 이미지는 선택 대상 아님
            if isSelected { selected.remove(url) } else { selected.insert(url) }
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topLeading) {
                    Group {
                        if let img = thumbs[url] {
                            Image(img, scale: 1, label: Text(url.lastPathComponent))
                                .resizable().scaledToFit()
                        } else {
                            RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5))
                                .overlay(ProgressView().controlSize(.small))
                        }
                    }
                    .frame(width: 150, height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6).stroke(
                            isKeep
                                ? Color.green
                                : (isSelected ? Color.accentColor : Color.secondary.opacity(0.3)),
                            lineWidth: (isKeep || isSelected) ? 2 : 1))
                    if isKeep {
                        Text("유지")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(.green))
                            .foregroundStyle(.white).padding(6)
                    } else {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                            .background(Circle().fill(.white).padding(3))
                            .padding(6)
                    }
                }
                Text(url.lastPathComponent)
                    .font(.caption2.monospaced()).lineLimit(1).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(url.lastPathComponent)\(isKeep ? ", 유지" : (isSelected ? ", 삭제 선택됨" : ""))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Actions

    private func scan(_ dir: URL) async {
        scanDir = dir
        statusText = ""
        scanning = true
        // 수천 장의 SHA256 해싱이 메인 스레드를 막지 않게 밖에서 수행
        let result: Result<[[URL]], Error> = await Task.detached(priority: .userInitiated) {
            Result { duplicateGroups(in: try collectPNGs(in: dir.path)) }
        }.value
        // 해싱 중 다른 폴더 스캔이 시작됐으면 이 결과는 폐기 (늦게 끝난 쪽이 UI를 덮어쓰는 것 방지)
        guard scanDir == dir else { return }
        scanning = false
        switch result {
        case .success(let g):
            groups = g
            scanError = nil
        case .failure(let e):
            // 폴더가 없으면 '중복 없음'으로 오표기하지 않고 오류를 그대로 보여준다
            groups = []
            scanError = "\(e)"
        }
        selected = Set(deletable)  // 전체 선택이 기본 ON
        await loadThumbs()  // groups가 채워진 뒤에 로드 (task(id:)는 스캔 완료를 알 수 없음)
    }

    private func toggleSelectAll() {
        selected = allSelected ? [] : Set(deletable)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = scanDir ?? initialDir
        if panel.runModal() == .OK, let url = panel.url {
            Task { await scan(url) }
        }
    }

    /// 썸네일은 원본 풀해상도 대신 축소본을 메인 밖에서 디코드해 UI 잔렉을 피한다.
    private func loadThumbs() async {
        let urls = groups.flatMap { $0 }.filter { thumbs[$0] == nil }
        for url in urls {
            let img = await Task.detached(priority: .userInitiated) {
                fileThumbnail(at: url)
            }.value
            thumbs[url] = img
        }
    }

    private func deleteSelected() {
        let toDelete = selected
        selected = []  // 즉시 버튼 비활성화 (완료 전 이중 클릭 방지, 실패분은 아래서 복원)
        Task {
            // 휴지통 이동(파일 수백 개 가능)은 메인 밖에서
            let outcome: (trashed: Set<URL>, failed: Int) = await Task.detached(
                priority: .userInitiated
            ) {
                var ok = Set<URL>()
                var failed = 0
                for url in toDelete {
                    do {
                        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                        ok.insert(url)
                    } catch {
                        failed += 1
                    }
                }
                return (ok, failed)
            }.value
            // 중복 구조는 이미 알고 있으므로 전체 재해싱 대신 메모리에서 정리
            groups = groups.map { $0.filter { !outcome.trashed.contains($0) } }
                .filter { $0.count > 1 }
            selected = toDelete.subtracting(outcome.trashed)  // 실패분만 선택 복원
            statusText =
                "\(outcome.trashed.count)장 휴지통으로 이동 (복구 가능)"
                + (outcome.failed > 0 ? " · 실패 \(outcome.failed)장" : "")
        }
    }
}
