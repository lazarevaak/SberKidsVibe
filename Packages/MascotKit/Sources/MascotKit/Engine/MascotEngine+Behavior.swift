//
//  MascotEngine+Behavior.swift
//  MascotKit
//
//  Что маскот делает сам (поведение по весам), как отвечает на события
//  (реакции из конфига) и как играет анимации — встроенные и свои из character.json.
//

import SwiftUI

extension MascotEngine {
    // MARK: - Поведение по весам

    var isNight: Bool {
        let hour = Calendar.current.component(.hour, from: .now)
        return hour >= MascotTuning.nightHours.from || hour < MascotTuning.nightHours.to
    }

    /// Следующее занятие, случайно по весам из behaviors.
    func nextBehavior() {
        var weights = config.behaviors
        if isNight { weights["sleep", default: 0] *= config.nightSleepBoost }
        if surfaces.count < 2 { weights[BuiltInAnimation.hop.rawValue] = 0 }
        // Своя анимация не повторяется сразу после себя — даже если в конфиге ей одной дали вес,
        // персонаж не «залипнет» в ней, а между повторами постоит спокойно.
        if mode == .performing, let last = performing { weights[last] = 0 }

        let total = weights.values.reduce(0) { $0 + max($1, 0) }
        guard total > 0 else { setMode(.idle, duration: MascotTuning.idleDuration); return }
        var roll = Double.random(in: 0..<total)
        let pick = weights.sorted { $0.key < $1.key }.first { roll -= max($0.value, 0); return roll < 0 }?.key ?? "idle"

        switch pick {
        case "walk":
            facing = Bool.random() ? 1 : -1
            setMode(.walking, duration: MascotTuning.walkDuration)
        case "idle":
            setMode(.idle, duration: MascotTuning.idleDuration)
        default:
            // Встроенная поза или своя анимация персонажа; неизвестное имя — просто постоит.
            if !animate(pick, byUser: false) { setMode(.idle, duration: MascotTuning.idleDuration) }
        }
    }

    /// Прыжок по дуге на другую карточку: случайную или ближайшую (когда выпрыгивает из вьюхи).
    func hop(nearest: Bool = false) {
        let options = surfaces.filter { $0.id != platformID }
        let distance = { (rect: CGRect) in hypot(rect.midX - self.pos.x, rect.minY - self.pos.y) }
        let picked = nearest ? options.min { distance($0.rect) < distance($1.rect) } : options.randomElement()
        guard let target = picked else {
            setMode(.idle, duration: 1)
            return
        }
        let to = CGPoint(x: .random(in: target.rect.minX...target.rect.maxX), y: target.rect.minY)
        let time = MascotTuning.hopTime
        vel = CGVector(dx: (to.x - pos.x) / time,
                       dy: (to.y - pos.y - 0.5 * MascotTuning.gravity * time * time) / time)
        facing = to.x >= pos.x ? 1 : -1
        setMode(.airborne)
        react("hop", gain: 0.7)
    }

    /// Уходит в домик; если домик не виден — убегает за край экрана.
    func goHome() {
        react("bye")
        if let home = homeFrame.map(local), home.maxY > 0 {
            leave = (pos, CGPoint(x: home.midX, y: home.midY + 20), now)
            facing = home.midX >= pos.x ? 1 : -1
            setMode(.leaving)
        } else {
            isThrown = true
            vel = CGVector(dx: pos.x < screen.width / 2 ? -320 : 320, dy: -420)
            setMode(.airborne)
        }
    }

    // MARK: - Реакции

    /// Реакция на любое событие из конфига: реплика, звук и анимация (встроенная или своя).
    /// - Parameter gain: громкость звука относительно реакции (тише для мягкого приземления).
    func react(_ key: String, gain: Float = 1) {
        guard let reaction = config.reactions[key] else { return }
        let t = now
        if let cooldown = reaction.cooldown, let last = lastReacted[key], t - last < cooldown { return }
        guard limiter.allow(key, reaction) else { return }
        lastReacted[key] = t

        if let (line, guaranteed) = limiter.pickLine(for: key, in: reaction) {
            // Гарантированную реплику, пока она висит, обычные не перебивают.
            let isPinnedNow = bubble.map { $0.pinned && $0.until > t } ?? false
            if guaranteed || !isPinnedNow {
                let standard = config.bubble.duration
                bubble = (line.text, t + (line.duration ?? (guaranteed ? standard * 1.9 : standard)), guaranteed)
            }
        }
        if reaction.sound?.isEmpty == false, Double.random(in: 0..<1) < (reaction.soundChance ?? 1) {
            sounds.play(key, gain: gain * Float(reaction.volume ?? 1))
        }
        if let name = reaction.animation, reactionDepth == 0 {
            reactionDepth += 1
            animate(name, byUser: true)
            reactionDepth -= 1
        }
    }

    // MARK: - Анимации

    /// Есть ли анимация с таким именем — встроенная или у текущего персонажа.
    func canAnimate(_ name: String) -> Bool {
        BuiltInAnimation(rawValue: name) != nil || character?.rig.animations[name] != nil
    }

    /// Играет анимацию по имени. Если он ещё в воздухе или только появляется — сыграет после приземления.
    /// - Parameter byUser: ответ на действие или событие — тогда это внимание, и домой он уйдёт не скоро.
    /// - Returns: false, если анимации с таким именем нет.
    @discardableResult
    func animate(_ name: String, byUser: Bool) -> Bool {
        guard mode.isGrounded else {
            if mode != .hidden { pendingAnimation = name }
            return true
        }
        if let builtIn = BuiltInAnimation(rawValue: name) {
            switch builtIn {
            case .hop:
                hop()
            case .jump:
                vel = CGVector(dx: 0, dy: -MascotTuning.tapJump)
                setMode(.airborne)
            case .celebrate:
                setMode(.celebrating, duration: MascotTuning.duration(of: builtIn))
            case .wave:
                setMode(.waving, duration: MascotTuning.duration(of: builtIn))
            case .dance:
                setMode(.dancing, duration: MascotTuning.duration(of: builtIn))
            case .sit:
                setMode(.sitting, duration: MascotTuning.duration(of: builtIn))
            case .sleep:
                setMode(.sleeping, duration: MascotTuning.duration(of: builtIn))
            }
        } else if let animation = character?.rig.animations[name] {
            performing = name
            setMode(.performing, duration: animation.duration)
        } else {
            return false
        }
        if byUser { lastInteraction = now }
        return true
    }
}
