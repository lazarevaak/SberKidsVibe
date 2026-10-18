//
//  MascotEngine.swift
//  MascotKit
//

import SwiftUI
import UIKit
import CoreMotion

@MainActor
final class MascotEngine {
    static let shared = MascotEngine()

    let presence = MascotPresence()

    private(set) var config = MascotConfig()
    private(set) var skin: MascotSkin?
    private(set) var hat: UIImage?
    private(set) var character: LoadedCharacter?
    private(set) var spriteScale: CGFloat = 0.75
    let sounds = SoundBank()

    var overlayFrame: CGRect = .zero
    var contentFrame: CGRect = .zero
    var platforms: [String: CGRect] = [:]
    var occluders: Set<String> = []
    var hideSpots: Set<String> = []
    var homeFrame: CGRect?
    var platformMotion: [String: (velocity: CGVector, reportedAt: TimeInterval)] = [:]
    var lastScreenSize: CGSize = .zero
    var lastSurfaceRect: CGRect?

    var mode: MascotMode = .hidden
    var pos = CGPoint.zero
    var vel = CGVector.zero
    var facing: CGFloat = 1
    var platformID: String?
    var platformOffset: CGFloat = 0
    var modeStart: TimeInterval = 0
    var modeDuration: TimeInterval = 0
    var walkPhase: Double = 0
    var squash: CGFloat = 0
    var spin: Double = 0
    var spinSpeed: Double = 0
    var scale: CGFloat = 1
    var rope: (top: CGFloat, bottom: CGFloat)?
    var isRopeRetracting = false
    var leave: (from: CGPoint, to: CGPoint, start: TimeInterval)?
    var isThrown = false
    var dizzyOnLanding = false
    var expressionOverride: (expression: MascotExpression, until: TimeInterval)?
    var lastInteraction: TimeInterval = 0
    var lastStep: TimeInterval?
    var grabOffset = CGVector.zero
    var holdStart: TimeInterval?

    var bubble: (text: String, until: TimeInterval, pinned: Bool)?
    var limiter = VisitLimiter()
    var lastReacted: [String: TimeInterval] = [:]
    var pendingAnimation: String?
    var performing: String?
    var reactionDepth = 0

    let motion = CMMotionManager()
    var gravity = CGVector(dx: 0, dy: -1)
    var lastShake: TimeInterval = 0
    let haptics = Haptics()
    var sensorsStarted = false
    var sensorsAllowed = true

    private var didStart = false
    private(set) var isReady = false

    var now: TimeInterval { CACurrentMediaTime() }

    func start(configFile: String) async {
        guard !didStart else { return }
        didStart = true

        guard let (config, base) = await CDNContent.load(MascotConfig.self, file: configFile), config.enabled else { return }
        self.config = config
        presence.triggerOverrides = config.triggers
        let ref = config.character()
        var loaded: LoadedCharacter?
        if let ref { loaded = await LoadedCharacter.load(ref.path, relativeTo: base) }
        MascotConfigValidator.log(MascotConfigValidator.check(config, character: loaded?.rig, characterID: ref?.id))
        guard let ref, let character = loaded else {
            MascotLog.content.error("Персонаж не загрузился — маскот не показывается")
            return
        }
        self.character = character
        spriteScale = CGFloat(min(max(ref.scale ?? config.scale, 0.3), 2))
        skin = config.skin()
        if let hatRef = skin?.hat, hatRef != "none" { hat = await CDNContent.image(hatRef, relativeTo: base) }
        let clips = config.soundClips, settings = config.sounds
        Task { await sounds.load(clips, settings: settings, relativeTo: base) }

        startSensors()
        try? await Task.sleep(nanoseconds: UInt64(MascotTuning.appearDelay * 1_000_000_000))
        isReady = true
        appearanceCheck()
    }

    func appearanceCheck() {
        guard isReady, config.enabled, mode == .hidden else { return }
        let today = Date.now.formatted(.iso8601.year().month().day())
        let isFirstToday = UserDefaults.standard.string(forKey: "pet.lastDay") != today
        UserDefaults.standard.set(today, forKey: "pet.lastDay")

        if UserDefaults.standard.bool(forKey: "MascotAlwaysAppear") || (config.firstOpenOfDay && isFirstToday) {
            summon(.rope, greeting: isNight ? "night" : "hello")
        } else if Double.random(in: 0..<1) < config.randomChance {
            summon(.rope, greeting: "comeBack")
        }
    }

    enum Entrance {
        case rope
        case drop
        case from(CGRect?)
    }

    func summon(_ entrance: Entrance, greeting: String? = nil) {
        guard overlayFrame.width > 0 else { return }
        scale = 1; spin = 0; spinSpeed = 0; squash = 0; isThrown = false
        rope = nil; isRopeRetracting = false; leave = nil
        lastInteraction = now
        presence.isVisible = true
        updateMotion()
        limiter.reset()

        switch entrance {
        case .rope:
            let target = surfaces.filter { $0.rect.minY < screen.height * 0.6 }.randomElement() ?? surfaces.randomElement()
            let x = target.map { CGFloat.random(in: $0.rect.minX...$0.rect.maxX) } ?? screen.width / 2
            pos = CGPoint(x: x, y: -10)
            rope = (0, pos.y - spriteHeight)
            setMode(.descending)
            react("descend")
        case .drop:
            pos = CGPoint(x: .random(in: 60...(screen.width - 60)), y: -30)
            vel = CGVector(dx: .random(in: -120...120), dy: 0)
            spinSpeed = .random(in: -500...500)
            dizzyOnLanding = true
            setMode(.airborne)
            react("fall")
        case .from(let frame):
            let origin = (frame ?? homeFrame).map(local)
            pos = origin.map { CGPoint(x: $0.midX, y: $0.midY + 20) } ?? CGPoint(x: 40, y: safeTop + 60)
            scale = 0.3
            hop(nearest: true)
            react("appear")
        }
        if let greeting { react(greeting) }
    }

    func perform(_ action: MascotAction, from frame: CGRect?) {
        guard isReady, config.enabled else { return }
        haptics.medium.impactOccurred()
        switch action {
        case .summon:
            if mode == .hidden { summon(.from(frame), greeting: "comeBack") }
        case .toggle:
            if mode == .hidden { summon(.from(frame), greeting: "comeBack") } else { goHome() }
        case .sendHome:
            if mode != .hidden { goHome() }
        case .celebrate:
            if mode == .hidden { summon(.from(frame)) }
            animate(BuiltInAnimation.celebrate.rawValue, byUser: true)
        case .event(let event):
            send(event, from: frame)
        case .react(let key):
            if mode == .hidden { summon(.from(frame)) }
            react(key)
        }
    }

    func send(_ event: MascotEvent, from frame: CGRect? = nil) {
        guard isReady, config.onEvents else { return }
        if mode == .hidden { summon(.from(frame)) }
        react(event.rawValue)
    }

    func shake() {
        guard isReady, now - lastShake > MascotTuning.shakeCooldown else { return }
        lastShake = now
        if mode == .hidden {
            if config.onShake { summon(.drop, greeting: "shake") }
            return
        }
        guard mode != .grabbed, mode != .leaving else { return }
        vel = CGVector(dx: .random(in: MascotTuning.shakeKnockSide), dy: MascotTuning.shakeKnockUp)
        spinSpeed = .random(in: 400...800) * (Bool.random() ? 1 : -1)
        dizzyOnLanding = true
        setMode(.airborne)
        react("shake")
        lastInteraction = now
    }

    func chargingChanged(_ state: UIDevice.BatteryState) {
        guard isReady, state == .charging, config.onCharging else { return }
        if mode == .hidden { summon(.from(nil)) }
        react("charging")
    }

    func touchBegan(at global: CGPoint) {
        let p = local(global)
        grabOffset = CGVector(dx: pos.x - p.x, dy: pos.y - p.y)
        holdStart = now
    }

    var isHolding: Bool {
        guard let holdStart else { return false }
        let held = now - holdStart
        return held > MascotTuning.holdToRead && held < MascotTuning.maxHold
    }

    func isBeingRead(_ bubble: (text: String, until: TimeInterval, pinned: Bool)) -> Bool {
        guard isHolding, let holdStart else { return false }
        return holdStart < bubble.until
    }

    func touchEnded() {
        if let current = bubble, isBeingRead(current), config.bubble.isTruncated(current.text) {
            bubble?.until = max(current.until, now + MascotTuning.readAfterHold)
        }
        holdStart = nil
    }

    func dragged(to global: CGPoint) {
        guard mode != .hidden, mode != .leaving else { return }
        if mode != .grabbed {
            setMode(.grabbed)
            react("grab")
            haptics.light.impactOccurred()
        }
        holdStart = nil
        let p = local(global)
        pos = CGPoint(x: p.x + grabOffset.dx, y: p.y + grabOffset.dy)
        lastInteraction = now
    }

    func released(velocity: CGSize) {
        guard mode == .grabbed else { return }
        let speed = hypot(velocity.width, velocity.height)
        let k = min(1, MascotTuning.maxThrowSpeed / max(speed, 1))
        vel = CGVector(dx: velocity.width * k, dy: velocity.height * k)
        spinSpeed = Double(vel.dx) / 4
        isThrown = speed > MascotTuning.flyAwaySpeed
        dizzyOnLanding = speed > MascotTuning.throwSpeed
        setMode(.airborne)
        if speed > MascotTuning.throwSpeed { react("thrown") }
    }

    func tapped() {
        guard mode.isGrounded else { return }
        if mode == .hiding {
            vel = CGVector(dx: 0, dy: -MascotTuning.tapJump * 1.15)
            expressionOverride = (.happy, now + 1.5)
            setMode(.airborne)
            react("found")
        } else if playableAnimation(config.reactions["tap"]) != nil {
            react("tap")
        } else {
            vel = CGVector(dx: 0, dy: -MascotTuning.tapJump)
            expressionOverride = (.happy, now + 1)
            setMode(.airborne)
            react("tap")
        }
        lastInteraction = now
        haptics.soft.impactOccurred()
    }
}
