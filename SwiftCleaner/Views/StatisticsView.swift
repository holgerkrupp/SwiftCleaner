import SwiftUI

struct StatisticsView: View {
    @State private var statistics = CleanupActionStatisticsStore().load()

    private var projectRows: [(path: String, counts: CleanupActionCounts)] {
        statistics.projectTotals
            .map { ($0.key, $0.value) }
            .sorted { lhs, rhs in
                lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                overallSection
                projectsSection
            }
            .padding(24)
        }
        .frame(minWidth: 760, minHeight: 540)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .cleanupStatisticsDidChange)) { _ in
            reload()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cleanup Statistics")
                .font(.largeTitle.weight(.semibold))

            if let lastUpdated = statistics.lastUpdated {
                Text("Last updated \(lastUpdated.formatted(date: .abbreviated, time: .shortened))")
                    .foregroundStyle(.secondary)
            } else {
                Text("No cleanup actions have been recorded yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var overallSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overall")
                .font(.title3.weight(.semibold))

            HStack(spacing: 12) {
                StatisticsCard(
                    title: "Commented Out",
                    itemCount: statistics.totals.commentedOutItems,
                    lineCount: statistics.totals.commentedOutLines,
                    accentColor: .blue
                )
                StatisticsCard(
                    title: "Marked",
                    itemCount: statistics.totals.markedItems,
                    lineCount: statistics.totals.markedLines,
                    accentColor: .orange
                )
                StatisticsCard(
                    title: "Deleted",
                    itemCount: statistics.totals.deletedItems,
                    lineCount: statistics.totals.deletedLines,
                    accentColor: .red
                )
            }
        }
    }

    @ViewBuilder
    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By Project")
                .font(.title3.weight(.semibold))

            if projectRows.isEmpty {
                ContentUnavailableView(
                    "No Project Statistics",
                    systemImage: "chart.bar.doc.horizontal",
                    description: Text("Run cleanup actions in a project to start building project-level statistics.")
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                VStack(spacing: 10) {
                    ForEach(projectRows, id: \.path) { row in
                        ProjectStatisticsRow(path: row.path, counts: row.counts)
                    }
                }
            }
        }
    }

    private func reload() {
        statistics = CleanupActionStatisticsStore().load()
    }
}

private struct StatisticsCard: View {
    let title: String
    let itemCount: Int
    let lineCount: Int
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("\(itemCount) items")
                .font(.title2.weight(.semibold))
                .foregroundStyle(accentColor)

            Text("\(lineCount) lines")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
    }
}

private struct ProjectStatisticsRow: View {
    let path: String
    let counts: CleanupActionCounts

    private var projectName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(projectName)
                    .font(.headline)
                Spacer()
            }

            Text(path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(spacing: 18) {
                ProjectMetric(label: "Commented", items: counts.commentedOutItems, lines: counts.commentedOutLines, color: .blue)
                ProjectMetric(label: "Marked", items: counts.markedItems, lines: counts.markedLines, color: .orange)
                ProjectMetric(label: "Deleted", items: counts.deletedItems, lines: counts.deletedLines, color: .red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
    }
}

private struct ProjectMetric: View {
    let label: String
    let items: Int
    let lines: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text("\(items) items")
                .font(.subheadline.weight(.medium))
            Text("\(lines) lines")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
