import SwiftUI

struct ProjectDetailsView: View {
    @ObservedObject var analyzer: ProjectAnalyzer
    @State private var selectedTab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            summary

            if analyzer.isAnalyzing {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Scanning Swift files and resolving references...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if analyzer.summary.fileCount == 0 {
                ContentUnavailableView(
                    "No Analysis Yet",
                    systemImage: "wand.and.rays",
                    description: Text("Choose a folder and run the analyzer to see usage counts and likely unused declarations.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TabView(selection: $selectedTab) {
                    ProjectStructureView(files: analyzer.outlineFiles)
                        .tabItem {
                            Label("Structure", systemImage: "list.bullet.indent")
                        }
                        .tag(0)

                    ElementUsageView(usages: analyzer.elementUsages)
                        .tabItem {
                            Label("Usage", systemImage: "chart.bar")
                        }
                        .tag(1)

                    UnusedElementsView(analyzer: analyzer)
                        .tabItem {
                            Label("Unused", systemImage: "trash.slash")
                        }
                        .tag(2)

                    LikelyUnusedFilesView(files: analyzer.likelyUnusedFiles)
                        .tabItem {
                            Label("Files", systemImage: "doc.text.magnifyingglass")
                        }
                        .tag(3)
                }
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            SummaryCard(title: "Files", value: "\(analyzer.summary.fileCount)")
            SummaryCard(title: "Declarations", value: "\(analyzer.summary.declarationCount)")
            SummaryCard(title: "Tracked", value: "\(analyzer.summary.trackedDeclarationCount)")
            SummaryCard(title: "References", value: "\(analyzer.summary.referenceCount)")
            SummaryCard(title: "Unused", value: "\(analyzer.summary.unusedCount)", accentColor: .orange)
            SummaryCard(title: "Unused Files", value: "\(analyzer.summary.unusedFileCount)", accentColor: .orange)
        }
    }
}

private struct SummaryCard: View {
    let title: String
    let value: String
    var accentColor: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundStyle(accentColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
    }
}
