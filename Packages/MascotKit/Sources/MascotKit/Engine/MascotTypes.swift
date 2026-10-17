//
//  MascotTypes.swift
//  MascotKit
//
//  Небольшие типы, которыми движок общается с отрисовкой.
//

import SwiftUI

/// События приложения, на которые реагирует маскот.
public enum MascotEvent: String, Sendable {
    case topUp, taskDone, achievement
}

/// Что маскот делает сейчас.
enum MascotMode: Equatable {
    case hidden, descending, airborne, grabbed, leaving
    case walking, idle, sitting, waving, sleeping, dizzy, dancing, celebrating
    /// Своя анимация из character.json.
    case performing

    /// Стоит на карточке — а не летит, не висит в руке и не уходит домой.
    var isGrounded: Bool {
        switch self {
        case .walking, .idle, .sitting, .waving, .sleeping, .dizzy, .dancing, .celebrating, .performing: true
        case .hidden, .descending, .airborne, .grabbed, .leaving: false
        }
    }
}

/// Эмоция. Имена совпадают с ключами картинок в character.json → images.
enum MascotExpression: String {
    case normal, happy, dizzy, sleepy, scared
}

/// Встроенные анимации, которые можно вызвать из конфига по имени.
enum BuiltInAnimation: String {
    case celebrate, wave, dance, sit, sleep, hop, jump
}

/// Всё, что нужно, чтобы нарисовать один кадр.
struct MascotSnapshot {
    var position: CGPoint
    var facing: CGFloat
    var mode: MascotMode
    var expression: MascotExpression
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

/// Единственное наблюдаемое состояние — чтобы TimelineView останавливался, пока маскота нет,
/// а жесты на вьюхах переподключались, когда с CDN приходят новые триггеры.
final class MascotPresence: ObservableObject {
    @Published var isVisible = false
    /// Переопределения триггеров с CDN: id → жест / действие.
    @Published var triggerOverrides: [String: MascotTriggerSpec] = [:]
}
