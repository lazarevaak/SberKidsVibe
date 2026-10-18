import QuartzCore
import os

/// Включается аргументом -LaunchDiagnostics; не меняет данные или конфигурацию приложения.
@MainActor
final class LaunchDiagnostics: NSObject {
    static let shared = LaunchDiagnostics()
    private let logger = Logger(subsystem: "AlfaKids.Performance", category: "Launch")
    private var clock: CADisplayLink?
    private var started: CFTimeInterval = 0
    private var previous: CFTimeInterval?
    private var gaps: [Double] = []

    func start() {
        guard ProcessInfo.processInfo.arguments.contains("-LaunchDiagnostics") else { return }
        started = CACurrentMediaTime()
        logger.notice("launch started")
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFramesPerSecond = 60
        link.add(to: .main, forMode: .common)
        clock = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        if let previous {
            let gap = (now - previous) * 1000
            gaps.append(gap)
            if gap >= 50 { logger.warning("main gap ms=\(gap, privacy: .public) elapsed=\(now - self.started, privacy: .public)") }
        } else { logger.notice("first display callback ms=\((now - self.started) * 1000, privacy: .public)") }
        previous = now
        if now - started >= 12 {
            clock?.invalidate()
            clock = nil
            let sorted = gaps.sorted()
            guard !sorted.isEmpty else { return }
            let p95 = sorted[Int(Double(sorted.count - 1) * 0.95)]
            logger.notice("launch cadence samples=\(sorted.count) p95_ms=\(p95, privacy: .public) max_ms=\(sorted.last!, privacy: .public) gaps_over_50ms=\(sorted.filter { $0 >= 50 }.count)")
        }
    }
}
