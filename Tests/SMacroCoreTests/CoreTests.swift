// SMacroCore 단위 테스트 - TCC 권한이 필요 없는 순수 로직만 (캡처/입력 E2E는
// scripts/validate-swift-proto.sh, pre-push 훅이 권한 있는 터미널에서 자동 실행).

import XCTest

@testable import SMacroCore

final class CoreTests: XCTestCase {
    // MARK: - 좌표 문자열 직렬화

    func testRectStorageRoundTrip() {
        let r = CGRect(x: 10, y: 20, width: 300, height: 400)
        XCTAssertEqual(CGRect(storageString: r.storageString), r)
    }

    func testRectStorageRejectsInvalid() {
        XCTAssertNil(CGRect(storageString: ""))
        XCTAssertNil(CGRect(storageString: "1,2,3"))
        XCTAssertNil(CGRect(storageString: "1,2,0,4"))  // 폭 0
        XCTAssertNil(CGRect(storageString: "1,2,3,-4"))  // 음수 높이
        XCTAssertNil(CGRect(storageString: "a,b,c,d"))
    }

    func testPointStorageRoundTrip() {
        let p = CGPoint(x: 5, y: 7)
        XCTAssertEqual(CGPoint(storageString: p.storageString), p)
        XCTAssertNil(CGPoint(storageString: ""))
        XCTAssertNil(CGPoint(storageString: "5"))
        XCTAssertNil(CGPoint(storageString: "5,6,7"))
    }

    // MARK: - 중복 탐지 (파일 바이트 SHA256)

    func testFileHashAndDuplicateGroups() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let a = dir.appendingPathComponent("a.png")
        let b = dir.appendingPathComponent("b.png")
        let c = dir.appendingPathComponent("c.png")
        try Data([1, 2, 3]).write(to: a)
        try Data([1, 2, 3]).write(to: b)
        try Data([9, 9, 9]).write(to: c)

        XCTAssertEqual(fileHash(at: a), fileHash(at: b))
        XCTAssertNotEqual(fileHash(at: a), fileHash(at: c))
        XCTAssertNil(fileHash(at: dir.appendingPathComponent("none.png")))

        let groups = duplicateGroups(in: try collectPNGs(in: dir.path))
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].map(\.lastPathComponent), ["a.png", "b.png"])
    }

    func testCollectPNGsMissingDirThrows() {
        XCTAssertThrowsError(try collectPNGs(in: "/nonexistent/smacro-none"))
    }

    func testCollectPNGsRecursiveAndSorted() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let sub = dir.appendingPathComponent("01")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data([1]).write(to: sub.appendingPathComponent("b.png"))
        try Data([2]).write(to: dir.appendingPathComponent("a.PNG"))  // 대문자 확장자
        try Data([3]).write(to: dir.appendingPathComponent("skip.txt"))

        let names = try collectPNGs(in: dir.path).map(\.lastPathComponent)
        XCTAssertEqual(names.sorted(), ["a.PNG", "b.png"])
    }

    // MARK: - 세션 디렉토리 번호

    func testNextSessionDirNumbering() throws {
        let base = try makeTempDir().path
        defer { try? FileManager.default.removeItem(atPath: base) }

        XCTAssertEqual(try nextSessionDir(base: base).lastPathComponent, "01")
        XCTAssertEqual(try nextSessionDir(base: base).lastPathComponent, "02")
    }

    // MARK: - 불투명 콘텐츠 영역 (창 frame보다 좁게 렌더링된 캡처의 투명 패딩 탐지)

    func testOpaqueContentRectDetectsRightPadding() throws {
        // 400x200 중 왼쪽 300px만 불투명 (오른쪽 100px 투명 패딩 — Chrome 캡처 재현)
        let img = try makeImage(width: 400, height: 200, opaque: CGRect(x: 0, y: 0, width: 300, height: 200))
        let r = opaqueContentRect(of: img)
        XCTAssertEqual(r.minX, 0, accuracy: 4)
        XCTAssertEqual(r.width, 300, accuracy: 4)
        XCTAssertEqual(r.height, 200, accuracy: 4)
    }

    func testOpaqueContentRectFullWhenNoPadding() throws {
        let img = try makeImage(width: 100, height: 50, opaque: CGRect(x: 0, y: 0, width: 100, height: 50))
        XCTAssertEqual(opaqueContentRect(of: img), CGRect(x: 0, y: 0, width: 100, height: 50))
    }

    func testOpaqueContentRectAllTransparentReturnsFull() throws {
        let img = try makeImage(width: 100, height: 50, opaque: .zero)
        XCTAssertEqual(opaqueContentRect(of: img), CGRect(x: 0, y: 0, width: 100, height: 50))
    }

    func testOpaqueContentRectTopLeftOrigin() throws {
        // 위쪽 절반만 불투명 — y 원점이 좌상단인지 검증 (CG 좌표 뒤집힘 회귀 방지)
        let img = try makeImage(width: 100, height: 100, opaque: CGRect(x: 0, y: 0, width: 100, height: 50))
        let r = opaqueContentRect(of: img)
        XCTAssertEqual(r.minY, 0, accuracy: 4)
        XCTAssertEqual(r.height, 50, accuracy: 4)
    }

    // MARK: - 안티 패턴 매칭

    func testAntiPatternMatching() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let teal = CGColor(red: 0.35, green: 0.78, blue: 0.75, alpha: 1)
        let dark = CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)

        // 기준: 흰 배경 중앙에 원형 아이콘 (전자책 뷰어 로딩 화면 형태)
        let pattern = dir.appendingPathComponent("pattern.png")
        try writePage(to: pattern) { ctx, w, h in
            ctx.setFillColor(teal)
            ctx.fillEllipse(in: CGRect(x: w / 2 - 40, y: h / 2 - 40, width: 80, height: 80))
        }
        // 같은 로딩 화면의 재등장 (렌더링 미세 차이로 해시는 다른 별개 캡처)
        let loading = dir.appendingPathComponent("loading.png")
        try writePage(to: loading) { ctx, w, h in
            ctx.setFillColor(CGColor(gray: 0.99, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.setFillColor(teal)
            ctx.fillEllipse(in: CGRect(x: w / 2 - 40, y: h / 2 - 40, width: 80, height: 80))
        }
        // 여백 많은 실제 페이지 (짧은 텍스트) - 삭제되면 안 됨
        let sparse = dir.appendingPathComponent("sparse.png")
        try writePage(to: sparse) { ctx, _, _ in
            ctx.setFillColor(dark)
            for row in 0..<3 {
                ctx.fill(CGRect(x: 40, y: 60 + row * 24, width: 240, height: 10))
            }
        }

        let files = [loading, sparse]
        XCTAssertEqual(antiPatternMatches(in: files, patterns: [pattern]), [loading])
        XCTAssertTrue(antiPatternMatches(in: files, patterns: []).isEmpty, "기준 없으면 매칭 없음")
    }

    func testAntiPatternLowContrastIconVsSparsePage() throws {
        // 실측 회귀: 연회색 아이콘 로딩 화면은 전역 평균으로는 여백 많은 실제 페이지와
        // 구분이 안 된다 - 블록 최댓값 지표가 실제 페이지의 국소 텍스트를 잡아내야 한다.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let faint = CGColor(gray: 0.92, alpha: 1)

        let pattern = dir.appendingPathComponent("pattern.png")
        try writePage(to: pattern) { ctx, w, h in
            ctx.setFillColor(faint)
            ctx.fill(CGRect(x: w / 2 - 30, y: h / 2 - 30, width: 60, height: 60))
        }
        // 거의 빈 실제 페이지: 작은 제목 텍스트 한 줄 - 삭제되면 안 됨
        let titlePage = dir.appendingPathComponent("title.png")
        try writePage(to: titlePage) { ctx, w, _ in
            ctx.setFillColor(CGColor(gray: 0.2, alpha: 1))
            ctx.fill(CGRect(x: w / 2 - 50, y: 120, width: 100, height: 8))
        }

        XCTAssertTrue(antiPatternMatches(in: [titlePage], patterns: [pattern]).isEmpty)
    }

    func testMaxBlockRMS() {
        let n = 64 * 80
        let blank = [UInt8](repeating: 255, count: n)
        XCTAssertEqual(maxBlockRMS(blank, blank), 0)
        // 한 블록(8x8)만 완전히 다름 -> 전역 평균이면 255*sqrt(64/5120)=28.5지만 블록 최댓값은 255
        var oneBlock = blank
        for y in 0..<8 { for x in 0..<8 { oneBlock[y * 64 + x] = 0 } }
        XCTAssertEqual(maxBlockRMS(blank, oneBlock), 255)
        XCTAssertEqual(maxBlockRMS(blank, [0]), .infinity)  // 길이 불일치
    }

    // MARK: - 키 테이블

    func testKeyCodesContainDocumentedKeys() {
        // README에 문서화된 지원 키 8종
        for key in ["right", "left", "up", "down", "space", "return", "pageup", "pagedown"] {
            XCTAssertNotNil(keyCodes[key], "keyCodes에 '\(key)' 누락")
        }
    }

    // MARK: - helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("smacro-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 흰 배경 320x400 페이지를 그려 PNG로 저장 (안티 패턴 테스트용)
    private func writePage(to url: URL, draw: (CGContext, Int, Int) -> Void) throws {
        let w = 320
        let h = 400
        let ctx = try XCTUnwrap(
            CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        draw(ctx, w, h)
        try savePNG(try XCTUnwrap(ctx.makeImage()), to: url)
    }

    /// opaque 영역(좌상단 원점 픽셀 좌표)만 흰색, 나머지는 투명한 테스트 이미지
    private func makeImage(width: Int, height: Int, opaque: CGRect) throws -> CGImage {
        let ctx = try XCTUnwrap(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        if !opaque.isEmpty {
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            // CGContext는 y-상향 좌표 — 좌상단 원점 입력을 뒤집어 채운다
            ctx.fill(
                CGRect(
                    x: opaque.minX, y: CGFloat(height) - opaque.maxY,
                    width: opaque.width, height: opaque.height))
        }
        return try XCTUnwrap(ctx.makeImage())
    }
}
