//
//  PhysicsBenchmark.swift
//  VinesKit
//

import CoreGraphics
import Foundation

@main
struct PhysicsBenchmark {
    static func main() {
        func makeVines() -> [Vine] {
            (0..<12).map { column in
                let x = CGFloat(column) * 30 + 15
                let points = (0..<18).map { CGPoint(x: x, y: CGFloat($0) * 18) }

                return Vine(points: points, previous: points, anchor: points[0], segment: 18,
                            glyphSize: 20, opacity: 1, phase: Double(column) * 0.7, seed: column)
            }
        }

        for active in [false, true] {
            var runs: [Double] = []
            var checksum: CGFloat = 0

            for _ in 0..<3 {
                let physics = VinePhysics(lite: false)
                var vines = makeVines()
                let started = ProcessInfo.processInfo.systemUptime

                for frame in 0..<2400 {
                    let time = Double(frame) / 120
                    let force = active ? CGVector(dx: sin(time * 17) * 18000, dy: cos(time * 19) * 12000) : .zero

                    physics.step(&vines, dt: 1.0 / 120, gravity: CGVector(dx: 0, dy: 1500),
                                 motionForce: force, time: time, sway: 1, shake: active ? 4 : 0)
                }
                runs.append(ProcessInfo.processInfo.systemUptime - started)
                checksum += vines[0].points.last!.x
            }
            print(active ? "shake" : "quiet", "median_seconds", runs.sorted()[1], "checksum", checksum)
        }
    }
}
