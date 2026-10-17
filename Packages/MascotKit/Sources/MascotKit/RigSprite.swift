//
//  RigSprite.swift
//  MascotKit
//
//  Рисует персонажа из деталей по CharacterRig. Код ничего не знает о том,
//  кто перед ним — обезьянка или машинка: всё берёт из character.json.
//

import SwiftUI
import UIKit

struct RigSprite: View {
    let s: PetSnapshot
    let character: LoadedCharacter
    /// Шапка из сезонного костюма: подменяет деталь "hat".
    let hat: UIImage?
    let hideHat: Bool

    private var rig: CharacterRig { character.rig }

    /// Имя состояния в character.json.
    private var state: String {
        if let animation = s.animation { return animation }
        return switch s.mode {
        case .walking: "walk"
        case .idle: "idle"
        case .sitting: "sit"
        case .sleeping: "sleep"
        case .waving: "wave"
        case .dancing: "dance"
        case .celebrating: "celebrate"
        case .grabbed: "grabbed"
        case .airborne, .leaving: "air"
        case .dizzy: "dizzy"
        case .descending: "descend"
        case .performing, .hidden: "idle"
        }
    }

    /// «Часы» колебаний: в движении — шаги (ноги в такт ходьбе), в покое — время.
    private var clock: Double {
        switch s.mode {
        case .walking, .airborne, .grabbed, .dancing, .celebrating, .descending, .leaving, .performing: s.walkPhase
        default: s.time * 2.2
        }
    }

    private var expressionKey: String {
        switch s.expression {
        case .normal: s.blink ? "blink" : "normal"
        case .happy: "happy"
        case .dizzy: "dizzy"
        case .sleepy: "sleepy"
        case .scared: "scared"
        }
    }

    private var currentAnimation: RigAnimation? { s.animation.flatMap { rig.animations[$0] } }

    private var wholeBody: (angle: Double, dx: CGFloat, dy: CGFloat) {
        guard let animation = currentAnimation else { return (0, 0, 0) }
        let phase = s.modeTime * (animation.freq ?? 2) * 2 * Double.pi
        let angle = (animation.spin ?? 0) * s.modeTime
        let dx = CGFloat((animation.sway ?? 0) * sin(phase))
        let dy = CGFloat(-(animation.bob ?? 0) * abs(sin(phase)))
        return (angle, dx, dy)
    }

    private var effect: MascotEffects.Effect {
        if let animation = currentAnimation {
            return MascotEffects.Effect(rawValue: animation.effect ?? "") ?? .none
        }
        switch s.mode {
        case .dizzy: return .stars
        case .sleeping: return .zzz
        case .celebrating: return .sparkles
        default: return .none
        }
    }

    private var footAnchor: UnitPoint {
        UnitPoint(x: rig.footPoint.x / rig.size.width, y: rig.footPoint.y / rig.size.height)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(rig.parts.indices, id: \.self) { index in
                part(rig.parts[index])
            }
            MascotEffects(effect: effect, time: s.time, head: rig.headPoint, center: CGPoint(x: rig.size.width / 2, y: rig.size.height / 2))
        }
        .frame(width: rig.size.width, height: rig.size.height)
        // Своя анимация двигает персонажа целиком: вращение, подпрыгивания, покачивание.
        .rotationEffect(.degrees(wholeBody.angle))
        .offset(x: wholeBody.dx, y: wholeBody.dy)
        // Все детали — одним растровым слоем; отступ — чтобы не обрезались эффекты и размах лап.
        .padding(24)
        .drawingGroup()
        .padding(-24)
        .scaleEffect(x: s.facing * (1 + s.squash), y: 1 - s.squash, anchor: footAnchor)
        .rotationEffect(.degrees(s.spin))
        .scaleEffect(s.scale, anchor: footAnchor)
    }

    @ViewBuilder
    private func part(_ part: RigPart) -> some View {
        let motion = part.motion(for: state)
        if motion?.hidden != true, let image = image(for: part, motion: motion) {
            let pose = self.pose(of: part, motion: motion)
            PartImage(image: image, fit: part.fit)
                .frame(width: part.size.width, height: part.size.height)
                .scaleEffect(pose.scale, anchor: pose.pivot)
                .rotationEffect(.degrees(pose.angle), anchor: pose.pivot)
                .position(pose.center)
        }
    }

    private struct Pose {
        var angle: Double
        var scale: CGFloat
        var pivot: UnitPoint
        var center: CGPoint
    }

    /// Поза детали в этом кадре: постоянный поворот и сдвиг + колебания по «часам» + вращение.
    private func pose(of part: RigPart, motion: RigMotion?) -> Pose {
        let frequency = motion?.freq ?? 1
        let phase = (motion?.phase ?? 0) * 2 * Double.pi
        let oscillation = sin(clock * frequency + phase)

        var angle = motion?.rotate ?? 0
        angle += (motion?.swing ?? 0) * oscillation
        angle += (motion?.spin ?? 0) * clock

        let dx = (motion?.dx ?? 0) + (motion?.sway ?? 0) * oscillation
        let dy = (motion?.dy ?? 0) + (motion?.bob ?? 0) * oscillation
        let center = CGPoint(x: part.at.x + (0.5 - part.pivot.x) * part.size.width + CGFloat(dx),
                             y: part.at.y + (0.5 - part.pivot.y) * part.size.height + CGFloat(dy))
        return Pose(angle: angle,
                    scale: CGFloat(motion?.scale ?? 1),
                    pivot: UnitPoint(x: part.pivot.x, y: part.pivot.y),
                    center: center)
    }

    /// Картинка детали: картинка состояния → картинка эмоции → обычная. Шапку может подменить костюм.
    private func image(for part: RigPart, motion: RigMotion?) -> UIImage? {
        if part.id == "hat" {
            if hideHat { return nil }
            if let hat { return hat }
        }
        let ref = motion?.image
            ?? part.images?[expressionKey]
            ?? (expressionKey == "blink" ? part.images?["normal"] : nil)
            ?? part.images?["normal"]
            ?? part.image
        return ref.flatMap { character.images[$0] }
    }
}

private struct PartImage: View {
    let image: UIImage
    let fit: Bool

    var body: some View {
        if fit {
            Image(uiImage: image).resizable().scaledToFit()
        } else {
            Image(uiImage: image).resizable()
        }
    }
}

/// Звёздочки над головой, «z» во сне, искорки радости — общие для всех персонажей.
struct MascotEffects: View {
    enum Effect: String { case none, stars, zzz, sparkles }

    let effect: Effect
    let time: TimeInterval
    let head: CGPoint
    let center: CGPoint

    var body: some View {
        switch effect {
        case .stars:
            ForEach(0..<3, id: \.self) { i in
                let a = time * 4 + Double(i) * 2.09
                Image(systemName: "star.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(Color(hex: 0xFFC83D))
                    .position(x: head.x + cos(a) * 16, y: head.y - 6 + sin(a) * 4)
            }
        case .zzz:
            ForEach(0..<3, id: \.self) { i in
                let u = (time * 0.5 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                Text("z")
                    .font(.system(size: 8 + u * 6, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x6E7BA8).opacity(1 - u))
                    .position(x: head.x + 16 + u * 10, y: head.y - u * 18)
            }
        case .sparkles:
            ForEach(0..<4, id: \.self) { i in
                let a = Double(i) * 1.57 + time * 3
                Image(systemName: "sparkle")
                    .font(.system(size: 8))
                    .foregroundStyle([Color(hex: 0xFFC83D), Color(hex: 0x3DBE55), Color(hex: 0x8E7BEF), Color(hex: 0xFF6FB5)][i])
                    .position(x: center.x + cos(a) * 26, y: center.y + sin(a) * 22)
            }
        case .none:
            EmptyView()
        }
    }
}
