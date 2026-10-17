//
//  VinesConfigStore.swift
//  VinesKit
//
//  Решает, показывать ли лианы, и готовит выбранный пак: конфиг берётся
//  через CDNContent (CDN → кэш → бандл), картинки скачиваются до показа,
//  поэтому лианы никогда не появляются «с дырками».
//

import SwiftUI
import UIKit

/// Пак, готовый к показу: конфиг + уже загруженные картинки.
struct PreparedVinePack {
    let pack: VinePack
    let images: [String: UIImage]
}

@MainActor
final class VinesConfigStore {
    static let shared = VinesConfigStore()

    private let lastShownKey = "vines.lastShownAt"

    func packToShow(configFile: String, bundledFallback: String) async -> PreparedVinePack? {
        guard let (config, baseURL) = await CDNContent.load(VinesConfig.self, file: configFile, bundled: bundledFallback) else { return nil }

        if config.cooldownMinutes > 0,
           let last = UserDefaults.standard.object(forKey: lastShownKey) as? Date,
           Date.now.timeIntervalSince(last) < config.cooldownMinutes * 60 {
            return nil
        }
        guard let pack = config.pickPack() else { return nil }

        var images: [String: UIImage] = [:]
        for ref in pack.imageRefs {
            if let image = await CDNContent.image(ref, relativeTo: baseURL) { images[ref] = image }
        }
        // Пак на одних картинках без единой загруженной картинки показывать нечем.
        let needsImages = !pack.images.isEmpty && pack.glyphs.isEmpty
        if needsImages && !pack.images.contains(where: { images[$0] != nil }) { return nil }

        UserDefaults.standard.set(Date.now, forKey: lastShownKey)
        return PreparedVinePack(pack: pack, images: images)
    }
}
