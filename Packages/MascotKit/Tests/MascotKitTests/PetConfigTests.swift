//
//  PetConfigTests.swift
//  MascotKitTests
//

import XCTest
@testable import MascotKit

final class PetConfigTests: XCTestCase {
    @MainActor
    private func decode(_ json: String) throws -> PetConfig {
        try JSONDecoder().decode(PetConfig.self, from: Data(json.utf8))
    }

    @MainActor
    func testLineDecodesFromStringAndObject() throws {
        let config = try decode("""
        { "reactions": { "tap": { "say": [
            "Хи-хи!",
            { "text": "А ты видел новую цель?", "maxPerVisit": 3, "first": true, "duration": 5 }
        ] } } }
        """)
        let lines = try XCTUnwrap(config.reactions["tap"]?.say)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].text, "Хи-хи!")
        XCTAssertNil(lines[0].maxPerVisit)
        XCTAssertEqual(lines[1].maxPerVisit, 3)
        XCTAssertEqual(lines[1].first, true)
        XCTAssertEqual(lines[1].duration, 5)
    }

    @MainActor
    func testReactionsOverrideOnlyGivenFields() throws {
        let config = try decode("""
        { "reactions": { "tilt": { "sound": ["slide.wav"] } } }
        """)
        let tilt = try XCTUnwrap(config.reactions["tilt"])
        // Звук добавился, встроенные реплики и пауза остались.
        XCTAssertEqual(tilt.sound, ["slide.wav"])
        XCTAssertEqual(tilt.say?.first?.text, "Скользко!")
        XCTAssertEqual(tilt.cooldown, 4)
    }

    @MainActor
    func testLegacyFieldsStillWork() throws {
        let config = try decode("""
        { "phrases": { "tap": ["Старая реплика"] },
          "sounds": { "volume": 0.3, "tap": ["tap.wav"] } }
        """)
        XCTAssertEqual(config.reactions["tap"]?.say?.map(\.text), ["Старая реплика"])
        XCTAssertEqual(config.reactions["tap"]?.sound, ["tap.wav"])
        XCTAssertEqual(config.sounds.volume, 0.3)
        XCTAssertEqual(config.soundClips["tap"], ["tap.wav"])
    }

    @MainActor
    func testReactionsWinOverLegacyFields() throws {
        let config = try decode("""
        { "phrases": { "tap": ["Старая"] },
          "reactions": { "tap": { "say": ["Новая"], "maxPerVisit": 2 } } }
        """)
        XCTAssertEqual(config.reactions["tap"]?.say?.map(\.text), ["Новая"])
        XCTAssertEqual(config.reactions["tap"]?.maxPerVisit, 2)
    }

    @MainActor
    func testCustomEventFromConfig() throws {
        let config = try decode("""
        { "reactions": { "secret": { "say": ["Тайник!"], "animation": "dance" } } }
        """)
        XCTAssertEqual(config.reactions["secret"]?.animation, "dance")
        XCTAssertEqual(MascotAction("react:secret"), .react("secret"))
        XCTAssertEqual(MascotAction("say:secret"), .react("secret"))
    }

    @MainActor
    func testBrokenOptionalFieldsFallBackToDefaults() throws {
        let config = try decode("{}")
        XCTAssertTrue(config.enabled)
        XCTAssertEqual(config.reactions["hello"]?.say?.isEmpty, false)
    }
}
