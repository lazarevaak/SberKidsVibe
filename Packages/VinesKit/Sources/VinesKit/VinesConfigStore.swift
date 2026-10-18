//
//  VinesConfigStore.swift
//  VinesKit
//
//  Решает, показывать ли лианы, и готовит выбранный пак: конфиг берётся
//  только из CDN или его кэша, картинки скачиваются до показа.
//

import SwiftUI
import UIKit

/// Пак, готовый к показу: конфиг + уже загруженные картинки.
nonisolated struct PreparedVinePack: Sendable {
    let pack: VinePack
    let images: [String: UIImage]
    let sounds: [Data]
}

@MainActor
final class VinesConfigStore {
    static let shared = VinesConfigStore()

    private let lastShownKey = "vines.lastShownAt"

    func packToShow(configFile: String, ignoreCooldown: Bool = false) async -> PreparedVinePack? {
        guard let (config, baseURL) = await CDNContent.load(VinesConfig.self, file: configFile) else { return nil }

        if !ignoreCooldown, isCoolingDown(config.cooldownMinutes) { return nil }
        guard let pack = config.pickPack() else { return nil }

        guard let prepared = await prepare(pack, relativeTo: baseURL), !Task.isCancelled else { return nil }
        UserDefaults.standard.set(Date.now, forKey: lastShownKey)
        return prepared
    }

    private func prepare(_ pack: VinePack, relativeTo baseURL: URL?) async -> PreparedVinePack? {
        async let loadedImages = loadImages(pack.imageRefs, relativeTo: baseURL)
        async let loadedSounds = loadSounds(pack.sound, relativeTo: baseURL)
        let images = await loadedImages
        // Пак на одних картинках без единой загруженной картинки показывать нечем.
        let needsImages = !pack.images.isEmpty && pack.glyphs.isEmpty
        if needsImages && !pack.images.contains(where: { images[$0] != nil }) { return nil }
        let sounds = await loadedSounds

        guard !Task.isCancelled else { return nil }
        return PreparedVinePack(pack: pack, images: images, sounds: sounds)
    }

    private func isCoolingDown(_ minutes: Double) -> Bool {
        guard minutes > 0,
              let last = UserDefaults.standard.object(forKey: lastShownKey) as? Date else { return false }
        return Date.now.timeIntervalSince(last) < minutes * 60
    }

    private func loadImages(_ refs: [String], relativeTo baseURL: URL?) async -> [String: UIImage] {
        await withTaskGroup(of: (String, UIImage?).self, returning: [String: UIImage].self) { group in
            for ref in refs {
                group.addTask { (ref, await CDNContent.image(ref, relativeTo: baseURL)) }
            }
            var result: [String: UIImage] = [:]
            for await (ref, image) in group {
                if let image { result[ref] = image }
            }
            return result
        }
    }

    private func loadSounds(_ sound: VineSoundConfig, relativeTo baseURL: URL?) async -> [Data] {
        guard sound.enabled, sound.volume > 0 else { return [] }
        return await withTaskGroup(of: (Int, Data?).self, returning: [Data].self) { group in
            for (index, ref) in sound.files.enumerated() {
                group.addTask { (index, await CDNContent.data(ref, relativeTo: baseURL)) }
            }
            var result: [(Int, Data)] = []
            for await (index, data) in group {
                if let data { result.append((index, data)) }
            }
            return result.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
}
