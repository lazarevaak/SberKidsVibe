//
//  VineChainSound.swift
//  VinesKit
//

import AVFoundation

actor VineChainSound {
    private var players: [Int: AVAudioPlayer] = [:]
    private let settings: VineSoundConfig
    private let clips: [Data]
    private var generation = -1
    private var active = false

    init(settings: VineSoundConfig, clips: [Data]) {
        self.settings = settings
        self.clips = clips
    }

    func setRunning(_ active: Bool, generation: Int) {
        guard generation >= self.generation else { return }
        self.generation = generation
        self.active = active
        if !active { stop() }
    }

    func apply(_ event: VineAudioEvent, generation: Int) {
        guard active, generation == self.generation, settings.enabled, settings.volume > 0 else { return }
        switch event {
        case .fade:
            for player in players.values where player.isPlaying { player.setVolume(0, fadeDuration: 0.06) }
            return
        case .play: break
        }
        guard case .play(let volume, let rate) = event, !clips.isEmpty else { return }
        let start = Int.random(in: clips.indices)
        guard let index = (0..<clips.count).lazy.map({ (start + $0) % self.clips.count })
            .first(where: { self.players[$0]?.isPlaying != true }) else { return }
        let player: AVAudioPlayer
        if let cached = players[index] { player = cached }
        else {
            guard let created = try? AVAudioPlayer(data: clips[index]) else { return }
            created.enableRate = true
            players[index] = created
            player = created
        }
        let session = AVAudioSession.sharedInstance()
        if session.category == .soloAmbient { try? session.setCategory(.ambient, options: [.mixWithOthers]) }

        player.currentTime = 0
        player.volume = volume
        player.rate = rate
        player.play()
    }

    private func stop() {
        for player in players.values {
            player.stop()
            player.currentTime = 0
        }
    }
}
