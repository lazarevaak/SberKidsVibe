//
//  MascotLayer.swift
//  MascotKit
//
//  Слой, в котором рисуется маскот, и его внешний вид.
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
                if let s = world.step() {
                    if let rope = s.rope {
                        Path { p in
                            p.move(to: CGPoint(x: s.position.x, y: rope.top))
                            p.addLine(to: CGPoint(x: s.position.x, y: rope.bottom))
                        }
                        .stroke(Color(hex: 0x8A5A2B), lineWidth: 1.5)
                        .allowsHitTesting(false)
                    }

                    PetSprite(s: s, skin: world.skin, hat: world.hat)
                        .contentShape(Rectangle())
                        .gesture(dragGesture)
                        .position(x: s.position.x, y: s.position.y - PetSprite.size.height / 2)

                    if let text = s.bubble {
                        SpeechBubble(text: text)
                            .fixedSize()
                            .position(x: min(max(s.position.x, 80), world.overlayFrame.width - 80),
                                      y: s.position.y - PetSprite.size.height - 22)
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

// MARK: - Реплика

private struct SpeechBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(hex: 0x1C1C1E))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}

// MARK: - Обезьянка

/// Рисуется кодом, а не кадрами — поэтому позы и эмоции бесплатные,
/// а с CDN приходят только цвета и шапка.
struct PetSprite: View {
    static let size = CGSize(width: 64, height: 72)

    let s: PetSnapshot
    let skin: PetSkin?
    let hat: UIImage?

    private var fur: Color { Color(hexString: skin?.fur) ?? Color(hex: 0x7A4B2C) }
    private var furDark: Color { Color(hex: 0x4E2F1A) }
    private var face: Color { Color(hexString: skin?.face) ?? Color(hex: 0xE8B98F) }

    private var isSitting: Bool { s.mode == .sitting || s.mode == .sleeping || s.mode == .dizzy }
    private var isMoving: Bool { [.walking, .airborne, .grabbed, .dancing, .celebrating, .descending].contains(s.mode) }

    var body: some View {
        let swing = isMoving ? sin(s.walkPhase) : 0
        let bodyDrop: CGFloat = isSitting ? 7 : 0

        ZStack {
            tail.offset(y: bodyDrop)
            legs(swing: swing)
            // Туловище
            Ellipse().fill(LinearGradient(colors: [fur, furDark], startPoint: .top, endPoint: .bottom))
                .frame(width: 28, height: 26).position(x: 32, y: 52 + bodyDrop)
            Ellipse().fill(face.opacity(0.9))
                .frame(width: 15, height: 15).position(x: 32, y: 55 + bodyDrop)
            arms(swing: swing).offset(y: bodyDrop)
            head.offset(y: bodyDrop + (s.mode == .dancing || s.mode == .celebrating ? CGFloat(abs(sin(s.walkPhase))) * -3 : 0))
            effects.offset(y: bodyDrop)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        // Десятки фигур рисуются одним растровым слоем — дешевле для видеокарты.
        // Отступ — чтобы не обрезались звёздочки и «z» над головой.
        .padding(16)
        .drawingGroup()
        .padding(-16)
        .scaleEffect(x: s.facing * (1 + s.squash), y: 1 - s.squash, anchor: .bottom)
        .rotationEffect(.degrees(s.spin))
        .scaleEffect(s.scale, anchor: .bottom)
    }

    // MARK: Части тела

    private var tail: some View {
        Path { p in
            p.move(to: CGPoint(x: 18, y: 58))
            p.addCurve(to: CGPoint(x: 6, y: 40), control1: CGPoint(x: 4, y: 60), control2: CGPoint(x: 0, y: 48))
            p.addQuadCurve(to: CGPoint(x: 13, y: 38), control: CGPoint(x: 10, y: 33))
        }
        .stroke(furDark, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        .rotationEffect(.degrees(sin(s.time * 2.2) * 6), anchor: UnitPoint(x: 0.28, y: 0.8))
    }

    private func legs(swing: Double) -> some View {
        let angle = isSitting ? 70.0 : swing * 30
        return ZStack {
            leg.rotationEffect(.degrees(isSitting ? -angle : angle), anchor: .top).position(x: 26, y: isSitting ? 66 : 67)
            leg.rotationEffect(.degrees(isSitting ? angle : -angle), anchor: .top).position(x: 38, y: isSitting ? 66 : 67)
        }
    }

    private var leg: some View {
        Capsule().fill(furDark).frame(width: 6.5, height: 12)
    }

    private func arms(swing: Double) -> some View {
        let wave = sin(s.time * 12) * 25
        let (left, right): (Double, Double) = switch s.mode {
        case .waving: (15, -150 + wave)
        case .celebrating, .dancing: (150 + wave, -150 - wave)
        case .grabbed, .airborne: (120 + swing * 20, -120 - swing * 20)
        case .descending: (160, -160)
        case .sitting, .sleeping: (-10, 10)
        default: (-swing * 25, swing * 25)
        }
        return ZStack {
            arm.rotationEffect(.degrees(left), anchor: .top).position(x: 20, y: 50)
            arm.rotationEffect(.degrees(right), anchor: .top).position(x: 44, y: 50)
        }
    }

    private var arm: some View {
        Capsule().fill(fur).frame(width: 5.5, height: 14).offset(y: 5)
    }

    private var head: some View {
        ZStack {
            Circle().fill(furDark).frame(width: 13).position(x: 17, y: 25)
            Circle().fill(furDark).frame(width: 13).position(x: 47, y: 25)
            Circle().fill(face).frame(width: 7).position(x: 17, y: 25)
            Circle().fill(face).frame(width: 7).position(x: 47, y: 25)
            Circle().fill(LinearGradient(colors: [fur, furDark], startPoint: .top, endPoint: .bottom))
                .frame(width: 30, height: 30).position(x: 32, y: 24)
            Ellipse().fill(face).frame(width: 23, height: 18).position(x: 33, y: 29)
            eyes
            mouth
            hatView
        }
    }

    @ViewBuilder
    private var eyes: some View {
        switch s.expression {
        case .happy:
            ForEach([28.0, 38.0], id: \.self) { x in
                Path { p in p.addArc(center: CGPoint(x: x, y: 26), radius: 3, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false) }
                    .stroke(Color(hex: 0x2B1A10), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
        case .sleepy:
            ForEach([28.0, 38.0], id: \.self) { x in
                Capsule().fill(Color(hex: 0x2B1A10)).frame(width: 6, height: 1.6).position(x: x, y: 25)
            }
        case .dizzy:
            ForEach([28.0, 38.0], id: \.self) { x in
                Circle().trim(from: 0, to: 0.8)
                    .stroke(Color(hex: 0x2B1A10), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    .frame(width: 6, height: 6)
                    .rotationEffect(.degrees(s.time * 720))
                    .position(x: x, y: 25)
            }
        case .scared, .normal:
            let big = s.expression == .scared
            ForEach([28.0, 38.0], id: \.self) { x in
                ZStack {
                    Circle().fill(.white).frame(width: big ? 9 : 7.5)
                    Circle().fill(Color(hex: 0x1C1C1E)).frame(width: big ? 2.6 : 4).offset(x: 1.2)
                }
                .scaleEffect(y: s.blink && !big ? 0.1 : 1)
                .position(x: x, y: 25)
            }
        }
    }

    @ViewBuilder
    private var mouth: some View {
        switch s.expression {
        case .happy:
            Ellipse().fill(Color(hex: 0xC2413B)).frame(width: 7, height: 5).position(x: 33, y: 33)
        case .scared:
            Ellipse().fill(Color(hex: 0x2B1A10)).frame(width: 4, height: 5).position(x: 33, y: 34)
        default:
            Path { p in p.addArc(center: CGPoint(x: 33, y: 31.5), radius: 3, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false) }
                .stroke(Color(hex: 0x2B1A10), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
    }

    @ViewBuilder
    private var hatView: some View {
        if skin?.hat == "none" {
            EmptyView()
        } else if let hat {
            Image(uiImage: hat).resizable().scaledToFit().frame(width: 36).position(x: 32, y: 9)
        } else {
            // Шапка как на аватарке.
            Ellipse().fill(LinearGradient(colors: [Color(hex: 0xE07A3A), Color(hex: 0xA94E20)], startPoint: .top, endPoint: .bottom))
                .frame(width: 30, height: 18).position(x: 32, y: 13)
            Capsule().fill(Color(hex: 0x8C3F18)).frame(width: 32, height: 6).position(x: 32, y: 18)
        }
    }

    @ViewBuilder
    private var effects: some View {
        switch s.mode {
        case .dizzy:
            ForEach(0..<3, id: \.self) { i in
                let a = s.time * 4 + Double(i) * 2.09
                Image(systemName: "star.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(Color(hex: 0xFFC83D))
                    .position(x: 32 + cos(a) * 16, y: 6 + sin(a) * 4)
            }
        case .sleeping:
            ForEach(0..<3, id: \.self) { i in
                let u = (s.time * 0.5 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                Text("z")
                    .font(.system(size: 8 + u * 6, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x6E7BA8).opacity(1 - u))
                    .position(x: 48 + u * 10, y: 12 - u * 18)
            }
        case .celebrating:
            ForEach(0..<4, id: \.self) { i in
                let a = Double(i) * 1.57 + s.time * 3
                Image(systemName: "sparkle")
                    .font(.system(size: 8))
                    .foregroundStyle([Color(hex: 0xFFC83D), Color(hex: 0x3DBE55), Color(hex: 0x8E7BEF), Color(hex: 0xFF6FB5)][i])
                    .position(x: 32 + cos(a) * 26, y: 30 + sin(a) * 22)
            }
        default:
            EmptyView()
        }
    }
}
