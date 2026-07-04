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
}
