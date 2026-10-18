//
//  ContentView.swift
//  GreenAlfaKids
//
//  Created by Karabelnikov Stepan on 16.10.2026.
//

import SwiftUI
import MascotKit
import VinesKit

struct ContentView: View {
    @State private var vinesRefreshID = 0
    @State private var hasUserScrolled = false

    var body: some View {
        HomeView(
            onRefresh: { vinesRefreshID += 1 },
            onFirstScroll: { hasUserScrolled = true }
        )
            .hangingVines(isActive: hasUserScrolled, refreshID: vinesRefreshID)
            .mascot()
    }
}

#Preview {
    ContentView()
}
