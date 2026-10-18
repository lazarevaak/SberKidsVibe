//
//  VisitLimiterTests.swift
//  MascotKitTests
//

import XCTest
@testable import MascotKit

final class VisitLimiterTests: XCTestCase {
    @MainActor
    private func tapReaction() throws -> MascotReaction {
        let json = """
        { "say": [ "Хи-хи!",
                   { "text": "А ты видел новую цель в Копилках?", "maxPerVisit": 3, "first": true } ] }
        """
        return try JSONDecoder().decode(MascotReaction.self, from: Data(json.utf8))
    }

    @MainActor
    func testGuaranteedLineThreeTimesPerVisitThenResets() throws {
        let reaction = try tapReaction()
        var limiter = VisitLimiter()
        let say = { (limiter: inout VisitLimiter) in limiter.pickLine(for: "tap", in: reaction, roll: { 0 }) }

        for _ in 0..<3 {
            let pick = try XCTUnwrap(say(&limiter))
            XCTAssertEqual(pick.line.text, "А ты видел новую цель в Копилках?")
            XCTAssertTrue(pick.guaranteed)
        }
        let fourth = try XCTUnwrap(say(&limiter))
        XCTAssertEqual(fourth.line.text, "Хи-хи!")
        XCTAssertFalse(fourth.guaranteed)

        limiter.reset()
        XCTAssertEqual(say(&limiter)?.line.text, "А ты видел новую цель в Копилках?")
    }

    @MainActor
    func testGuaranteedLineIgnoresSayChance() throws {
        var reaction = try tapReaction()
        reaction.sayChance = 0
        var limiter = VisitLimiter()
        XCTAssertEqual(limiter.pickLine(for: "tap", in: reaction, roll: { 0.99 })?.guaranteed, true)
    }

    @MainActor
    func testRegularLinesRespectSayChance() throws {
        var reaction = try JSONDecoder().decode(MascotReaction.self, from: Data(#"{ "say": ["Хи-хи!"] }"#.utf8))
        reaction.sayChance = 0.3
        var limiter = VisitLimiter()
        XCTAssertNil(limiter.pickLine(for: "tap", in: reaction, roll: { 0.5 }))
        XCTAssertNotNil(limiter.pickLine(for: "tap", in: reaction, roll: { 0.1 }))
    }

    @MainActor
    func testReactionLimitPerVisit() throws {
        let reaction = try JSONDecoder().decode(MascotReaction.self, from: Data(#"{ "maxPerVisit": 2 }"#.utf8))
        var limiter = VisitLimiter()
        XCTAssertTrue(limiter.allow("shake", reaction))
        XCTAssertTrue(limiter.allow("shake", reaction))
        XCTAssertFalse(limiter.allow("shake", reaction))
        limiter.reset()
        XCTAssertTrue(limiter.allow("shake", reaction))
    }
}
