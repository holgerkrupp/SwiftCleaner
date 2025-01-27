//
//  SwiftCleanerApp.swift
//  SwiftCleaner
//
//  Created by Holger Krupp on 22.01.25.
//

import SwiftUI
import SwiftData

@main
struct SwiftCleanerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
       //     FileNode.self,
       //     Project.self,
       //     ClassTree.self,
       //     ClassElement.self
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
                .onAppear(){
                    guard let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).last else { return }
                    print(appSupportDir.path())
                }
        }
        
        .modelContainer(sharedModelContainer)
    }
}
