//
//  MascotConfigValidator.swift
//  MascotKit
//

import Foundation

struct MascotConfigIssue: Equatable {
    enum Level { case warning, info }

    let level: Level
    let message: String
}

enum MascotConfigValidator {
    static let engineEvents: Set<String> = Set([
        "hello", "night", "comeBack", "descend", "fall", "appear", "disappear", "bye",
        "land", "hardLanding", "dizzy", "tap", "grab", "thrown", "shake", "tilt", "upsideDown",
        "hop", "snore", "celebrate", "charging", "hide", "found",
    ]).union([MascotEvent.topUp, .taskDone, .achievement].map(\.rawValue))

    static let motionStates: Set<String> = [
        "walk", "idle", "sit", "sleep", "wave", "dance", "celebrate",
        "grabbed", "air", "dizzy", "descend", "hide", "default",
    ]

    static let behaviorNames: Set<String> = ["walk", "idle", MascotEngine.hideBehavior]

    static func check(_ config: MascotConfig, character: CharacterRig?, characterID: String?) -> [MascotConfigIssue] {
        var issues: [MascotConfigIssue] = []
        func warn(_ text: String) { issues.append(MascotConfigIssue(level: .warning, message: text)) }
        func note(_ text: String) { issues.append(MascotConfigIssue(level: .info, message: text)) }

        let who = characterID.map { "у персонажа «\($0)»" } ?? "у персонажа"
        let customAnimations = Set(character.map { Array($0.animations.keys) } ?? [])
        func animationExists(_ name: String) -> Bool {
            BuiltInAnimation(rawValue: name) != nil || customAnimations.contains(name)
        }

        for (key, reaction) in config.reactions.sorted(by: { $0.key < $1.key }) {
            if let names = reaction.animation, !names.isEmpty, !names.contains(where: animationExists) {
                let list = names.map { "«\($0)»" }.joined(separator: ", ")
                warn("Реакция «\(key)» ссылается на анимацию \(list), а её нет ни среди встроенных, ни \(who) — анимация не сыграет.")
            }
            let hasContent = reaction.say?.isEmpty == false || reaction.sound?.isEmpty == false || reaction.animation != nil
            if hasContent, !engineEvents.contains(key), !customAnimations.contains(key) {
                note("Реакция «\(key)» не относится к событиям маскота — сработает, только если её вызывает триггер .react(\"\(key)\").")
            }
        }

        for (name, weight) in config.behaviors.sorted(by: { $0.key < $1.key }) where weight > 0 {
            if !behaviorNames.contains(name), !animationExists(name) {
                warn("В behaviors есть «\(name)», но такой анимации нет \(who) — вес не используется.")
            }
        }

        if let force = config.forceCharacter, !config.characters.contains(where: { $0.id == force }) {
            warn("forceCharacter = «\(force)», но такого персонажа нет в characters — выбор пойдёт по сезонам и весам.")
        }
        if let force = config.forceSkin, !config.skins.contains(where: { $0.id == force }) {
            warn("forceSkin = «\(force)», но такого костюма нет в skins.")
        }

        for (id, spec) in config.triggers.sorted(by: { $0.key < $1.key }) {
            if let gesture = spec.gesture, MascotGesture(gesture) == nil {
                warn("Триггер «\(id)»: неизвестный жест «\(gesture)» — останется жест из кода. Жесты: tap, doubleTap, tripleTap, longPress.")
            }
            if let action = spec.action, MascotAction(action) == nil {
                warn("Триггер «\(id)»: неизвестное действие «\(action)» — останется действие из кода.")
            }
        }

        if let character {
            let states = motionStates.union(customAnimations)
            for part in character.parts {
                for state in (part.motion?.keys).map(Array.init) ?? [] where !states.contains(state) {
                    warn("Деталь «\(part.id)» \(who): движение для неизвестного состояния «\(state)» — опечатка? Состояния: \(motionStates.sorted().joined(separator: ", ")) и свои анимации.")
                }
                if let images = part.images {
                    var expected = MascotExpression.allNames.subtracting(["normal"])
                    if images["blink"] == nil { expected.remove("blink") }
                    let missing = expected.subtracting(images.keys).sorted()
                    if images["normal"] == nil, part.image == nil {
                        warn("Деталь «\(part.id)» \(who): в images нет «normal» и нет image — на обычном лице детали не будет.")
                    }
                    if !missing.isEmpty {
                        note("Деталь «\(part.id)» \(who): нет картинок для \(missing.joined(separator: ", ")) — будет обычная.")
                    }
                }
            }
            for (name, animation) in character.animations.sorted(by: { $0.key < $1.key }) {
                if let expression = animation.expression, MascotExpression(rawValue: expression) == nil {
                    warn("Анимация «\(name)» \(who): неизвестная эмоция «\(expression)». Эмоции: \(MascotExpression.allNames.sorted().joined(separator: ", ")).")
                }
                if let effect = animation.effect, MascotEffects.Effect(rawValue: effect) == nil {
                    warn("Анимация «\(name)» \(who): неизвестный эффект «\(effect)». Эффекты: sparkles, stars, zzz.")
                }
            }
        }
        return issues
    }

    static func log(_ issues: [MascotConfigIssue]) {
        guard !issues.isEmpty else {
            MascotLog.validation.info("Конфиг и персонаж проверены — замечаний нет.")
            return
        }
        for issue in issues {
            switch issue.level {
            case .warning: MascotLog.validation.warning("\(issue.message, privacy: .public)")
            case .info: MascotLog.validation.info("\(issue.message, privacy: .public)")
            }
        }
    }
}

extension MascotExpression {
    static let allNames: Set<String> = ["normal", "happy", "dizzy", "sleepy", "scared", "blink"]
}
