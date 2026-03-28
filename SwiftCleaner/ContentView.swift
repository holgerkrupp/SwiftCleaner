import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var analyzer = ProjectAnalyzer()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            controls

            if let errorMessage = analyzer.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            if analyzer.projectPath == nil {
                ContentUnavailableView(
                    "Select a Swift Project",
                    systemImage: "folder.badge.questionmark",
                    description: Text("SwiftCleaner will scan your Swift files, count references, and highlight declarations that look unused.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProjectDetailsView(analyzer: analyzer)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(24)
        .frame(minWidth: 980, minHeight: 700)
    }

    private var controls: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(analyzer.projectPath?.lastPathComponent ?? "No project selected")
                    .font(.title2.weight(.semibold))

                Text(analyzer.projectPath?.path ?? "Choose the root folder of a Swift project or package.")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }

            Spacer(minLength: 16)

            Toggle("Include public/open APIs", isOn: $analyzer.includePublicDeclarations)
                .toggleStyle(.switch)
                .disabled(analyzer.isAnalyzing || analyzer.isApplyingEdit)
                .help("Leave this off to avoid flagging declarations that may be used by other modules.")

            Button("Select Folder", action: selectFolder)
                .keyboardShortcut("o", modifiers: [.command])

            Button(analyzer.isAnalyzing ? "Analyzing..." : "Analyze") {
                Task {
                    await analyzer.analyzeSelectedProject()
                }
            }
            .disabled(analyzer.projectPath == nil || analyzer.isAnalyzing || analyzer.isApplyingEdit)
            .buttonStyle(.borderedProminent)
        }
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Project"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        analyzer.setProjectPath(url)
        Task {
            await analyzer.analyzeProject(at: url)
        }
    }
}

#Preview {
    ContentView()
}
