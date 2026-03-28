import SwiftUI

struct ProjectStructureView: View {
    let files: [OutlineFile]

    @State private var searchText = ""
    @State private var expandedIDs: Set<String> = []

    private var filteredFiles: [OutlineFile] {
        guard !searchText.isEmpty else { return files }
        return files.compactMap { filter($0, query: searchText) }
    }

    var body: some View {
        List {
            controls

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
                            StructureNodeView(node: node, expandedIDs: $expandedIDs)
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
                    }
                }
            }
        }
        .searchable(text: $searchText)
        .onAppear {
            if expandedIDs.isEmpty {
                expandedIDs = Set(files.map(\.id))
            }
        }
    }

    private var controls: some View {
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
        .padding(.vertical, 4)
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

    var body: some View {
        if node.children.isEmpty {
            StructureNodeLabel(node: node)
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
                    StructureNodeView(node: child, expandedIDs: $expandedIDs)
                }
            } label: {
                StructureNodeLabel(node: node)
            }
        }
    }
}

private struct StructureNodeLabel: View {
    let node: OutlineNode

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

            Text("L\(node.line)")
                .font(.caption)
                .foregroundStyle(.secondary)
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
