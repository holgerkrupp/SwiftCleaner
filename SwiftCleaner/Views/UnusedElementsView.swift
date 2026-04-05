import SwiftUI

struct UnusedElementsView: View {
    @ObservedObject var analyzer: ProjectAnalyzer
    var onSelectElement: ((UnusedElement) -> Void)? = nil

    @State private var expandedGroups: Set<String> = []
    @State private var searchText = ""
    @State private var selectedType: ElementType? = nil
    @State private var pendingBulkAction: UnusedItemAction?

    private var unusedElements: [UnusedElement] {
        analyzer.unusedElements
    }

    private var filteredElements: [UnusedElement] {
        unusedElements.filter { element in
            let matchesSearch =
                searchText.isEmpty ||
                element.name.localizedCaseInsensitiveContains(searchText) ||
                element.qualifiedName.localizedCaseInsensitiveContains(searchText) ||
                (element.containingType?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                element.file.lastPathComponent.localizedCaseInsensitiveContains(searchText) ||
                (element.note?.localizedCaseInsensitiveContains(searchText) ?? false)

            let matchesType = selectedType == nil || element.type == selectedType
            return matchesSearch && matchesType
        }
    }

    private var groupedElements: [(String, [UnusedElement])] {
        let grouped = Dictionary(grouping: filteredElements) { element in
            element.containingType ?? "Global Scope"
        }
        return grouped.sorted { $0.key < $1.key }
    }

    var body: some View {
        List {
            controls

            if unusedElements.isEmpty {
                ContentUnavailableView(
                    "No Likely Unused Declarations",
                    systemImage: "checkmark.circle",
                    description: Text("Nothing was flagged with the current settings.")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            } else if filteredElements.isEmpty {
                ContentUnavailableView(
                    "No Matching Unused Declarations",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Try a different search term or type filter.")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                ForEach(groupedElements, id: \.0) { group, elements in
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
                            UnusedElementRow(
                                analyzer: analyzer,
                                element: element,
                                onSelect: onSelectElement
                            )
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
        }
        .searchable(text: $searchText)
        .confirmationDialog(
            pendingBulkAction?.confirmationTitle(count: filteredElements.count) ?? "Apply to All",
            isPresented: bulkConfirmationBinding,
            titleVisibility: .visible,
            presenting: pendingBulkAction
        ) { action in
            Button(action.shortTitle, role: action.isDestructive ? .destructive : nil) {
                let elements = filteredElements
                pendingBulkAction = nil
                Task {
                    await analyzer.apply(action, to: elements)
                }
            }

            Button("Cancel", role: .cancel) {
                pendingBulkAction = nil
            }
        } message: { action in
            Text("\(action.confirmationMessage(count: filteredElements.count)) This applies to the currently visible unused items.")
        }
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

            Menu {
                ForEach(UnusedItemAction.allCases) { action in
                    Button(role: action.isDestructive ? .destructive : nil) {
                        pendingBulkAction = action
                    } label: {
                        Label(action.shortTitle, systemImage: action.systemImage)
                    }
                }
            } label: {
                Label("Apply to All", systemImage: "wand.and.stars")
            }
            .disabled(filteredElements.isEmpty || analyzer.isAnalyzing || analyzer.isApplyingEdit)
            .help("Apply an action to all currently visible unused items.")

            Spacer()

            Button("Expand All") {
                expandedGroups = Set(groupedElements.map(\.0))
            }
            .disabled(groupedElements.isEmpty)

            Button("Collapse All") {
                expandedGroups.removeAll()
            }
            .disabled(groupedElements.isEmpty)
        }
        .padding(.vertical, 4)
    }

    private var bulkConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingBulkAction != nil },
            set: { isPresented in
                if !isPresented {
                    pendingBulkAction = nil
                }
            }
        )
    }
}

private struct UnusedElementRow: View {
    @ObservedObject var analyzer: ProjectAnalyzer
    let element: UnusedElement
    var onSelect: ((UnusedElement) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName(for: element.type))
                    .foregroundStyle(.orange)

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

                VStack(alignment: .trailing, spacing: 8) {
                    Menu {
                        ForEach(UnusedItemAction.allCases) { action in
                            Button(role: action.isDestructive ? .destructive : nil) {
                                Task {
                                    await analyzer.apply(action, to: element)
                                }
                            } label: {
                                Label(action.shortTitle, systemImage: action.systemImage)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .imageScale(.large)
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .disabled(analyzer.isAnalyzing || analyzer.isApplyingEdit)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect?(element)
            }
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
