//
//  MascotConfigValidatorTests.swift
//  MascotKitTests
//

import XCTest
@testable import MascotKit

final class MascotConfigValidatorTests: XCTestCase {
    @MainActor
    private func config(_ json: String) throws -> MascotConfig {
        try JSONDecoder().decode(MascotConfig.self, from: Data(json.utf8))
    }

    @MainActor
    private func rig(_ json: String) throws -> CharacterRig {
        try JSONDecoder().decode(CharacterRig.self, from: Data(json.utf8))
    }

    @MainActor
    private func warnings(_ issues: [MascotConfigIssue]) -> [String] {
        issues.filter { $0.level == .warning }.map(\.message)
    }

    @MainActor
    func testCleanConfigHasNoWarnings() throws {
        let cfg = try config("""
        { "reactions": { "tap": { "say": ["Хи-хи!"], "animation": "party" }, "land": { "animation": "wave" } },
          "behaviors": { "party": 0.3 },
          "characters": [ { "id": "monkey", "path": "m.json" } ], "forceCharacter": "monkey" }
        """)
        let character = try rig("""
        { "size": [64, 72], "animations": { "party": { "duration": 2 } },
          "parts": [ { "id": "arm", "image": "arm.png", "size": [5, 19], "at": [20, 43],
                       "motion": { "walk": { "swing": 25 }, "party": { "rotate": 160 } } } ] }
        """)
        XCTAssertEqual(warnings(MascotConfigValidator.check(cfg, character: character, characterID: "monkey")), [])
    }

    @MainActor
    func testTyposAreReported() throws {
        let cfg = try config("""
        { "reactions": { "tap": { "animation": "paty" } },
          "behaviors": { "dnace": 1 },
          "forceCharacter": "dragon", "forceSkin": "winter",
          "triggers": { "avatar": { "gesture": "doubletap", "action": "summmon" } } }
        """)
        let character = try rig("""
        { "size": [64, 72],
          "animations": { "party": { "expression": "joy", "effect": "confetti" } },
          "parts": [ { "id": "leg", "image": "leg.png", "size": [6, 12], "at": [26, 61],
                       "motion": { "wlak": { "swing": 30 } } } ] }
        """)
        let found = warnings(MascotConfigValidator.check(cfg, character: character, characterID: "snowman"))
        let expected = ["«paty»", "«dnace»", "«dragon»", "«winter»", "«doubletap»", "«summmon»", "«wlak»", "«joy»", "«confetti»"]
        for word in expected {
            XCTAssertTrue(found.contains { $0.contains(word) }, "нет предупреждения про \(word)")
        }
        XCTAssertTrue(found.contains { $0.contains("«paty»") && $0.contains("«snowman»") }, "в сообщении должен быть персонаж")
    }

    @MainActor
    func testCustomEventIsInfoNotWarning() throws {
        let cfg = try config(#"{ "reactions": { "secret": { "say": ["Тайник!"] } } }"#)
        let issues = MascotConfigValidator.check(cfg, character: nil, characterID: nil)
        XCTAssertTrue(warnings(issues).isEmpty)
        XCTAssertTrue(issues.contains { $0.level == .info && $0.message.contains("«secret»") })
    }

    @MainActor
    func testMissingExpressionImagesAreInfo() throws {
        let character = try rig("""
        { "size": [10, 10], "parts": [ { "id": "eyes", "images": { "normal": "e.png", "happy": "h.png" },
                                         "size": [5, 5], "at": [5, 5] } ] }
        """)
        let issues = MascotConfigValidator.check(try config("{}"), character: character, characterID: "car")
        XCTAssertTrue(warnings(issues).isEmpty)
        XCTAssertTrue(issues.contains { $0.level == .info && $0.message.contains("sleepy") })
    }
}
