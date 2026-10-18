//
//  CDNWorkerTests.swift
//  VinesKitTests
//

import XCTest
@testable import VinesKit

nonisolated private struct WorkerProbe: Decodable, Sendable {
    let decodedOffMain: Bool
    init(from decoder: Decoder) throws {
        decodedOffMain = !Thread.isMainThread
    }
}

final class CDNWorkerTests: XCTestCase {
    @MainActor
    func testLocalConfigIsReadAndDecodedOutsideMainActor() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try Data("{}".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let result = await CDNContent.load(WorkerProbe.self, file: url.absoluteString)
        XCTAssertTrue(try XCTUnwrap(result?.0).decodedOffMain)
        XCTAssertEqual(result?.1, url)
    }
}
