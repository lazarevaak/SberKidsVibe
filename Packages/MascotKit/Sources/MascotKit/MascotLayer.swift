//
//  MascotLayer.swift
//  MascotKit
//
//  Слой, в котором живёт маскот: персонаж из деталей (RigSprite), реплики и касания.
//  Подключение и триггеры — в Mascot.swift.
//
//  Касания ловит только сам маскот — остальной экран работает как обычно.
//

import SwiftUI
import UIKit

// MARK: - Слой

struct PetLayer: View {
    let isRunning: Bool
    private let world = PetWorld.shared
    @ObservedObject private var presence = PetWorld.shared.presence
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
                        // Уменьшаем и картинку, и место под неё — касания ловит только видимый маскот.
                        .scaleEffect(metrics.scale)
                        .frame(width: metrics.size.width, height: metrics.size.height)
                        .contentShape(Rectangle())
                        .gesture(dragGesture)
                        .position(x: s.position.x - metrics.footOffset.x, y: s.position.y - metrics.footOffset.y)

                    if let text = s.bubble {
                        // Реплика растёт вверх от точки над головой, сколько бы строк в ней ни было.
                        let style = world.config.bubble
                        let width = CGFloat(style.maxWidth)
                        let screenWidth = world.overlayFrame.width
                        let margin: CGFloat = 8
                        SpeechBubble(text: text, style: style)
                            // Центр реплики — над маскотом, по её настоящей ширине (короткая фраза уже окна);
                            // у края экрана реплика сдвигается ровно настолько, чтобы влезть.
                            .alignmentGuide(.leading) { d in
                                let left = min(max(s.position.x - d.width / 2, margin), screenWidth - margin - d.width)
                                return -(left - margin)
                            }
                            // Ширина окна ограничивает перенос строк; растёт реплика вверх от головы.
                            .frame(width: width, height: 1, alignment: .bottomLeading)
                            .position(x: margin + width / 2,
                                      y: s.position.y - metrics.foot.y + metrics.head.y - 14 * metrics.scale - 6)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onGlobalFrameChange { world.overlayFrame = $0 }
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
                if isTap { world.tapped() } else { world.released(velocity: Self.velocity(of: value)) }
            }
    }

    /// Настоящая скорость жеста на iOS 17+; на старых — оценка по предсказанной точке остановки
    /// (SwiftUI предсказывает её примерно на четверть секунды вперёд).
    private static func velocity(of value: DragGesture.Value) -> CGSize {
        if #available(iOS 17.0, *) { return value.velocity }
        return CGSize(width: (value.predictedEndLocation.x - value.location.x) * 4,
                      height: (value.predictedEndLocation.y - value.location.y) * 4)
    }
}

/// Размеры текущего персонажа: где у него опора и голова.
private struct SpriteMetrics {
    let size: CGSize
    let foot: CGPoint
    let head: CGPoint
    /// Смещение центра рамки от точки опоры (с учётом того, куда он смотрит).
    let footOffset: CGPoint

    let scale: CGFloat

    /// Все размеры — уже с учётом масштаба.
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

// MARK: - Реплика

private struct SpeechBubble: View {
    let text: String
    let style: PetBubbleStyle

    var body: some View {
        let size = CGFloat(style.fontSize)
        Text(text)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(hexString: style.textColor) ?? Color(hex: 0x1C1C1E))
            .multilineTextAlignment(.center)
            .lineLimit(style.maxLines)
            .fixedSize(horizontal: false, vertical: true)
            // Отступы растут вместе со шрифтом, чтобы крупный текст не прилипал к краям.
            .padding(.horizontal, size * 0.75)
            .padding(.vertical, size * 0.42)
            .background(background)
            .shadow(color: .black.opacity(0.08 + 0.06 * style.opacity), radius: 6, y: 2)
    }

    /// Полупрозрачный фон: размытие того, что под репликой, + цвет фона с заданной непрозрачностью.
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
