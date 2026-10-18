//
//  MascotLayer.swift
//  MascotKit
//

import SwiftUI
import UIKit

struct MascotLayerView: View {
    let isRunning: Bool
    private let world = MascotEngine.shared
    @ObservedObject private var presence = MascotEngine.shared.presence
    @State private var dragStart: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: DevicePerformance.minimumFrameInterval,
                                paused: !presence.isVisible || !isRunning)) { _ in
            ZStack(alignment: .topLeading) {
                if let s = world.step(), let character = world.character {
                    if let rope = s.rope {
                        Path { p in
                            p.move(to: CGPoint(x: s.position.x, y: rope.top))
                            p.addLine(to: CGPoint(x: s.position.x, y: rope.bottom))
                        }
                        .stroke(Color(hex: 0x8A5A2B), lineWidth: 1.5)
                        .allowsHitTesting(false)
                    }

                    let metrics = SpriteMetrics(character: character, facing: s.facing, scale: world.spriteScale)

                    RigSprite(s: s, character: character, hat: world.hat, hideHat: world.skin?.hat == "none")
                        .scaleEffect(metrics.scale)
                        .frame(width: metrics.size.width, height: metrics.size.height)
                        .modifier(BehindEdge(sink: s.sink, edge: metrics.foot.y, width: metrics.size.width))
                        .contentShape(Rectangle())
                        .gesture(dragGesture)
                        .position(x: s.position.x - metrics.footOffset.x, y: s.position.y - metrics.footOffset.y)

                    if let text = s.bubble {
                        let style = world.config.bubble
                        let width = CGFloat(style.maxWidth)
                        let screenWidth = world.overlayFrame.width
                        let margin: CGFloat = 8
                        SpeechBubble(text: text, style: style, expanded: s.bubbleExpanded)
                            .alignmentGuide(.leading) { d in
                                let left = min(max(s.position.x - d.width / 2, margin), screenWidth - margin - d.width)
                                return -(left - margin)
                            }
                            .frame(width: width, height: 1, alignment: .bottomLeading)
                            .position(x: margin + width / 2,
                                      y: s.position.y - metrics.foot.y + metrics.head.y - 14 * metrics.scale - 6 + s.sink)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onGlobalFrameChange { world.overlayFrame = $0 }
        .onAppear { world.setSensorsActive(isRunning) }
        .onChange(of: isRunning) { world.setSensorsActive($0) }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = .now
                    world.touchBegan(at: value.startLocation)
                }
                if hypot(value.translation.width, value.translation.height) > 6 {
                    world.dragged(to: value.location)
                }
            }
            .onEnded { value in
                let isTap = hypot(value.translation.width, value.translation.height) <= 6
                    && Date.now.timeIntervalSince(dragStart ?? .now) < 0.35
                dragStart = nil
                world.touchEnded()
                if isTap { world.tapped() } else { world.released(velocity: Self.velocity(of: value)) }
            }
    }

    private static func velocity(of value: DragGesture.Value) -> CGSize {
        if #available(iOS 17.0, *) { return value.velocity }
        return CGSize(width: (value.predictedEndLocation.x - value.location.x) * 4,
                      height: (value.predictedEndLocation.y - value.location.y) * 4)
    }
}

private struct SpriteMetrics {
    let size: CGSize
    let foot: CGPoint
    let head: CGPoint
    let footOffset: CGPoint

    let scale: CGFloat

    init(character: LoadedCharacter, facing: CGFloat, scale: CGFloat) {
        self.scale = scale
        let drawn = character.rig.size
        let drawnFoot = character.rig.footPoint
        let drawnHead = character.rig.headPoint
        size = CGSize(width: drawn.width * scale, height: drawn.height * scale)
        foot = CGPoint(x: drawnFoot.x * scale, y: drawnFoot.y * scale)
        head = CGPoint(x: drawnHead.x * scale, y: drawnHead.y * scale)
        let footX = facing >= 0 ? foot.x : size.width - foot.x
        footOffset = CGPoint(x: footX - size.width / 2, y: foot.y - size.height / 2)
    }
}

private struct BehindEdge: ViewModifier {
    let sink: CGFloat
    let edge: CGFloat
    let width: CGFloat
    private let overhang: CGFloat = 120

    func body(content: Content) -> some View {
        if sink > 0 {
            content
                .offset(y: sink)
                .mask(alignment: .top) {
                    Rectangle()
                        .frame(width: width + overhang * 2, height: edge + overhang)
                        .offset(y: -overhang)
                }
        } else {
            content
        }
    }
}

private struct SpeechBubble: View {
    let text: String
    let style: MascotBubbleStyle
    let expanded: Bool

    var body: some View {
        let size = CGFloat(style.fontSize)
        Text(style.display(text, expanded: expanded))
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(hexString: style.textColor) ?? Color(hex: 0x1C1C1E))
            .multilineTextAlignment(.center)
            .lineLimit(expanded ? nil : style.maxLines)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, size * 0.75)
            .padding(.vertical, size * 0.42)
            .background(background)
            .shadow(color: .black.opacity(DevicePerformance.isLite ? 0 : 0.08 + 0.06 * style.opacity), radius: 6, y: 2)
    }

    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: CGFloat(style.cornerRadius), style: .continuous)
        let tint = (Color(hexString: style.background) ?? .white).opacity(style.opacity)
        return ZStack {
            if style.blur { shape.fill(.ultraThinMaterial) }
            shape.fill(tint)
            shape.stroke(Color.white.opacity(0.5), lineWidth: 0.5)
        }
    }
}
