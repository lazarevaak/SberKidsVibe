//
//  CharacterRigTests.swift
//  MascotKitTests
//

import XCTest
@testable import MascotKit

final class CharacterRigTests: XCTestCase {
    @MainActor
    func testRigDecodesPartsMotionsAndDefaults() throws {
        let json = """
        { "size": [80, 50],
          "parts": [
            { "id": "body", "image": "body.png", "size": [76, 32], "at": [40, 26],
              "motion": { "walk": { "bob": 1, "freq": 2 }, "default": { "dy": 2 } } },
            { "id": "eyes", "images": { "normal": "eyes_normal.png", "happy": "eyes_happy.png" },
              "size": [20, 10], "at": [46, 16], "pivot": [0.5, 1] },
            { "id": "hat", "size": [30, 24], "at": [34, 0], "fit": true }
          ] }
        """
        let rig = try JSONDecoder().decode(CharacterRig.self, from: Data(json.utf8))

        XCTAssertEqual(rig.size, CGSize(width: 80, height: 50))
        XCTAssertEqual(rig.footPoint, CGPoint(x: 40, y: 50), "опора по умолчанию — низ по центру")
        XCTAssertEqual(rig.parts[1].pivot, CGPoint(x: 0.5, y: 1))
        XCTAssertEqual(rig.parts[0].pivot, CGPoint(x: 0.5, y: 0.5), "точка вращения по умолчанию — центр")
        XCTAssertTrue(rig.parts[2].fit)

        XCTAssertEqual(rig.parts[0].motion(for: "walk")?.bob, 1)
        XCTAssertEqual(rig.parts[0].motion(for: "sleep")?.dy, 2, "нет своего состояния — берётся default")

        // Деталь без картинки (шапка, которую подставит костюм) не требует файла.
        XCTAssertEqual(rig.imageRefs, ["body.png", "eyes_normal.png", "eyes_happy.png"])
    }

    @MainActor
    func testCustomAnimationsDecode() throws {
        let json = """
        { "size": [64, 72],
          "animations": {
            "party": { "duration": 2.6, "spin": 280, "bob": 6, "freq": 2.5, "expression": "happy", "effect": "sparkles" },
            "tooLong": { "duration": 999 }
          },
          "parts": [ { "id": "arm", "image": "arm.png", "size": [5, 19], "at": [20, 43],
                       "motion": { "party": { "rotate": 160, "swing": 30 } } } ] }
        """
        let rig = try JSONDecoder().decode(CharacterRig.self, from: Data(json.utf8))
        let party = try XCTUnwrap(rig.animations["party"])
        XCTAssertEqual(party.duration, 2.6)
        XCTAssertEqual(party.spin, 280)
        XCTAssertEqual(party.effect, "sparkles")
        XCTAssertEqual(rig.animations["tooLong"]?.duration, 15, "слишком длинная анимация ограничивается")
        XCTAssertEqual(rig.parts[0].motion(for: "party")?.rotate, 160, "движение детали — под именем анимации")

        let plain = try JSONDecoder().decode(CharacterRig.self, from: Data(#"{ "size": [10, 10], "parts": [] }"#.utf8))
        XCTAssertTrue(plain.animations.isEmpty, "анимаций может не быть")
    }

    @MainActor
    func testCharacterSelection() throws {
        func config(_ json: String) throws -> PetConfig {
            try JSONDecoder().decode(PetConfig.self, from: Data(json.utf8))
        }
        let characters = """
          "characters": [
            { "id": "monkey", "path": "monkey.json" },
            { "id": "car", "path": "car.json", "weight": 0 },
            { "id": "snowman", "path": "snowman.json", "from": "12-15", "to": "01-10" } ]
        """
        let october = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 17))!
        let newYear = Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 31))!

        let regular = try config("{ \(characters) }")
        XCTAssertEqual(regular.character(on: october)?.id, "monkey", "вес 0 — только принудительно")
        XCTAssertEqual(regular.character(on: newYear)?.id, "snowman", "сезонный важнее круглогодичного")

        let forced = try config("{ \(characters), \"forceCharacter\": \"car\" }")
        XCTAssertEqual(forced.character(on: october)?.id, "car")

        XCTAssertNil(try config("{}").character(on: october), "без персонажей — маскота нет")

        let sized = try config("""
        { "scale": 0.6, "characters": [ { "id": "car", "path": "car.json", "scale": 0.5 } ] }
        """)
        XCTAssertEqual(sized.scale, 0.6)
        XCTAssertEqual(sized.character(on: october)?.scale, 0.5, "у персонажа может быть свой размер")
        XCTAssertEqual(try config("{}").scale, 0.75, "по умолчанию — на четверть меньше нарисованного")
    }
}
