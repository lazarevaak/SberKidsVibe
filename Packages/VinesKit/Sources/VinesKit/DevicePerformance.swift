//
//  DevicePerformance.swift
//  VinesKit
//

import Foundation

/// Облегчённый режим для слабых устройств: у детей часто старые телефоны.
/// iPhone 6s/7/SE (последняя iOS у них — 15) имеют 2 ГБ памяти — по ней и определяем.
/// Режим также включается при энергосбережении. Для проверки: аргумент запуска -FunLiteMode YES/NO.
enum DevicePerformance {
    static var isLite: Bool {
        if UserDefaults.standard.object(forKey: "FunLiteMode") != nil {
            return UserDefaults.standard.bool(forKey: "FunLiteMode")
        }
        return ProcessInfo.processInfo.physicalMemory <= 2_200_000_000
            || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    /// 60 fps достаточно для плавности; на слабых устройствах — 30 fps.
    static var minimumFrameInterval: Double? { isLite ? 1.0 / 30 : 1.0 / 60 }
}
