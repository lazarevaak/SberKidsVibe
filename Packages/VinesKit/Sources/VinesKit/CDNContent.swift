//
//  CDNContent.swift
//  VinesKit
//
//  Загрузка контента лиан только с CDN или из кэша ранее загруженного CDN.
//  Картинки кэшируются на диск навсегда по адресу.
//

import SwiftUI
import UIKit

nonisolated enum CDNContent {
    @MainActor private static var configuredBaseURL: URL?

    /// Папка с контентом на CDN. Приложение задаёт её через публичное contentURL.
    /// Для демо можно переопределить аргументом запуска `-CDNBaseURL https://…/cdn/`
    /// (или file:///…/cdn/ в симуляторе).
    @MainActor static var baseURL: URL? {
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
    @concurrent
    static func load<T: Decodable & Sendable>(_ type: T.Type, file: String) async -> (T, URL?)? {
        let baseURL = await baseURL
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

    /// Абсолютный URL или путь относительно CDN-конфига.
    @concurrent
    static func image(_ ref: String, relativeTo base: URL?) async -> UIImage? {
        guard let url = URL(string: ref, relativeTo: base)?.absoluteURL else { return nil }

        let file = cacheDirectory.appendingPathComponent(cacheName(for: url))
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data, scale: 3) { return image }
        guard let data = await fetch(url), let image = UIImage(data: data, scale: 3) else { return nil }
        try? data.write(to: file)
        return image
    }

    /// Звук: путь от конфига или полный URL. Файлы кэшируются после загрузки.
    @concurrent
    static func data(_ ref: String, relativeTo base: URL?) async -> Data? {
        guard !ref.hasPrefix("bundle:") else { return nil }
        guard let url = URL(string: ref, relativeTo: base)?.absoluteURL else { return nil }
        let cached = cacheDirectory.appendingPathComponent("audio_" + cacheName(for: url))
        if let data = try? Data(contentsOf: cached) { return data }
        guard let data = await fetch(url), !Task.isCancelled else { return nil }
        try? data.write(to: cached)
        return data
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
        if url.isFileURL { return try? Data(contentsOf: url) }
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
nonisolated enum Season {
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
    nonisolated func value<T: Decodable>(_ key: Key, default value: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? value
    }
}
