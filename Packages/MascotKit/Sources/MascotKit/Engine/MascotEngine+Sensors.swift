//
//  MascotEngine+Sensors.swift
//  MascotKit
//

import UIKit
import CoreMotion

extension MascotEngine {
    func startSensors() {
        sensorsStarted = true
        haptics.prepare()
        updateMotion()
        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.addObserver(forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.chargingChanged(UIDevice.current.batteryState) }
        }
    }

    func setSensorsActive(_ active: Bool) {
        sensorsAllowed = active
        updateMotion()
    }

    func updateMotion() {
        guard sensorsStarted, motion.isDeviceMotionAvailable else { return }
        guard sensorsAllowed else {
            if motion.isDeviceMotionActive { motion.stopDeviceMotionUpdates() }
            return
        }
        motion.deviceMotionUpdateInterval = presence.isVisible ? 1.0 / 30 : 1.0 / 15
        guard !motion.isDeviceMotionActive else { return }
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let data else { return }
            MainActor.assumeIsolated { self?.handle(data) }
        }
    }

    private func handle(_ data: CMDeviceMotion) {
        gravity = CGVector(dx: data.gravity.x, dy: data.gravity.y)
        let a = data.userAcceleration
        if (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot() > MascotTuning.shakeThreshold { shake() }
    }
}

@MainActor
final class Haptics {
    let light = UIImpactFeedbackGenerator(style: .light)
    let medium = UIImpactFeedbackGenerator(style: .medium)
    let soft = UIImpactFeedbackGenerator(style: .soft)

    func prepare() {
        light.prepare()
        medium.prepare()
        soft.prepare()
    }
}
