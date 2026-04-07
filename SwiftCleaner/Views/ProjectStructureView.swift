import SwiftUI

struct ProjectStructureView: View {
    let files: [OutlineFile]
    var selectedFileURL: URL? = nil
    var selectedNodeID: String? = nil
    var onSelectFile: ((URL) -> Void)? = nil
    var onSelectNode: ((OutlineNode) -> Void)? = nil
    var usageCountForNode: ((OutlineNode) -> Int?)? = nil
    var usageReferencesForNode: ((OutlineNode) -> [UsageReference])? = nil
    var onUsageBadgeTap: ((OutlineNode) -> Void)? = nil

    @State private var searchText = ""
    @State private var expandedIDs: Set<String> = []

    private var filteredFiles: [OutlineFile] {
        guard !searchText.isEmpty else { return files }
        return files.compactMap { filter($0, query: searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            List {
                if filteredFiles.isEmpty {
                    ContentUnavailableView(
                        "No Structure Matches",
                        systemImage: "list.bullet.rectangle.portrait",
                        description: Text(searchText.isEmpty ? "No outline data is available yet." : "Try a different search term.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    ForEach(filteredFiles) { file in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedIDs.contains(file.id) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedIDs.insert(file.id)
                                    } else {
                                        expandedIDs.remove(file.id)
                                    }
                                }
                            )
                        ) {
                            ForEach(file.children) { node in
                                StructureNodeView(
                                    node: node,
                                    expandedIDs: $expandedIDs,
                                    selectedNodeID: selectedNodeID,
                                    onSelectNode: onSelectNode,
                                    usageCountForNode: usageCountForNode,
                                    usageReferencesForNode: usageReferencesForNode,
                                    onUsageBadgeTap: onUsageBadgeTap
                                )
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(file.url.lastPathComponent, systemImage: "doc.text")
                                    .font(.headline)

                                Text(file.url.deletingLastPathComponent().path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isSelectedFile(file.url) ? Color.accentColor.opacity(0.2) : Color.clear)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelectFile?(file.url)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            if expandedIDs.isEmpty {
                expandedIDs = Set(files.map(\.id))
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Declaration Tree")
                    .font(.headline)

                Spacer()

                Button("Expand All") {
                    expandedIDs = allExpandableIDs(in: filteredFiles)
                }

                Button("Collapse All") {
                    expandedIDs.removeAll()
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search symbols", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func isSelectedFile(_ fileURL: URL) -> Bool {
        guard let selectedFileURL else { return false }
        return selectedFileURL.standardizedFileURL == fileURL.standardizedFileURL
    }

    private func filter(_ file: OutlineFile, query: String) -> OutlineFile? {
        let filteredChildren = file.children.compactMap { filter($0, query: query) }
        let matchesFile = file.url.lastPathComponent.localizedCaseInsensitiveContains(query)

        if matchesFile || !filteredChildren.isEmpty {
            return OutlineFile(
                id: file.id,
                url: file.url,
                children: matchesFile ? file.children : filteredChildren
            )
        }

        return nil
    }

    private func filter(_ node: OutlineNode, query: String) -> OutlineNode? {
        let matchesSelf =
            node.name.localizedCaseInsensitiveContains(query) ||
            node.kind.rawValue.localizedCaseInsensitiveContains(query) ||
            (node.detail?.localizedCaseInsensitiveContains(query) ?? false)

        if matchesSelf {
            return node
        }

        let filteredChildren = node.children.compactMap { filter($0, query: query) }
        guard !filteredChildren.isEmpty else { return nil }

        return OutlineNode(
            id: node.id,
            name: node.name,
            kind: node.kind,
            file: node.file,
            line: node.line,
            column: node.column,
            detail: node.detail,
            children: filteredChildren
        )
    }

    private func allExpandableIDs(in files: [OutlineFile]) -> Set<String> {
        var ids = Set(files.map(\.id))
        for file in files {
            for node in file.children {
                ids.formUnion(allExpandableIDs(in: node))
            }
        }
        return ids
    }

    private func allExpandableIDs(in node: OutlineNode) -> Set<String> {
        guard !node.children.isEmpty else { return [] }
        var ids: Set<String> = [node.id]
        for child in node.children {
            ids.formUnion(allExpandableIDs(in: child))
        }
        return ids
    }
}

private struct StructureNodeView: View {
    let node: OutlineNode
    @Binding var expandedIDs: Set<String>
    var selectedNodeID: String?
    var onSelectNode: ((OutlineNode) -> Void)? = nil
    var usageCountForNode: ((OutlineNode) -> Int?)? = nil
    var usageReferencesForNode: ((OutlineNode) -> [UsageReference])? = nil
    var onUsageBadgeTap: ((OutlineNode) -> Void)? = nil

    var body: some View {
        if node.children.isEmpty {
            StructureNodeLabel(
                node: node,
                isSelected: selectedNodeID == node.id,
                onSelect: onSelectNode,
                usageCount: usageCountForNode?(node),
                canOpenUsages: !(usageReferencesForNode?(node).isEmpty ?? true),
                onUsageTap: {
                    onUsageBadgeTap?(node)
                }
            )
                .padding(.vertical, 2)
        } else {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedIDs.contains(node.id) },
                    set: { isExpanded in
                        if isExpanded {
                            expandedIDs.insert(node.id)
                        } else {
                            expandedIDs.remove(node.id)
                        }
                    }
                )
            ) {
                ForEach(node.children) { child in
                    StructureNodeView(
                        node: child,
                        expandedIDs: $expandedIDs,
                        selectedNodeID: selectedNodeID,
                        onSelectNode: onSelectNode,
                        usageCountForNode: usageCountForNode,
                        usageReferencesForNode: usageReferencesForNode,
                        onUsageBadgeTap: onUsageBadgeTap
                    )
                }
            } label: {
                StructureNodeLabel(
                    node: node,
                    isSelected: selectedNodeID == node.id,
                    onSelect: onSelectNode,
                    usageCount: usageCountForNode?(node),
                    canOpenUsages: !(usageReferencesForNode?(node).isEmpty ?? true),
                    onUsageTap: {
                        onUsageBadgeTap?(node)
                    }
                )
            }
        }
    }
}

private struct StructureNodeLabel: View {
    let node: OutlineNode
    var isSelected = false
    var onSelect: ((OutlineNode) -> Void)? = nil
    var usageCount: Int?
    var canOpenUsages = false
    var onUsageTap: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName(for: node.kind))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(node.name)
                    .font(.system(.body, design: .monospaced))

                if let detail = node.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                if let usageCount {
                    Button {
                        onUsageTap?()
                    } label: {
                        Text("\(usageCount)x")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(usageCount == 0 ? .orange : .green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill((usageCount == 0 ? Color.orange : Color.green).opacity(0.18))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canOpenUsages)
                    .help(canOpenUsages ? "Show usage locations" : "No usage locations available")
                }

                Text("L\(node.line)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect?(node)
        }
    }

    private func iconName(for kind: OutlineKind) -> String {
        switch kind {
        case .file: return "doc.text"
        case .class: return "cube.fill"
        case .actor: return "person.crop.rectangle"
        case .struct: return "square.stack.3d.up"
        case .enum: return "list.bullet.rectangle"
        case .protocol: return "point.3.connected.trianglepath.dotted"
        case .extensionDecl: return "arrow.triangle.branch"
        case .typeAlias: return "arrow.triangle.branch"
        case .function, .method, .initializer: return "function"
        case .property: return "square.fill"
        case .variable: return "character.cursor.ibeam"
        case .parameter: return "slider.horizontal.3"
        case .enumCase: return "list.bullet"
        }
    }
}
