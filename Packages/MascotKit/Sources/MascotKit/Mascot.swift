//
//  Mascot.swift
//  MascotKit
//
//  Публичный API маскота. Всё подключение — модификаторами:
//
//      import MascotKit
//
//      Mascot.contentURL = URL(string: "https://cdn.example.com/fun/")   // один раз при старте
//
//      RootView()
//          .mascot()                                       // слой, где живёт маскот
//
//      avatar.mascotHome()                                 // домик: сюда уходит, отсюда выпрыгивает
//      card.mascotSurface()                                // по верхнему краю можно ходить
//      tabBar.mascotSurface(occludesBelow: true)           // всё, что под ней, считается скрытым
//
//      avatar.mascotTrigger("avatar", .longPress(), .toggle)
//      balance.mascotTrigger("balance", .tap(), .event(.topUp))
//      qrIcon.mascotTrigger("qr", .tap(count: 3), .summon)
//
//  Триггеры не мешают собственным жестам вьюхи (кнопки продолжают работать).
//  Маскот выпрыгивает из той вьюхи, на которой сработал триггер.
//  Жест и действие любого триггера можно переопределить с CDN — pet.json → "triggers".
//  События из бизнес-логики: Mascot.send(.topUp).
//

import SwiftUI

// MARK: - Жесты и действия

public enum MascotGesture: Equatable, Sendable {
    case tap(count: Int = 1)
    case longPress(duration: Double = 0.5)

    /// "tap", "doubleTap", "tripleTap", "longPress".
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
    /// Позвать, если его нет.
    case summon
    /// Позвать или отпустить домой.
    case toggle
    case sendHome
    /// Порадоваться (если его нет — прибежит и порадуется).
    case celebrate
    /// Событие приложения: реакция и реплика по ключу события.
    case event(MascotEvent)
    /// Реакция по ключу из pet.json → reactions: реплика, звук, анимация.
    /// Ключ может быть любым — например, "secret1" для пасхалки.
    case react(String)

    /// Старое имя react — оставлено для совместимости.
    public static func say(_ key: String) -> MascotAction { .react(key) }

    /// "summon", "toggle", "home", "celebrate", "event:topUp", "react:secret1" (или "say:…").
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

/// Переопределение триггера с CDN. Пустые поля — оставить как в коде.
struct MascotTriggerSpec: Decodable, Equatable {
    var enabled: Bool?
    var gesture: String?
    var action: String?
}

// MARK: - Модификаторы

/// Настройка и вызовы маскота из бизнес-логики, без привязки к вьюхе.
public enum Mascot {
    /// Папка на CDN с pet.json и картинками. Задаётся один раз при старте приложения.
    public static var contentURL: URL? {
        get { CDNContent.baseURL }
        set { CDNContent.baseURL = newValue }
    }

    /// Событие приложения: пополнение, выполненное дело, достижение.
    public static func send(_ event: MascotEvent) {
        MascotEngine.shared.send(event)
    }

    /// Любое действие маскота — например, позвать его из кода.
    public static func perform(_ action: MascotAction) {
        MascotEngine.shared.perform(action, from: nil)
    }
}

extension View {
    /// Слой, в котором живёт маскот. Вешается один раз на корневую вьюху экрана.
    /// - Parameters:
    ///   - configFile: имя конфига в папке `Mascot.contentURL`.
    ///   Нет ни CDN, ни кэша — маскот просто не появляется: в приложение ничего не зашито.
    public func mascot(configFile: String = "pet.json") -> some View {
        modifier(MascotRootModifier(configFile: configFile))
    }

    /// Вьюха, по верхнему краю которой маскот может ходить и на которую прыгает.
    /// - Parameter occludesBelow: всё, что окажется под этой вьюхой при скролле, считается скрытым (таб-бар).
    public func mascotSurface(_ id: String? = nil, occludesBelow: Bool = false) -> some View {
        modifier(MascotSurfaceModifier(explicitID: id, occludesBelow: occludesBelow))
    }

    /// Домик маскота: сюда он уходит, отсюда выпрыгивает по событиям.
    public func mascotHome() -> some View {
        onGlobalFrameChange { MascotEngine.shared.setHome(frame: $0) }
    }

    /// Триггер на вьюхе: жест → действие маскота.
    /// - Parameter id: имя триггера — по нему его можно переопределить или выключить с CDN.
    public func mascotTrigger(_ id: String, _ gesture: MascotGesture = .longPress(), _ action: MascotAction = .toggle) -> some View {
        modifier(MascotTriggerModifier(id: id, gesture: gesture, action: action))
    }
}

// MARK: - Реализация модификаторов

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
                    // Анимация стоит, когда приложение свёрнуто или экран закрыт другим.
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
    @State private var autoID = UUID().uuidString

    private var id: String { explicitID ?? autoID }

    func body(content: Content) -> some View {
        content
            .onGlobalFrameChange {
                MascotEngine.shared.setPlatform(id, frame: $0, occludesBelow: occludesBelow)
            }
            .onDisappear { MascotEngine.shared.setPlatform(id, frame: nil) }
    }
}

private struct MascotTriggerModifier: ViewModifier {
    let id: String
    let gesture: MascotGesture
    let action: MascotAction

    /// Фрейм вьюхи. Хранится в объекте, а не в @State: при скролле он меняется каждый кадр,
    /// и @State заставлял бы SwiftUI перерисовывать вьюху 60 раз в секунду впустую.
    @State private var frameBox = FrameBox()
    @ObservedObject private var presence = MascotEngine.shared.presence

    /// Код задаёт значения по умолчанию, CDN может их заменить.
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
