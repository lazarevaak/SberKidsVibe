import CoreGraphics
import Foundation

nonisolated struct Vine: Sendable {
    var points: [CGPoint]
    var previous: [CGPoint]
    var anchor: CGPoint
    var segment: CGFloat
    var glyphSize: CGFloat
    var opacity: Double
    var phase: Double
    var seed: Int
    var isAttached = true
    var life: Double = 1
    var profiles: [VineNodeProfile] = []
}

nonisolated struct VineNodeProfile: Sendable {
    let depth: CGFloat
    let windSin: CGFloat
    let windCos: CGFloat
    let response: CGFloat
}

/// Независимо качающиеся подвесы с инерцией и упругим натяжением.
nonisolated final class VinePhysics {
    let lite: Bool
    private var predictedTips: [CGVector] = []

    init(lite: Bool) {
        self.lite = lite
    }

    /// Предварительно вычисляет профили реакции звеньев.
    func prepare(_ vines: inout [Vine]) {
        predictedTips.reserveCapacity(vines.count)
        for vineIndex in vines.indices {
            let vine = vines[vineIndex]
            vines[vineIndex].profiles = vine.points.indices.map { i in
                VineNodeProfile(depth: CGFloat(i) / CGFloat(max(vine.points.count - 1, 1)),
                                windSin: CGFloat(sin(Double(i) * 0.24)),
                                windCos: CGFloat(cos(Double(i) * 0.24)),
                                response: 0.85 + 0.25 * CGFloat(sin(vine.phase + Double(i) * 0.31)))
            }
        }
    }

    func step(_ vines: inout [Vine], dt: CGFloat, gravity: CGVector,
              motionForce: CGVector, time: Double, sway: CGFloat, shake: CGFloat, resizing: Bool = false) {
        guard !vines.isEmpty else { return }
        if vines.contains(where: { $0.profiles.count != $0.points.count }) {
            prepare(&vines)
        }
        predictedTips.removeAll(keepingCapacity: true)
        // The outer array is uniquely borrowed once for all integration passes.
        // No array is resized while these pointers are borrowed.
        vines.withUnsafeMutableBufferPointer { buffer in
            for v in buffer.indices {
                predictedTips.append(advance(&buffer[v], dt: dt, gravity: gravity,
                                             motionForce: motionForce, time: time, sway: sway, shake: shake))
            }
            // Each strand solves only its own segment lengths; nearby strands never interact.
            let iterations = lite || resizing ? 3 : 4
            for _ in 0..<iterations {
                for v in buffer.indices { constrain(&buffer[v]) }
            }
            for v in buffer.indices { rebound(&buffer[v], predictedVelocity: predictedTips[v]) }
        }
    }

    private func advance(_ vine: inout Vine, dt: CGFloat, gravity: CGVector,
                         motionForce: CGVector, time: Double, sway: CGFloat, shake: CGFloat) -> CGVector {
        guard vine.profiles.count == vine.points.count else { return .zero }
        let windSin = CGFloat(sin(time * 1.3 + vine.phase))
        let windCos = CGFloat(cos(time * 1.3 + vine.phase))
        let windScale = 120 * (sway + shake * 2)
        let dtSquared = dt * dt
        let limit = 1800 * dt
        let first = vine.isAttached ? 1 : 0
        let profiles = vine.profiles
        vine.previous.withUnsafeMutableBufferPointer { previous in
            vine.points.withUnsafeMutableBufferPointer { points in
                for i in first..<points.count {
                    let p = points[i]
                    // Медленнее теряем энергию, но ограничиваем скорость при повторных сильных рывках.
                    var dx = (p.x - previous[i].x) * 0.997
                    var dy = (p.y - previous[i].y) * 0.997
                    let speedSquared = dx * dx + dy * dy
                    if speedSquared > limit * limit {
                        let scale = limit / sqrt(speedSquared)
                        dx *= scale
                        dy *= scale
                    }
                    let profile = profiles[i]
                    let wind = (windSin * profile.windCos + windCos * profile.windSin) * windScale * profile.depth
                    // Разная фаза и масса украшений не дают всем нитям двигаться синхронно.
                    let response = profile.response
                    previous[i] = p
                    points[i] = CGPoint(
                        x: p.x + dx + (gravity.dx + motionForce.dx * response + wind * gravity.dy / 1500) * dtSquared,
                        y: p.y + dy + (gravity.dy + motionForce.dy * response - wind * gravity.dx / 1500) * dtSquared
                    )
                }
            }
        }
        if vine.isAttached { vine.points[0] = vine.anchor }
        let tip = vine.points.count - 1
        if !vine.isAttached { vine.life -= Double(dt) / 1.4 }
        return CGVector(dx: vine.points[tip].x - vine.previous[tip].x,
                        dy: vine.points[tip].y - vine.previous[tip].y)
    }

    private func constrain(_ vine: inout Vine) {
        let last = vine.points.count - 1
        let attached = vine.isAttached
        let segment = vine.segment
        // Один доступ к буферу вместо повторной проверки уникальности массива
        // при каждой записи координаты. Буфер не выходит за пределы этого вызова.
        vine.points.withUnsafeMutableBufferPointer { points in
            for i in 0..<last {
                let a = points[i], b = points[i + 1]
                let dx = b.x - a.x, dy = b.y - a.y
                let distance = max(sqrt(dx * dx + dy * dy), 0.0001)
                let wa: CGFloat = i == 0 && attached ? 0 : 1
                let wb: CGFloat = i + 1 == last ? 0.65 : 1
                let correction = (distance - segment) / distance * 0.94 / (wa + wb)
                points[i] = CGPoint(x: a.x + dx * correction * wa, y: a.y + dy * correction * wa)
                points[i + 1] = CGPoint(x: b.x - dx * correction * wb, y: b.y - dy * correction * wb)
            }
        }
    }

    private func rebound(_ vine: inout Vine, predictedVelocity: CGVector) {
        guard vine.isAttached else { return }
        let i = vine.points.count - 1
        let tip = vine.points[i]
        let dx = tip.x - vine.anchor.x, dy = tip.y - vine.anchor.y
        let reach = hypot(dx, dy), length = vine.segment * CGFloat(i)
        guard reach > length * 0.965, reach > 0 else { return }
        let nx = dx / reach, ny = dy / reach
        let outward = predictedVelocity.dx * nx + predictedVelocity.dy * ny
        guard outward > 0.8 else { return }
        // Резкий рывок натягивает всю нить и возвращает кончик обратно к подвесу.
        // Сохраняем касательную скорость при возврате кончика от предела длины.
        let current = CGVector(dx: tip.x - vine.previous[i].x, dy: tip.y - vine.previous[i].y)
        let radial = current.dx * nx + current.dy * ny
        let vx = current.dx - nx * (radial + outward * 0.4)
        let vy = current.dy - ny * (radial + outward * 0.4)
        vine.previous[i] = CGPoint(x: tip.x - vx, y: tip.y - vy)
    }
}
