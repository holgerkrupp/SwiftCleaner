import SwiftUI

struct LikelyUnusedFilesView: View {
    let files: [LikelyUnusedFile]

    @State private var searchText = ""
    @State private var expandedFolders: Set<String> = []

    private var filteredFiles: [LikelyUnusedFile] {
        guard !searchText.isEmpty else { return files }

        return files.filter { file in
            file.file.lastPathComponent.localizedCaseInsensitiveContains(searchText) ||
            file.file.deletingLastPathComponent().path.localizedCaseInsensitiveContains(searchText) ||
            file.reason.localizedCaseInsensitiveContains(searchText) ||
            file.primaryDeclarations.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
        }
    }

    private var groupedFiles: [(String, [LikelyUnusedFile])] {
        let grouped = Dictionary(grouping: filteredFiles) { file in
            file.file.deletingLastPathComponent().path
        }
        return grouped.sorted { $0.key < $1.key }
    }

    var body: some View {
        List {
            controls

            if files.isEmpty {
                ContentUnavailableView(
                    "No Likely Unused Files",
                    systemImage: "doc.text",
                    description: Text("No Swift files look fully unreferenced with the current heuristics.")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            } else if filteredFiles.isEmpty {
                ContentUnavailableView(
                    "No Matching Files",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Try a different search term.")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                ForEach(groupedFiles, id: \.0) { folder, folderFiles in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedFolders.contains(folder) },
                            set: { isExpanded in
                                if isExpanded {
                                    expandedFolders.insert(folder)
                                } else {
                                    expandedFolders.remove(folder)
                                }
                            }
                        )
                    ) {
                        ForEach(folderFiles) { file in
                            LikelyUnusedFileRow(file: file)
                        }
                    } label: {
                        HStack {
                            Text(folder)
                                .font(.headline)
                                .lineLimit(1)
                            Text("(\(folderFiles.count))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText)
    }

    private var controls: some View {
        HStack {
            Text("Likely Unused Files")
                .font(.headline)

            Spacer()

            Button("Expand All") {
                expandedFolders = Set(groupedFiles.map(\.0))
            }
            .disabled(groupedFiles.isEmpty)

            Button("Collapse All") {
                expandedFolders.removeAll()
            }
            .disabled(groupedFiles.isEmpty)
        }
        .padding(.vertical, 4)
    }
}

private struct LikelyUnusedFileRow: View {
    let file: LikelyUnusedFile

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text(file.file.lastPathComponent)
                        .font(.system(.body, design: .monospaced))

                    Text(file.file.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Text("Top-level declarations: \(file.primaryDeclarations.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(file.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Text("L\(file.line)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
}
