//
//  CDNContent.swift
//  MascotKit
//
//  Загрузка контента с CDN:
//    1. CDN (свежий, с таймаутом) → сохраняется в кэш;
//    2. кэш с прошлого удачного запуска — если сети нет.
//  Ничего не зашито в приложение: нет ни CDN, ни кэша — прикол просто не показывается.
//  Картинки и звуки кэшируются на диск навсегда по адресу.
//

import SwiftUI
import UIKit

@MainActor
enum CDNContent {
    private static var configuredBaseURL: URL?

    /// Папка с контентом на CDN. Приложение задаёт её через публичное contentURL.
    /// Для демо можно переопределить аргументом запуска `-CDNBaseURL https://…/cdn/`
    /// (или file:///…/cdn/ в симуляторе).
    static var baseURL: URL? {
        get {
            if let override = UserDefaults.standard.string(forKey: "CDNBaseURL") { return URL(string: override) }
            return configuredBaseURL
        }
        set { configuredBaseURL = newValue }
    }

    private static var cacheDirectory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cdn", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Загружает и декодирует конфиг. Возвращает его и адрес, от которого считать относительные пути картинок.
    static func load<T: Decodable>(_ type: T.Type, file: String) async -> (T, URL?)? {
        let cached = cacheDirectory.appendingPathComponent(file)
        let source = cacheDirectory.appendingPathComponent(file + ".source")

        if let url = URL(string: file, relativeTo: baseURL)?.absoluteURL,
           let data = await fetch(url), let value = decode(type, data, file) {
            try? data.write(to: cached)
            try? url.absoluteString.write(to: source, atomically: true, encoding: .utf8)
            return (value, url)
        }
        if let data = try? Data(contentsOf: cached), let value = decode(type, data, file) {
            let base = (try? String(contentsOf: source, encoding: .utf8)).flatMap(URL.init(string:))
            return (value, base)
        }
        return nil
    }

    /// "asset:имя" — из Assets.xcassets; иначе абсолютный URL или путь относительно конфига.
    static func image(_ ref: String, relativeTo base: URL?) async -> UIImage? {
        if ref.hasPrefix("asset:") { return UIImage(named: String(ref.dropFirst(6))) }
        return await data(ref, relativeTo: base).flatMap { UIImage(data: $0, scale: 3) }
    }

    /// Любой файл (картинка, звук): абсолютный URL или путь относительно конфига. Кэшируется на диск навсегда.
    static func data(_ ref: String, relativeTo base: URL?) async -> Data? {
        guard let url = URL(string: ref, relativeTo: base)?.absoluteURL else { return nil }
        // Файлы из бандла и локальные — читаем напрямую, кэшировать их незачем.
        if url.isFileURL { return try? Data(contentsOf: url) }
        let file = cacheDirectory.appendingPathComponent(cacheName(for: url))
        if let data = try? Data(contentsOf: file) { return data }
        guard let data = await fetch(url) else { return nil }
        try? data.write(to: file)
        return data
    }

    /// Несколько файлов сразу — параллельно, а не по одному: на мобильной сети это в разы быстрее.
    static func data(_ refs: Set<String>, relativeTo base: URL?) async -> [String: Data] {
        await withTaskGroup(of: (String, Data?).self) { group in
            for ref in refs {
                group.addTask { (ref, await CDNContent.data(ref, relativeTo: base)) }
            }
            var result: [String: Data] = [:]
            for await (ref, data) in group {
                if let data { result[ref] = data }
            }
            return result
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data, _ file: String) -> T? {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            print("CDN: не удалось разобрать \(file) — \(error)")
            return nil
        }
    }

    private static func fetch(_ url: URL) async -> Data? {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        return data
    }

    private static func cacheName(for url: URL) -> String {
        let safe = url.absoluteString.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" }
        return "img_" + String(String(safe).suffix(120))
    }
}

/// Сезон в формате "MM-dd", повторяется каждый год; может переходить через Новый год.
enum Season {
    static func isActive(from: String?, to: String?, on date: Date = .now) -> Bool {
        guard let start = monthDay(from), let end = monthDay(to) else { return from == nil && to == nil }
        let parts = Calendar.current.dateComponents([.month, .day], from: date)
        let today = (parts.month ?? 1) * 100 + (parts.day ?? 1)
        return start <= end ? (start...end).contains(today) : (today >= start || today <= end)
    }

    private static func monthDay(_ string: String?) -> Int? {
        guard let parts = string?.split(separator: "-").compactMap({ Int($0) }), parts.count == 2 else { return nil }
        return parts[0] * 100 + parts[1]
    }
}

extension KeyedDecodingContainer {
    /// decodeIfPresent со значением по умолчанию — чтобы в JSON можно было писать только нужные поля.
    func value<T: Decodable>(_ key: Key, default value: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? value
    }
}
