//
//  VinesConfig.swift
//  VinesKit
//
//  Схема конфига лиан, который лежит на CDN. Все поля пака необязательны —
//  контент-менеджер указывает только то, что хочет поменять.
//

import SwiftUI

struct VinesConfig: Decodable {
    /// Глобальный выключатель пасхалки.
    var enabled = true
    /// Не показывать лианы чаще, чем раз в N минут. 0 — при каждом открытии.
    var cooldownMinutes: Double = 0
    /// Принудительно показать пак по id (для демо и тестов), игнорируя расписание и веса.
    var forcePack: String?
    var packs: [VinePack] = []

    private enum CodingKeys: String, CodingKey { case enabled, cooldownMinutes, forcePack, packs }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        cooldownMinutes = try c.decodeIfPresent(Double.self, forKey: .cooldownMinutes) ?? cooldownMinutes
        forcePack = try c.decodeIfPresent(String.self, forKey: .forcePack)
        // Битый пак не должен ломать весь конфиг — просто пропускаем его.
        packs = (try c.decodeIfPresent([Failable<VinePack>].self, forKey: .packs) ?? []).compactMap(\.value)
    }

    /// Пак для показа: принудительный, иначе случайный по весам среди активных сегодня.
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

struct VinePack: Decodable, Identifiable {
    var id: String
    var weight: Double = 1
    /// Сезон в формате "MM-dd", повторяется каждый год. Можно через Новый год: "12-15" … "01-10".
    var from: String?
    var to: String?

    // Что висит на лиане
    /// Текстовые символы звеньев (цифры, буквы, эмодзи).
    var glyphs: [String] = ["0", "1"]
    /// Картинки звеньев (URL, относительный путь от конфига или "asset:имя"). Важнее, чем glyphs.
    var images: [String] = []
    /// Символ или картинка на кончике лианы.
    var head: [String] = []
    var headImages: [String] = []
    /// Рисовать звено на каждом N-м сегменте. 0 — только нить и кончик.
    var itemEvery = 1
    /// Символы мерцают и сменяют друг друга, как в Матрице.
    var flicker = false

    // Внешний вид
    var colors: [String] = ["#12B33A"]
    var headColor: String?
    /// Цвет нити между звеньями. Нет — нить не рисуется.
    var thread: String?
    var threadWidth: Double = 1.2
    var glow: String?
    var monospaced = true
    var glyphSize: [Double] = [10, 17]
    var headSize: Double?

    // Поведение
    var count: Int?
    var length: [Double] = [0.1, 0.34]
    var sway: Double = 1
    var tearSpeed: Double = 1100
    var haptic = true

    private enum CodingKeys: String, CodingKey {
        case id, weight, from, to, glyphs, images, head, headImages, itemEvery, flicker
        case colors, headColor, thread, threadWidth, glow, monospaced, glyphSize, headSize
        case count, length, sway, tearSpeed, haptic
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        weight = try c.decodeIfPresent(Double.self, forKey: .weight) ?? weight
        from = try c.decodeIfPresent(String.self, forKey: .from)
        to = try c.decodeIfPresent(String.self, forKey: .to)
        images = try c.decodeIfPresent([String].self, forKey: .images) ?? images
        // Пак на картинках не должен молча превращаться в «0/1», если картинки не загрузились.
        glyphs = try c.decodeIfPresent([String].self, forKey: .glyphs) ?? (images.isEmpty ? glyphs : [])
        head = try c.decodeIfPresent([String].self, forKey: .head) ?? head
        headImages = try c.decodeIfPresent([String].self, forKey: .headImages) ?? headImages
        itemEvery = try c.decodeIfPresent(Int.self, forKey: .itemEvery) ?? itemEvery
        flicker = try c.decodeIfPresent(Bool.self, forKey: .flicker) ?? flicker
        colors = try c.decodeIfPresent([String].self, forKey: .colors) ?? colors
        headColor = try c.decodeIfPresent(String.self, forKey: .headColor)
        thread = try c.decodeIfPresent(String.self, forKey: .thread)
        threadWidth = try c.decodeIfPresent(Double.self, forKey: .threadWidth) ?? threadWidth
        glow = try c.decodeIfPresent(String.self, forKey: .glow)
        monospaced = try c.decodeIfPresent(Bool.self, forKey: .monospaced) ?? monospaced
        glyphSize = try c.decodeIfPresent([Double].self, forKey: .glyphSize) ?? glyphSize
        headSize = try c.decodeIfPresent(Double.self, forKey: .headSize)
        count = try c.decodeIfPresent(Int.self, forKey: .count)
        length = try c.decodeIfPresent([Double].self, forKey: .length) ?? length
        sway = try c.decodeIfPresent(Double.self, forKey: .sway) ?? sway
        tearSpeed = try c.decodeIfPresent(Double.self, forKey: .tearSpeed) ?? tearSpeed
        haptic = try c.decodeIfPresent(Bool.self, forKey: .haptic) ?? haptic
    }

    func isActive(on date: Date) -> Bool {
        Season.isActive(from: from, to: to, on: date)
    }

    /// Все ссылки на картинки пака — их надо скачать до показа.
    var imageRefs: [String] { images + headImages }
}

// MARK: - Helpers

/// Декодирует элемент массива, а при ошибке отдаёт nil вместо падения всего массива.
private struct Failable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}
