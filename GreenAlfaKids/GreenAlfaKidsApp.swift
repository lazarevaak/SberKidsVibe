//
//  GreenAlfaKidsApp.swift
//  GreenAlfaKids
//
//  Created by Karabelnikov Stepan on 16.10.2026.
//

import SwiftUI
import MascotKit
import VinesKit

@main
struct GreenAlfaKidsApp: App {
    init() {
        // Папка с контентом приколов. Подменяется аргументом -CDNBaseURL для демо.
        let content = URL(string: "https://raw.githubusercontent.com/lazarevaak/SberKidsVibe/main/cdn/")
        Mascot.contentURL = content
        Vines.contentURL = content
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
