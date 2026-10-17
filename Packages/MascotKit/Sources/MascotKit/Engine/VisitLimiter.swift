//
//  VisitLimiter.swift
//  MascotKit
//
//  Лимиты реакций и реплик за один визит маскота (пока он на экране).
//  Сбрасывается, когда маскот ушёл и его позвали снова.
//

import Foundation

struct VisitLimiter {
    private var counts: [String: Int] = [:]

    mutating func reset() { counts = [:] }

    /// Можно ли сработать реакции ещё раз за этот визит. Если да — засчитывает срабатывание.
    mutating func allow(_ key: String, _ reaction: MascotReaction) -> Bool {
        if let limit = reaction.maxPerVisit, counts[key, default: 0] >= limit { return false }
        counts[key, default: 0] += 1
        return true
    }

    /// Какую реплику сказать: сначала гарантированные (first), пока не исчерпан их лимит за визит,
    /// иначе — случайная из обычных с вероятностью sayChance.
    /// - Parameter roll: случайное число 0…1 (подменяется в тестах).
    mutating func pickLine(for key: String,
                           in reaction: MascotReaction,
                           roll: () -> Double = { .random(in: 0..<1) }) -> (line: MascotLine, guaranteed: Bool)? {
        guard let lines = reaction.say, !lines.isEmpty else { return nil }
        let available = lines.indices.filter { i in
            guard let limit = lines[i].maxPerVisit else { return true }
            return counts[lineKey(key, i), default: 0] < limit
        }
        let index: Int
        let guaranteed: Bool
        if let first = available.first(where: { lines[$0].first == true }) {
            index = first
            guaranteed = true
        } else {
            let regular = available.filter { lines[$0].first != true }
            guard !regular.isEmpty, roll() < (reaction.sayChance ?? 1) else { return nil }
            index = regular[min(Int(roll() * Double(regular.count)), regular.count - 1)]
            guaranteed = false
        }
        counts[lineKey(key, index), default: 0] += 1
        return (lines[index], guaranteed)
    }

    private func lineKey(_ key: String, _ index: Int) -> String { "\(key)#\(index)" }
}
