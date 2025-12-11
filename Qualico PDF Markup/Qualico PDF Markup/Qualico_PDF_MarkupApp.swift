//
//  Qualico_PDF_MarkupApp.swift
//  Qualico PDF Markup
//
//  Created by Yancey Register on 12/11/25.
//

import SwiftUI
import SwiftData

@main
struct Qualico_PDF_MarkupApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
