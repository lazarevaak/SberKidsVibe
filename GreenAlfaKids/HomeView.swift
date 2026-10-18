//
//  HomeView.swift
//  GreenAlfaKids
//

import SwiftUI
import MascotKit
import VinesKit

// MARK: - Palette

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    static let screenBackground = Color(hex: 0xF2F3F5)
    static let textPrimary = Color(hex: 0x111111)
    static let textSecondary = Color(hex: 0x8A8F99)
    static let brandGreen = Color(hex: 0x3DBE55)
    static let limeLight = Color(hex: 0xEEFBC8)
    static let tabInactive = Color(hex: 0xA6B3CC)
}

// MARK: - Models

struct QuickAction: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
}

struct Transaction: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let amount: String
    let cashback: String?
}

// MARK: - Home

struct HomeView: View {
    var onRefresh: () -> Void = {}
    var onFirstScroll: () -> Void = {}

    @State private var selectedTab: Tab = .home
    @State private var cardPage = 0

    private static let actions = [
        QuickAction(title: "QR", icon: "action_qr"),
        QuickAction(title: "Скинуть\nденег", icon: "action_transfer"),
        QuickAction(title: "Пополнить\nмобилку", icon: "action_phone"),
    ]

    private static let transactions = [
        Transaction(icon: "history_home", title: "Товары для дома", subtitle: "Маркетплейсы", amount: "-2 292 ₽", cashback: "+28"),
        Transaction(icon: "history_kuper", title: "Купер", subtitle: "Супермаркет", amount: "-4 686 ₽", cashback: nil),
        Transaction(icon: "history_transfer", title: "Мария Валерьевна Р.", subtitle: "Клиенту Сбера", amount: "-500 ₽", cashback: nil),
    ]

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height && geometry.size.width >= 620
            let inset: CGFloat = landscape ? 24 : 20
            let contentWidth = min(max(geometry.size.width - inset * 2, 0), 1120)
            let columnWidth = (contentWidth - 24) / 2

            ZStack {
                ScrollView(showsIndicators: false) {
                    Group {
                        if #available(iOS 16.0, *) {
                            HomeColumnsLayout(horizontal: landscape) {
                                accountColumn(width: landscape ? columnWidth : contentWidth, compact: landscape)
                                detailsColumn(compact: landscape)
                            }
                        } else {
                            LegacyHomeColumns(
                                horizontal: landscape, width: contentWidth,
                                first: accountColumn(width: landscape ? columnWidth : contentWidth, compact: landscape),
                                second: detailsColumn(compact: landscape)
                            )
                        }
                    }
                    .frame(width: contentWidth)
                    .padding(.top, landscape ? 8 : 12)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { onRefresh() }
                .modifier(FirstScrollAction(action: onFirstScroll))
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TabBar(selected: $selectedTab, compact: landscape)
                    .vineOcclusion()
                    .mascotSurface("tabbar", occludesBelow: true)
                    .frame(maxWidth: landscape ? 640 : 520)
                    .padding(.horizontal, inset)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .frame(maxWidth: .infinity)
            }
            .background { background }
        }
    }

    private var avatar: some View {
        Image("avatar")
            .resizable()
            .frame(width: 64, height: 64)
            .clipShape(Circle())
            .vineOcclusion()
            .mascotHome()
            .mascotTrigger("avatar", .longPress(), .toggle)
            .padding(.horizontal, 8)
    }

    private func accountColumn(width: CGFloat, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            avatar
            cardSection(width: width, compact: compact)
                .padding(.top, compact ? -12 : -24)
            pageIndicator
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            quickActions(width: width, compact: compact)
                .padding(.top, compact ? 20 : 32)
        }
    }

    private func detailsColumn(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            promoBanner(compact: compact)
                .vineOcclusion()
                .mascotSurface("promo")
                .padding(.top, compact ? 14 : 0)

            Text("История")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .padding(.top, compact ? 24 : 28)

            historyCard(compact: compact)
                .vineOcclusion()
                .mascotSurface("history")
                .padding(.top, compact ? 16 : 20)

            Button {} label: {
                Text("Посмотреть историю")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 52 : 62)
                    .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .vineOcclusion()
            .mascotSurface("historyButton")
            .padding(.top, compact ? 16 : 28)
        }
    }

    // MARK: Background

    private var background: some View {
        ZStack(alignment: .top) {
            Color.screenBackground
            RadialGradient(colors: [Color(hex: 0xD9F57A, alpha: 0.75), Color(hex: 0xD9F57A, alpha: 0)],
                           center: UnitPoint(x: 0.85, y: 0.3), startRadius: 0, endRadius: 320)
                .frame(height: 620)
            RadialGradient(colors: [Color(hex: 0xBDEFD0, alpha: 0.6), Color(hex: 0xBDEFD0, alpha: 0)],
                           center: UnitPoint(x: 0.1, y: 0.45), startRadius: 0, endRadius: 260)
                .frame(height: 620)
        }
        .ignoresSafeArea()
    }

    // MARK: Card + balance

    private func cardSection(width: CGFloat, compact: Bool) -> some View {
        let scale = min(1, width / 350)
        return ZStack(alignment: .bottom) {
            TabView(selection: $cardPage) {
                ForEach(0..<3, id: \.self) { index in
                    cardStack
                        .frame(width: 350, height: 210)
                        .scaleEffect(scale)
                        .offset(y: compact ? -4 : -20)
                        .frame(width: width, height: compact ? 200 : 240)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: compact ? 200 : 240)

            balanceBar(compact: compact)
        }
        .frame(height: compact ? 240 : 280)
    }

    private var cardStack: some View {
        ZStack {
            Image("card_back")
                .resizable()
                .scaledToFill()
                .frame(width: 200, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .opacity(0.7)
                .rotationEffect(.degrees(6))
                .offset(x: 110, y: 6)

            Image("card_main")
                .resizable()
                .scaledToFill()
                .frame(width: 260, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
                .rotationEffect(.degrees(-5))
        }
    }

    private func balanceBar(compact: Bool) -> some View {
        HStack {
            (Text("7 932").foregroundColor(Color.textPrimary)
             + Text(",04 ₽").foregroundColor(Color.textSecondary.opacity(0.7)))
                .font(.system(size: compact ? 20 : 22, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.leading, compact ? 12 : 20)

            Spacer()

            HStack(spacing: 6) {
                Text("256")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Image("coin")
                    .resizable()
                    .frame(width: 20, height: 20)
            }
            .frame(width: compact ? 88 : 112, height: compact ? 48 : 60)
            .background(Color.limeLight, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(8)
        .background(.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
        .vineOcclusion()
        .mascotSurface("balance")
        // Демо: тап по балансу имитирует пополнение — маскот радуется.
        .mascotTrigger("balance", .tap(), .event(.topUp))
    }

    private var pageIndicator: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index == cardPage ? Color(hex: 0xB8C49A) : Color(hex: 0xC9D2B5, alpha: 0.7))
                    .frame(width: index == cardPage ? 30 : 6, height: 6)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: cardPage)
    }

    // MARK: Quick actions

    @ViewBuilder
    private func quickActions(width: CGFloat, compact: Bool) -> some View {
        if compact {
            HStack(spacing: 10) {
                ForEach(Self.actions) { action in
                    actionTile(action, width: (width - 20) / 3, dense: true)
                }
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Self.actions) { action in
                        actionTile(action)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.horizontal, -20)
        }
    }

    private func actionTile(_ action: QuickAction, width: CGFloat? = nil, dense: Bool = false) -> some View {
        QuickActionTile(action: action, compact: action.title == "QR", width: width, dense: dense)
            .vineOcclusion()
            .mascotSurface("action-\(action.title)")
            .mascotTrigger("tile-\(action.title)", .tap(count: 3), .react("secret"))
    }

    // MARK: Promo

    private func promoBanner(compact: Bool) -> some View {
        ZStack(alignment: .leading) {
            LinearGradient(colors: [Color(hex: 0x8E7BEF), Color(hex: 0x6FA4E8), Color(hex: 0x8CCBD4)],
                           startPoint: .leading, endPoint: .trailing)

            VStack(alignment: .leading, spacing: 6) {
                Text("Узнай свои сильные\nстороны")
                    .font(.system(size: compact ? 17 : 19, weight: .bold))
                    .foregroundStyle(.white)
                Text("с тестом по профориентации")
                    .font(.system(size: compact ? 12 : 13))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.leading, compact ? 18 : 26)
            .padding(.trailing, compact ? 84 : 72)
        }
        .frame(height: 114)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Image("ufo")
                .resizable()
                .frame(width: compact ? 94 : 120, height: compact ? 76 : 94)
                .offset(x: 6, y: -14)
        }
    }

    // MARK: History

    private func historyCard(compact: Bool) -> some View {
        VStack(spacing: compact ? 18 : 22) {
            ForEach(Self.transactions) { TransactionRow(transaction: $0, compact: compact) }
        }
        .padding(.horizontal, compact ? 18 : 24)
        .padding(.vertical, compact ? 20 : 26)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .vineOcclusion()
    }
}

/// Uses the scroll view's own phase on iOS 18+, avoiding an extra competing drag recognizer.
private struct FirstScrollAction: ViewModifier {
    let action: () -> Void
    @State private var didTrigger = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { oldPhase, newPhase in
                guard !didTrigger, oldPhase == .interacting, newPhase != .interacting else { return }
                didTrigger = true
                action()
            }
        } else {
            content.simultaneousGesture(
                DragGesture(minimumDistance: 12).onEnded { value in
                    guard !didTrigger,
                          abs(value.translation.height) > abs(value.translation.width) else { return }
                    didTrigger = true
                    action()
                }
            )
        }
    }
}

// MARK: - Components

/// Меняется только размещение колонок; карусель карты не пересоздаётся при повороте.
@available(iOS 16.0, *)
private struct HomeColumnsLayout: Layout {
    let horizontal: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(0, proposal.width ?? 350)
        let columnWidth = horizontal ? max(0, (width - 24) / 2) : width
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)) }
        let height = horizontal ? (sizes.map(\.height).max() ?? 0) : sizes.reduce(0) { $0 + $1.height } + 44
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = horizontal ? max(0, (bounds.width - 24) / 2) : bounds.width
        let childProposal = ProposedViewSize(width: width, height: nil)
        var y = bounds.minY
        for index in subviews.indices {
            let x = bounds.minX + (horizontal ? CGFloat(index) * (width + 24) : 0)
            subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: childProposal)
            if !horizontal { y += subviews[index].sizeThatFits(childProposal).height + 44 }
        }
    }
}

/// Та же стабильная структура для iOS 15, где ещё нет протокола Layout.
private struct LegacyHomeColumns<First: View, Second: View>: View {
    let horizontal: Bool
    let width: CGFloat
    let first: First
    let second: Second
    @State private var firstHeight: CGFloat = 0
    @State private var secondHeight: CGFloat = 0

    var body: some View {
        let columnWidth = horizontal ? max(0, (width - 24) / 2) : width
        ZStack(alignment: .topLeading) {
            measured(first, width: columnWidth, height: $firstHeight)
            measured(second, width: columnWidth, height: $secondHeight)
                .offset(x: horizontal ? columnWidth + 24 : 0,
                        y: horizontal ? 0 : firstHeight + 44)
        }
        .frame(width: width,
               height: horizontal ? max(firstHeight, secondHeight) : firstHeight + secondHeight + 44,
               alignment: .topLeading)
    }

    private func measured<V: View>(_ view: V, width: CGFloat, height: Binding<CGFloat>) -> some View {
        view.frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { height.wrappedValue = proxy.size.height }
                        .onChange(of: proxy.size.height) { height.wrappedValue = $0 }
                }
            }
    }
}

struct QuickActionTile: View {
    let action: QuickAction
    var compact = false
    var width: CGFloat?
    var dense = false

    var body: some View {
        VStack(alignment: compact ? .center : .leading, spacing: 0) {
            Text(action.title)
                .font(.system(size: dense ? 14 : 16, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
            Spacer(minLength: 12)
            Image(action.icon)
                .resizable()
                .frame(width: dense ? 40 : 52, height: dense ? 40 : 52)
                .frame(maxWidth: .infinity, alignment: compact ? .center : .trailing)
        }
        .padding(dense ? 12 : (compact ? 14 : 18))
        .frame(width: width ?? (compact ? 80 : 158), height: dense ? 112 : 134)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct TransactionRow: View {
    let transaction: Transaction
    var compact = false

    var body: some View {
        HStack(alignment: compact ? .top : .center, spacing: compact ? 12 : 18) {
            Image(transaction.icon)
                .resizable()
                .frame(width: compact ? 42 : 52, height: compact ? 42 : 52)

            VStack(alignment: .leading, spacing: compact ? 6 : 4) {
                Text(transaction.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                Text(transaction.subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textSecondary)
                if compact {
                    HStack(spacing: 12) {
                        amount
                        cashback
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, compact ? 0 : 6)

            if !compact {
                VStack(alignment: .trailing, spacing: 4) {
                    amount
                    cashback
                }
                .padding(.top, 4)
            }
        }
    }

    private var amount: some View {
        Text(transaction.amount)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(Color.textPrimary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var cashback: some View {
        if let cashback = transaction.cashback {
            HStack(spacing: 3) {
                Text(cashback)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.brandGreen)
                Image("coin_green")
                    .resizable()
                    .frame(width: 15, height: 15)
            }
        }
    }
}

// MARK: - Tab bar

enum Tab: CaseIterable {
    case home, piggy, paw, tasks, content

    var title: String {
        switch self {
        case .home: "Главный"
        case .piggy: "Копилки"
        case .paw: ""
        case .tasks: "Дела"
        case .content: "Контент"
        }
    }

    var icon: String {
        switch self {
        case .home: "tab_home"
        case .piggy: "tab_piggy"
        case .paw: "tab_paw"
        case .tasks: "tab_tasks"
        case .content: "tab_content"
        }
    }
}

struct TabBar: View {
    @Binding var selected: Tab
    var compact = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    selected = tab
                } label: {
                    if tab == .paw {
                        Image(tab.icon)
                            .resizable()
                            .frame(width: compact ? 42 : 54, height: compact ? 42 : 54)
                            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
                    } else {
                        VStack(spacing: 4) {
                            Image(tab.icon)
                                .renderingMode(.template)
                                .resizable()
                                .frame(width: 26, height: 26)
                                .overlay(alignment: .leading) {
                                    if tab == .home && selected == .home {
                                        ActiveSparks().offset(x: -12)
                                    }
                                }
                            Text(tab.title)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(selected == tab ? Color.brandGreen : Color.tabInactive)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: compact ? 58 : 76)
        .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }
}

/// Little purple "wiggle" marks next to the active tab icon.
private struct ActiveSparks: View {
    var body: some View {
        ZStack {
            Capsule().fill(Color(hex: 0xC86BF5)).frame(width: 2.5, height: 9).rotationEffect(.degrees(-40)).offset(x: 0, y: 6)
            Capsule().fill(Color(hex: 0xC86BF5)).frame(width: 2.5, height: 9).rotationEffect(.degrees(-70)).offset(x: 5, y: 10)
            Capsule().fill(Color(hex: 0xC86BF5)).frame(width: 2.5, height: 9).rotationEffect(.degrees(30)).offset(x: 40, y: -6)
            Capsule().fill(Color(hex: 0xC86BF5)).frame(width: 2.5, height: 9).rotationEffect(.degrees(60)).offset(x: 44, y: -1)
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            HomeView()
                .previewLayout(.fixed(width: 390, height: 844))
                .previewDisplayName("Портрет")
            HomeView()
                .previewLayout(.fixed(width: 844, height: 390))
                .previewDisplayName("Горизонтально")
            HomeView()
                .previewLayout(.fixed(width: 667, height: 375))
                .previewDisplayName("Компактный горизонтальный")
        }
    }
}
