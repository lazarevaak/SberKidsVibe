//
//  CharacterRig.swift
//  MascotKit
//

import SwiftUI
import UIKit

struct CharacterRig: Decodable {
    var size: CGSize
    var foot: CGPoint?
    var head: CGPoint?
    var parts: [RigPart]
    var animations: [String: RigAnimation]

    var footPoint: CGPoint { foot ?? CGPoint(x: size.width / 2, y: size.height) }
    var headPoint: CGPoint { head ?? CGPoint(x: size.width / 2, y: size.height * 0.25) }

    var imageRefs: Set<String> {
        var refs = Set<String>()
        for part in parts {
            if let image = part.image { refs.insert(image) }
            part.images?.values.forEach { refs.insert($0) }
            part.motion?.values.compactMap(\.image).forEach { refs.insert($0) }
        }
        return refs
    }

    private enum CodingKeys: String, CodingKey { case size, foot, head, parts, animations }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        size = try c.decode(PointPair.self, forKey: .size).size
        foot = try c.decodeIfPresent(PointPair.self, forKey: .foot)?.point
        head = try c.decodeIfPresent(PointPair.self, forKey: .head)?.point
        parts = try c.decode([RigPart].self, forKey: .parts)
        animations = try c.decodeIfPresent([String: RigAnimation].self, forKey: .animations) ?? [:]
    }
}

struct RigAnimation: Decodable {
    var duration: Double = 2
    var spin: Double?
    var bob: Double?
    var sway: Double?
    var freq: Double?
    var expression: String?
    var effect: String?
    var mirror = true

    private enum CodingKeys: String, CodingKey { case duration, spin, bob, sway, freq, expression, effect, mirror }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        duration = min(max(try c.decodeIfPresent(Double.self, forKey: .duration) ?? 2, 0.3), 15)
        spin = try c.decodeIfPresent(Double.self, forKey: .spin)
        bob = try c.decodeIfPresent(Double.self, forKey: .bob)
        sway = try c.decodeIfPresent(Double.self, forKey: .sway)
        freq = try c.decodeIfPresent(Double.self, forKey: .freq)
        expression = try c.decodeIfPresent(String.self, forKey: .expression)
        effect = try c.decodeIfPresent(String.self, forKey: .effect)
        mirror = try c.decodeIfPresent(Bool.self, forKey: .mirror) ?? true
    }
}

struct RigPart: Decodable {
    var id: String
    var image: String?
    var images: [String: String]?
    var size: CGSize
    var at: CGPoint
    var pivot: CGPoint
    var fit: Bool
    var motion: [String: RigMotion]?

    private enum CodingKeys: String, CodingKey { case id, image, images, size, at, pivot, fit, motion }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        image = try c.decodeIfPresent(String.self, forKey: .image)
        images = try c.decodeIfPresent([String: String].self, forKey: .images)
        size = try c.decode(PointPair.self, forKey: .size).size
        at = try c.decode(PointPair.self, forKey: .at).point
        pivot = try c.decodeIfPresent(PointPair.self, forKey: .pivot)?.point ?? CGPoint(x: 0.5, y: 0.5)
        fit = try c.decodeIfPresent(Bool.self, forKey: .fit) ?? false
        motion = try c.decodeIfPresent([String: RigMotion].self, forKey: .motion)
    }

    func motion(for state: String, orElse fallback: String? = nil) -> RigMotion? {
        motion?[state] ?? fallback.flatMap { motion?[$0] } ?? motion?["default"]
    }
}

struct RigMotion: Decodable {
    var rotate: Double?
    var swing: Double?
    var bob: Double?
    var sway: Double?
    var freq: Double?
    var phase: Double?
    var spin: Double?
    var dx: Double?
    var dy: Double?
    var scale: Double?
    var hidden: Bool?
    var image: String?
}

private struct PointPair: Decodable {
    let x: Double
    let y: Double
    var point: CGPoint { CGPoint(x: x, y: y) }
    var size: CGSize { CGSize(width: x, height: y) }

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        x = try c.decode(Double.self)
        y = try c.decode(Double.self)
    }
}

struct LoadedCharacter {
    let rig: CharacterRig
    let images: [String: UIImage]

    static func load(_ ref: String, relativeTo base: URL?) async -> LoadedCharacter? {
        guard let url = URL(string: ref, relativeTo: base)?.absoluteURL,
              let data = await CDNContent.data(url.absoluteString, relativeTo: nil) else { return nil }
        let rig: CharacterRig
        do {
            rig = try JSONDecoder().decode(CharacterRig.self, from: data)
        } catch {
            MascotLog.content.error("Не удалось разобрать персонажа \(ref, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
        let files = await CDNContent.data(rig.imageRefs, relativeTo: url)
        var images: [String: UIImage] = [:]
        for imageRef in rig.imageRefs {
            guard let image = files[imageRef].flatMap({ UIImage(data: $0, scale: 3) }) else {
                MascotLog.content.error("У персонажа \(ref, privacy: .public) не загрузилась картинка \(imageRef, privacy: .public) — персонаж не показывается")
                return nil
            }
            images[imageRef] = await image.byPreparingForDisplay() ?? image
        }
        return LoadedCharacter(rig: rig, images: images)
    }
}
