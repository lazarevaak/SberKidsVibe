//
//  MascotReaction.swift
//  MascotKit
//

import Foundation

struct MascotReaction: Decodable {
    var say: [MascotLine]?
    var sayChance: Double?
    var sound: [String]?
    var soundChance: Double?
    var volume: Double?
    var animation: [String]?
    var cooldown: Double?
    var maxPerVisit: Int?

    init(say: [String]? = nil, sound: [String]? = nil, animation: String? = nil, cooldown: Double? = nil) {
        self.say = say?.map(MascotLine.init(text:))
        self.sound = sound
        self.animation = animation.map { [$0] }
        self.cooldown = cooldown
    }

    private enum CodingKeys: String, CodingKey {
        case say, sayChance, sound, soundChance, volume, animation, cooldown, maxPerVisit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        say = try c.decodeIfPresent([MascotLine].self, forKey: .say)
        sayChance = try c.decodeIfPresent(Double.self, forKey: .sayChance)
        sound = try c.decodeIfPresent([String].self, forKey: .sound)
        soundChance = try c.decodeIfPresent(Double.self, forKey: .soundChance)
        volume = try c.decodeIfPresent(Double.self, forKey: .volume)
        if let one = try? c.decodeIfPresent(String.self, forKey: .animation) {
            animation = [one]
        } else {
            animation = try c.decodeIfPresent([String].self, forKey: .animation)
        }
        cooldown = try c.decodeIfPresent(Double.self, forKey: .cooldown)
        maxPerVisit = try c.decodeIfPresent(Int.self, forKey: .maxPerVisit)
    }

    func merged(over base: MascotReaction) -> MascotReaction {
        var result = base
        if let say { result.say = say }
        if let sayChance { result.sayChance = sayChance }
        if let sound { result.sound = sound }
        if let soundChance { result.soundChance = soundChance }
        if let volume { result.volume = volume }
        if let animation { result.animation = animation }
        if let cooldown { result.cooldown = cooldown }
        if let maxPerVisit { result.maxPerVisit = maxPerVisit }
        return result
    }
}

struct MascotLine: Decodable {
    var text: String
    var maxPerVisit: Int?
    var first: Bool?
    var duration: Double?

    init(text: String) { self.text = text }

    private enum CodingKeys: String, CodingKey { case text, maxPerVisit, first, duration }

    init(from decoder: Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            self.text = text
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        maxPerVisit = try c.decodeIfPresent(Int.self, forKey: .maxPerVisit)
        first = try c.decodeIfPresent(Bool.self, forKey: .first)
        duration = try c.decodeIfPresent(Double.self, forKey: .duration)
    }
}

struct MascotCharacterRef: Decodable {
    var id: String
    var path: String
    var from: String?
    var to: String?
    var weight: Double
    var scale: Double?

    var priority: Int { from == nil ? 0 : 1 }

    private enum CodingKeys: String, CodingKey { case id, path, from, to, weight, scale }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        path = try c.decode(String.self, forKey: .path)
        from = try c.decodeIfPresent(String.self, forKey: .from)
        to = try c.decodeIfPresent(String.self, forKey: .to)
        weight = try c.decodeIfPresent(Double.self, forKey: .weight) ?? 1
        scale = try c.decodeIfPresent(Double.self, forKey: .scale)
    }
}
