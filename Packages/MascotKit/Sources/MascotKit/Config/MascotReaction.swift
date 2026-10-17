//
//  MascotReaction.swift
//  MascotKit
//
//  Реакция на событие и реплика — из pet.json → reactions.
//

import Foundation

/// Реакция на событие. Все поля необязательны: не указано — значит нет.
struct MascotReaction: Decodable {
    /// Реплики — каждый раз случайная. Реплика может быть строкой или объектом MascotLine
    /// (с лимитом за визит и гарантированным показом).
    var say: [MascotLine]?
    /// Вероятность реплики (0…1), по умолчанию 1.
    var sayChance: Double?
    /// Звуки — каждый раз случайный.
    var sound: [String]?
    var soundChance: Double?
    /// Громкость этого звука относительно общей (0…1).
    var volume: Double?
    /// Анимация: celebrate, wave, dance, sit, sleep, hop, jump.
    /// Срабатывает на событиях приложения и триггерах, а не на физике (приземление и т. п.).
    var animation: String?
    /// Не повторять реакцию чаще, чем раз в N секунд.
    var cooldown: Double?
    /// Сколько раз реакция может сработать за один визит (пока маскот на экране).
    /// Счётчик сбрасывается, когда маскот ушёл и его позвали снова.
    var maxPerVisit: Int?

    init(say: [String]? = nil, sound: [String]? = nil, animation: String? = nil, cooldown: Double? = nil) {
        self.say = say?.map(MascotLine.init(text:))
        self.sound = sound
        self.animation = animation
        self.cooldown = cooldown
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

/// Реплика. В JSON — просто строка или объект:
/// { "text": "…", "maxPerVisit": 3, "first": true, "duration": 5 }
struct MascotLine: Decodable {
    var text: String
    /// Сколько раз эту реплику можно сказать за один визит.
    var maxPerVisit: Int?
    /// Гарантированная: пока лимит не исчерпан, говорится она, без учёта sayChance,
    /// и пока висит — другие реплики её не перебивают.
    var first: Bool?
    /// Сколько секунд висит реплика.
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

/// Ссылка на персонажа из деталей.
struct MascotCharacterRef: Decodable {
    var id: String
    /// Путь к character.json — относительно конфига или полный URL.
    var path: String
    var from: String?
    var to: String?
    var weight: Double
    /// Свой размер персонажа — важнее общего scale.
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
