//
//  SoundBank.swift
//  MascotKit
//
//  Короткие звуки маскота. Файлы приходят с CDN и кэшируются, проигрыватели
//  создаются один раз при загрузке. Звук всегда — ответ на действие, сам не играет.
//  Уважает беззвучный режим и не прерывает музыку, которую слушает пользователь.
//

import AVFoundation
import QuartzCore

final class SoundBank {
    private var players: [String: [AVAudioPlayer]] = [:]
    private var lastPlayed: [String: TimeInterval] = [:]
    private var volume: Float = 0.6

    func load(_ clips: [String: [String]], settings: PetSounds, relativeTo base: URL?) async {
        guard settings.enabled, !clips.isEmpty else { return }
        Self.prepareSession()
        volume = Float(min(max(settings.volume, 0), 1))

        for (key, refs) in clips {
            var list: [AVAudioPlayer] = []
            for ref in refs {
                guard let data = await CDNContent.data(ref, relativeTo: base),
                      let player = try? AVAudioPlayer(data: data) else { continue }
                player.prepareToPlay()
                list.append(player)
            }
            if !list.isEmpty { players[key] = list }
        }
        #if DEBUG
        print("MascotKit: звуков загружено \(players.count) из \(clips.count)")
        #endif
    }

    /// - Parameters:
    ///   - gain: громкость относительно общей (например, тише для мягкого приземления).
    ///   - minInterval: не повторять этот звук чаще — чтобы не было «пулемёта».
    func play(_ key: String, gain: Float = 1, minInterval: TimeInterval = 0.12) {
        guard let player = players[key]?.randomElement() else { return }
        let now = CACurrentMediaTime()
        if let last = lastPlayed[key], now - last < minInterval { return }
        lastPlayed[key] = now
        player.currentTime = 0
        player.volume = volume * min(max(gain, 0), 1)
        player.play()
    }

    /// Если приложение само не настраивало звук (категория по умолчанию), включаем .ambient:
    /// молчит в беззвучном режиме и смешивается с музыкой. Настройки приложения не трогаем.
    private static func prepareSession() {
        let session = AVAudioSession.sharedInstance()
        guard session.category == .soloAmbient else { return }
        try? session.setCategory(.ambient, options: [.mixWithOthers])
    }
}
