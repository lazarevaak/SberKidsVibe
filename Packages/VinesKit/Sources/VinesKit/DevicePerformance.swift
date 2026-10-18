//
//  DevicePerformance.swift
//  VinesKit
//

import Foundation

enum DevicePerformance {
    static var isLite: Bool {
        if UserDefaults.standard.object(forKey: "FunLiteMode") != nil {
            return UserDefaults.standard.bool(forKey: "FunLiteMode")
        }
        return ProcessInfo.processInfo.physicalMemory <= 2_200_000_000
            || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    static var minimumFrameInterval: Double? { isLite ? 1.0 / 30 : 1.0 / 60 }
}
