//
//  MascotTypes.swift
//  MascotKit
//

import SwiftUI

public enum MascotEvent: String, Sendable {
    case topUp, taskDone, achievement
}

enum MascotMode: Equatable {
    case hidden, descending, airborne, grabbed, leaving
    case walking, idle, sitting, waving, sleeping, dizzy, dancing, celebrating
    case performing
    case hiding

    var isGrounded: Bool {
        switch self {
        case .walking, .idle, .sitting, .waving, .sleeping, .dizzy, .dancing, .celebrating, .performing, .hiding: true
        case .hidden, .descending, .airborne, .grabbed, .leaving: false
        }
    }
}

enum MascotExpression: String {
    case normal, happy, dizzy, sleepy, scared
}

enum BuiltInAnimation: String {
    case celebrate, wave, dance, sit, sleep, hop, jump
}

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
    var sink: CGFloat
    var bubbleExpanded: Bool
    var blink: Bool
    var time: TimeInterval
    var animation: String?
    var modeTime: TimeInterval
}

final class MascotPresence: ObservableObject {
    @Published var isVisible = false
    @Published var triggerOverrides: [String: MascotTriggerSpec] = [:]
}
