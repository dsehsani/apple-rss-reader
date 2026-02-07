//
//  OpenRSSApp.swift
//  OpenRSS
//
//  Created by Darius Ehsani on 2/3/26.
//

import SwiftUI

@main
struct OpenRSSApp: App {

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            MainTabView()
            // Removed .preferredColorScheme(.dark) to allow system Light/Dark mode
        }
    }
}
