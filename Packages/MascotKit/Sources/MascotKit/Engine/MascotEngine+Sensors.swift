//
//  MascotEngine+Sensors.swift
//  MascotKit
//
//  Датчик движения (наклон, тряска, переворот), зарядка и вибрация.
//  Разрешения не нужны. Датчик работает, только пока экран с маскотом виден.
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

    /// Вызывает слой маскота: экран закрыт другим или приложение свёрнуто — датчики стоят.
    func setSensorsActive(_ active: Bool) {
        sensorsAllowed = active
        updateMotion()
    }

    /// Пока маскот на экране, датчик нужен 30 раз в секунду (наклон, тряска);
    /// пока его нет — 15 раз, только чтобы заметить тряску.
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

/// Генераторы вибрации создаются один раз и заранее «прогреваются» — без задержки на первом толчке.
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
