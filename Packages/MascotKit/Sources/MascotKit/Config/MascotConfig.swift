//
//  MascotConfig.swift
//  MascotKit
//

import Foundation

struct MascotConfig: Decodable {
    var enabled = true

    var firstOpenOfDay = true
    var randomChance = 0.15
    var onShake = true
    var onEvents = true
    var onCharging = true
    var triggers: [String: MascotTriggerSpec] = [:]

    var stayMinutes = 2.0

    var behaviors: [String: Double] = MascotConfig.defaultBehaviors
    var walkSpeed = 42.0
    var nightSleepBoost = 4.0

    var reactions: [String: MascotReaction] = MascotConfig.defaultReactions
    var sounds = MascotSoundSettings()
    var skins: [MascotSkin] = []
    var characters: [MascotCharacterRef] = []
    var scale = 0.75
    var bubble = MascotBubbleStyle()
    var hideSpots: [String]?
    var forceCharacter: String?
    var forceSkin: String?

    init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled
        case firstOpenOfDay, randomChance, onShake, onEvents, onCharging, triggers, stayMinutes
        case behaviors, walkSpeed, nightSleepBoost, hideSpots
        case phrases, sounds, reactions, bubble
        case characters, forceCharacter, scale, skins, forceSkin
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.value(.enabled, default: enabled)

        firstOpenOfDay = try c.value(.firstOpenOfDay, default: firstOpenOfDay)
        randomChance = try c.value(.randomChance, default: randomChance)
        onShake = try c.value(.onShake, default: onShake)
        onEvents = try c.value(.onEvents, default: onEvents)
        onCharging = try c.value(.onCharging, default: onCharging)
        triggers = try c.value(.triggers, default: [:])
        stayMinutes = try c.value(.stayMinutes, default: stayMinutes)

        behaviors.merge(try c.value(.behaviors, default: [:])) { $1 }
        walkSpeed = try c.value(.walkSpeed, default: walkSpeed)
        nightSleepBoost = try c.value(.nightSleepBoost, default: nightSleepBoost)
        hideSpots = try c.decodeIfPresent([String].self, forKey: .hideSpots)

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

        characters = try c.value(.characters, default: [])
        forceCharacter = try c.decodeIfPresent(String.self, forKey: .forceCharacter)
        scale = try c.value(.scale, default: scale)
        skins = try c.value(.skins, default: [])
        forceSkin = try c.decodeIfPresent(String.self, forKey: .forceSkin)
    }

    func allowsHiding(behind id: String, markedInCode: Bool) -> Bool {
        guard let hideSpots else { return markedInCode }
        return hideSpots.contains { $0.hasSuffix("*") ? id.hasPrefix($0.dropLast()) : $0 == id }
    }

    var soundClips: [String: [String]] {
        reactions.compactMapValues { $0.sound?.isEmpty == false ? $0.sound : nil }
    }

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
        "walk": 4, "idle": 2, "sit": 1.5, "wave": 1, "hop": 2, "sleep": 0.4, "dance": 0.6, "hide": 0.5,
    ]

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
    var hat: String?
    var priority: Int { from == nil ? 0 : 1 }
}

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

struct MascotBubbleStyle: Decodable {
    var fontSize: Double = 12
    var maxWidth: Double = 200
    var maxLines = 3
    var textColor = "#1C1C1E"
    var background = "#FFFFFF"
    var opacity: Double = 0.5
    var blur = false
    var cornerRadius: Double = 12
    var maxChars = 0
    var duration: Double = 2.4

    init() {}

    private enum CodingKeys: String, CodingKey {
        case fontSize, maxWidth, maxLines, textColor, background, opacity, blur, cornerRadius, maxChars, duration
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
        let chars = try c.value(.maxChars, default: maxChars)
        maxChars = chars <= 0 ? 0 : max(chars, 4)
        duration = min(max(try c.value(.duration, default: duration), 0.8), 15)
    }

    func display(_ text: String, expanded: Bool) -> String {
        guard maxChars > 0, !expanded, text.count > maxChars else { return text }
        let cut = text.prefix(maxChars).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return cut + "…"
    }

    func isTruncated(_ text: String) -> Bool { maxChars > 0 && text.count > maxChars }
}
