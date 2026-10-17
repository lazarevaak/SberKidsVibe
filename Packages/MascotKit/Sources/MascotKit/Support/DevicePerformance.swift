//
//  DevicePerformance.swift
//  MascotKit
//

import Foundation

/// Облегчённый режим для слабых устройств: у детей часто старые телефоны.
/// iPhone 6s/7/SE (последняя iOS у них — 15) имеют 2 ГБ памяти — по ней и определяем.
/// Режим также включается при энергосбережении. Для проверки: аргумент запуска -FunLiteMode YES/NO.
enum DevicePerformance {
    private static var cached: Bool?
    private static var powerObserver: NSObjectProtocol?

    /// Считается один раз (оно читается каждый кадр) и пересчитывается при смене режима энергосбережения.
    static var isLite: Bool {
        if let cached { return cached }
        let value: Bool
        if UserDefaults.standard.object(forKey: "FunLiteMode") != nil {
            value = UserDefaults.standard.bool(forKey: "FunLiteMode")
        } else {
            value = ProcessInfo.processInfo.physicalMemory <= 2_200_000_000
                || ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        cached = value
        if powerObserver == nil {
            powerObserver = NotificationCenter.default.addObserver(
                forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
            ) { _ in
                MainActor.assumeIsolated { cached = nil }
            }
        }
        return value
    }

    /// Минимальный интервал кадров для TimelineView: 30 fps в облегчённом режиме, иначе — сколько даст экран.
    static var minimumFrameInterval: Double? { isLite ? 1.0 / 30 : nil }
}
