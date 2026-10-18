//
//  Mascot.swift
//  MascotKit
//

import SwiftUI

public enum MascotGesture: Equatable, Sendable {
    case tap(count: Int = 1)
    case longPress(duration: Double = 0.5)

    public init?(_ string: String) {
        switch string {
        case "tap": self = .tap()
        case "doubleTap": self = .tap(count: 2)
        case "tripleTap": self = .tap(count: 3)
        case "longPress": self = .longPress()
        default: return nil
        }
    }
}

public enum MascotAction: Equatable, Sendable {
    case summon
    case toggle
    case sendHome
    case celebrate
    case event(MascotEvent)
    case react(String)

    public static func say(_ key: String) -> MascotAction { .react(key) }

    public init?(_ string: String) {
        let parts = string.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts[0] {
        case "summon": self = .summon
        case "toggle": self = .toggle
        case "home": self = .sendHome
        case "celebrate": self = .celebrate
        case "event": guard parts.count == 2, let event = MascotEvent(rawValue: parts[1]) else { return nil }; self = .event(event)
        case "react", "say": guard parts.count == 2 else { return nil }; self = .react(parts[1])
        default: return nil
        }
    }
}

struct MascotTriggerSpec: Decodable, Equatable {
    var enabled: Bool?
    var gesture: String?
    var action: String?
}

public enum Mascot {
    public static var contentURL: URL? {
        get { CDNContent.baseURL }
        set { CDNContent.baseURL = newValue }
    }

    public static func send(_ event: MascotEvent) {
        MascotEngine.shared.send(event)
    }

    public static func perform(_ action: MascotAction) {
        MascotEngine.shared.perform(action, from: nil)
    }
}

extension View {
    public func mascot(configFile: String = "pet.json") -> some View {
        modifier(MascotRootModifier(configFile: configFile))
    }

    public func mascotSurface(_ id: String? = nil, occludesBelow: Bool = false, hideBehind: Bool = false) -> some View {
        modifier(MascotSurfaceModifier(explicitID: id, occludesBelow: occludesBelow, hideBehind: hideBehind))
    }

    public func mascotHome() -> some View {
        onGlobalFrameChange { MascotEngine.shared.setHome(frame: $0) }
    }

    public func mascotTrigger(_ id: String, _ gesture: MascotGesture = .longPress(), _ action: MascotAction = .toggle) -> some View {
        modifier(MascotTriggerModifier(id: id, gesture: gesture, action: action))
    }
}

private struct MascotRootModifier: ViewModifier {
    let configFile: String

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOnScreen = false

    func body(content: Content) -> some View {
        content
            .onGlobalFrameChange { MascotEngine.shared.contentFrame = $0 }
            .overlay {
                if !reduceMotion {
                    MascotLayerView(isRunning: isOnScreen && scenePhase == .active).ignoresSafeArea()
                }
            }
            .onAppear { isOnScreen = true }
            .onDisappear { isOnScreen = false }
            .task { if !reduceMotion { await MascotEngine.shared.start(configFile: configFile) } }
            .onChange(of: scenePhase) { phase in
                if phase == .active { MascotEngine.shared.appearanceCheck() }
            }
    }
}

private struct MascotSurfaceModifier: ViewModifier {
    let explicitID: String?
    let occludesBelow: Bool
    let hideBehind: Bool
    @State private var autoID = UUID().uuidString

    private var id: String { explicitID ?? autoID }

    func body(content: Content) -> some View {
        content
            .onGlobalFrameChange {
                MascotEngine.shared.setPlatform(id, frame: $0, occludesBelow: occludesBelow, hideBehind: hideBehind)
            }
            .onDisappear { MascotEngine.shared.setPlatform(id, frame: nil) }
    }
}

private struct MascotTriggerModifier: ViewModifier {
    let id: String
    let gesture: MascotGesture
    let action: MascotAction

    @State private var frameBox = FrameBox()
    @ObservedObject private var presence = MascotEngine.shared.presence

    private var resolved: (enabled: Bool, gesture: MascotGesture, action: MascotAction) {
        let spec = presence.triggerOverrides[id]
        return (spec?.enabled ?? true,
                spec?.gesture.flatMap(MascotGesture.init) ?? gesture,
                spec?.action.flatMap(MascotAction.init) ?? action)
    }

    func body(content: Content) -> some View {
        let trigger = resolved
        content
            .onGlobalFrameChange { frameBox.frame = $0 }
            .simultaneousGesture(recognizer(for: trigger.gesture), including: trigger.enabled ? .all : .subviews)
    }

    private func recognizer(for gesture: MascotGesture) -> AnyGesture<Void> {
        let fire = { MascotEngine.shared.perform(resolved.action, from: frameBox.frame) }
        switch gesture {
        case .tap(let count):
            return AnyGesture(TapGesture(count: count).onEnded { fire() })
        case .longPress(let duration):
            return AnyGesture(LongPressGesture(minimumDuration: duration).onEnded { _ in fire() }.map { _ in () })
        }
    }
}

private final class FrameBox {
    var frame: CGRect?
}
