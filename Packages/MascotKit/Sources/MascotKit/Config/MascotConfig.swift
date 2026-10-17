//
//  MascotConfig.swift
//  MascotKit
//
//  Конфиг маскота с CDN (pet.json): когда он появляется, кто он, как себя ведёт,
//  что говорит и как звучит, во что одет по сезону. Все поля необязательны.
//

import Foundation

struct MascotConfig: Decodable {
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
    var behaviors: [String: Double] = MascotConfig.defaultBehaviors
    var walkSpeed = 42.0
    /// Ночью (22:00–7:00) вес «спать» умножается на это число.
    var nightSleepBoost = 4.0

    /// Событие → реакция: реплика, звук, анимация. Итог слияния технических значений по умолчанию,
    /// старых полей phrases/sounds и нового reactions (последнее важнее).
    var reactions: [String: MascotReaction] = MascotConfig.defaultReactions
    /// Общие настройки звука: выключатель и громкость.
    var sounds = MascotSoundSettings()
    var skins: [MascotSkin] = []
    /// Персонажи из деталей (character.json на CDN). Нет подходящего — маскот не появляется.
    var characters: [MascotCharacterRef] = []
    /// Размер маскота относительно нарисованного (1 — как в character.json). У персонажа может быть свой.
    var scale = 0.75
    /// Внешний вид реплик: шрифт, ширина, строки, цвета, сколько висит.
    var bubble = MascotBubbleStyle()
    /// Принудительный персонаж по id — для демо.
    var forceCharacter: String?
    /// Принудительный костюм по id — для демо.
    var forceSkin: String?

    init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled
        case firstOpenOfDay, randomChance, onShake, onEvents, onCharging, triggers, stayMinutes
        case behaviors, walkSpeed, nightSleepBoost
        case phrases, sounds, reactions, bubble
        case characters, forceCharacter, scale, skins, forceSkin
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.value(.enabled, default: enabled)

        // Когда появляется
        firstOpenOfDay = try c.value(.firstOpenOfDay, default: firstOpenOfDay)
        randomChance = try c.value(.randomChance, default: randomChance)
        onShake = try c.value(.onShake, default: onShake)
        onEvents = try c.value(.onEvents, default: onEvents)
        onCharging = try c.value(.onCharging, default: onCharging)
        triggers = try c.value(.triggers, default: [:])
        stayMinutes = try c.value(.stayMinutes, default: stayMinutes)

        // Как себя ведёт: веса из JSON дополняют значения по умолчанию
        behaviors.merge(try c.value(.behaviors, default: [:])) { $1 }
        walkSpeed = try c.value(.walkSpeed, default: walkSpeed)
        nightSleepBoost = try c.value(.nightSleepBoost, default: nightSleepBoost)

        // Что говорит и как звучит. Старые поля: phrases — только реплики, sounds — только звуки;
        // reactions важнее: указанные в нём свойства заменяют прежние, остальные остаются.
        sounds = try c.value(.sounds, default: sounds)
        for (key, lines) in try c.value(.phrases, default: [String: [String]]()) {
            reactions[key, default: MascotReaction()].say = lines.map(MascotLine.init(text:))
        }
        for (key, files) in sounds.clips {
            reactions[key, default: MascotReaction()].sound = files
        }
        for (key, reaction) in try c.value(.reactions, default: [String: MascotReaction]()) {
            reactions[key] = reaction.merged(over: reactions[key] ?? MascotReaction())
        }
        bubble = try c.value(.bubble, default: bubble)

        // Кто он и как выглядит
        characters = try c.value(.characters, default: [])
        forceCharacter = try c.decodeIfPresent(String.self, forKey: .forceCharacter)
        scale = try c.value(.scale, default: scale)
        skins = try c.value(.skins, default: [])
        forceSkin = try c.decodeIfPresent(String.self, forKey: .forceSkin)
    }

    /// Все файлы звуков по событиям — их нужно скачать заранее.
    var soundClips: [String: [String]] {
        reactions.compactMapValues { $0.sound?.isEmpty == false ? $0.sound : nil }
    }

    /// Персонаж на сегодня: принудительный, иначе сезонный важнее круглогодичного, среди равных — по весам.
    func character(on date: Date = .now) -> MascotCharacterRef? {
        if let forceCharacter, let pick = characters.first(where: { $0.id == forceCharacter }) { return pick }
        let active = characters.filter { $0.weight > 0 && Season.isActive(from: $0.from, to: $0.to, on: date) }
        guard let top = active.map(\.priority).max() else { return nil }
        let candidates = active.filter { $0.priority == top }
        var roll = Double.random(in: 0..<candidates.reduce(0) { $0 + $1.weight })
        return candidates.first { roll -= $0.weight; return roll < 0 } ?? candidates.last
    }

    func skin(on date: Date = .now) -> MascotSkin? {
        if let forceSkin, let skin = skins.first(where: { $0.id == forceSkin }) { return skin }
        return skins.filter { Season.isActive(from: $0.from, to: $0.to, on: date) }.max { $0.priority < $1.priority }
    }

    static let defaultBehaviors: [String: Double] = [
        "walk": 4, "idle": 2, "sit": 1.5, "wave": 1, "hop": 2, "sleep": 0.4, "dance": 0.6,
    ]

    /// Технические значения по умолчанию — паузы, чтобы повторяющиеся события не «строчили».
    /// Реплик и звуков в коде нет: весь контент приходит из конфига.
    static let defaultReactions: [String: MascotReaction] = [
        "tilt": MascotReaction(cooldown: 4),
        "upsideDown": MascotReaction(cooldown: 6),
        "snore": MascotReaction(cooldown: 2.8),
        "dizzy": MascotReaction(cooldown: 1.1),
    ]
}

struct MascotSkin: Decodable {
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
struct MascotSoundSettings: Decodable {
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

/// Окно реплики. Все поля необязательны; значения ограничены разумными пределами,
/// чтобы опечатка в конфиге не закрыла пол-экрана.
struct MascotBubbleStyle: Decodable {
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
