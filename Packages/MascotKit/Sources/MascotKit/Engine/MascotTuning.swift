//
//  MascotTuning.swift
//  MascotKit
//

import CoreGraphics
import Foundation

enum MascotTuning {
    static let gravity: CGFloat = 1800
    static let tiltPushInAir: CGFloat = 900
    static let maxThrowSpeed: CGFloat = 2600
    static let throwSpeed: CGFloat = 900
    static let flyAwaySpeed: CGFloat = 1500
    static let hardLandingImpact: CGFloat = 1500
    static let wallBounce: CGFloat = 0.4
    static let wallMargin: CGFloat = 16

    static let tapJump: CGFloat = 420
    static let hopTime: CGFloat = 0.8
    static let edgeJumpChance = 0.35
    static let edgeJump = CGVector(dx: 130, dy: -280)
    static let shakeKnockUp: CGFloat = -560
    static let shakeKnockSide: ClosedRange<CGFloat> = -260...260

    static let hideDive: TimeInterval = 0.35
    static var hideDuration: TimeInterval { .random(in: 3...5.5) }
    static let peekVisible: CGFloat = 0.38
    static let peekLookInterval: TimeInterval = 1.1

    static let descendSpeed: CGFloat = 170
    static let ropeRetractSpeed: CGFloat = 700
    static let leaveDuration: TimeInterval = 0.6
    static let leaveArcHeight: CGFloat = 140

    static let shakeThreshold = 2.2
    static let shakeCooldown: TimeInterval = 1.2
    static let tiltThreshold: CGFloat = 0.45
    static let strongTilt: CGFloat = 0.7
    static let slideSpeed: CGFloat = 280
    static let upsideDown: CGFloat = 0.6

    static let appearDelay: TimeInterval = 1.2
    static let holdToRead: TimeInterval = 0.35
    static let readAfterHold: TimeInterval = 1.5
    static let maxHold: TimeInterval = 20
    static let nightHours: (from: Int, to: Int) = (22, 7)
    static let maxStep: TimeInterval = 1.0 / 20

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
