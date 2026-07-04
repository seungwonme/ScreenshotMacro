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
