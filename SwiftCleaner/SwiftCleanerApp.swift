import SwiftUI

@main
struct SwiftCleanerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }

        Window("Statistics", id: "statistics") {
            StatisticsView()
        }
        .defaultSize(width: 820, height: 600)
        .windowResizability(.contentSize)
        .commands {
            StatisticsCommands()
        }
    }
}

private struct StatisticsCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Statistics") {
            Button("Show Statistics") {
                openWindow(id: "statistics")
            }
            .keyboardShortcut("9", modifiers: [.command, .shift])
        }
    }
}
