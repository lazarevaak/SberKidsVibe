//
//  DevicePerformance.swift
//  MascotKit
//

import Foundation

enum DevicePerformance {
    private static var cached: Bool?
    private static var powerObserver: NSObjectProtocol?

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

    static var minimumFrameInterval: Double? { isLite ? 1.0 / 30 : nil }
}
