//
//  PetConfig.swift
//  MascotKit
//
//  Конфиг «Жильца» с CDN: когда он появляется, как себя ведёт (веса),
//  что говорит и во что одет по сезону. Все поля необязательны.
//

import Foundation

struct PetConfig: Decodable {
    var enabled = true

    // Когда появляется
    var firstOpenOfDay = true
    /// Шанс появиться сам по себе при открытии главного экрана (0…1).
    var randomChance = 0.15
    var onShake = true
    var onEvents = true
    var onCharging = true
    /// Переопределение триггеров на вьюхах по их id: другой жест, другое действие или выключить.
    var triggers: [String: MascotTriggerSpec] = [:]

    /// Через сколько минут без внимания уходит домой в аватар.
    var stayMinutes = 2.0

    // Как себя ведёт
    var behaviors: [String: Double] = PetConfig.defaultBehaviors
    var walkSpeed = 42.0
    /// Ночью (22:00–7:00) вес «спать» умножается на это число.
    var nightSleepBoost = 4.0

    /// Событие → реакция: реплика, звук, анимация. Итог слияния встроенных значений,
    /// старых полей phrases/sounds и нового reactions (последнее важнее).
    var reactions: [String: PetReaction] = PetConfig.defaultReactions
    /// Общие настройки звука: выключатель и громкость.
    var sounds = PetSounds()
    var skins: [PetSkin] = []
    /// Персонажи из деталей (character.json на CDN). Нет подходящего — маскот не появляется.
    var characters: [PetCharacterRef] = []
    /// Размер маскота относительно нарисованного (1 — как в character.json). У персонажа может быть свой.
    var scale = 0.75
    /// Внешний вид реплик: шрифт, ширина, строки, цвета, сколько висит.
    var bubble = PetBubbleStyle()
    /// Принудительный персонаж по id — для демо.
    var forceCharacter: String?
    /// Принудительный костюм по id — для демо.
    var forceSkin: String?

    init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled, firstOpenOfDay, randomChance, onShake, onEvents, onCharging, triggers
        case stayMinutes, behaviors, walkSpeed, nightSleepBoost, phrases, sounds, reactions, skins, forceSkin
        case characters, forceCharacter, scale, bubble
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.value(.enabled, default: enabled)
        firstOpenOfDay = try c.value(.firstOpenOfDay, default: firstOpenOfDay)
        randomChance = try c.value(.randomChance, default: randomChance)
        onShake = try c.value(.onShake, default: onShake)
        triggers = try c.value(.triggers, default: [:])
        onEvents = try c.value(.onEvents, default: onEvents)
        onCharging = try c.value(.onCharging, default: onCharging)
        stayMinutes = try c.value(.stayMinutes, default: stayMinutes)
        walkSpeed = try c.value(.walkSpeed, default: walkSpeed)
        nightSleepBoost = try c.value(.nightSleepBoost, default: nightSleepBoost)
        forceSkin = try c.decodeIfPresent(String.self, forKey: .forceSkin)
        sounds = try c.value(.sounds, default: sounds)
        skins = try c.value(.skins, default: [])
        characters = try c.value(.characters, default: [])
        scale = try c.value(.scale, default: scale)
        bubble = try c.value(.bubble, default: bubble)
        forceCharacter = try c.decodeIfPresent(String.self, forKey: .forceCharacter)
        // Ключи, которых нет в JSON, берутся из значений по умолчанию.
        behaviors.merge(try c.value(.behaviors, default: [:])) { $1 }

        // Старые поля: phrases — только реплики, sounds — только звуки.
        for (key, lines) in try c.value(.phrases, default: [String: [String]]()) {
            reactions[key, default: PetReaction()].say = lines.map(PetLine.init(text:))
        }
        for (key, files) in sounds.clips {
            reactions[key, default: PetReaction()].sound = files
        }
        // Новое поле: указанные в JSON свойства реакции заменяют прежние, остальные остаются.
        for (key, reaction) in try c.value(.reactions, default: [String: PetReaction]()) {
            reactions[key] = reaction.merged(over: reactions[key] ?? PetReaction())
        }
    }

    /// Все файлы звуков по событиям — их нужно скачать заранее.
    var soundClips: [String: [String]] {
        reactions.compactMapValues { $0.sound?.isEmpty == false ? $0.sound : nil }
    }

    /// Персонаж на сегодня: принудительный, иначе сезонный важнее круглогодичного, среди равных — по весам.
    func character(on date: Date = .now) -> PetCharacterRef? {
        if let forceCharacter, let pick = characters.first(where: { $0.id == forceCharacter }) { return pick }
        let active = characters.filter { $0.weight > 0 && Season.isActive(from: $0.from, to: $0.to, on: date) }
        guard let top = active.map(\.priority).max() else { return nil }
        let candidates = active.filter { $0.priority == top }
        var roll = Double.random(in: 0..<candidates.reduce(0) { $0 + $1.weight })
        return candidates.first { roll -= $0.weight; return roll < 0 } ?? candidates.last
    }

    func skin(on date: Date = .now) -> PetSkin? {
        if let forceSkin, let skin = skins.first(where: { $0.id == forceSkin }) { return skin }
        return skins.filter { Season.isActive(from: $0.from, to: $0.to, on: date) }.max { $0.priority < $1.priority }
    }

    static let defaultBehaviors: [String: Double] = [
        "walk": 4, "idle": 2, "sit": 1.5, "wave": 1, "hop": 2, "sleep": 0.4, "dance": 0.6,
    ]

    /// Технические значения по умолчанию — паузы, чтобы повторяющиеся события не «строчили».
    /// Реплик и звуков в коде нет: весь контент приходит из конфига.
    static let defaultReactions: [String: PetReaction] = [
        "tilt": PetReaction(cooldown: 4),
        "upsideDown": PetReaction(cooldown: 6),
        "snore": PetReaction(cooldown: 2.8),
        "dizzy": PetReaction(cooldown: 1.1),
    ]
}

struct PetSkin: Decodable {
    var id: String
    var from: String?
    var to: String?
    /// Картинка шапки (URL или путь относительно конфига). "none" — без шапки.
    var hat: String?
    /// Сезонный костюм важнее костюма на весь год.
    var priority: Int { from == nil ? 0 : 1 }
}

/// Общие настройки звука: "enabled", "volume". Списки файлов по событиям здесь
/// тоже понимаются (старый формат), но правильнее задавать их в reactions → sound.
struct PetSounds: Decodable {
    var enabled = true
    var volume = 0.6
    var clips: [String: [String]] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        for key in c.allKeys {
            switch key.stringValue {
            case "enabled": enabled = try c.decode(Bool.self, forKey: key)
            case "volume": volume = try c.decode(Double.self, forKey: key)
            default:
                if let list = try? c.decode([String].self, forKey: key) { clips[key.stringValue] = list }
                else if let one = try? c.decode(String.self, forKey: key) { clips[key.stringValue] = [one] }
            }
        }
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

/// Реакция на событие. Все поля необязательны: не указано — значит нет.
struct PetReaction: Decodable {
    /// Реплики — каждый раз случайная. Реплика может быть строкой или объектом PetLine
    /// (с лимитом за визит и гарантированным показом).
    var say: [PetLine]?
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
        self.say = say?.map(PetLine.init(text:))
        self.sound = sound
        self.animation = animation
        self.cooldown = cooldown
    }

    func merged(over base: PetReaction) -> PetReaction {
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
struct PetLine: Decodable {
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
struct PetCharacterRef: Decodable {
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

/// Окно реплики. Все поля необязательны; значения ограничены разумными пределами,
/// чтобы опечатка в конфиге не закрыла пол-экрана.
struct PetBubbleStyle: Decodable {
    var fontSize: Double = 12
    var maxWidth: Double = 200
    var maxLines = 3
    var textColor = "#1C1C1E"
    var background = "#FFFFFF"
    /// Непрозрачность фона: 1 — сплошной, меньше — сквозь него видно интерфейс.
    var opacity: Double = 0.5
    /// Матовое размытие под репликой (как у системных панелей iOS). Оно скрывает то, что под репликой,
    /// и даёт сероватый оттенок, поэтому по умолчанию выключено — фон просто полупрозрачный.
    var blur = false
    var cornerRadius: Double = 12
    /// Сколько секунд висит обычная реплика; гарантированная по умолчанию — почти вдвое дольше.
    var duration: Double = 2.4

    init() {}

    private enum CodingKeys: String, CodingKey {
        case fontSize, maxWidth, maxLines, textColor, background, opacity, blur, cornerRadius, duration
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fontSize = min(max(try c.value(.fontSize, default: fontSize), 9), 24)
        maxWidth = min(max(try c.value(.maxWidth, default: maxWidth), 100), 320)
        maxLines = min(max(try c.value(.maxLines, default: maxLines), 1), 6)
        textColor = try c.value(.textColor, default: textColor)
        background = try c.value(.background, default: background)
        opacity = min(max(try c.value(.opacity, default: opacity), 0.2), 1)
        blur = try c.value(.blur, default: blur)
        cornerRadius = min(max(try c.value(.cornerRadius, default: cornerRadius), 0), 24)
        duration = min(max(try c.value(.duration, default: duration), 0.8), 15)
    }
}
