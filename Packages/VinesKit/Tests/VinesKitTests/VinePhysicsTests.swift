//
//  VinePhysicsTests.swift
//  VinesKitTests
//

import XCTest
@testable import VinesKit

final class VinePhysicsTests: XCTestCase {
    func testStrongMotionKeepsPhysicsFinite() {
        let physics = VinePhysics(lite: false)
        var vines = (0..<12).map { column in
            let x = CGFloat(column) * 22 + 12
            let points = (0..<24).map { index in
                CGPoint(x: x + CGFloat(sin(Double(index) * 0.4 + Double(column))) * 14,
                        y: CGFloat(index) * 17)
            }
            return Vine(points: points, previous: points, anchor: CGPoint(x: x, y: 0), segment: 17,
                        glyphSize: 18, opacity: 1, phase: Double(column), seed: column)
        }

        for frame in 0..<600 {
            let time = Double(frame) / 120
            physics.step(&vines, dt: 1 / 120, gravity: CGVector(dx: 0, dy: 1500),
                         motionForce: CGVector(dx: sin(time * 13) * 18_000,
                                               dy: cos(time * 17) * 12_000),
                         time: time, sway: 1, shake: 4)
            XCTAssertTrue(vines.allSatisfy { vine in
                vine.points.allSatisfy { $0.x.isFinite && $0.y.isFinite }
                    && vine.previous.allSatisfy { $0.x.isFinite && $0.y.isFinite }
            })
        }
    }

    func testNearbyChainsMoveIndependentlyWithoutContact() {
        func makeVine(_ x: CGFloat, _ seed: Int) -> Vine {
            let points = (0..<8).map { index in CGPoint(x: x + CGFloat(index % 2), y: CGFloat(index) * 18) }
            return Vine(points: points, previous: points, anchor: CGPoint(x: x, y: 0), segment: 18,
                        glyphSize: 20, opacity: 1, phase: Double(seed), seed: seed)
        }
        var isolated = [makeVine(80, 1)]
        var together = [makeVine(80, 1), makeVine(84, 2)]

        VinePhysics(lite: false).step(&isolated, dt: 1 / 120, gravity: CGVector(dx: 0, dy: 1500),
                                      motionForce: CGVector(dx: 12_000, dy: 0), time: 0.1, sway: 1, shake: 2)
        VinePhysics(lite: false).step(&together, dt: 1 / 120, gravity: CGVector(dx: 0, dy: 1500),
                                      motionForce: CGVector(dx: 12_000, dy: 0), time: 0.1, sway: 1, shake: 2)
        XCTAssertEqual(isolated[0].points, together[0].points)
    }
}
