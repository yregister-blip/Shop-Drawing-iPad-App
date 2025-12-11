//
//  QualicoPDFMarkupApp.swift
//  QualicoPDFMarkup
//
//  Main app entry point
//

import SwiftUI

@main
struct QualicoPDFMarkupApp: App {
    @StateObject private var authManager = AuthManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
        }
    }
}
