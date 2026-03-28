import SwiftUI

struct ElementUsageView: View {
    let usages: [ElementUsage]

    @State private var expandedGroups: Set<String> = []
    @State private var searchText = ""
    @State private var selectedType: ElementType? = nil

    private var groupedUsages: [(String, [ElementUsage])] {
        let grouped = Dictionary(grouping: filteredUsages) { usage in
            usage.containingType ?? "Global Scope"
        }
        return grouped.sorted { $0.key < $1.key }
    }

    private var filteredUsages: [ElementUsage] {
        usages.filter { usage in
            let matchesSearch =
                searchText.isEmpty ||
                usage.name.localizedCaseInsensitiveContains(searchText) ||
                usage.qualifiedName.localizedCaseInsensitiveContains(searchText) ||
                (usage.note?.localizedCaseInsensitiveContains(searchText) ?? false)

            let matchesType = selectedType == nil || usage.type == selectedType
            return matchesSearch && matchesType
        }
    }

    var body: some View {
        List {
            controls

            ForEach(groupedUsages, id: \.0) { group, elements in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedGroups.contains(group) },
                        set: { isExpanded in
                            if isExpanded {
                                expandedGroups.insert(group)
                            } else {
                                expandedGroups.remove(group)
                            }
                        }
                    )
                ) {
                    ForEach(elements) { element in
                        ElementUsageRow(element: element)
                    }
                } label: {
                    HStack {
                        Text(group)
                            .font(.headline)
                        Text("(\(elements.count))")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .searchable(text: $searchText)
    }

    private var controls: some View {
        HStack {
            Picker("Filter by type", selection: $selectedType) {
                Text("All").tag(nil as ElementType?)
                ForEach(ElementType.allCases) { type in
                    Text(type.rawValue).tag(Optional(type))
                }
            }
            .pickerStyle(.menu)

            Spacer()

            Button("Expand All") {
                expandedGroups = Set(groupedUsages.map(\.0))
            }

            Button("Collapse All") {
                expandedGroups.removeAll()
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ElementUsageRow: View {
    let element: ElementUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName(for: element.type))
                    .foregroundStyle(element.isUnused ? .orange : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(element.name)
                            .font(.system(.body, design: .monospaced))

                        if let access = element.accessLevel {
                            Text(access)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("\(element.file.lastPathComponent):\(element.line)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let note = element.note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 4) {
                    Label("\(element.usageCount)", systemImage: "number.circle.fill")
                        .foregroundStyle(element.usageCount == 0 ? .orange : .green)

                    if element.isUnused {
                        Text("Likely unused")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func iconName(for type: ElementType) -> String {
        switch type {
        case .class: return "cube.fill"
        case .actor: return "person.crop.rectangle"
        case .struct: return "square.stack.3d.up"
        case .enum: return "list.bullet.rectangle"
        case .protocol: return "point.3.connected.trianglepath.dotted"
        case .typeAlias: return "arrow.triangle.branch"
        case .function, .method: return "function"
        case .property: return "square.fill"
        case .variable: return "character.cursor.ibeam"
        case .enumCase: return "list.bullet"
        }
    }
}
