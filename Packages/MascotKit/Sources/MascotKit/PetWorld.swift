//
//  PetWorld.swift
//  MascotKit
//
//  «Жилец» — зверёк, который живёт поверх главного экрана: ходит по верхним
//  краям карточек, прыгает между ними, реагирует на наклон, тряску, зарядку
//  и события приложения. Его можно схватить и швырнуть.
//
//  Публичный API (.mascot(), .mascotSurface(), .mascotHome(), .mascotTrigger()) — в Mascot.swift.
//  Все координаты внутри — в системе оверлея (весь экран, включая safe area).
//

import SwiftUI
import UIKit
import CoreMotion

/// События приложения, на которые реагирует маскот.
public enum MascotEvent: String, Sendable {
    case topUp, taskDone, achievement
}

enum PetMode: Equatable {
    case hidden, descending, airborne, grabbed, leaving
    case walking, idle, sitting, waving, sleeping, dizzy, dancing, celebrating
    /// Своя анимация из character.json.
    case performing

    var isGrounded: Bool {
        switch self {
        case .walking, .idle, .sitting, .waving, .sleeping, .dizzy, .dancing, .celebrating, .performing: true
        default: false
        }
    }
}

enum PetExpression {
    case normal, happy, dizzy, sleepy, scared
}

/// Всё, что нужно, чтобы нарисовать один кадр.
struct PetSnapshot {
    var position: CGPoint
    var facing: CGFloat
    var mode: PetMode
    var expression: PetExpression
    var walkPhase: Double
    var squash: CGFloat
    var spin: Double
    var scale: CGFloat
    var rope: (top: CGFloat, bottom: CGFloat)?
    var bubble: String?
    var blink: Bool
    var time: TimeInterval
    /// Своя анимация, которую он сейчас исполняет.
    var animation: String?
    /// Сколько секунд длится текущее состояние.
    var modeTime: TimeInterval
}

/// Единственное наблюдаемое состояние — чтобы TimelineView останавливался, пока маскота нет.
final class PetPresence: ObservableObject {
    @Published var isVisible = false
    /// Переопределения триггеров с CDN: id → жест/действие. Наблюдаемые, чтобы жесты на вьюхах переподключились.
    @Published var triggerOverrides: [String: MascotTriggerSpec] = [:]
}

@MainActor
final class PetWorld {
    static let shared = PetWorld()

    let presence = PetPresence()
    private(set) var config = PetConfig()
    private(set) var skin: PetSkin?
    private(set) var hat: UIImage?
    /// Персонаж из деталей с CDN. Пока его нет, маскот не появляется.
    private(set) var character: LoadedCharacter?

    // Геометрия экрана (глобальные координаты)
    var overlayFrame: CGRect = .zero
    var contentFrame: CGRect = .zero
    private var platforms: [String: CGRect] = [:]
    /// Поверхности, которые перекрывают всё, что под ними (например, таб-бар).
    private var occluders: Set<String> = []
    private var homeFrame: CGRect?

    // Состояние Жильца
    private var mode: PetMode = .hidden
    private var pos = CGPoint.zero
    private var vel = CGVector.zero
    private var facing: CGFloat = 1
    private var platformID: String?
    private var platformOffset: CGFloat = 0
    private var modeStart: TimeInterval = 0
    private var modeDuration: TimeInterval = 0
    private var walkPhase: Double = 0
    private var squash: CGFloat = 0
    private var spin: Double = 0
    private var spinSpeed: Double = 0
    private var scale: CGFloat = 1
    private var rope: (top: CGFloat, bottom: CGFloat)?
    private var isRopeRetracting = false
    private var bubble: (text: String, until: TimeInterval, pinned: Bool)?
    /// Лимиты реакций и реплик за текущий визит.
    private var limiter = VisitLimiter()
    private var lastReacted: [String: TimeInterval] = [:]
    private var expressionOverride: (PetExpression, until: TimeInterval)?
    private var lastInteraction: TimeInterval = 0
    private var lastStep: TimeInterval?
    private var isThrown = false
    private var dizzyOnLanding = false
    /// Анимация из реакции, которую надо сыграть, как только он встанет на карточку.
    private var pendingAnimation: String?
    /// Своя анимация, которая играет сейчас.
    private var performing: String?
    /// Глубина вложенных реакций: анимация, вызванная из реакции, сама анимаций не запускает —
    /// так не бывает петель вроде «прыгнул → анимация прыжка → прыгнул…».
    private var reactionDepth = 0
    private var leave: (from: CGPoint, to: CGPoint, start: TimeInterval)?

    // Датчики
    private let motion = CMMotionManager()
    private var gravity = CGVector(dx: 0, dy: -1)
    private var lastShake: TimeInterval = 0
    private var didStart = false
    /// Конфиг, персонаж и экран готовы. До этого маскот не появляется ни по какому поводу —
    /// иначе он успел бы прийти со встроенными значениями, а не с теми, что пришли с CDN.
    private var isReady = false
    private let sounds = SoundBank()

    private let g: CGFloat = 1800
    private var spriteHeight: CGFloat { (character.map { $0.rig.size.height * 0.85 } ?? 60) * spriteScale }
    /// Во сколько раз маскот меньше нарисованного: из конфига, у персонажа может быть свой.
    private(set) var spriteScale: CGFloat = 0.75
    private var now: TimeInterval { CACurrentMediaTime() }

    // MARK: - Геометрия

    private var screen: CGSize { overlayFrame.size }
    private var safeTop: CGFloat { max(contentFrame.minY - overlayFrame.minY, 20) }
    private var floorY: CGFloat { overlayFrame.maxY - overlayFrame.minY - max(overlayFrame.maxY - contentFrame.maxY, 0) }

    func setPlatform(_ id: String, frame: CGRect?, occludesBelow: Bool = false) {
        trackMotion(of: id, newFrame: frame)
        platforms[id] = frame
        if occludesBelow, frame != nil { occluders.insert(id) } else { occluders.remove(id) }
    }
    func setHome(frame: CGRect?) { homeFrame = frame }

    // MARK: - Предсказание положения при скролле (iOS 15)

    /// До iOS 16 фреймы приходят с опозданием на кадр, и маскот отставал бы от карточки при скролле.
    /// Поэтому запоминаем скорость карточки и досчитываем, где она сейчас.
    private static var geometryLags: Bool {
        if #available(iOS 16.0, *) { return false }
        return true
    }
    private var platformMotion: [String: (velocity: CGVector, reportedAt: TimeInterval)] = [:]
    /// Размер экрана в прошлом кадре — чтобы заметить поворот.
    private var lastScreenSize: CGSize = .zero
    /// Где была карточка под маскотом в прошлом кадре — чтобы заметить «телепорт».
    private var lastSurfaceRect: CGRect?

    private func trackMotion(of id: String, newFrame: CGRect?) {
        guard Self.geometryLags else { return }
        let t = now
        guard let newFrame, let old = platforms[id], let last = platformMotion[id] else {
            platformMotion[id] = (.zero, t)
            return
        }
        let dt = t - last.reportedAt
        let velocity = dt > 0 && dt < 0.1
            ? CGVector(dx: (newFrame.minX - old.minX) / dt, dy: (newFrame.minY - old.minY) / dt)
            : .zero
        platformMotion[id] = (velocity, t)
    }

    private func predicted(_ frame: CGRect, for id: String) -> CGRect {
        guard Self.geometryLags, let motion = platformMotion[id] else { return frame }
        let age = now - motion.reportedAt
        // Нет свежих сообщений два кадра — карточка остановилась, ничего не досчитываем.
        guard age < 1.0 / 30 else { return frame }
        let ahead = age + 1.0 / 60
        return frame.offsetBy(dx: motion.velocity.dx * ahead, dy: motion.velocity.dy * ahead)
    }

    private func local(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: -overlayFrame.minX, dy: -overlayFrame.minY) }
    private func local(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x - overlayFrame.minX, y: point.y - overlayFrame.minY) }

    /// Карточка, на которой можно стоять: видна на экране и не уехала под таб-бар или статус-бар.
    private func surface(_ id: String) -> CGRect? {
        guard let global = platforms[id] else { return nil }
        let rect = local(predicted(global, for: id))
        guard rect.minY > safeTop + spriteHeight * 0.6, rect.minY < floorY - 4 else { return nil }
        // То, что уехало под таб-бар и подобные плашки, не видно — там не стоим.
        for other in occluders where other != id {
            if let cover = platforms[other].map(local), rect.minY > cover.minY - 6 { return nil }
        }
        let minX = max(rect.minX + 10, 12), maxX = min(rect.maxX - 10, screen.width - 12)
        guard maxX - minX > 24 else { return nil }
        return CGRect(x: minX, y: rect.minY, width: maxX - minX, height: rect.height)
    }

    private var surfaces: [(id: String, rect: CGRect)] {
        platforms.keys.compactMap { id in surface(id).map { (id, $0) } }
    }

    // MARK: - Запуск и появление

    func start(configFile: String) async {
        guard !didStart else { return }
        didStart = true

        // Всё — только с CDN или из кэша. Нет конфига или персонажа — маскота нет.
        guard let (config, base) = await CDNContent.load(PetConfig.self, file: configFile), config.enabled else { return }
        self.config = config
        presence.triggerOverrides = config.triggers
        guard let ref = config.character(),
              let character = await LoadedCharacter.load(ref.path, relativeTo: base) else {
            print("MascotKit: персонаж не загрузился — маскот не показывается")
            return
        }
        self.character = character
        spriteScale = CGFloat(min(max(ref.scale ?? config.scale, 0.3), 2))
        skin = config.skin()
        if let hatRef = skin?.hat, hatRef != "none" { hat = await CDNContent.image(hatRef, relativeTo: base) }
        // Звуки грузятся параллельно и не задерживают появление маскота.
        let clips = config.soundClips, settings = config.sounds
        Task { await sounds.load(clips, settings: settings, relativeTo: base) }

        startSensors()
        // Даём главному экрану спокойно отрисоваться и зарегистрировать карточки.
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        isReady = true
        appearanceCheck()
    }

    /// Появление при открытии: первый вход за день или случайный шанс из конфига.
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
        case rope, drop
        /// Выпрыгивает из вьюхи (глобальный фрейм); nil — из домика.
        case from(CGRect?)
    }

    func summon(_ entrance: Entrance, greeting: String? = nil) {
        guard overlayFrame.width > 0 else { return }
        scale = 1; spin = 0; spinSpeed = 0; squash = 0; isThrown = false
        rope = nil; isRopeRetracting = false; leave = nil
        lastInteraction = now
        presence.isVisible = true
        // Новый визит — лимиты реплик начинаются заново.
        limiter.reset()

        switch entrance {
        case .rope:
            // Спускается на ниточке над случайной карточкой.
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

    // MARK: - Триггеры

    /// Действие от триггера на вьюхе. frame — глобальный фрейм вьюхи, из неё маскот и выпрыгнет.
    func perform(_ action: MascotAction, from frame: CGRect?) {
        guard isReady, config.enabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        switch action {
        case .summon:
            if mode == .hidden { summon(.from(frame), greeting: "comeBack") }
        case .toggle:
            if mode == .hidden { summon(.from(frame), greeting: "comeBack") } else { goHome() }
        case .sendHome:
            if mode != .hidden { goHome() }
        case .celebrate:
            if mode == .hidden { summon(.from(frame)) }
            animate("celebrate")
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

    private func shake() {
        guard isReady, now - lastShake > 1.2 else { return }
        lastShake = now
        if mode == .hidden {
            if config.onShake { summon(.drop, greeting: "shake") }
            return
        }
        guard mode != .grabbed, mode != .leaving else { return }
        // Тряска сшибает его с карточки.
        vel = CGVector(dx: .random(in: -260...260), dy: -560)
        spinSpeed = .random(in: 400...800) * (Bool.random() ? 1 : -1)
        dizzyOnLanding = true
        setMode(.airborne)
        react("shake")
        lastInteraction = now
    }

    private func chargingChanged(_ state: UIDevice.BatteryState) {
        guard isReady, state == .charging, config.onCharging else { return }
        if mode == .hidden { summon(.from(nil)) }
        react("charging")
    }

    // MARK: - Касания

    private var grabOffset = CGVector.zero

    func touchBegan(at global: CGPoint) {
        let p = local(global)
        grabOffset = CGVector(dx: pos.x - p.x, dy: pos.y - p.y)
    }

    func dragged(to global: CGPoint) {
        guard mode != .hidden, mode != .leaving else { return }
        if mode != .grabbed {
            setMode(.grabbed)
            react("grab")
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        let p = local(global)
        pos = CGPoint(x: p.x + grabOffset.dx, y: p.y + grabOffset.dy)
        lastInteraction = now
    }

    func released(velocity: CGSize) {
        guard mode == .grabbed else { return }
        let speed = hypot(velocity.width, velocity.height)
        let limit: CGFloat = 2600
        let k = speed > limit ? limit / speed : 1
        vel = CGVector(dx: velocity.width * k, dy: velocity.height * k)
        spinSpeed = Double(vel.dx) / 4
        isThrown = speed > 1500
        dizzyOnLanding = speed > 900
        setMode(.airborne)
        if speed > 900 { react("thrown") }
    }

    func tapped() {
        guard mode.isGrounded || mode == .idle else { return }
        if let name = config.reactions["tap"]?.animation, canAnimate(name) {
            // В конфиге на тап задана анимация — делает её вместо прыжка.
            react("tap")
        } else {
            vel = CGVector(dx: 0, dy: -420)
            expressionOverride = (.happy, now + 1)
            setMode(.airborne)
            react("tap")
        }
        lastInteraction = now
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    // MARK: - Симуляция

    func step() -> PetSnapshot? {
        let t = now
        let dt = CGFloat(min(t - (lastStep ?? t), 1.0 / 20))
        lastStep = t
        guard mode != .hidden else { return nil }
        if screen != lastScreenSize {
            if lastScreenSize != .zero { screenDidResize() }
            lastScreenSize = screen
        }

        squash *= CGFloat(pow(0.002, Double(dt)))
        if scale < 1, mode != .leaving { scale = min(1, scale + dt * 3) }
        updateRope(dt)

        switch mode {
        case .hidden:
            return nil

        case .descending:
            pos.y += 170 * dt
            if let rope { self.rope = (rope.top, pos.y - spriteHeight) }
            walkPhase += Double(dt) * 4
            if let hit = landing(fromY: pos.y - 170 * dt, toY: pos.y) {
                land(on: hit.id, rect: hit.rect)
                isRopeRetracting = true
            } else if pos.y >= floorY {
                landOnFloor()
                isRopeRetracting = true
            }

        case .airborne:
            let previous = pos
            vel.dx += gravity.dx * 900 * dt
            vel.dy += g * dt
            pos.x += vel.dx * dt
            pos.y += vel.dy * dt
            spin += spinSpeed * Double(dt)
            walkPhase += Double(dt) * 14

            if isThrown, pos.x < -60 || pos.x > screen.width + 60 || pos.y > screen.height + 80 {
                // Вылетел за экран — обиделся и ушёл, вернётся позже.
                hide()
                return nil
            }
            if !isThrown {
                if pos.x < 16 { pos.x = 16; vel.dx = abs(vel.dx) * 0.4 }
                if pos.x > screen.width - 16 { pos.x = screen.width - 16; vel.dx = -abs(vel.dx) * 0.4 }
            }
            if vel.dy > 0, let hit = landing(fromY: previous.y, toY: pos.y) {
                land(on: hit.id, rect: hit.rect)
            } else if pos.y >= floorY, pos.x > 0, pos.x < screen.width {
                landOnFloor()
            }

        case .grabbed:
            walkPhase += Double(dt) * 16

        case .leaving:
            guard let leave else { hide(); return nil }
            let u = min(1, (t - leave.start) / 0.6)
            let x = leave.from.x + (leave.to.x - leave.from.x) * u
            let y = leave.from.y + (leave.to.y - leave.from.y) * u - 140 * 4 * u * (1 - u)
            pos = CGPoint(x: x, y: y)
            scale = u > 0.55 ? max(0.05, 1 - (u - 0.55) / 0.45) : 1
            if u >= 1 { react("disappear"); hide(); return nil }

        default:
            stepGrounded(dt, t)
        }

        return snapshot(t)
    }

    private func stepGrounded(_ dt: CGFloat, _ t: TimeInterval) {
        guard let rect = currentSurface() else {
            // Карточка уехала при скролле — падаем.
            vel = CGVector(dx: facing * 60, dy: 0)
            setMode(.airborne)
            return
        }
        // Карточка скакнула за один кадр (перестройка экрана, а не скролл) — не телепортируемся вместе с ней.
        if let last = lastSurfaceRect, abs(rect.minY - last.minY) > 90 || abs(rect.minX - last.minX) > 90 {
            dropFromCurrentPlace()
            return
        }
        lastSurfaceRect = rect
        pos = CGPoint(x: rect.minX + platformOffset, y: rect.minY)

        // Сильный наклон телефона — скользит к краю и может сорваться.
        let tilt = gravity.dx
        if abs(tilt) > 0.45, mode != .sleeping || abs(tilt) > 0.7 {
            platformOffset += tilt * 280 * dt
            facing = tilt > 0 ? 1 : -1
            walkPhase += Double(dt) * 12
            expressionOverride = (.scared, t + 0.3)
            react("tilt")
            if platformOffset < 0 || platformOffset > rect.width {
                vel = CGVector(dx: tilt * 240, dy: -60)
                setMode(.airborne)
            }
            return
        }
        if gravity.dy > 0.6 { react("upsideDown") }

        switch mode {
        case .walking:
            platformOffset += facing * CGFloat(config.walkSpeed) * dt
            walkPhase += Double(dt) * 9
            if platformOffset < 0 || platformOffset > rect.width {
                platformOffset = min(max(platformOffset, 0), rect.width)
                if Double.random(in: 0..<1) < 0.35 {
                    // Спрыгивает с края карточки вниз.
                    vel = CGVector(dx: facing * 130, dy: -280)
                    setMode(.airborne)
                    return
                }
                facing = -facing
            }
        case .sleeping:
            react("snore", gain: 0.6)
        case .dizzy where t - modeStart > 0.5:
            react("dizzy", gain: 0.7)
        case .performing:
            walkPhase += Double(dt) * 10
        case .dancing, .celebrating:
            walkPhase += Double(dt) * 10
            if Int((t - modeStart) / 0.35) % 2 == 0 { facing = 1 } else { facing = -1 }
        default:
            break
        }

        if t - modeStart > modeDuration { nextBehavior() }
        if t - lastInteraction > config.stayMinutes * 60, mode != .sleeping { goHome() }
    }

    private func currentSurface() -> CGRect? {
        if platformID == "floor" {
            return CGRect(x: 12, y: floorY, width: screen.width - 24, height: 0)
        }
        return platformID.flatMap(surface)
    }

    private func landing(fromY: CGFloat, toY: CGFloat) -> (id: String, rect: CGRect)? {
        surfaces
            .filter { fromY <= $0.rect.minY + 2 && toY >= $0.rect.minY && ($0.rect.minX...$0.rect.maxX).contains(pos.x) }
            .min { $0.rect.minY < $1.rect.minY }
    }

    /// Экран поменял размер (поворот, Split View): старые координаты карточек больше не верны.
    /// Маскот отцепляется и падает с текущего места — приземлится уже на свежие.
    private func screenDidResize() {
        platformMotion.removeAll()
        switch mode {
        case .leaving:
            hide()
        case .grabbed:
            break
        default:
            dropFromCurrentPlace()
        }
    }

    private func dropFromCurrentPlace() {
        lastSurfaceRect = nil
        rope = nil
        isRopeRetracting = false
        pos.x = min(max(pos.x, 16), max(screen.width - 16, 16))
        pos.y = min(max(pos.y, safeTop), floorY - 1)
        vel = CGVector(dx: 0, dy: -120)
        platformID = nil
        setMode(.airborne)
    }

    private func land(on id: String, rect: CGRect) {
        lastSurfaceRect = nil
        platformID = id
        platformOffset = pos.x - rect.minX
        pos.y = rect.minY
        afterLanding()
    }

    private func landOnFloor() {
        lastSurfaceRect = nil
        platformID = "floor"
        pos.y = floorY
        platformOffset = pos.x - 12
        afterLanding()
    }

    private func afterLanding() {
        let impact = vel.dy
        vel = .zero
        spin = 0; spinSpeed = 0
        isThrown = false
        squash = min(max(impact, 300) / 2400, 0.35)
        if !(dizzyOnLanding || impact > 1500) {
            // Мягкое приземление — тише, чем прыжок с высоты.
            react("land", gain: Float(min(max(impact / 1200, 0.35), 1)))
        }

        if dizzyOnLanding || impact > 1500 {
            dizzyOnLanding = false
            setMode(.dizzy, duration: 2.2)
            react("hardLanding")
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } else if let name = pendingAnimation {
            pendingAnimation = nil
            setMode(.idle, duration: 0.3)
            animate(name)
        } else if mode == .descending {
            setMode(.waving, duration: 1.8)
        } else {
            setMode(.idle, duration: .random(in: 0.5...1.2))
        }
    }

    // MARK: - Поведение по весам

    private var isNight: Bool {
        let hour = Calendar.current.component(.hour, from: .now)
        return hour >= 22 || hour < 7
    }

    private func nextBehavior() {
        var weights = config.behaviors
        if isNight { weights["sleep", default: 0] *= config.nightSleepBoost }
        if surfaces.count < 2 { weights["hop"] = 0 }
        let total = weights.values.reduce(0) { $0 + max($1, 0) }
        guard total > 0 else { setMode(.idle, duration: 2); return }

        var roll = Double.random(in: 0..<total)
        let pick = weights.sorted { $0.key < $1.key }.first { roll -= max($0.value, 0); return roll < 0 }?.key ?? "idle"

        switch pick {
        case "walk":
            facing = Bool.random() ? 1 : -1
            setMode(.walking, duration: .random(in: 2...5))
        case "sit": setMode(.sitting, duration: .random(in: 3...6))
        case "wave": setMode(.waving, duration: 1.8)
        case "sleep": setMode(.sleeping, duration: .random(in: 5...9))
        case "dance": setMode(.dancing, duration: 2.6)
        case "hop": hop()
        default:
            // Своя анимация персонажа тоже может быть поведением — с весом в behaviors.
            if character?.rig.animations[pick] != nil { animate(pick) } else { setMode(.idle, duration: .random(in: 1.5...3)) }
        }
    }

    /// Прыжок по дуге на другую карточку: случайную или ближайшую (когда выпрыгивает из вьюхи).
    private func hop(nearest: Bool = false) {
        let options = surfaces.filter { $0.id != platformID }
        let distance = { (rect: CGRect) in hypot(rect.midX - self.pos.x, rect.minY - self.pos.y) }
        let picked = nearest ? options.min { distance($0.rect) < distance($1.rect) } : options.randomElement()
        guard let target = picked else {
            setMode(.idle, duration: 1)
            return
        }
        let to = CGPoint(x: .random(in: target.rect.minX...target.rect.maxX), y: target.rect.minY)
        let time: CGFloat = 0.8
        vel = CGVector(dx: (to.x - pos.x) / time, dy: (to.y - pos.y - 0.5 * g * time * time) / time)
        facing = to.x >= pos.x ? 1 : -1
        setMode(.airborne)
        react("hop", gain: 0.7)
    }

    private func goHome() {
        react("bye")
        if let home = homeFrame.map(local), home.maxY > 0 {
            leave = (pos, CGPoint(x: home.midX, y: home.midY + 20), now)
            facing = home.midX >= pos.x ? 1 : -1
            setMode(.leaving)
        } else {
            // Аватар не виден — убегает за край экрана.
            isThrown = true
            vel = CGVector(dx: pos.x < screen.width / 2 ? -320 : 320, dy: -420)
            setMode(.airborne)
        }
    }

    private func hide() {
        setMode(.hidden)
        bubble = nil
        rope = nil
        // hide() зовётся во время отрисовки кадра — меняем наблюдаемое состояние уже после неё.
        Task { @MainActor in self.presence.isVisible = false }
    }

    private func setMode(_ newMode: PetMode, duration: TimeInterval = 0) {
        if newMode == .celebrating, mode != .celebrating { react("celebrate") }
        mode = newMode
        modeStart = now
        modeDuration = duration
    }

    private func updateRope(_ dt: CGFloat) {
        guard isRopeRetracting, let current = rope else { return }
        let bottom = current.bottom - 700 * dt
        rope = bottom <= current.top ? nil : (current.top, bottom)
        if rope == nil { isRopeRetracting = false }
    }

    // MARK: - Реакции

    /// Реакция на любое событие из конфига: реплика, звук и анимация (встроенная или своя).
    /// - Parameter gain: громкость звука относительно реакции (тише для мягкого приземления).
    private func react(_ key: String, gain: Float = 1) {
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
            animate(name)
            reactionDepth -= 1
        }
    }

    private static let builtInAnimations: Set<String> = ["celebrate", "wave", "dance", "sit", "sleep", "hop", "jump"]

    private func canAnimate(_ name: String) -> Bool {
        Self.builtInAnimations.contains(name) || character?.rig.animations[name] != nil
    }

    /// Анимация по имени. Если он ещё в воздухе или только появляется — сыграет после приземления.
    private func animate(_ name: String) {
        guard mode.isGrounded else {
            if mode != .hidden { pendingAnimation = name }
            return
        }
        switch name {
        case "celebrate": setMode(.celebrating, duration: 2.4)
        case "wave": setMode(.waving, duration: 1.8)
        case "dance": setMode(.dancing, duration: 2.6)
        case "sit": setMode(.sitting, duration: 4)
        case "sleep": setMode(.sleeping, duration: 6)
        case "hop": hop()
        case "jump":
            vel = CGVector(dx: 0, dy: -420)
            setMode(.airborne)
        default:
            guard let animation = character?.rig.animations[name] else { return }
            performing = name
            setMode(.performing, duration: animation.duration)
        }
        lastInteraction = now
    }

    // MARK: - Кадр

    private func snapshot(_ t: TimeInterval) -> PetSnapshot {
        var expression: PetExpression
        switch mode {
        case .sleeping: expression = .sleepy
        case .dizzy: expression = .dizzy
        case .grabbed: expression = .scared
        case .airborne: expression = isThrown || dizzyOnLanding ? .scared : .happy
        case .celebrating, .dancing, .waving, .leaving: expression = .happy
        case .performing:
            switch performing.flatMap({ character?.rig.animations[$0]?.expression }) {
            case "normal": expression = .normal
            case "sleepy": expression = .sleepy
            case "dizzy": expression = .dizzy
            case "scared": expression = .scared
            default: expression = .happy
            }
        default: expression = .normal
        }
        if let override = expressionOverride, override.until > t { expression = override.0 }

        return PetSnapshot(
            position: pos,
            facing: facing,
            mode: mode,
            expression: expression,
            walkPhase: walkPhase,
            squash: squash,
            spin: spin,
            scale: scale,
            rope: rope,
            bubble: bubble.flatMap { $0.until > t ? $0.text : nil },
            blink: t.truncatingRemainder(dividingBy: 3.4) < 0.12,
            time: t,
            animation: mode == .performing ? performing : nil,
            modeTime: t - modeStart
        )
    }

    // MARK: - Датчики

    private func startSensors() {
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1.0 / 30
            motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let data else { return }
                MainActor.assumeIsolated { self?.handle(data) }
            }
        }
        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.addObserver(forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.chargingChanged(UIDevice.current.batteryState) }
        }
    }

    private func handle(_ data: CMDeviceMotion) {
        gravity = CGVector(dx: data.gravity.x, dy: data.gravity.y)
        let a = data.userAcceleration
        if sqrt(a.x * a.x + a.y * a.y + a.z * a.z) > 2.2 { shake() }
    }
}
