import Foundation
import CoreGraphics

nonisolated struct VineMotionSample: Sendable {
    let gravity: CGVector
    let acceleration: CGVector
    let accelerationZ: Double
    let rotationX: Double
    let rotationY: Double
    let rotationZ: Double
    var shakeStrength: Double {
        min(sqrt(acceleration.dx * acceleration.dx + acceleration.dy * acceleration.dy + accelerationZ * accelerationZ), 3.5)
    }
    var rotationSpeed: Double { sqrt(rotationX * rotationX + rotationY * rotationY + rotationZ * rotationZ) }
    let timestamp: TimeInterval
}
