//
//  HangingVines.swift
//  VinesKit
//

import SwiftUI
import UIKit
import os

private struct VineOcclusionPreferenceKey: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

public extension View {
    func vineOcclusion() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: VineOcclusionPreferenceKey.self,
                                       value: [proxy.frame(in: .global)])
            }
        }
    }
}

public enum Vines {
    public static var contentURL: URL? {
        get { CDNContent.baseURL }
        set { CDNContent.baseURL = newValue }
    }
}

extension View {
    public func hangingVines(isActive: Bool = true,
                             configFile: String = "vines.json",
                             refreshID: Int = 0,
                             onCleared: (() -> Void)? = nil) -> some View {
        modifier(HangingVinesModifier(isActive: isActive, configFile: configFile, refreshID: refreshID, onCleared: onCleared))
    }
}

private struct HangingVinesModifier: ViewModifier {
    let isActive: Bool
    let configFile: String
    let refreshID: Int
    let onCleared: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var field: VineField?
    @State private var isOnScreen = false
    @State private var lastRefreshID = 0
    @State private var uiOcclusions: [CGRect] = []

    private struct LoadRequest: Equatable {
        let scenePhase: ScenePhase
        let refreshID: Int
        let isActive: Bool
        let reduceMotion: Bool
    }

    private var isShown: Bool { isActive && !reduceMotion && field != nil }

    func body(content: Content) -> some View {
        content
            .overlay {
                if isShown, let field {
                    VinesCanvas(field: field, isRunning: isOnScreen && scenePhase == .active) { [weak field] in
                        guard let field, self.field === field else { return }
                        withAnimation { self.field = nil }
                        onCleared?()
                    }
                    .id(ObjectIdentifier(field))
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
            } onWindow: { window in
                field?.window = window
            })
            .onPreferenceChange(VineOcclusionPreferenceKey.self) { rects in
                uiOcclusions = rects
                field?.uiOcclusions = rects
            }
            .task(id: LoadRequest(scenePhase: scenePhase, refreshID: refreshID, isActive: isActive, reduceMotion: reduceMotion)) {
                guard scenePhase == .active, isActive, !reduceMotion else { return }
                let isRefresh = refreshID != lastRefreshID
                if isRefresh, let currentField = field {
                    lastRefreshID = refreshID
                    await currentField.refresh()
                    return
                }
                guard field == nil || isRefresh else { return }
                let prepared = await VinesConfigStore.shared.packToShow(configFile: configFile, ignoreCooldown: isRefresh)
                guard !Task.isCancelled else { return }
                lastRefreshID = refreshID
                if let prepared {
                    let lite = DevicePerformance.isLite
                    let atlas = await Task.detached(priority: .utility) {
                        VineSpriteAtlas.prepare(pack: prepared.pack, images: prepared.images, lite: lite)
                    }.value
                    guard !Task.isCancelled else { return }
                    let nextField = VineField(prepared: prepared, atlas: atlas)
                    nextField.uiOcclusions = uiOcclusions
                    field = nextField
                } else { field = nil }
            }
    }
}

private struct VinesCanvas: UIViewRepresentable {
    let field: VineField
    let isRunning: Bool
    let onCleared: () -> Void

    func makeUIView(context: Context) -> VineLayerView { VineLayerView(field: field) }

    func updateUIView(_ view: VineLayerView, context: Context) {
        field.onCleared = onCleared
        view.setRunning(isRunning)
    }

    static func dismantleUIView(_ view: VineLayerView, coordinator: ()) { view.setRunning(false) }
}

private struct WindowSwipeCatcher: UIViewRepresentable {
    let isEnabled: Bool
    let onChange: (CGPoint, TimeInterval) -> Void
    let onEnd: () -> Void
    let onWindow: (UIWindow?) -> Void

    func makeUIView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: CatcherView, context: Context) {
        view.recognizer.isEnabled = isEnabled
        view.onChange = onChange
        view.onEnd = onEnd
        view.onWindow = onWindow
        onWindow(view.window)
    }

    static func dismantleUIView(_ view: CatcherView, coordinator: ()) {
        view.detach()
    }

    final class CatcherView: UIView, UIGestureRecognizerDelegate {
        let recognizer = UIPanGestureRecognizer()
        var onChange: ((CGPoint, TimeInterval) -> Void)?
        var onEnd: (() -> Void)?
        var onWindow: ((UIWindow?) -> Void)?

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
            onWindow?(window)
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

@MainActor
final class VineField {
    weak var window: UIWindow?
    var canvasFrame: CGRect = .zero
    var uiOcclusions: [CGRect] = []
    var onCleared: (() -> Void)?
    let atlas: VineSpriteAtlas
    let threadColor: CGColor?
    let threadWidth: CGFloat
    let overlapOpacity: Float
    private(set) var frame = VineFrame()
    private(set) var revision = 0
    private let simulation: VineSimulation
    private let motion = VineMotion()
    private let chainSound: VineChainSound
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private var pendingTouches: [VineTouch] = []
    private var request: Task<Void, Never>?
    private var inFlight = false
    private var running = false
    private var generation = 0
    private var reportedCleared = false
    private let diagnosticsEnabled = ProcessInfo.processInfo.arguments.contains("-LaunchDiagnostics")
    private let diagnosticsLog = Logger(subsystem: "AlfaKids.Performance", category: "Vines")
    private var diagnosticsStart: TimeInterval?
    private var diagnosticsFinished = false
    private var roundTrips: [Double] = []
    private var readyGaps: [Double] = []
    private var lastReady: TimeInterval?
    private var skippedTicks = 0

    init(prepared: PreparedVinePack, atlas: VineSpriteAtlas) {
        let pack = prepared.pack
        self.atlas = atlas
        threadColor = VineSpriteAtlas.color(pack.thread)?.cgColor
        threadWidth = pack.threadWidth * pack.scale
        overlapOpacity = Float(pack.overlapOpacity)
        chainSound = VineChainSound(settings: pack.sound, clips: prepared.sounds)
        simulation = VineSimulation(pack: pack, lite: DevicePerformance.isLite,
                                    bodyImageCount: pack.images.compactMap { prepared.images[$0] }.count,
                                    headImageCount: pack.headImages.compactMap { prepared.images[$0] }.count,
                                    colorCount: max(1, pack.colors.compactMap { VineSpriteAtlas.color($0) }.count))
    }

    func setRunning(_ active: Bool) {
        guard running != active else { return }
        running = active
        generation += 1
        let audioGeneration = generation
        Task { [chainSound] in await chainSound.setRunning(active, generation: audioGeneration) }
        if active {
            motion.start()
        } else {
            motion.stop()
            request?.cancel()
            request = nil
            inFlight = false
            pendingTouches.removeAll(keepingCapacity: true)
        }
    }

    func refresh() async {
        let wasRunning = running
        running = false
        generation += 1
        request?.cancel()
        request = nil
        inFlight = false
        pendingTouches.removeAll(keepingCapacity: true)
        reportedCleared = false
        await simulation.restart(generation: generation)
        running = wasRunning
        let audioGeneration = generation
        Task { [chainSound] in await chainSound.setRunning(wasRunning, generation: audioGeneration) }
    }

    func step(to time: TimeInterval, size: CGSize) {
        guard running, size.width > 0, size.height > 0 else { return }
        guard !inFlight else {
            if diagnosticsEnabled, !diagnosticsFinished { skippedTicks += 1 }
            return
        }
        let requestedAt = CACurrentMediaTime()
        if diagnosticsEnabled, diagnosticsStart == nil { diagnosticsStart = requestedAt }
        inFlight = true
        let generation = generation
        let sample = motion.sample(in: window)
        let touches = pendingTouches
        pendingTouches.removeAll(keepingCapacity: true)
        let simulation = simulation
        request = Task(priority: .userInitiated) { [weak self] in
            let next = await simulation.advance(time: time, size: size, motion: sample,
                                                touches: touches, generation: generation)
            guard let self, !Task.isCancelled, self.generation == generation, self.running else { return }
            self.inFlight = false
            self.frame = next
            self.revision &+= 1
            self.recordFrame(requestedAt: requestedAt)
            if let audio = next.audio {
                Task { [chainSound = self.chainSound] in await chainSound.apply(audio, generation: generation) }
            }
            if next.didTear { self.haptic.impactOccurred(intensity: 0.7) }
            if next.cleared && !self.reportedCleared {
                self.reportedCleared = true
                self.onCleared?()
            }
        }
    }

    private func recordFrame(requestedAt: TimeInterval) {
        guard diagnosticsEnabled, !diagnosticsFinished, let start = diagnosticsStart else { return }
        let now = CACurrentMediaTime()
        roundTrips.append((now - requestedAt) * 1000)
        if let lastReady { readyGaps.append((now - lastReady) * 1000) }
        else { diagnosticsLog.notice("first simulation ready ms=\((now - start) * 1000, privacy: .public)") }
        lastReady = now
        guard now - start >= 12 else { return }
        diagnosticsFinished = true
        let trips = roundTrips.sorted(), gaps = readyGaps.sorted()
        guard !gaps.isEmpty else { return }
        diagnosticsLog.notice("simulation frames=\(trips.count) skipped_ticks=\(self.skippedTicks) roundtrip_p95_ms=\(trips[Int(Double(trips.count - 1) * 0.95)], privacy: .public) ready_gap_p95_ms=\(gaps[Int(Double(gaps.count - 1) * 0.95)], privacy: .public) ready_gap_max_ms=\(gaps.last!, privacy: .public)")
    }

    func handleTouch(atGlobal point: CGPoint, time: TimeInterval) {
        if pendingTouches.count >= 32 { pendingTouches.removeFirst() }
        pendingTouches.append(.move(global: point, canvas: canvasFrame, time: time))
    }

    func endTouch() { pendingTouches.append(.end) }
}
