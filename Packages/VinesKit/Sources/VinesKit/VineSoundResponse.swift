//
//  VineSoundResponse.swift
//  VinesKit
//

import Foundation

nonisolated struct VineSoundResponse: Sendable {
    let intensity: Double

    init(acceleration: Double, rotationSpeed: Double) {
        let shake = min(max((acceleration - 0.45) / 2.5, 0), 1)
        let turn = min(max((rotationSpeed - 0.75) / 2.5, 0), 1)

        intensity = max(shake, turn * 0.85)
    }

    var isAudible: Bool { intensity > 0.025 }
    var volume: Float { isAudible ? Float(0.06 + 0.50 * pow(intensity, 0.7)) : 0 }
    var interval: TimeInterval { 0.40 - 0.20 * intensity }
}

nonisolated struct VineSoundGate: Sendable {
    private var movementStartedAt: TimeInterval?
    private var lastSampleAt: TimeInterval?

    mutating func allows(_ response: VineSoundResponse, acceleration: Double, at time: TimeInterval) -> Bool {
        if let lastSampleAt, time - lastSampleAt > 0.2 || time < lastSampleAt {
            movementStartedAt = nil
        }

        lastSampleAt = time

        guard response.isAudible else {
            movementStartedAt = nil
            return false
        }

        if movementStartedAt == nil { movementStartedAt = time }
        return acceleration >= 1.0 || time - (movementStartedAt ?? time) >= 0.08
    }
}

nonisolated enum VineAudioEvent: Sendable {
    case play(volume: Float, rate: Float)
    case fade
}

nonisolated struct VineAudioPolicy: Sendable {
    let settings: VineSoundConfig
    private var gate = VineSoundGate()
    private var lastPlayed: TimeInterval?
    private var quietSince: TimeInterval?
    private var fading = false

    init(settings: VineSoundConfig) { self.settings = settings }

    mutating func reset() {
        gate = VineSoundGate()
        lastPlayed = nil
        quietSince = nil
        fading = false
    }

    mutating func update(acceleration: Double, rotationSpeed: Double, timestamp: TimeInterval) -> VineAudioEvent? {
        guard settings.enabled, settings.volume > 0 else { return nil }

        let response = VineSoundResponse(acceleration: acceleration, rotationSpeed: rotationSpeed)
        let canPlay = gate.allows(response, acceleration: acceleration, at: timestamp)

        if response.isAudible {
            quietSince = nil
        } else {
            if quietSince == nil { quietSince = timestamp }
            if timestamp - (quietSince ?? timestamp) >= 0.10, !fading {
                fading = true
                return .fade
            }
        }

        guard canPlay, lastPlayed.map({ timestamp - $0 >= response.interval }) ?? true else { return nil }

        lastPlayed = timestamp
        fading = false

        return .play(volume: response.volume * Float(settings.volume), rate: Float(0.98 + response.intensity * 0.06))
    }
}
