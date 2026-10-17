//
//  GlobalFrame.swift
//  MascotKit
//

import SwiftUI

extension View {
    /// Сообщает глобальный фрейм вьюхи при появлении и при каждом изменении, в том числе при скролле.
    /// На iOS 16+ — onGeometryChange: он отдаёт фрейм в том же кадре, и маскот не отстаёт от карточки.
    /// На iOS 15 — GeometryReader (фрейм приходит с задержкой в кадр, но работает).
    @ViewBuilder
    func onGlobalFrameChange(_ action: @escaping (CGRect) -> Void) -> some View {
        if #available(iOS 16.0, *) {
            onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { action($0) }
        } else {
            background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { action(proxy.frame(in: .global)) }
                        .onChange(of: proxy.frame(in: .global)) { action($0) }
                }
                .allowsHitTesting(false)
            )
        }
    }
}
