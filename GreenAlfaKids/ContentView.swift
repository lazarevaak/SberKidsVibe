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
    var body: some View {
        HomeView()
            .hangingVines()
            .mascot()
    }
}

#Preview {
    ContentView()
}
