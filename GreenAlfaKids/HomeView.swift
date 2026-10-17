//
//  HomeView.swift
//  GreenAlfaKids
//

import SwiftUI
import MascotKit

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
    @State private var selectedTab: Tab = .home
    @State private var cardPage = 0

    private let actions = [
        QuickAction(title: "QR", icon: "action_qr"),
        QuickAction(title: "Скинуть\nденег", icon: "action_transfer"),
        QuickAction(title: "Пополнить\nмобилку", icon: "action_phone"),
    ]

    private let transactions = [
        Transaction(icon: "history_home", title: "Товары для дома", subtitle: "Маркетплейсы", amount: "-2 292 ₽", cashback: "+28"),
        Transaction(icon: "history_kuper", title: "Купер", subtitle: "Супермаркет", amount: "-4 686 ₽", cashback: nil),
        Transaction(icon: "history_transfer", title: "Мария Валерьевна Р.", subtitle: "Клиенту Сбера", amount: "-500 ₽", cashback: nil),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            background

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Image("avatar")
                        .resizable()
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                        .mascotHome()
                        .mascotTrigger("avatar", .longPress(), .toggle)
                        .padding(.horizontal, 8)

                    cardSection
                        .padding(.top, -24)

                    pageIndicator
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)

                    quickActions
                        .padding(.top, 32)

                    promoBanner
                        .mascotSurface("promo")
                        .padding(.top, 44)

                    Text("История")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                        .padding(.top, 28)

                    historyCard
                        .mascotSurface("history")
                        .padding(.top, 20)

                    Button {} label: {
                        Text("Посмотреть историю")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 62)
                            .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                    .mascotSurface("historyButton")
                    .padding(.top, 28)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }

            TabBar(selected: $selectedTab)
                .mascotSurface("tabbar", occludesBelow: true)
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
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

    private var cardSection: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $cardPage) {
                ForEach(0..<3, id: \.self) { index in
                    cardStack.tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 240)

            balanceBar
        }
        .frame(height: 280)
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
        .frame(maxWidth: .infinity)
        .offset(y: -20)
    }

    private var balanceBar: some View {
        HStack {
            (Text("7 932").foregroundColor(Color.textPrimary)
             + Text(",04 ₽").foregroundColor(Color.textSecondary.opacity(0.7)))
                .font(.system(size: 22, weight: .bold))
                .padding(.leading, 20)

            Spacer()

            HStack(spacing: 6) {
                Text("256")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Image("coin")
                    .resizable()
                    .frame(width: 20, height: 20)
            }
            .frame(width: 112, height: 60)
            .background(Color.limeLight, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(8)
        .background(.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
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

    private var quickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(actions) { action in
                    QuickActionTile(action: action, compact: action.title == "QR")
                        .mascotSurface("action-\(action.title)")
                        // Пасхалка: тройной тап по плитке — событие "secret", заданное только в конфиге.
                        .mascotTrigger("tile-\(action.title)", .tap(count: 3), .react("secret"))
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
    }

    // MARK: Promo

    private var promoBanner: some View {
        ZStack(alignment: .leading) {
            LinearGradient(colors: [Color(hex: 0x8E7BEF), Color(hex: 0x6FA4E8), Color(hex: 0x8CCBD4)],
                           startPoint: .leading, endPoint: .trailing)

            VStack(alignment: .leading, spacing: 6) {
                Text("Узнай свои сильные\nстороны")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                Text("с тестом по профориентации")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.leading, 26)
        }
        .frame(height: 114)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Image("ufo")
                .resizable()
                .frame(width: 120, height: 94)
                .offset(x: 6, y: -14)
        }
    }

    // MARK: History

    private var historyCard: some View {
        VStack(spacing: 22) {
            ForEach(transactions) { TransactionRow(transaction: $0) }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 26)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

// MARK: - Components

struct QuickActionTile: View {
    let action: QuickAction
    var compact = false

    var body: some View {
        VStack(alignment: compact ? .center : .leading, spacing: 0) {
            Text(action.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
            Spacer(minLength: 12)
            Image(action.icon)
                .resizable()
                .frame(width: 52, height: 52)
                .frame(maxWidth: .infinity, alignment: compact ? .center : .trailing)
        }
        .padding(compact ? 14 : 18)
        .frame(width: compact ? 80 : 158, height: 134)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(transaction.icon)
                .resizable()
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                Text(transaction.subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.top, 6)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(transaction.amount)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
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
            .padding(.top, 4)
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

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    selected = tab
                } label: {
                    if tab == .paw {
                        Image(tab.icon)
                            .resizable()
                            .frame(width: 54, height: 54)
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
        .frame(height: 76)
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

#Preview {
    HomeView()
}
