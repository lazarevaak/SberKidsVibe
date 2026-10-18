//
//  GlobalFrame.swift
//  VinesKit
//

import SwiftUI

extension View {
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
