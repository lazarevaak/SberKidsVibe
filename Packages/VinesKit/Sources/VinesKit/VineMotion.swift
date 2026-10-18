//
//  VineMotion.swift
//  VinesKit
//

import CoreMotion
import UIKit

final class VineMotion {
    private let manager = CMMotionManager()
    private var lastTimestamp: TimeInterval?

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = DevicePerformance.minimumFrameInterval ?? 1.0 / 60
        manager.startDeviceMotionUpdates()
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        lastTimestamp = nil
    }

    func sample(in window: UIWindow?) -> VineMotionSample? {
        guard manager.isDeviceMotionActive,
              let data = manager.deviceMotion,
              ProcessInfo.processInfo.systemUptime - data.timestamp < 0.2,
              data.timestamp != lastTimestamp else { return nil }
        lastTimestamp = data.timestamp
        let a = data.userAcceleration
        let r = data.rotationRate
        return VineMotionSample(
            gravity: Self.screenVector(x: data.gravity.x, y: data.gravity.y, in: window),
            acceleration: Self.screenVector(x: a.x, y: a.y, in: window),
            accelerationZ: a.z, rotationX: r.x, rotationY: r.y, rotationZ: r.z,
            timestamp: data.timestamp
        )
    }

    private static func screenVector(x: Double, y: Double, in window: UIWindow?) -> CGVector {
        let point = CGPoint(x: x, y: -y)
        guard let window else { return CGVector(dx: point.x, dy: point.y) }
        let space = window.screen.fixedCoordinateSpace
        let origin = window.convert(CGPoint.zero, from: space)
        let end = window.convert(point, from: space)
        return CGVector(dx: end.x - origin.x, dy: end.y - origin.y)
    }
}
