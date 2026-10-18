import XCTest
@testable import VinesKit

final class VinesConfigTests: XCTestCase {
    func testSpacingAndOverlapOpacityDecodeAndClamp() throws {
        let pack = try JSONDecoder().decode(
            VinePack.self,
            from: Data(#"{"id":"test","spacing":0.14,"overlapOpacity":0.62}"#.utf8)
        )
        XCTAssertEqual(pack.spacing, 0.14)
        XCTAssertEqual(pack.overlapOpacity, 0.62)

        let clamped = try JSONDecoder().decode(
            VinePack.self,
            from: Data(#"{"id":"test","spacing":-1,"overlapOpacity":2}"#.utf8)
        )
        XCTAssertEqual(clamped.spacing, 0.03)
        XCTAssertEqual(clamped.overlapOpacity, 1)
    }
}
