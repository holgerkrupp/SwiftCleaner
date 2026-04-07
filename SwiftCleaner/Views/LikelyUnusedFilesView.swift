import SwiftUI

struct LikelyUnusedFilesView: View {
    let files: [LikelyUnusedFile]
    let diskOnlySwiftFiles: [DiskOnlySwiftFile]
    var onSelectLikelyUnusedFile: ((LikelyUnusedFile) -> Void)? = nil
    var onSelectDiskOnlyFile: ((DiskOnlySwiftFile) -> Void)? = nil

    @State private var searchText = ""
    @State private var expandedFolders: Set<String> = []

    private var filteredLikelyUnusedFiles: [LikelyUnusedFile] {
        guard !searchText.isEmpty else { return files }

        return files.filter { file in
            file.file.lastPathComponent.localizedCaseInsensitiveContains(searchText) ||
            file.file.deletingLastPathComponent().path.localizedCaseInsensitiveContains(searchText) ||
            file.reason.localizedCaseInsensitiveContains(searchText) ||
            file.primaryDeclarations.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
        }
    }

    private var filteredDiskOnlySwiftFiles: [DiskOnlySwiftFile] {
        guard !searchText.isEmpty else { return diskOnlySwiftFiles }

        return diskOnlySwiftFiles.filter { file in
            file.file.lastPathComponent.localizedCaseInsensitiveContains(searchText) ||
            file.file.deletingLastPathComponent().path.localizedCaseInsensitiveContains(searchText) ||
            file.reason.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var likelyUnusedGroups: [FolderGroup<LikelyUnusedFile>] {
        groupedFolders(for: filteredLikelyUnusedFiles, prefix: "likely", fileURL: \.file)
    }

    private var diskOnlyGroups: [FolderGroup<DiskOnlySwiftFile>] {
        groupedFolders(for: filteredDiskOnlySwiftFiles, prefix: "disk", fileURL: \.file)
    }

    private var allGroupIDs: Set<String> {
        Set(likelyUnusedGroups.map(\.id) + diskOnlyGroups.map(\.id))
    }

    var body: some View {
        List {
            controls

            if files.isEmpty && diskOnlySwiftFiles.isEmpty {
                ContentUnavailableView(
                    "No File Cleanup Candidates",
                    systemImage: "doc.text",
                    description: Text("No likely unused project files or folder-only Swift files were found.")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            } else if filteredLikelyUnusedFiles.isEmpty && filteredDiskOnlySwiftFiles.isEmpty {
                ContentUnavailableView(
                    "No Matching File Candidates",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Try a different search term.")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                if !likelyUnusedGroups.isEmpty {
                    Section("Likely Unused In Project") {
                        ForEach(likelyUnusedGroups) { group in
                            folderDisclosureGroup(id: group.id, folder: group.folder, itemCount: group.items.count) {
                                ForEach(group.items) { file in
                                    LikelyUnusedFileRow(file: file, onSelect: onSelectLikelyUnusedFile)
                                }
                            }
                        }
                    }
                }

                if !diskOnlyGroups.isEmpty {
                    Section("On Disk But Not In Xcode") {
                        ForEach(diskOnlyGroups) { group in
                            folderDisclosureGroup(id: group.id, folder: group.folder, itemCount: group.items.count) {
                                ForEach(group.items) { file in
                                    DiskOnlySwiftFileRow(file: file, onSelect: onSelectDiskOnlyFile)
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText)
    }

    private var controls: some View {
        HStack {
            Text("File Cleanup Candidates")
                .font(.headline)

            Spacer()

            Button("Expand All") {
                expandedFolders = allGroupIDs
            }
            .disabled(allGroupIDs.isEmpty)

            Button("Collapse All") {
                expandedFolders.removeAll()
            }
            .disabled(allGroupIDs.isEmpty)
        }
        .padding(.vertical, 4)
    }

    private func groupedFolders<Item>(
        for items: [Item],
        prefix: String,
        fileURL: KeyPath<Item, URL>
    ) -> [FolderGroup<Item>] {
        let grouped = Dictionary(grouping: items) { item in
            item[keyPath: fileURL].deletingLastPathComponent().path
        }

        return grouped
            .map { folder, folderItems in
                FolderGroup(
                    id: "\(prefix):\(folder)",
                    folder: folder,
                    items: folderItems.sorted {
                        $0[keyPath: fileURL].path < $1[keyPath: fileURL].path
                    }
                )
            }
            .sorted { $0.folder < $1.folder }
    }

    @ViewBuilder
    private func folderDisclosureGroup<Content: View>(
        id: String,
        folder: String,
        itemCount: Int,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedFolders.contains(id) },
                set: { isExpanded in
                    if isExpanded {
                        expandedFolders.insert(id)
                    } else {
                        expandedFolders.remove(id)
                    }
                }
            )
        ) {
            content()
        } label: {
            HStack {
                Text(folder)
                    .font(.headline)
                    .lineLimit(1)
                Text("(\(itemCount))")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct FolderGroup<Item>: Identifiable {
    let id: String
    let folder: String
    let items: [Item]
}

private struct LikelyUnusedFileRow: View {
    let file: LikelyUnusedFile
    var onSelect: ((LikelyUnusedFile) -> Void)? = nil

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
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect?(file)
            }
        }
    }
}

private struct DiskOnlySwiftFileRow: View {
    let file: DiskOnlySwiftFile
    var onSelect: ((DiskOnlySwiftFile) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "externaldrive.badge.xmark")
                    .foregroundStyle(.yellow)

                VStack(alignment: .leading, spacing: 4) {
                    Text(file.file.lastPathComponent)
                        .font(.system(.body, design: .monospaced))

                    Text(file.file.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Text(file.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect?(file)
            }
        }
    }
}
