//
//  MascotEngine+Geometry.swift
//  MascotKit
//

import SwiftUI

extension MascotEngine {
    var screen: CGSize { overlayFrame.size }
    var safeTop: CGFloat { max(contentFrame.minY - overlayFrame.minY, 20) }
    var floorY: CGFloat { overlayFrame.maxY - overlayFrame.minY - max(overlayFrame.maxY - contentFrame.maxY, 0) }
    var bottomY: CGFloat {
        occluders.compactMap { platforms[$0].map(local)?.minY }.reduce(floorY, min)
    }
    var spriteHeight: CGFloat { (character.map { $0.rig.size.height * 0.85 } ?? 60) * spriteScale }

    func local(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: -overlayFrame.minX, dy: -overlayFrame.minY) }
    func local(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x - overlayFrame.minX, y: point.y - overlayFrame.minY) }

    func setPlatform(_ id: String, frame: CGRect?, occludesBelow: Bool = false, hideBehind: Bool = false) {
        trackMotion(of: id, newFrame: frame)
        platforms[id] = frame
        if occludesBelow, frame != nil { occluders.insert(id) } else { occluders.remove(id) }
        if hideBehind, frame != nil { hideSpots.insert(id) } else { hideSpots.remove(id) }
    }

    func canHide(behind id: String) -> Bool {
        config.allowsHiding(behind: id, markedInCode: hideSpots.contains(id))
    }

    func setHome(frame: CGRect?) { homeFrame = frame }

    func surface(_ id: String) -> CGRect? {
        guard let global = platforms[id] else { return nil }
        let rect = local(predicted(global, for: id))
        guard rect.minY > safeTop + spriteHeight * 0.6, rect.minY < floorY - 4 else { return nil }
        for other in occluders where other != id {
            if let cover = platforms[other].map(local), rect.minY > cover.minY - 6 { return nil }
        }
        let minX = max(rect.minX + 10, 12), maxX = min(rect.maxX - 10, screen.width - 12)
        guard maxX - minX > 24 else { return nil }
        return CGRect(x: minX, y: rect.minY, width: maxX - minX, height: rect.height)
    }

    var surfaces: [(id: String, rect: CGRect)] {
        platforms.keys.compactMap { id in surface(id).map { (id, $0) } }
    }

    func currentSurface() -> CGRect? {
        platformID.flatMap(surface)
    }

    func landing(fromY: CGFloat, toY: CGFloat) -> (id: String, rect: CGRect)? {
        surfaces
            .filter { fromY <= $0.rect.minY + 2 && toY >= $0.rect.minY && ($0.rect.minX...$0.rect.maxX).contains(pos.x) }
            .min { $0.rect.minY < $1.rect.minY }
    }

    private static var geometryLags: Bool {
        if #available(iOS 16.0, *) { return false }
        return true
    }

    private func trackMotion(of id: String, newFrame: CGRect?) {
        guard Self.geometryLags else { return }
        let t = now
        guard let newFrame, let old = platforms[id], let last = platformMotion[id] else {
            platformMotion[id] = (.zero, t)
            return
        }
        let dt = t - last.reportedAt
        let velocity = dt > 0 && dt < 0.1
            ? CGVector(dx: (newFrame.minX - old.minX) / dt, dy: (newFrame.minY - old.minY) / dt)
            : .zero
        platformMotion[id] = (velocity, t)
    }

    private func predicted(_ frame: CGRect, for id: String) -> CGRect {
        guard Self.geometryLags, let motion = platformMotion[id] else { return frame }
        let age = now - motion.reportedAt
        guard age < 1.0 / 30 else { return frame }
        let ahead = age + 1.0 / 60
        return frame.offsetBy(dx: motion.velocity.dx * ahead, dy: motion.velocity.dy * ahead)
    }
}
