//
//  ContentView.swift
//  QualicoPDFMarkup
//
//  Main view that handles authentication state
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                FileBrowserView()
            } else {
                LoginView()
            }
        }
    }
}
