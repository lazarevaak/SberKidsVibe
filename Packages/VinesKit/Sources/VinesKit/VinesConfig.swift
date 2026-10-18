//
//  VinesConfig.swift
//  VinesKit
//

import SwiftUI

nonisolated struct VinesConfig: Decodable, Sendable {
    var enabled = true
    var cooldownMinutes: Double = 0
    var forcePack: String?
    var packs: [VinePack] = []

    private enum CodingKeys: String, CodingKey { case enabled, cooldownMinutes, forcePack, packs }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        cooldownMinutes = try c.decodeIfPresent(Double.self, forKey: .cooldownMinutes) ?? cooldownMinutes
        forcePack = try c.decodeIfPresent(String.self, forKey: .forcePack)
        packs = (try c.decodeIfPresent([Failable<VinePack>].self, forKey: .packs) ?? []).compactMap { $0.value }
    }

    func pickPack(on date: Date = .now) -> VinePack? {
        guard enabled else { return nil }
        if let forcePack, let pack = packs.first(where: { $0.id == forcePack }) { return pack }

        let active = packs.filter { $0.weight > 0 && $0.isActive(on: date) }
        let total = active.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return nil }
        var roll = Double.random(in: 0..<total)
        for pack in active {
            roll -= pack.weight
            if roll < 0 { return pack }
        }
        return active.last
    }
}

nonisolated struct VinePack: Decodable, Identifiable, Sendable {
    var id: String
    var weight: Double = 1
    var from: String?
    var to: String?

    var glyphs: [String] = ["6", "7"]
    var images: [String] = []
    var head: [String] = []
    var headImages: [String] = []
    var itemEvery = 1
    var flicker = false

    var scale: Double = 1.35
    var colors: [String] = ["#12B33A"]
    var headColor: String?
    var thread: String?
    var threadWidth: Double = 1.2
    var glow: String?
    var monospaced = true
    var glyphSize: [Double] = [10, 17]
    var headSize: Double?

    var count: Int?
    var spacing: Double?
    var length: [Double] = [0.1, 0.34]
    var sway: Double = 1
    var overlapOpacity: Double = 0.38
    var tearSpeed: Double = 1100
    var haptic = true
    var sound = VineSoundConfig()

    private enum CodingKeys: String, CodingKey {
        case id, weight, from, to, glyphs, images, head, headImages, itemEvery, flicker
        case scale, colors, headColor, thread, threadWidth, glow, monospaced, glyphSize, headSize
        case count, spacing, length, sway, overlapOpacity, tearSpeed, haptic, sound
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        weight = try c.decodeIfPresent(Double.self, forKey: .weight) ?? weight
        from = try c.decodeIfPresent(String.self, forKey: .from)
        to = try c.decodeIfPresent(String.self, forKey: .to)
        images = try c.decodeIfPresent([String].self, forKey: .images) ?? images
        glyphs = try c.decodeIfPresent([String].self, forKey: .glyphs) ?? (images.isEmpty ? glyphs : [])
        head = try c.decodeIfPresent([String].self, forKey: .head) ?? head
        headImages = try c.decodeIfPresent([String].self, forKey: .headImages) ?? headImages
        itemEvery = try c.decodeIfPresent(Int.self, forKey: .itemEvery) ?? itemEvery
        flicker = try c.decodeIfPresent(Bool.self, forKey: .flicker) ?? flicker
        scale = min(max(try c.decodeIfPresent(Double.self, forKey: .scale) ?? scale, 0.6), 2)
        colors = try c.decodeIfPresent([String].self, forKey: .colors) ?? colors
        headColor = try c.decodeIfPresent(String.self, forKey: .headColor)
        thread = try c.decodeIfPresent(String.self, forKey: .thread)
        threadWidth = try c.decodeIfPresent(Double.self, forKey: .threadWidth) ?? threadWidth
        glow = try c.decodeIfPresent(String.self, forKey: .glow)
        monospaced = try c.decodeIfPresent(Bool.self, forKey: .monospaced) ?? monospaced
        glyphSize = try c.decodeIfPresent([Double].self, forKey: .glyphSize) ?? glyphSize
        headSize = try c.decodeIfPresent(Double.self, forKey: .headSize)
        count = try c.decodeIfPresent(Int.self, forKey: .count)
        spacing = try c.decodeIfPresent(Double.self, forKey: .spacing).map { min(max($0, 0.03), 1) }
        length = try c.decodeIfPresent([Double].self, forKey: .length) ?? length
        sway = try c.decodeIfPresent(Double.self, forKey: .sway) ?? sway
        overlapOpacity = min(max(try c.decodeIfPresent(Double.self, forKey: .overlapOpacity) ?? overlapOpacity, 0), 1)
        tearSpeed = try c.decodeIfPresent(Double.self, forKey: .tearSpeed) ?? tearSpeed
        haptic = try c.decodeIfPresent(Bool.self, forKey: .haptic) ?? haptic
        sound = try c.decodeIfPresent(VineSoundConfig.self, forKey: .sound) ?? sound
    }

    func isActive(on date: Date) -> Bool {
        Season.isActive(from: from, to: to, on: date)
    }

    var imageRefs: [String] { images + headImages }
}

nonisolated struct VineSoundConfig: Decodable, Sendable {
    var enabled = true
    var volume: Double = 1
    var files: [String] = []

    init() {}

    private enum CodingKeys: String, CodingKey { case enabled, volume, files }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        volume = min(max(try c.decodeIfPresent(Double.self, forKey: .volume) ?? volume, 0), 1)
        files = try c.decodeIfPresent([String].self, forKey: .files) ?? files
    }
}

nonisolated private struct Failable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}
