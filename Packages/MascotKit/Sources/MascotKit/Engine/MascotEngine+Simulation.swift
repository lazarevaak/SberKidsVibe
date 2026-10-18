//
//  MascotEngine+Simulation.swift
//  MascotKit
//

import SwiftUI

extension MascotEngine {
    func step() -> MascotSnapshot? {
        let t = now
        let dt = CGFloat(min(t - (lastStep ?? t), MascotTuning.maxStep))
        lastStep = t
        guard mode != .hidden else { return nil }
        if screen != lastScreenSize {
            if lastScreenSize != .zero { screenDidResize() }
            lastScreenSize = screen
        }

        squash *= CGFloat(pow(0.002, Double(dt)))
        if scale < 1, mode != .leaving { scale = min(1, scale + dt * 3) }
        updateRope(dt)

        switch mode {
        case .hidden:
            return nil
        case .descending:
            stepDescending(dt)
        case .airborne:
            guard stepAirborne(dt) else { return nil }
        case .grabbed:
            walkPhase += Double(dt) * 16
        case .leaving:
            guard stepLeaving(t) else { return nil }
        case .walking, .idle, .sitting, .waving, .sleeping, .dizzy, .dancing, .celebrating, .performing, .hiding:
            stepGrounded(dt, t)
        }
        return snapshot(t)
    }

    private func stepDescending(_ dt: CGFloat) {
        let fall = MascotTuning.descendSpeed * dt
        pos.y += fall
        if let rope { self.rope = (rope.top, pos.y - spriteHeight) }
        walkPhase += Double(dt) * 4
        if let hit = landing(fromY: pos.y - fall, toY: pos.y) {
            land(on: hit.id, rect: hit.rect)
            isRopeRetracting = true
        } else if pos.y >= bottomY {
            isRopeRetracting = true
            bounceOffBottom()
        }
    }

    private func stepAirborne(_ dt: CGFloat) -> Bool {
        let previous = pos
        vel.dx += gravity.dx * MascotTuning.tiltPushInAir * dt
        vel.dy += MascotTuning.gravity * dt
        pos.x += vel.dx * dt
        pos.y += vel.dy * dt
        spin += spinSpeed * Double(dt)
        walkPhase += Double(dt) * 14

        if isThrown, pos.x < -60 || pos.x > screen.width + 60 || pos.y > screen.height + 80 {
            hide()
            return false
        }
        if !isThrown {
            let margin = MascotTuning.wallMargin
            if pos.x < margin { pos.x = margin; vel.dx = abs(vel.dx) * MascotTuning.wallBounce }
            if pos.x > screen.width - margin { pos.x = screen.width - margin; vel.dx = -abs(vel.dx) * MascotTuning.wallBounce }
        }
        if vel.dy > 0, let hit = landing(fromY: previous.y, toY: pos.y) {
            land(on: hit.id, rect: hit.rect)
        } else if !isThrown, pos.y >= bottomY {
            bounceOffBottom()
        }
        return true
    }

    private func stepLeaving(_ t: TimeInterval) -> Bool {
        guard let leave else { hide(); return false }
        let u = min(1, (t - leave.start) / MascotTuning.leaveDuration)
        let x = leave.from.x + (leave.to.x - leave.from.x) * u
        let y = leave.from.y + (leave.to.y - leave.from.y) * u - MascotTuning.leaveArcHeight * 4 * u * (1 - u)
        pos = CGPoint(x: x, y: y)
        scale = u > 0.55 ? max(0.05, 1 - (u - 0.55) / 0.45) : 1
        if u >= 1 {
            react("disappear")
            hide()
            return false
        }
        return true
    }

    private func stepGrounded(_ dt: CGFloat, _ t: TimeInterval) {
        guard let rect = currentSurface() else {
            vel = CGVector(dx: facing * 60, dy: 0)
            setMode(.airborne)
            return
        }
        if let last = lastSurfaceRect, abs(rect.minY - last.minY) > 90 || abs(rect.minX - last.minX) > 90 {
            dropFromCurrentPlace()
            return
        }
        lastSurfaceRect = rect
        pos = CGPoint(x: rect.minX + platformOffset, y: rect.minY)

        if slideOnTilt(dt, t, along: rect) { return }
        if gravity.dy > MascotTuning.upsideDown { react("upsideDown") }

        switch mode {
        case .walking:
            platformOffset += facing * CGFloat(config.walkSpeed) * dt
            walkPhase += Double(dt) * 9
            if platformOffset < 0 || platformOffset > rect.width {
                platformOffset = min(max(platformOffset, 0), rect.width)
                if Double.random(in: 0..<1) < MascotTuning.edgeJumpChance {
                    vel = CGVector(dx: facing * MascotTuning.edgeJump.dx, dy: MascotTuning.edgeJump.dy)
                    setMode(.airborne)
                    return
                }
                facing = -facing
            }
        case .sleeping:
            react("snore", gain: 0.6)
        case .dizzy where t - modeStart > 0.5:
            react("dizzy", gain: 0.7)
        case .hiding:
            facing = Int((t - modeStart) / MascotTuning.peekLookInterval).isMultiple(of: 2) ? 1 : -1
        case .performing:
            walkPhase += Double(dt) * 10
        case .dancing, .celebrating:
            walkPhase += Double(dt) * 10
            facing = Int((t - modeStart) / 0.35).isMultiple(of: 2) ? 1 : -1
        default:
            break
        }

        if t - modeStart > modeDuration { nextBehavior() }
        if t - lastInteraction > config.stayMinutes * 60, mode != .sleeping { goHome() }
    }

    private func slideOnTilt(_ dt: CGFloat, _ t: TimeInterval, along rect: CGRect) -> Bool {
        let tilt = gravity.dx
        guard abs(tilt) > MascotTuning.tiltThreshold,
              mode != .sleeping || abs(tilt) > MascotTuning.strongTilt else { return false }
        if mode == .hiding { setMode(.idle, duration: MascotTuning.idleDuration) }
        platformOffset += tilt * MascotTuning.slideSpeed * dt
        facing = tilt > 0 ? 1 : -1
        walkPhase += Double(dt) * 12
        expressionOverride = (.scared, t + 0.3)
        react("tilt")
        if platformOffset < 0 || platformOffset > rect.width {
            vel = CGVector(dx: tilt * 240, dy: -60)
            setMode(.airborne)
        }
        return true
    }

    func land(on id: String, rect: CGRect) {
        lastSurfaceRect = nil
        platformID = id
        platformOffset = pos.x - rect.minX
        pos.y = rect.minY
        afterLanding()
    }

    private func bounceOffBottom() {
        pos.y = bottomY
        platformID = nil
        lastSurfaceRect = nil
        spin = 0; spinSpeed = 0
        guard !surfaces.isEmpty else { goHome(); return }
        hop(nearest: true)
    }

    private func afterLanding() {
        let impact = vel.dy
        let isHard = dizzyOnLanding || impact > MascotTuning.hardLandingImpact
        vel = .zero
        spin = 0; spinSpeed = 0
        isThrown = false
        squash = min(max(impact, 300) / 2400, 0.35)

        if isHard {
            dizzyOnLanding = false
            setMode(.dizzy, duration: MascotTuning.dizzyDuration)
            react("hardLanding")
            haptics.medium.impactOccurred()
            return
        }
        react("land", gain: Float(min(max(impact / 1200, 0.35), 1)))
        if let name = pendingAnimation {
            pendingAnimation = nil
            setMode(.idle, duration: 0.3)
            animate(name, byUser: true)
        } else if mode == .descending {
            setMode(.waving, duration: MascotTuning.duration(of: .wave))
        } else {
            setMode(.idle, duration: MascotTuning.settleDuration)
        }
    }

    private func screenDidResize() {
        platformMotion.removeAll()
        switch mode {
        case .leaving: hide()
        case .grabbed: break
        default: dropFromCurrentPlace()
        }
    }

    private func dropFromCurrentPlace() {
        lastSurfaceRect = nil
        rope = nil
        isRopeRetracting = false
        pos.x = min(max(pos.x, 16), max(screen.width - 16, 16))
        pos.y = min(max(pos.y, safeTop), bottomY - 1)
        vel = CGVector(dx: 0, dy: -120)
        platformID = nil
        setMode(.airborne)
    }

    func setMode(_ newMode: MascotMode, duration: TimeInterval = 0) {
        if newMode == .celebrating, mode != .celebrating { react("celebrate") }
        mode = newMode
        modeStart = now
        modeDuration = duration
    }

    func hide() {
        setMode(.hidden)
        bubble = nil
        holdStart = nil
        rope = nil
        Task { @MainActor in
            self.presence.isVisible = false
            self.updateMotion()
        }
    }

    private func updateRope(_ dt: CGFloat) {
        guard isRopeRetracting, let current = rope else { return }
        let bottom = current.bottom - MascotTuning.ropeRetractSpeed * dt
        rope = bottom <= current.top ? nil : (current.top, bottom)
        if rope == nil { isRopeRetracting = false }
    }

    private func hideDepth(_ t: TimeInterval) -> CGFloat {
        guard mode == .hiding, let rig = character?.rig else { return 0 }
        let u = t - modeStart
        let progress = CGFloat(min(max(min(u, modeDuration - u) / MascotTuning.hideDive, 0), 1))
        let eased = progress * progress * (3 - 2 * progress)
        let height = (rig.footPoint.y - rig.headPoint.y) * spriteScale
        let fidget = CGFloat(sin(u * 2.4)) * 1.5 * eased
        return max(height * (1 - MascotTuning.peekVisible) * eased + fidget, 0)
    }

    private func snapshot(_ t: TimeInterval) -> MascotSnapshot {
        var expression: MascotExpression
        switch mode {
        case .sleeping: expression = .sleepy
        case .dizzy: expression = .dizzy
        case .grabbed: expression = .scared
        case .airborne: expression = isThrown || dizzyOnLanding ? .scared : .happy
        case .celebrating, .dancing, .waving, .leaving: expression = .happy
        case .performing:
            expression = performing
                .flatMap { character?.rig.animations[$0]?.expression }
                .flatMap(MascotExpression.init(rawValue:)) ?? .happy
        default: expression = .normal
        }
        if let override = expressionOverride, override.until > t { expression = override.expression }

        let animation = mode == .performing ? performing : nil
        let mirrored = animation.flatMap { character?.rig.animations[$0]?.mirror } ?? true

        return MascotSnapshot(
            position: pos,
            facing: mirrored ? facing : 1,
            mode: mode,
            expression: expression,
            walkPhase: walkPhase,
            squash: squash,
            spin: spin,
            scale: scale,
            rope: rope,
            bubble: bubble.flatMap { $0.until > t || isBeingRead($0) ? $0.text : nil },
            sink: hideDepth(t),
            bubbleExpanded: isHolding,
            blink: t.truncatingRemainder(dividingBy: 3.4) < 0.12,
            time: t,
            animation: animation,
            modeTime: t - modeStart
        )
    }
}
