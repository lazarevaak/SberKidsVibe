//
//  MascotTuning.swift
//  MascotKit
//
//  Числа, на которых держится «характер» движений. Это не контент, поэтому они в коде,
//  но собраны в одном месте и названы — чтобы подкручивать, не выискивая по движку.
//  Скорости — в pt/с, ускорения — в pt/с², время — в секундах.
//

import CoreGraphics
import Foundation

enum MascotTuning {
    // MARK: Физика

    static let gravity: CGFloat = 1800
    /// Насколько наклон телефона сносит маскота в полёте.
    static let tiltPushInAir: CGFloat = 900
    /// Самый быстрый бросок; быстрее — обрезается.
    static let maxThrowSpeed: CGFloat = 2600
    /// Бросок быстрее — это «кинули»: реплика, звук и головокружение после приземления.
    static let throwSpeed: CGFloat = 900
    /// Бросок быстрее — может улететь за экран и обидеться.
    static let flyAwaySpeed: CGFloat = 1500
    /// Приземление быстрее — кружится голова.
    static let hardLandingImpact: CGFloat = 1500
    /// Отскок от края экрана: доля скорости, которая остаётся.
    static let wallBounce: CGFloat = 0.4
    static let wallMargin: CGFloat = 16

    // MARK: Прыжки и ходьба

    static let tapJump: CGFloat = 420
    /// Время прыжка по дуге на другую карточку.
    static let hopTime: CGFloat = 0.8
    /// Шанс спрыгнуть с края карточки, дойдя до него.
    static let edgeJumpChance = 0.35
    static let edgeJump = CGVector(dx: 130, dy: -280)
    /// Тряска сшибает с карточки.
    static let shakeKnockUp: CGFloat = -560
    static let shakeKnockSide: ClosedRange<CGFloat> = -260...260

    // MARK: Ниточка и уход домой

    static let descendSpeed: CGFloat = 170
    static let ropeRetractSpeed: CGFloat = 700
    static let leaveDuration: TimeInterval = 0.6
    static let leaveArcHeight: CGFloat = 140

    // MARK: Датчики

    /// Резкость тряски, g.
    static let shakeThreshold = 2.2
    static let shakeCooldown: TimeInterval = 1.2
    /// Наклон телефона (доля силы тяжести вдоль экрана), с которого маскот начинает скользить.
    static let tiltThreshold: CGFloat = 0.45
    /// Такой наклон будит даже спящего.
    static let strongTilt: CGFloat = 0.7
    static let slideSpeed: CGFloat = 280
    /// С какого наклона телефон считается перевёрнутым.
    static let upsideDown: CGFloat = 0.6

    // MARK: Время

    /// Пауза после открытия, чтобы главный экран отрисовался и зарегистрировал карточки.
    static let appearDelay: TimeInterval = 1.2
    static let nightHours: (from: Int, to: Int) = (22, 7)
    /// Самый длинный шаг симуляции: если кадр подвис, физика замедляется, а не «телепортирует».
    static let maxStep: TimeInterval = 1.0 / 20

    // MARK: Длительность встроенных поз

    static func duration(of animation: BuiltInAnimation) -> TimeInterval {
        switch animation {
        case .celebrate: 2.4
        case .wave: 1.8
        case .dance: 2.6
        case .sit: .random(in: 3...6)
        case .sleep: .random(in: 5...9)
        case .hop, .jump: 0
        }
    }

    static var walkDuration: TimeInterval { .random(in: 2...5) }
    static var idleDuration: TimeInterval { .random(in: 1.5...3) }
    static var settleDuration: TimeInterval { .random(in: 0.5...1.2) }
    static let dizzyDuration: TimeInterval = 2.2
}
