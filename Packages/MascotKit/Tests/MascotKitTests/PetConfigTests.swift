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
        // Звук добавился, техническая пауза из кода осталась; реплик в коде нет.
        XCTAssertEqual(tilt.sound, ["slide.wav"])
        XCTAssertNil(tilt.say)
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
    func testBubbleStyleIsConfigurableAndClamped() throws {
        let custom = try decode("""
        { "bubble": { "fontSize": 16, "maxWidth": 260, "maxLines": 4, "background": "#FFF4D6" } }
        """)
        XCTAssertEqual(custom.bubble.fontSize, 16)
        XCTAssertEqual(custom.bubble.maxWidth, 260)
        XCTAssertEqual(custom.bubble.maxLines, 4)
        XCTAssertEqual(custom.bubble.background, "#FFF4D6")
        XCTAssertEqual(custom.bubble.duration, 2.4, "не указано — по умолчанию")
        XCTAssertEqual(custom.bubble.opacity, 0.5)
        XCTAssertFalse(custom.bubble.blur)

        // Опечатка в конфиге не должна закрыть пол-экрана.
        let wild = try decode(#"{ "bubble": { "fontSize": 80, "maxWidth": 5000, "maxLines": 0 } }"#)
        XCTAssertEqual(wild.bubble.fontSize, 24)
        XCTAssertEqual(wild.bubble.maxWidth, 320)
        XCTAssertEqual(wild.bubble.maxLines, 1)

        let solid = try decode(#"{ "bubble": { "opacity": 0, "blur": false } }"#)
        XCTAssertEqual(solid.bubble.opacity, 0.2, "совсем прозрачный фон — нечитаемо, ограничиваем")
        XCTAssertFalse(solid.bubble.blur)
    }

    @MainActor
    func testNoContentIsBuiltIn() throws {
        let config = try decode("{}")
        XCTAssertTrue(config.enabled)
        // Весь контент — только из конфига: в коде нет ни реплик, ни звуков, ни персонажей.
        XCTAssertTrue(config.reactions.values.allSatisfy { $0.say == nil && $0.sound == nil })
        XCTAssertTrue(config.characters.isEmpty)
    }
}
