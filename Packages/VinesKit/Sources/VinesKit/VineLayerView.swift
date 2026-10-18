//
//  VineLayerView.swift
//  VinesKit
//

import SwiftUI
import UIKit

nonisolated struct VineSprite: Sendable {
    let image: CGImage
    let bounds: CGRect
    let anchor: CGPoint
}

nonisolated struct VineSpriteAtlas: Sendable {
    let sprites: [VineVisual: VineSprite]

    static func color(_ string: String?) -> UIColor? {
        guard var hex = string?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
        let rgba = hex.count == 6 ? value << 8 | 255 : value

        return UIColor(red: CGFloat((rgba >> 24) & 255) / 255,
                       green: CGFloat((rgba >> 16) & 255) / 255,
                       blue: CGFloat((rgba >> 8) & 255) / 255,
                       alpha: CGFloat(rgba & 255) / 255)
    }

    static func prepare(pack: VinePack, images: [String: UIImage], lite: Bool) -> Self {
        dispatchPrecondition(condition: .notOnQueue(.main))

        var sprites: [VineVisual: VineSprite] = [:]
        let palette = pack.colors.compactMap { color($0) }
        let colors = palette.isEmpty ? [UIColor.systemGreen] : palette
        let glow = lite ? nil : color(pack.glow)
        let format = UIGraphicsImageRendererFormat()

        format.scale = 2
        format.opaque = false

        func render(glyph: String?, image: UIImage?, tint: UIColor, head: Bool) -> VineSprite? {
            let aspect = image.map { $0.size.height / max(1, $0.size.width) } ?? 1
            let size = CGSize(width: 80, height: 48 * aspect + 32)
            let bounds = CGRect(origin: .zero, size: size)

            let bitmap = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
                if let glow { renderer.cgContext.setShadow(offset: .zero, blur: 6, color: glow.cgColor) }

                if let image {
                    image.draw(in: CGRect(x: 16, y: 16, width: 48, height: 48 * aspect))
                } else if let glyph {
                    let weight: UIFont.Weight = head ? .heavy : .bold
                    let font: UIFont

                    if pack.monospaced {
                        font = .monospacedSystemFont(ofSize: 48, weight: weight)
                    } else {
                        let base = UIFont.systemFont(ofSize: 48, weight: weight)
                        font = UIFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: 48)
                    }

                    let text = glyph as NSString
                    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: tint]
                    let measured = text.size(withAttributes: attributes)

                    text.draw(at: CGPoint(x: (size.width - measured.width) / 2,
                                          y: (size.height - measured.height) / 2),
                              withAttributes: attributes)
                }
            }

            guard let image = bitmap.cgImage else { return nil }

            return VineSprite(image: image, bounds: bounds,
                              anchor: CGPoint(x: 0.5, y: glyph == nil ? (16 + 48 * 0.15) / size.height : 0.5))
        }

        for glyph in pack.glyphs {
            let headSprite = pack.head.isEmpty
                ? render(glyph: glyph, image: nil, tint: color(pack.headColor) ?? colors[0], head: true)
                : nil

            for (index, tint) in colors.enumerated() {
                sprites[.glyph(glyph, color: index, head: false)] = render(glyph: glyph, image: nil, tint: tint, head: false)

                if let headSprite {
                    sprites[.glyph(glyph, color: index, head: true)] = headSprite
                }
            }
        }

        for glyph in pack.head {
            sprites[.glyph(glyph, color: 0, head: true)] = render(glyph: glyph, image: nil, tint: color(pack.headColor) ?? colors[0], head: true)
        }

        for (index, image) in pack.images.compactMap({ images[$0] }).enumerated() {
            sprites[.bodyImage(index)] = render(glyph: nil, image: image, tint: .white, head: false)
        }

        for (index, image) in pack.headImages.compactMap({ images[$0] }).enumerated() {
            sprites[.headImage(index)] = render(glyph: nil, image: image, tint: .white, head: true)
        }

        return Self(sprites: sprites)
    }
}

@MainActor
final class VineLayerView: UIView {
    nonisolated private final class SpriteLayer: CALayer {
        override func action(forKey event: String) -> (any CAAction)? { nil }
    }
    nonisolated private final class ThreadLayer: CAShapeLayer {
        override func action(forKey event: String) -> (any CAAction)? { nil }
    }
    private final class LinkTarget: NSObject {
        weak var owner: VineLayerView?
        @objc func tick(_ link: CADisplayLink) { owner?.tick(link) }
    }
    private final class StrandLayers {
        let thread = ThreadLayer()
        var nodes: [CALayer] = []
        var visuals: [VineVisual?] = []
        var opacities: [Float] = []
        var activeNodes = 0
    }
    private let field: VineField
    private let target = LinkTarget()
    private var link: CADisplayLink?
    private var requestedRunning = false
    private var revision = -1
    private var strands: [Int: StrandLayers] = [:]

    init(field: VineField) {
        self.field = field
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isOpaque = false
        target.owner = self
    }
    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        field.window = window
        updateClock()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        field.canvasFrame = convert(bounds, to: nil)
    }

    func setRunning(_ active: Bool) {
        requestedRunning = active
        updateClock()
    }

    private func updateClock() {
        let active = requestedRunning && window != nil
        field.setRunning(active)
        if active, link == nil {
            let next = CADisplayLink(target: target, selector: #selector(LinkTarget.tick(_:)))
            next.preferredFramesPerSecond = DevicePerformance.isLite ? 30 : 60
            next.add(to: .main, forMode: .common)
            link = next
        } else if !active {
            link?.invalidate()
            link = nil
        }
    }

    private func tick(_ link: CADisplayLink) {
        if revision != field.revision {
            revision = field.revision
            display(field.frame)
        }
        field.step(to: link.targetTimestamp, size: bounds.size)
    }

    func display(_ frame: VineFrame) {
        var layerCreationBudget = 48
        if frame.strands.count != strands.count || !frame.strands.allSatisfy({ strands[$0.id] != nil }) {
            let ids = Set(frame.strands.map(\.id))
            for id in Array(strands.keys) where !ids.contains(id) {
                guard let removed = strands.removeValue(forKey: id) else { continue }
                removed.thread.removeFromSuperlayer()
                for node in removed.nodes { node.removeFromSuperlayer() }
            }
        }
        for strand in frame.strands {
            let overlapsUI = field.uiOcclusions.contains { globalRect in
                let localRect = globalRect.offsetBy(dx: -field.canvasFrame.minX, dy: -field.canvasFrame.minY)
                guard strand.points.count > 1 else { return false }
                for index in 1..<strand.points.count {
                    let a = strand.points[index - 1], b = strand.points[index]
                    let segmentBounds = CGRect(x: min(a.x, b.x) - 18,
                                               y: min(a.y, b.y) - 18,
                                               width: abs(a.x - b.x) + 36,
                                               height: abs(a.y - b.y) + 36)
                    if localRect.intersects(segmentBounds) { return true }
                }
                return false
            }
            let visibility = overlapsUI ? field.overlapOpacity : 1
            let layers: StrandLayers
            if let existing = strands[strand.id] { layers = existing }
            else {
                layers = StrandLayers()
                strands[strand.id] = layers
                if let color = field.threadColor {
                    layers.thread.strokeColor = color
                    layers.thread.fillColor = nil
                    layers.thread.lineWidth = field.threadWidth
                    layers.thread.lineCap = .round
                    layers.thread.lineJoin = .round
                    layer.addSublayer(layers.thread)
                }
            }
            if field.threadColor != nil {
                layers.thread.path = strand.threadPath?.value
                layers.thread.opacity = Float(strand.opacity) * visibility
            }
            while layers.nodes.count < strand.nodes.count {
                guard layerCreationBudget > 0 else { break }
                let node = SpriteLayer()
                node.contentsGravity = .resize
                layer.addSublayer(node)
                layers.nodes.append(node)
                layers.visuals.append(nil)
                layers.opacities.append(-1)
                layerCreationBudget -= 1
            }
            let visibleNodeCount = min(strand.nodes.count, layers.nodes.count)
            for (index, node) in strand.nodes.prefix(visibleNodeCount).enumerated() {
                let spriteLayer = layers.nodes[index]
                if layers.visuals[index] != node.visual {
                    layers.visuals[index] = node.visual
                    let sprite = field.atlas.sprites[node.visual]
                    spriteLayer.contents = sprite?.image
                    spriteLayer.bounds = sprite?.bounds ?? .zero
                    spriteLayer.anchorPoint = sprite?.anchor ?? CGPoint(x: 0.5, y: 0.5)
                }
                if index >= layers.activeNodes { spriteLayer.isHidden = false }
                spriteLayer.position = node.point
                spriteLayer.setAffineTransform(node.transform)
                let opacity = Float(node.opacity) * visibility
                if layers.opacities[index] != opacity {
                    spriteLayer.opacity = opacity
                    layers.opacities[index] = opacity
                }
            }
            if visibleNodeCount < layers.activeNodes {
                for index in visibleNodeCount..<layers.activeNodes { layers.nodes[index].isHidden = true }
            }
            layers.activeNodes = visibleNodeCount
        }
    }
}
