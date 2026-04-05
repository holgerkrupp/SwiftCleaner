import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var analyzer = ProjectAnalyzer()
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            controls

            if let errorMessage = analyzer.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            if analyzer.projectPath == nil {
                Button(action: selectFolder) {
                    ContentUnavailableView(
                        "Select a Swift Project",
                        systemImage: "folder.badge.questionmark",
                        description: Text("SwiftCleaner will scan your Swift files, count references, and highlight declarations that look unused.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Click to choose a Swift project folder.")
            } else {
                ProjectDetailsView(analyzer: analyzer)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(24)
        .frame(minWidth: 980, minHeight: 700)
        .background(dropTargetBackground)
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted, perform: handleProjectDrop(providers:))
    }

    private var controls: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(analyzer.projectPath?.lastPathComponent ?? "No project selected")
                        .font(.title2.weight(.semibold))
                    if analyzer.projectPath != nil {
                        accessBadge
                    }
                }

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

    private var accessBadge: some View {
        let isReadWrite = analyzer.projectAccessMode == .readWrite
        return Text(isReadWrite ? "Write Access" : "Read Only")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill((isReadWrite ? Color.green : Color.gray).opacity(0.2))
            )
            .foregroundStyle(isReadWrite ? Color.green : Color.secondary)
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

    @ViewBuilder
    private var dropTargetBackground: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [8]))
                .padding(10)
        }
    }

    private func handleProjectDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let droppedURL: URL?

            if let url = item as? URL {
                droppedURL = url
            } else if let data = item as? Data {
                droppedURL = NSURL(absoluteURLWithDataRepresentation: data, relativeTo: nil) as URL?
            } else if let text = item as? String {
                droppedURL = URL(string: text)
            } else {
                droppedURL = nil
            }

            guard let droppedURL else {
                return
            }

            let standardizedURL = droppedURL.standardizedFileURL
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: standardizedURL.path, isDirectory: &isDirectory)
            guard exists else { return }

            let projectURL = isDirectory.boolValue ? standardizedURL : standardizedURL.deletingLastPathComponent()

            Task { @MainActor in
                analyzer.setProjectPath(projectURL)
                await analyzer.analyzeProject(at: projectURL)
            }
        }

        return true
    }
}

#Preview {
    ContentView()
}
