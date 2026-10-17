//
//  HangingVines.swift
//  VinesKit
//
//  Пасхалка: лианы свисают с верхнего края экрана, покачиваются и
//  срываются резким смахом. Что именно висит (матрица 0/1, паутина с
//  пауком, новогодняя гирлянда…) задаётся паком в конфиге на CDN —
//  см. VinesConfig и cdn/vines.json. Адрес CDN — Vines.contentURL.
//
//  Лианы не перехватывают касания — весь UI под ними продолжает работать.
//
//  Использование:
//      import VinesKit
//
//      Vines.contentURL = URL(string: "https://cdn.example.com/fun/")   // один раз при старте
//
//      HomeView()
//          .hangingVines()
//

import SwiftUI
import UIKit

/// Настройка лиан.
public enum Vines {
    /// Папка на CDN с vines.json и картинками. Задаётся один раз при старте приложения.
    public static var contentURL: URL? {
        get { CDNContent.baseURL }
        set { CDNContent.baseURL = newValue }
    }
}

extension View {
    /// Навешивает на экран свисающие сверху лианы из конфига.
    /// - Parameters:
    ///   - isActive: показывать ли пасхалку на этом экране.
    ///   - configFile: имя конфига в папке `Vines.contentURL`.
    ///   - bundledFallback: имя JSON в бандле приложения — если нет ни сети, ни кэша.
    ///   - onCleared: вызывается, когда смахнули все лианы.
    public func hangingVines(isActive: Bool = true,
                             configFile: String = "vines.json",
                             bundledFallback: String = "vines_default",
                             onCleared: (() -> Void)? = nil) -> some View {
        modifier(HangingVinesModifier(isActive: isActive, configFile: configFile, bundledFallback: bundledFallback, onCleared: onCleared))
    }
}

// MARK: - Modifier

private struct HangingVinesModifier: ViewModifier {
    let isActive: Bool
    let configFile: String
    let bundledFallback: String
    let onCleared: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var field: VineField?
    @State private var isOnScreen = false

    private var isShown: Bool { isActive && !reduceMotion && field != nil }

    func body(content: Content) -> some View {
        content
            .overlay {
                if isShown, let field {
                    VinesCanvas(field: field, isRunning: isOnScreen && scenePhase == .active) {
                        withAnimation { self.field = nil }
                        onCleared?()
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .onAppear { isOnScreen = true }
            .onDisappear { isOnScreen = false }
            .background(WindowSwipeCatcher(isEnabled: isShown) { location, time in
                field?.handleTouch(atGlobal: location, time: time)
            } onEnd: {
                field?.endTouch()
            })
            // Конфиг и картинки грузятся в фоне уже после первого кадра —
            // запуск и главный экран не ждут сеть.
            .task(id: scenePhase) {
                guard scenePhase == .active, isActive, !reduceMotion, field == nil else { return }
                guard let prepared = await VinesConfigStore.shared.packToShow(configFile: configFile, bundledFallback: bundledFallback) else { return }
                field = VineField(prepared: prepared)
            }
    }
}

// MARK: - Canvas

private struct VinesCanvas: View {
    let field: VineField
    let isRunning: Bool
    let onCleared: () -> Void

    var body: some View {
        // Анимация стоит, когда приложение свёрнуто или экран закрыт другим.
        TimelineView(.animation(minimumInterval: DevicePerformance.minimumFrameInterval, paused: !isRunning)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                field.step(to: time, size: size)
                field.draw(in: &context, time: time)
            }
        }
        .onGlobalFrameChange { field.canvasFrame = $0 }
        .onAppear { field.onCleared = onCleared }
    }
}

// MARK: - Gesture

/// Пан на всём окне, который распознаётся одновременно со скроллом и не отменяет касания под собой.
/// Сама вьюха невидима и касаний не принимает — она только вешает распознаватель на окно.
/// Координаты — глобальные (окна).
private struct WindowSwipeCatcher: UIViewRepresentable {
    let isEnabled: Bool
    let onChange: (CGPoint, TimeInterval) -> Void
    let onEnd: () -> Void

    func makeUIView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: CatcherView, context: Context) {
        view.recognizer.isEnabled = isEnabled
        view.onChange = onChange
        view.onEnd = onEnd
    }

    static func dismantleUIView(_ view: CatcherView, coordinator: ()) {
        view.detach()
    }

    final class CatcherView: UIView, UIGestureRecognizerDelegate {
        let recognizer = UIPanGestureRecognizer()
        var onChange: ((CGPoint, TimeInterval) -> Void)?
        var onEnd: (() -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            recognizer.addTarget(self, action: #selector(handle(_:)))
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            detach()
            window?.addGestureRecognizer(recognizer)
        }

        func detach() {
            recognizer.view?.removeGestureRecognizer(recognizer)
        }

        @objc private func handle(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed:
                onChange?(recognizer.location(in: nil), CACurrentMediaTime())
            default:
                onEnd?()
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

// MARK: - Physics

private struct Vine {
    var points: [CGPoint]
    var previous: [CGPoint]
    var anchor: CGPoint
    var segment: CGFloat
    var glyphSize: CGFloat
    var opacity: Double
    var phase: Double
    var seed: Int
    var isAttached = true
    var life: Double = 1
}

/// Верёвочная физика (Verlet) для всех лиан. Ссылочный тип, чтобы его можно было
/// мутировать прямо из Canvas и из распознавателя жестов без лишних перерисовок.
private final class VineField {
    var canvasFrame: CGRect = .zero
    var onCleared: (() -> Void)?

    private let pack: VinePack
    private let images: [String: UIImage]
    private let bodyColors: [Color]
    private let headColor: Color
    private let threadColor: Color?
    private let glowColor: Color?
    /// Эмодзи заранее отрисованы в картинки: Canvas не умеет цветные глифы в resolve(Text).
    private var emojiImages: [String: UIImage] = [:]

    private var vines: [Vine] = []
    private var size: CGSize = .zero
    private var lastTime: TimeInterval?
    private var accumulator: TimeInterval = 0
    private var simTime: TimeInterval = 0
    private var lastTouch: (point: CGPoint, time: TimeInterval)?
    private var didSpawn = false
    private var didReportCleared = false
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private let lite = DevicePerformance.isLite

    private let gravity: CGFloat = 1500
    private let fixedStep: TimeInterval = 1.0 / 120
    private let damping: CGFloat = 0.985
    private let touchRadius: CGFloat = 26

    init(prepared: PreparedVinePack) {
        pack = prepared.pack
        images = prepared.images
        let colors = pack.colors.compactMap { Color(hexString: $0) }
        bodyColors = colors.isEmpty ? [.green] : colors
        headColor = Color(hexString: pack.headColor) ?? bodyColors[0]
        threadColor = Color(hexString: pack.thread)
        glowColor = Color(hexString: pack.glow)
        for glyph in pack.glyphs + pack.head where !glyph.unicodeScalars.allSatisfy(\.isASCII) {
            emojiImages[glyph] = Self.render(emoji: glyph)
        }
    }

    private static func render(emoji: String) -> UIImage {
        let font = UIFont.systemFont(ofSize: 48)
        let text = emoji as NSString
        let size = text.size(withAttributes: [.font: font])
        return UIGraphicsImageRenderer(size: size).image { _ in
            text.draw(at: .zero, withAttributes: [.font: font])
        }
    }

    // MARK: Setup

    private func spawn(in size: CGSize) {
        didSpawn = true
        var rng = SystemRandomNumberGenerator()
        let fullCount = max(1, pack.count ?? max(6, Int(size.width / 34)))
        // На слабых устройствах лиан меньше.
        let count = lite ? max(1, Int((Double(fullCount) * 0.6).rounded())) : fullCount
        let spacing = size.width / CGFloat(count)
        let glyphRange = range(pack.glyphSize, fallback: 10...17)
        let lengthRange = range(pack.length, fallback: 0.1...0.34)

        vines = (0..<count).map { index in
            let glyph = CGFloat.random(in: glyphRange, using: &rng)
            let segment = glyph * 1.05
            let length = size.height * CGFloat.random(in: lengthRange, using: &rng)
            let links = max(5, Int(length / segment))
            let x = spacing * (CGFloat(index) + 0.5) + .random(in: -spacing * 0.3...spacing * 0.3, using: &rng)
            let anchor = CGPoint(x: x, y: -2)
            // Стартуем свёрнутыми над краем — при открытии лианы «падают» и раскачиваются.
            let points = (0..<links).map { i in
                CGPoint(x: x + .random(in: -6...6, using: &rng), y: anchor.y - CGFloat(i) * segment * 0.35)
            }
            return Vine(points: points,
                        previous: points,
                        anchor: anchor,
                        segment: segment,
                        glyphSize: glyph,
                        opacity: pack.flicker ? .random(in: 0.55...1, using: &rng) : 1,
                        phase: .random(in: 0...(2 * .pi), using: &rng),
                        seed: .random(in: 0...10_000, using: &rng))
        }
    }

    private func range(_ values: [Double], fallback: ClosedRange<CGFloat>) -> ClosedRange<CGFloat> {
        guard values.count == 2 else { return fallback }
        let low = CGFloat(min(values[0], values[1])), high = CGFloat(max(values[0], values[1]))
        return low...high
    }

    // MARK: Simulation

    func step(to time: TimeInterval, size: CGSize) {
        if !didSpawn && size.width > 0 { spawn(in: size) }
        self.size = size

        let delta = min(time - (lastTime ?? time), 1.0 / 20)
        lastTime = time
        accumulator += delta
        while accumulator >= fixedStep {
            integrate(fixedStep)
            accumulator -= fixedStep
            simTime += fixedStep
        }

        vines.removeAll { !$0.isAttached && ($0.life <= 0 || $0.points.allSatisfy { $0.y > size.height + 40 }) }
        if didSpawn && vines.isEmpty && !didReportCleared {
            didReportCleared = true
            DispatchQueue.main.async { self.onCleared?() }
        }
    }

    private func integrate(_ dt: TimeInterval) {
        let dt = CGFloat(dt)
        let sway = CGFloat(pack.sway)
        for v in vines.indices {
            var vine = vines[v]
            let n = vine.points.count
            let start = vine.isAttached ? 1 : 0

            for i in start..<n {
                let p = vine.points[i]
                let velocity = CGVector(dx: (p.x - vine.previous[i].x) * damping,
                                        dy: (p.y - vine.previous[i].y) * damping)
                let depth = CGFloat(i) / CGFloat(n)
                let wind = CGFloat(sin(simTime * 1.3 + vine.phase + Double(i) * 0.18)) * 120 * depth * sway
                vine.previous[i] = p
                vine.points[i] = CGPoint(x: p.x + velocity.dx + wind * dt * dt,
                                         y: p.y + velocity.dy + gravity * dt * dt)
            }
            if vine.isAttached { vine.points[0] = vine.anchor }

            for _ in 0..<(lite ? 5 : 8) {
                for i in 0..<(n - 1) {
                    let a = vine.points[i], b = vine.points[i + 1]
                    let dx = b.x - a.x, dy = b.y - a.y
                    let distance = max(sqrt(dx * dx + dy * dy), 0.0001)
                    let diff = (distance - vine.segment) / distance
                    if vine.isAttached && i == 0 {
                        vine.points[1] = CGPoint(x: b.x - dx * diff, y: b.y - dy * diff)
                    } else {
                        vine.points[i] = CGPoint(x: a.x + dx * diff * 0.5, y: a.y + dy * diff * 0.5)
                        vine.points[i + 1] = CGPoint(x: b.x - dx * diff * 0.5, y: b.y - dy * diff * 0.5)
                    }
                }
            }

            if !vine.isAttached { vine.life -= Double(dt) / 1.4 }
            vines[v] = vine
        }
    }

    // MARK: Touch

    func handleTouch(atGlobal global: CGPoint, time: TimeInterval) {
        let point = CGPoint(x: global.x - canvasFrame.minX, y: global.y - canvasFrame.minY)
        defer { lastTouch = (point, time) }
        guard let last = lastTouch, time > last.time else { return }

        let move = CGVector(dx: point.x - last.point.x, dy: point.y - last.point.y)
        let speed = hypot(move.dx, move.dy) / CGFloat(time - last.time)

        for v in vines.indices where vines[v].isAttached {
            var hit = false
            for i in 1..<vines[v].points.count {
                let d = distance(from: vines[v].points[i], toSegment: last.point, point)
                guard d < touchRadius else { continue }
                hit = true
                let falloff = 1 - d / touchRadius
                vines[v].points[i].x += move.dx * 0.6 * falloff
                vines[v].points[i].y += move.dy * 0.6 * falloff
            }
            if hit && speed > CGFloat(pack.tearSpeed) {
                vines[v].isAttached = false
                // Отрываем с запасом скорости по направлению смаха.
                for i in vines[v].points.indices {
                    vines[v].previous[i].x -= move.dx * 0.35
                    vines[v].previous[i].y -= move.dy * 0.35 + 4
                }
                if pack.haptic { haptic.impactOccurred(intensity: 0.7) }
            }
        }
    }

    func endTouch() {
        lastTouch = nil
    }

    private func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let ab = CGVector(dx: b.x - a.x, dy: b.y - a.y)
        let lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * ab.dx + (p.y - a.y) * ab.dy) / lengthSquared))
        return hypot(p.x - (a.x + ab.dx * t), p.y - (a.y + ab.dy * t))
    }

    // MARK: Drawing

    private enum Item {
        case text(String, Color)
        case image(UIImage)
    }

    /// Звено №i лианы: картинка или символ, с мерцанием или без.
    private func bodyItem(of vine: Vine, at i: Int, time: TimeInterval) -> Item? {
        let index: Int
        if pack.flicker {
            let tick = Int(time * (2 + Double((vine.seed + i) % 5))) + vine.seed * 31 + i * 7
            index = abs(tick &* 2_654_435_761)
        } else {
            index = vine.seed + i
        }
        let loaded = pack.images.compactMap { images[$0] }
        if !loaded.isEmpty { return .image(loaded[index % loaded.count]) }
        guard !pack.glyphs.isEmpty else { return nil }
        let color = bodyColors[(pack.flicker ? vine.seed : vine.seed + i) % bodyColors.count]
        return item(for: pack.glyphs[index % pack.glyphs.count], color: color)
    }

    /// Кончик лианы: отдельная картинка/символ из пака, иначе обычное звено, но ярче.
    private func headItem(of vine: Vine, time: TimeInterval) -> Item? {
        let loaded = pack.headImages.compactMap { images[$0] }
        if !loaded.isEmpty { return .image(loaded[vine.seed % loaded.count]) }
        if !pack.head.isEmpty { return item(for: pack.head[vine.seed % pack.head.count], color: headColor) }
        switch bodyItem(of: vine, at: vine.points.count - 1, time: time) {
        case .text(let glyph, _): return .text(glyph, headColor)
        case let other: return other
        }
    }

    private func item(for glyph: String, color: Color) -> Item {
        emojiImages[glyph].map(Item.image) ?? .text(glyph, color)
    }

    func draw(in context: inout GraphicsContext, time: TimeInterval) {
        var cache: [String: GraphicsContext.ResolvedText] = [:]
        func resolved(_ glyph: String, _ color: Color, size: CGFloat, head: Bool) -> GraphicsContext.ResolvedText {
            let key = "\(glyph)|\(color.description)|\(Int(size))|\(head)"
            if let hit = cache[key] { return hit }
            let text = context.resolve(
                Text(glyph)
                    .font(.system(size: CGFloat(Int(size)), weight: head ? .heavy : .bold,
                                  design: pack.monospaced ? .monospaced : .rounded))
                    .foregroundColor(color)
            )
            cache[key] = text
            return text
        }

        context.drawLayer { layer in
            // Свечение — размытие тени, самая дорогая операция для старой видеокарты; на слабых устройствах без него.
            if let glowColor, !lite { layer.addFilter(.shadow(color: glowColor, radius: 3)) }

            for vine in vines {
                let n = vine.points.count
                let life = max(vine.life, 0)

                if let threadColor {
                    var path = Path()
                    path.addLines(vine.points)
                    var g = layer
                    g.opacity = life
                    g.stroke(path, with: .color(threadColor), style: StrokeStyle(lineWidth: pack.threadWidth, lineCap: .round, lineJoin: .round))
                }

                for i in 0..<n {
                    let isHead = i == n - 1
                    let onStep = pack.itemEvery > 0 && i % pack.itemEvery == 0 && i > 0
                    guard isHead || onStep else { continue }
                    guard let item = isHead ? headItem(of: vine, time: time) : bodyItem(of: vine, at: i, time: time) else { continue }

                    let p = vine.points[i]
                    let neighbor = vine.points[isHead ? i - 1 : i + 1]
                    var angle = atan2(neighbor.y - p.y, neighbor.x - p.x) - .pi / 2
                    if isHead { angle += .pi }
                    let size = isHead ? CGFloat(pack.headSize ?? Double(vine.glyphSize)) : vine.glyphSize
                    // Матрица гаснет к верхнему краю, остальные паки рисуются ровно.
                    let fade = pack.flicker ? 0.35 + 0.65 * Double(i) / Double(max(n - 1, 1)) : 1

                    var g = layer
                    g.opacity = vine.opacity * fade * life
                    g.translateBy(x: p.x, y: p.y)
                    g.rotate(by: .radians(Double(angle)))
                    switch item {
                    case .text(let glyph, let color):
                        g.draw(resolved(glyph, color, size: size, head: isHead), at: .zero, anchor: .center)
                    case .image(let image):
                        let aspect = image.size.height / max(image.size.width, 1)
                        let rect = CGRect(x: -size / 2, y: -size * aspect / 2, width: size, height: size * aspect)
                        // Картинка «подвешена» за верх, чтобы шарики и пауки висели на нити, а не на центре.
                        g.draw(Image(uiImage: image), in: rect.offsetBy(dx: 0, dy: size * aspect / 2 - size * 0.15))
                    }
                }
            }
        }
    }
}
