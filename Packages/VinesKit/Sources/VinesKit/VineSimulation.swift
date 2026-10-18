import CoreGraphics
import Foundation
import Dispatch

nonisolated enum VineTouch: Sendable {
    case move(global: CGPoint, canvas: CGRect, time: TimeInterval)
    case end
}

nonisolated enum VineVisual: Hashable, Sendable {
    case bodyImage(Int)
    case headImage(Int)
    case glyph(String, color: Int, head: Bool)
}

nonisolated struct VineRenderNode: Sendable {
    let point: CGPoint
    let transform: CGAffineTransform
    let opacity: Double
    let visual: VineVisual
}

/// Owns a CGPath.copy(), never a shared mutable path. Immutable Core Graphics paths
/// are safe to hand to the renderer; the SDK does not declare CGPath Sendable.
nonisolated struct VineThreadPath: @unchecked Sendable {
    let value: CGPath
}

nonisolated struct VineRenderStrand: Sendable {
    let id: Int
    let points: [CGPoint]
    let threadPath: VineThreadPath?
    let opacity: Double
    let nodes: [VineRenderNode]
}

nonisolated struct VineFrame: Sendable {
    var strands: [VineRenderStrand] = []
    var size: CGSize = .zero
    var cleared = false
    var didTear = false
    var audio: VineAudioEvent?
}

/// Единственный владелец изменяемой физики. Этот actor не связан с MainActor.
actor VineSimulation {
    private let pack: VinePack
    private let lite: Bool
    private let physics: VinePhysics
    private let bodyImageCount: Int
    private let headImageCount: Int
    private let colorCount: Int
    private var vines: [Vine] = []
    private var size: CGSize = .zero
    private var lastTime: TimeInterval?
    private var accumulator: TimeInterval = 0
    private var simTime: TimeInterval = 0
    private var lastTouch: (point: CGPoint, time: TimeInterval)?
    private var didSpawn = false
    private var didReportCleared = false
    private var didTear = false
    private var motionForce = CGVector.zero
    private var targetMotionForce = CGVector.zero
    private var lastMotionSampleAt: TimeInterval?
    private var gravityDirection = CGVector(dx: 0, dy: 1)
    private var targetGravityDirection = CGVector(dx: 0, dy: 1)
    private var lastShakeTime: TimeInterval?
    private var shakeBoost: CGFloat = 0
    private var resizingUntil: TimeInterval = 0
    private var reducedWorkUntil: TimeInterval = 0
    private var consecutiveOverBudgetFrames = 0
    private var generation = -1
    private var audioPolicy: VineAudioPolicy
    private var audioEvent: VineAudioEvent?
    private let gravity: CGFloat = 1500
    private let fixedStep: TimeInterval = 1.0 / 120
    private let touchRadius: CGFloat = 26

    init(pack: VinePack, lite: Bool, bodyImageCount: Int, headImageCount: Int, colorCount: Int) {
        self.pack = pack
        self.lite = lite
        self.bodyImageCount = bodyImageCount
        self.headImageCount = headImageCount
        self.colorCount = max(1, colorCount)
        physics = VinePhysics(lite: lite)
        audioPolicy = VineAudioPolicy(settings: pack.sound)
    }

    func advance(time: TimeInterval, size: CGSize, motion: VineMotionSample?, touches: [VineTouch], generation: Int) -> VineFrame {
        dispatchPrecondition(condition: .notOnQueue(.main))
        guard !Task.isCancelled else { return VineFrame() }
        if self.generation != generation {
            self.generation = generation
            lastTime = nil
            accumulator = 0
            lastTouch = nil
            lastShakeTime = nil
            lastMotionSampleAt = nil
            motionForce = .zero
            targetMotionForce = .zero
            audioPolicy.reset()
        }
        didTear = false
        audioEvent = nil
        for touch in touches {
            switch touch {
            case .move(let point, let canvas, let time): handleTouch(atGlobal: point, canvasFrame: canvas, time: time)
            case .end: endTouch()
            }
        }
        step(to: time, size: size, motion: motion)
        return renderFrame(time: time)
    }

    func restart(generation: Int) {
        self.generation = generation
        vines.removeAll(keepingCapacity: true)
        lastTime = nil
        accumulator = 0
        simTime = 0
        didSpawn = false
        didReportCleared = false
        didTear = false
        lastTouch = nil
        lastShakeTime = nil
        lastMotionSampleAt = nil
        motionForce = .zero
        targetMotionForce = .zero
        shakeBoost = 0
        audioEvent = nil
        audioPolicy.reset()
    }

    private func spawn(in size: CGSize) {
        didSpawn = true
        var rng = SystemRandomNumberGenerator()
        let fullCount = min(18, max(1, pack.count ?? max(6, Int(size.width / 34))))
        // На слабых устройствах лиан меньше.
        let glyphRange = range(pack.glyphSize, fallback: 10...17)
        let largest = max(glyphRange.upperBound * pack.scale, CGFloat((pack.headSize ?? 0) * pack.scale))
        let fittingCount = max(1, Int(min(size.width, size.height) / max(24, largest * 1.2 + 24)))
        let requested = lite ? max(1, Int((Double(fullCount) * 0.6).rounded())) : fullCount
        let spacingLimitedCount = pack.spacing.map { max(1, Int(1 / $0)) } ?? requested
        let count = min(requested, fittingCount, spacingLimitedCount)
        let spacing = size.width / CGFloat(count)
        let lengthRange = range(pack.length, fallback: 0.1...0.34)

        vines = (0..<count).map { index in
            let glyph = CGFloat.random(in: glyphRange, using: &rng) * CGFloat(pack.scale)
            let segment = glyph * 1.05
            let length = size.height * CGFloat.random(in: lengthRange, using: &rng)
            let links = min(lite ? 20 : 28, max(5, Int(length / segment)))
            let jitterBound: CGFloat
            if let spacingFraction = pack.spacing {
                let requestedGap = size.width * CGFloat(spacingFraction)
                jitterBound = max(0, min(spacing * 0.15, (spacing - requestedGap) * 0.5))
            } else {
                jitterBound = spacing * 0.3
            }
            let x = spacing * (CGFloat(index) + 0.5)
                + CGFloat.random(in: -jitterBound...jitterBound, using: &rng)
            let anchor = CGPoint(x: x, y: -2)
            // Стартуем свёрнутыми над краем — при открытии лианы «падают» и раскачиваются.
            let points = (0..<links).map { i in
                CGPoint(x: x + CGFloat.random(in: -6...6, using: &rng),
                        y: anchor.y - CGFloat(i) * segment * 0.35)
            }
            return Vine(points: points,
                        previous: points,
                        anchor: anchor,
                        segment: segment,
                        glyphSize: glyph,
                        opacity: pack.flicker ? .random(in: 0.85...1, using: &rng) : 1,
                        phase: .random(in: 0...(2 * .pi), using: &rng),
                        seed: .random(in: 0...10_000, using: &rng) * 32 + index)
        }
        physics.prepare(&vines)
    }

    private func range(_ values: [Double], fallback: ClosedRange<CGFloat>) -> ClosedRange<CGFloat> {
        guard values.count == 2 else { return fallback }
        let low = CGFloat(min(values[0], values[1])), high = CGFloat(max(values[0], values[1]))
        return low...high
    }

    // MARK: Simulation

    private func updateMotion(_ sample: VineMotionSample) {
        lastMotionSampleAt = sample.timestamp
        if !vines.isEmpty {
            audioEvent = audioPolicy.update(acceleration: sample.shakeStrength,
                              rotationSpeed: sample.rotationSpeed,
                              timestamp: sample.timestamp)
        }
        let g = sample.gravity
        let magnitude = hypot(g.dx, g.dy)
        // Когда телефон лежит плашмя, сохраняем последнее направление:
        // проекция силы тяжести слишком мала для устойчивого угла.
        if magnitude > 0.15 {
            targetGravityDirection = CGVector(dx: g.dx / magnitude, dy: g.dy / magnitude)
        }
        let a = sample.acceleration
        let length = hypot(a.dx, a.dy)
        // Непрерывная инерция меняет направление вместе с каждым движением телефона.
        let forceScale = length > 0.06 ? min(3.5 / max(length, 0.001), 1) * gravity * 3.4 : 0
        targetMotionForce = CGVector(dx: -a.dx * forceScale, dy: -a.dy * forceScale)
        guard sample.shakeStrength > 0.8,
              lastShakeTime.map({ sample.timestamp - $0 > 0.12 }) ?? true else { return }
        lastShakeTime = sample.timestamp
        shakeBoost = min(4, shakeBoost + CGFloat(sample.shakeStrength))

        // Инерция направлена против ускорения телефона. Тряска к экрану/от экрана
        // тоже раскачивает гирлянды — поперёк текущей силы тяжести.
        let direction = length > 0.2
            ? CGVector(dx: -a.dx / length, dy: -a.dy / length)
            : CGVector(dx: targetGravityDirection.dy, dy: -targetGravityDirection.dx)
        let impulse = CGFloat(sample.shakeStrength) * 480 * CGFloat(fixedStep)
        for index in vines.indices {
            let n = vines[index].points.count
            let variation = CGFloat(sin(vines[index].phase + sample.timestamp * 17))
            let tangent = CGVector(dx: targetGravityDirection.dy, dy: -targetGravityDirection.dx)
            for i in (vines[index].isAttached ? 1 : 0)..<n {
                let depth = CGFloat(i) / CGFloat(n - 1)
                let response = (0.3 + 0.7 * sqrt(depth)) * (0.85 + 0.2 * variation)
                vines[index].previous[i].x -= (direction.dx + tangent.dx * variation * 0.65) * impulse * response
                vines[index].previous[i].y -= (direction.dy + tangent.dy * variation * 0.65) * impulse * response
            }
        }
    }

    private func step(to time: TimeInterval, size: CGSize, motion: VineMotionSample?) {
        if !didSpawn && size.width > 0 { spawn(in: size) }
        if self.size.width > 0,
           abs(self.size.width - size.width) > 0.5 || abs(self.size.height - size.height) > 0.5 {
            resizingUntil = time + 0.2
        }
        if self.size.width > 0, self.size.width != size.width {
            for v in vines.indices {
                let x = vines[v].anchor.x * size.width / self.size.width
                let shift = x - vines[v].anchor.x
                vines[v].anchor.x = x
                for i in vines[v].points.indices {
                    vines[v].points[i].x += shift
                    vines[v].previous[i].x += shift
                }
            }
        }
        self.size = size
        if let motion { updateMotion(motion) }
        if let lastMotionSampleAt, ProcessInfo.processInfo.systemUptime - lastMotionSampleAt > 0.15 {
            targetMotionForce = .zero
        }

        // Не накапливаем очередь тяжёлых шагов после задержки кадра.
        let delta = max(0, min(time - (lastTime ?? time), 1.0 / 30))
        lastTime = time
        accumulator += delta
        let started = ProcessInfo.processInfo.systemUptime
        let budget = lite ? 0.0015 : 0.0025
        while accumulator >= fixedStep && !Task.isCancelled {
            integrate(fixedStep, resizing: time < resizingUntil || time < reducedWorkUntil)
            accumulator -= fixedStep
            simTime += fixedStep
            if ProcessInfo.processInfo.systemUptime - started >= budget {
                consecutiveOverBudgetFrames += 1
                if consecutiveOverBudgetFrames >= 2 {
                    // Stay in the lower-cost contact solver briefly instead of
                    // repeating an over-budget full solve on every display tick.
                    reducedWorkUntil = time + 1.5
                    consecutiveOverBudgetFrames = 0
                }
                accumulator = 0
                break
            }
        }
        if ProcessInfo.processInfo.systemUptime - started < budget {
            consecutiveOverBudgetFrames = 0
        }

        vines.removeAll { !$0.isAttached && ($0.life <= 0 || $0.points.allSatisfy { $0.y > size.height + 40 }) }
        if didSpawn && vines.isEmpty { didReportCleared = true }
    }

    private func integrate(_ dt: TimeInterval, resizing: Bool) {
        let dt = CGFloat(dt)
        let blend = 1 - exp(-dt / 0.12)
        gravityDirection.dx += (targetGravityDirection.dx - gravityDirection.dx) * blend
        gravityDirection.dy += (targetGravityDirection.dy - gravityDirection.dy) * blend
        let forceBlend = 1 - exp(-dt / 0.035)
        motionForce.dx += (targetMotionForce.dx - motionForce.dx) * forceBlend
        motionForce.dy += (targetMotionForce.dy - motionForce.dy) * forceBlend
        shakeBoost *= exp(-dt / 1.4)
        physics.step(&vines, dt: dt,
                     gravity: CGVector(dx: gravityDirection.dx * gravity, dy: gravityDirection.dy * gravity),
                     motionForce: motionForce, time: simTime,
                     sway: CGFloat(pack.sway), shake: shakeBoost, resizing: resizing)
    }

    private func handleTouch(atGlobal global: CGPoint, canvasFrame: CGRect, time: TimeInterval) {
        let point = CGPoint(x: global.x - canvasFrame.minX, y: global.y - canvasFrame.minY)
        defer { lastTouch = (point, time) }
        guard let last = lastTouch, time > last.time else { return }

        let move = CGVector(dx: point.x - last.point.x, dy: point.y - last.point.y)
        let speed = hypot(move.dx, move.dy) / CGFloat(time - last.time)

        for v in vines.indices where vines[v].isAttached {
            var hit = false
            for i in 1..<vines[v].points.count {
                let d = distance(from: vines[v].points[i], toSegment: last.point, point)
                guard d < touchRadius else { continue }
                hit = true
                let falloff = 1 - d / touchRadius
                vines[v].points[i].x += move.dx * 0.6 * falloff
                vines[v].points[i].y += move.dy * 0.6 * falloff
            }
            if hit && speed > CGFloat(pack.tearSpeed) {
                vines[v].isAttached = false
                for i in vines[v].points.indices {
                    vines[v].previous[i].x -= move.dx * 0.35
                    vines[v].previous[i].y -= move.dy * 0.35 + 4
                }
                if pack.haptic { didTear = true }
            }
        }
    }

    func endTouch() {
        lastTouch = nil
    }

    private func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let ab = CGVector(dx: b.x - a.x, dy: b.y - a.y)
        let lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * ab.dx + (p.y - a.y) * ab.dy) / lengthSquared))
        return hypot(p.x - (a.x + ab.dx * t), p.y - (a.y + ab.dy * t))
    }


    private func visual(of vine: Vine, at index: Int, head: Bool, time: TimeInterval) -> VineVisual? {
        if head {
            if headImageCount > 0 { return .headImage(vine.seed % headImageCount) }
            if !pack.head.isEmpty { return .glyph(pack.head[vine.seed % pack.head.count], color: 0, head: true) }
        }
        let value: Int
        if pack.flicker {
            let tick = Int(time * (2 + Double((vine.seed + index) % 5))) + vine.seed * 31 + index * 7
            value = Int(UInt(bitPattern: tick &* 2_654_435_761) & UInt(Int.max))
        } else { value = vine.seed + index }
        if bodyImageCount > 0 { return .bodyImage(value % bodyImageCount) }
        guard !pack.glyphs.isEmpty else { return nil }
        let color = (pack.flicker ? vine.seed : vine.seed + index) % colorCount
        return .glyph(pack.glyphs[value % pack.glyphs.count], color: color, head: head)
    }

    private func renderFrame(time: TimeInterval) -> VineFrame {
        let strands = vines.map { vine in
            let n = vine.points.count
            let life = max(vine.life, 0)
            var nodes: [VineRenderNode] = []
            nodes.reserveCapacity(n)
            for i in 1..<n {
                let head = i == n - 1
                guard head || (pack.itemEvery > 0 && i % pack.itemEvery == 0),
                      let visual = visual(of: vine, at: i, head: head, time: time) else { continue }
                let p = vine.points[i]
                let neighbor = vine.points[head ? i - 1 : i + 1]
                let angle = atan2(neighbor.y - p.y, neighbor.x - p.x) - .pi / 2 + (head ? .pi : 0)
                let requestedSize = head ? CGFloat(pack.headSize.map { $0 * pack.scale } ?? Double(vine.glyphSize)) : vine.glyphSize
                let size = requestedSize
                let fade = pack.flicker ? 0.65 + 0.35 * Double(i) / Double(max(n - 1, 1)) : 1
                let transform = CGAffineTransform(rotationAngle: angle).scaledBy(x: size / 48, y: size / 48)
                nodes.append(VineRenderNode(point: p, transform: transform,
                                            opacity: vine.opacity * fade * life, visual: visual))
            }
            let path: VineThreadPath?
            if pack.thread != nil {
                let builder = CGMutablePath()
                builder.addLines(between: vine.points)
                path = builder.copy().map { VineThreadPath(value: $0) }
            } else { path = nil }
            return VineRenderStrand(id: vine.seed, points: vine.points, threadPath: path, opacity: life, nodes: nodes)
        }
        return VineFrame(strands: strands, size: size,
                         cleared: didReportCleared, didTear: didTear, audio: audioEvent)
    }
}
