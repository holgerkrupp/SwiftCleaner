import AppKit
import SwiftUI

private enum EditorAction {
    case undo
    case redo
    case save
    case revert
}

struct ProjectDetailsView: View {
    private enum NavigatorMode: String, CaseIterable, Identifiable {
        case allSymbols = "All Symbols"
        case unusedSymbols = "Unused Symbols"
        case unusedFiles = "Unused Files"

        var id: String { rawValue }
    }

    private struct PendingUnusedFileAction: Identifiable {
        let id = UUID()
        let fileURL: URL?
        let removeFromProject: Bool
        let appliesToAll: Bool
    }

    @ObservedObject var analyzer: ProjectAnalyzer
    @State private var selectedFileURL: URL?
    @State private var selectedLine: Int = 1
    @State private var selectedSymbolName: String?
    @State private var selectedNodeID: String?
    @State private var selectedNavigatorMode: NavigatorMode = .allSymbols
    @State private var usagePresentation: UsagePresentation?
    @State private var pendingEditorCommand: EditorCommandRequest?
    @State private var isEditorDirty = false
    @State private var canUndo = false
    @State private var canRedo = false
    @State private var editorStatusMessage: String?
    @State private var pendingBulkUnusedAction: UnusedItemAction?
    @State private var pendingUnusedFileAction: PendingUnusedFileAction?
    @State private var pendingNavigatorSyncTask: Task<Void, Never>?
    @State private var lastCursorSyncFilePath: String = ""
    @State private var lastCursorSyncLine: Int = -1

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
                workspaceSplitView
            }
        }
        .onAppear {
            ensureInitialSelectionIfNeeded()
        }
        .onChange(of: analyzer.outlineFiles) { _, _ in
            ensureInitialSelectionIfNeeded()
        }
        .sheet(item: $usagePresentation) { presentation in
            UsageLocationsView(
                symbolName: presentation.symbolName,
                locations: presentation.locations,
                onSelectLocation: { location in
                    open(fileURL: location.file, line: location.line, symbolName: presentation.symbolName)
                    usagePresentation = nil
                },
                onClose: {
                    usagePresentation = nil
                }
            )
            .frame(minWidth: 700, minHeight: 460)
        }
        .confirmationDialog(
            pendingBulkUnusedAction?.confirmationTitle(count: analyzer.unusedElements.count) ?? "Apply to All Unused",
            isPresented: bulkActionConfirmationBinding,
            titleVisibility: .visible,
            presenting: pendingBulkUnusedAction
        ) { action in
            Button(action.shortTitle, role: action.isDestructive ? .destructive : nil) {
                let elements = analyzer.unusedElements
                pendingBulkUnusedAction = nil
                Task {
                    await analyzer.apply(action, to: elements)
                    editorStatusMessage = "\(action.shortTitle) applied to \(elements.count) unused symbols."
                }
            }
            Button("Cancel", role: .cancel) {
                pendingBulkUnusedAction = nil
            }
        } message: { action in
            Text("\(action.confirmationMessage(count: analyzer.unusedElements.count)) This applies to all currently detected unused symbols.")
        }
        .confirmationDialog(
            unusedFileConfirmationTitle,
            isPresented: unusedFileActionConfirmationBinding,
            titleVisibility: .visible,
            presenting: pendingUnusedFileAction
        ) { pendingAction in
            Button(pendingAction.removeFromProject ? "Delete + Remove From Project" : "Delete File", role: .destructive) {
                handleUnusedFileActionConfirmation(pendingAction)
            }
            Button("Cancel", role: .cancel) {
                pendingUnusedFileAction = nil
            }
        } message: { pendingAction in
            if pendingAction.appliesToAll {
                Text("This will process all currently listed unused files. Deleting removes the files from disk; project removal also updates .xcodeproj references.")
            } else {
                Text("This will process the selected unused file. Deleting removes it from disk; project removal also updates .xcodeproj references.")
            }
        }
    }

    private var workspaceSplitView: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Project Navigator", systemImage: "sidebar.left")
                        .font(.headline)
                    Text(navigatorCountText)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.2)))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                Picker("Navigator Mode", selection: $selectedNavigatorMode) {
                    ForEach(NavigatorMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .labelsHidden() 

                navigatorContent
            }
            .frame(minWidth: 300, maxWidth: 420)
            .background(Color(nsColor: .controlBackgroundColor))

            editorPane
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            editorHeader
            Divider()

            if let selectedFileURL {
                SourceCodeEditorView(
                    fileURL: selectedFileURL,
                    targetLine: selectedLine,
                    commandRequest: $pendingEditorCommand,
                    onDirtyStateChange: { isDirty in
                        isEditorDirty = isDirty
                    },
                    onUndoRedoStateChange: { newCanUndo, newCanRedo in
                        canUndo = newCanUndo
                        canRedo = newCanRedo
                    },
                    onSaveFinished: { result in
                        switch result {
                        case .success:
                            editorStatusMessage = "Saved"
                        case .failure(let error):
                            editorStatusMessage = "Save failed: \(error.localizedDescription)"
                        }
                    },
                    onCursorPositionChange: { fileURL, line, _ in
                        scheduleNavigatorSyncFromEditorCursor(fileURL: fileURL, line: line)
                    }
                )
            } else {
                ContentUnavailableView(
                    "Select a Source File",
                    systemImage: "doc.text",
                    description: Text("Choose a file or declaration in the navigator to open it in the editor.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredOutlineFiles: [OutlineFile] {
        let unusedKeys = Set(analyzer.unusedElements.map { unused in
            outlineKey(file: unused.file, line: unused.line, name: unused.name)
        })

        return analyzer.outlineFiles.compactMap { file in
            let children = file.children.compactMap { filter(node: $0, matching: unusedKeys) }
            guard !children.isEmpty else { return nil }

            return OutlineFile(
                id: file.id,
                url: file.url,
                children: children
            )
        }
    }

    @ViewBuilder
    private var navigatorContent: some View {
        switch selectedNavigatorMode {
        case .allSymbols:
            ProjectStructureView(
                files: analyzer.outlineFiles,
                selectedFileURL: selectedFileURL,
                selectedNodeID: selectedNodeID,
                onSelectFile: { fileURL in
                    open(fileURL: fileURL, line: 1, symbolName: nil)
                },
                onSelectNode: { node in
                    open(fileURL: node.file, line: node.line, symbolName: node.name)
                },
                usageCountForNode: usageCount(for:),
                usageReferencesForNode: usageReferences(for:),
                onUsageBadgeTap: showUsageLocations(for:)
            )
        case .unusedSymbols:
            if filteredOutlineFiles.isEmpty {
                ContentUnavailableView(
                    "No Unused Symbols",
                    systemImage: "checkmark.circle",
                    description: Text("Run analysis and unused declarations will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProjectStructureView(
                    files: filteredOutlineFiles,
                    selectedFileURL: selectedFileURL,
                    selectedNodeID: selectedNodeID,
                    onSelectFile: { fileURL in
                        open(fileURL: fileURL, line: 1, symbolName: nil)
                    },
                    onSelectNode: { node in
                        open(fileURL: node.file, line: node.line, symbolName: node.name)
                    },
                    usageCountForNode: usageCount(for:),
                    usageReferencesForNode: usageReferences(for:),
                    onUsageBadgeTap: showUsageLocations(for:)
                )
            }
        case .unusedFiles:
            UnusedFilesNavigatorView(
                likelyUnusedFiles: analyzer.likelyUnusedFiles,
                diskOnlySwiftFiles: analyzer.diskOnlySwiftFiles,
                onSelectLikelyUnusedFile: { file in
                    open(fileURL: file.file, line: file.line, symbolName: file.file.lastPathComponent)
                },
                onSelectDiskOnlyFile: { file in
                    open(fileURL: file.file, line: 1, symbolName: file.file.lastPathComponent)
                }
            )
        }
    }

    private var navigatorCountText: String {
        switch selectedNavigatorMode {
        case .allSymbols:
            return "\(analyzer.summary.trackedDeclarationCount)"
        case .unusedSymbols:
            return "\(analyzer.unusedElements.count)"
        case .unusedFiles:
            return "\(analyzer.likelyUnusedFiles.count + analyzer.diskOnlySwiftFiles.count)"
        }
    }

    private func filter(node: OutlineNode, matching unusedKeys: Set<String>) -> OutlineNode? {
        let filteredChildren = node.children.compactMap { filter(node: $0, matching: unusedKeys) }
        let isUnused = unusedKeys.contains(outlineKey(file: node.file, line: node.line, name: node.name))

        guard isUnused || !filteredChildren.isEmpty else {
            return nil
        }

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

    private func outlineKey(file: URL, line: Int, name: String) -> String {
        "\(file.standardizedFileURL.path)#\(line)#\(name)"
    }

    private var usageCountsByKey: [String: Int] {
        analyzer.elementUsages.reduce(into: [String: Int]()) { partialResult, usage in
            partialResult[outlineKey(file: usage.file, line: usage.line, name: usage.name)] = usage.usageCount
        }
    }

    private func usageCount(for node: OutlineNode) -> Int? {
        usageCountsByKey[outlineKey(file: node.file, line: node.line, name: node.name)]
    }

    private var usageByKey: [String: ElementUsage] {
        analyzer.elementUsages.reduce(into: [String: ElementUsage]()) { partialResult, usage in
            partialResult[outlineKey(file: usage.file, line: usage.line, name: usage.name)] = usage
        }
    }

    private func usageReferences(for node: OutlineNode) -> [UsageReference] {
        usageByKey[outlineKey(file: node.file, line: node.line, name: node.name)]?.usageReferences ?? []
    }

    private func showUsageLocations(for node: OutlineNode) {
        guard let usage = usageByKey[outlineKey(file: node.file, line: node.line, name: node.name)] else {
            return
        }
        guard !usage.usageReferences.isEmpty else { return }

        usagePresentation = UsagePresentation(
            symbolName: usage.name,
            locations: usage.usageReferences
        )
    }

    private var editorHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "curlybraces.square")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedFileURL?.lastPathComponent ?? "Editor")
                    .font(.headline)

                Text(editorSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let editorStatusMessage {
                Text(editorStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                sendEditorAction(.undo)
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .disabled(!canUndo)
            .help("Undo")

            Button {
                sendEditorAction(.redo)
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .buttonStyle(.borderless)
            .disabled(!canRedo)
            .help("Redo")

            Button("Revert") {
                sendEditorAction(.revert)
            }
            .disabled(!isEditorDirty)
            .help("Discard unsaved changes in the current file.")

            Button("Save") {
                sendEditorAction(.save)
            }
            .disabled(!isEditorDirty)
            .keyboardShortcut("s", modifiers: [.command])

            Button("Open in Xcode") {
                openInXcode()
            }
            .disabled(selectedFileURL == nil)

            if let selectedUnusedElement {
                Menu {
                    ForEach(UnusedItemAction.allCases) { action in
                        Button(role: action.isDestructive ? .destructive : nil) {
                            Task {
                                await analyzer.apply(action, to: selectedUnusedElement)
                                editorStatusMessage = "\(action.shortTitle) applied to \(selectedUnusedElement.name)."
                            }
                        } label: {
                            Label(action.shortTitle, systemImage: action.systemImage)
                        }
                    }
                } label: {
                    Label("Selected Unused", systemImage: "wand.and.stars")
                }
                .disabled(analyzer.isAnalyzing || analyzer.isApplyingEdit)
                .help("Apply cleanup action to the currently selected unused symbol.")
            }

            Menu {
                ForEach(UnusedItemAction.allCases) { action in
                    Button(role: action.isDestructive ? .destructive : nil) {
                        pendingBulkUnusedAction = action
                    } label: {
                        Label(action.shortTitle, systemImage: action.systemImage)
                    }
                }
            } label: {
                Label("All Unused (\(analyzer.unusedElements.count))", systemImage: "trash.slash")
            }
            .disabled(analyzer.unusedElements.isEmpty || analyzer.isAnalyzing || analyzer.isApplyingEdit)
            .help("Apply cleanup action to all currently detected unused symbols.")

            if let selectedUnusedFileCandidate {
                Menu {
                    Button(role: .destructive) {
                        pendingUnusedFileAction = PendingUnusedFileAction(
                            fileURL: selectedUnusedFileCandidate,
                            removeFromProject: false,
                            appliesToAll: false
                        )
                    } label: {
                        Label("Delete File", systemImage: "trash")
                    }

                    Button(role: .destructive) {
                        pendingUnusedFileAction = PendingUnusedFileAction(
                            fileURL: selectedUnusedFileCandidate,
                            removeFromProject: true,
                            appliesToAll: false
                        )
                    } label: {
                        Label("Delete + Remove From Project", systemImage: "trash.slash")
                    }
                } label: {
                    Label("Selected File", systemImage: "doc.badge.gearshape")
                }
                .disabled(analyzer.isAnalyzing || analyzer.isApplyingEdit)
                .help("Delete selected unused file and optionally remove it from Xcode projects.")
            }

            Menu {
                Button(role: .destructive) {
                    pendingUnusedFileAction = PendingUnusedFileAction(
                        fileURL: nil,
                        removeFromProject: false,
                        appliesToAll: true
                    )
                } label: {
                    Label("Delete All Unused Files", systemImage: "trash")
                }

                Button(role: .destructive) {
                    pendingUnusedFileAction = PendingUnusedFileAction(
                        fileURL: nil,
                        removeFromProject: true,
                        appliesToAll: true
                    )
                } label: {
                    Label("Delete All + Remove From Project", systemImage: "trash.slash")
                }
            } label: {
                Label("All Unused Files (\(unusedFileCandidates.count))", systemImage: "folder.badge.minus")
            }
            .disabled(unusedFileCandidates.isEmpty || analyzer.isAnalyzing || analyzer.isApplyingEdit)
            .help("Delete all listed unused files and optionally remove them from Xcode projects.")
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var editorSubtitle: String {
        if let selectedFileURL {
            let symbol = selectedSymbolName ?? "File"
            return "\(selectedFileURL.path)  •  \(symbol)  •  line \(selectedLine)"
        } else {
            return "No source selected"
        }
    }

    private func ensureInitialSelectionIfNeeded() {
        guard selectedFileURL == nil else { return }
        guard let firstFile = analyzer.outlineFiles.first?.url else { return }
        open(fileURL: firstFile, line: 1, symbolName: nil)
    }

    private func open(fileURL: URL, line: Int, symbolName: String?) {
        selectedFileURL = fileURL
        selectedLine = max(1, line)
        selectedSymbolName = symbolName
        selectedNodeID = Self.bestMatchingNode(
            in: visibleNavigatorFiles,
            filePath: fileURL.standardizedFileURL.path,
            line: line
        )?.id
        editorStatusMessage = nil
    }

    private func scheduleNavigatorSyncFromEditorCursor(fileURL: URL, line: Int) {
        guard selectedNavigatorMode != .unusedFiles else { return }

        let normalizedPath = fileURL.standardizedFileURL.path
        if normalizedPath == lastCursorSyncFilePath && line == lastCursorSyncLine {
            return
        }
        lastCursorSyncFilePath = normalizedPath
        lastCursorSyncLine = line

        let filesSnapshot = visibleNavigatorFiles
        pendingNavigatorSyncTask?.cancel()
        pendingNavigatorSyncTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            let match = Self.bestMatchingNode(in: filesSnapshot, filePath: normalizedPath, line: line)

            await MainActor.run {
                guard !Task.isCancelled else { return }
                if self.selectedFileURL?.standardizedFileURL.path != normalizedPath {
                    self.selectedFileURL = URL(fileURLWithPath: normalizedPath)
                }
                guard let match else { return }
                if self.selectedNodeID != match.id {
                    self.selectedNodeID = match.id
                    self.selectedSymbolName = match.name
                }
            }
        }
    }

    private var visibleNavigatorFiles: [OutlineFile] {
        switch selectedNavigatorMode {
        case .allSymbols:
            return analyzer.outlineFiles
        case .unusedSymbols:
            return filteredOutlineFiles
        case .unusedFiles:
            return []
        }
    }

    nonisolated private static func bestMatchingNode(in files: [OutlineFile], filePath: String, line: Int) -> OutlineNode? {
        guard let targetFile = files.first(where: { $0.url.standardizedFileURL.path == filePath }) else {
            return nil
        }

        var best: OutlineNode?
        for node in targetFile.children {
            if let candidate = bestMatchingNode(in: node, line: line) {
                if best == nil || candidate.line >= (best?.line ?? 0) {
                    best = candidate
                }
            }
        }
        return best
    }

    nonisolated private static func bestMatchingNode(in node: OutlineNode, line: Int) -> OutlineNode? {
        guard node.line <= line else { return nil }
        var best: OutlineNode? = node

        for child in node.children {
            if let candidate = bestMatchingNode(in: child, line: line) {
                if candidate.line >= (best?.line ?? 0) {
                    best = candidate
                }
            }
        }
        return best
    }

    private func sendEditorAction(_ action: EditorAction) {
        pendingEditorCommand = EditorCommandRequest(
            id: UUID(),
            action: action
        )
    }

    private func openInXcode() {
        guard let selectedFileURL else { return }
        guard let xcodeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode") else {
            editorStatusMessage = "Xcode not found."
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([selectedFileURL], withApplicationAt: xcodeURL, configuration: configuration) { _, error in
            if let error {
                editorStatusMessage = "Could not open Xcode: \(error.localizedDescription)"
            }
        }
    }

    private var selectedUnusedElement: UnusedElement? {
        guard let selectedFileURL else { return nil }
        let path = selectedFileURL.standardizedFileURL.path
        return analyzer.unusedElements.first { element in
            element.file.standardizedFileURL.path == path &&
            element.line == selectedLine &&
            (selectedSymbolName == nil || element.name == selectedSymbolName)
        }
    }

    private var selectedUnusedFileCandidate: URL? {
        guard let selectedFileURL else { return nil }
        let path = selectedFileURL.standardizedFileURL.path
        return unusedFileCandidates.first { $0.standardizedFileURL.path == path }
    }

    private var unusedFileCandidates: [URL] {
        let likely = analyzer.likelyUnusedFiles.map(\.file)
        let diskOnly = analyzer.diskOnlySwiftFiles.map(\.file)
        let unique = Dictionary(grouping: likely + diskOnly, by: { $0.standardizedFileURL.path }).compactMap { $0.value.first }
        return unique.sorted { $0.path < $1.path }
    }

    private var bulkActionConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingBulkUnusedAction != nil },
            set: { isPresented in
                if !isPresented {
                    pendingBulkUnusedAction = nil
                }
            }
        )
    }

    private var unusedFileActionConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingUnusedFileAction != nil },
            set: { isPresented in
                if !isPresented {
                    pendingUnusedFileAction = nil
                }
            }
        )
    }

    private var unusedFileConfirmationTitle: String {
        guard let pendingUnusedFileAction else { return "Delete Unused File" }
        if pendingUnusedFileAction.appliesToAll {
            return "Process \(unusedFileCandidates.count) unused file(s)?"
        }
        return "Process selected unused file?"
    }

    private func handleUnusedFileActionConfirmation(_ pendingAction: PendingUnusedFileAction) {
        pendingUnusedFileAction = nil
        Task {
            if pendingAction.appliesToAll {
                let targets = unusedFileCandidates
                for fileURL in targets {
                    await analyzer.deleteUnusedFile(fileURL, removeFromProject: pendingAction.removeFromProject)
                }
                editorStatusMessage = "Processed \(targets.count) unused file(s)."
            } else if let fileURL = pendingAction.fileURL {
                await analyzer.deleteUnusedFile(fileURL, removeFromProject: pendingAction.removeFromProject)
                editorStatusMessage = "Processed \(fileURL.lastPathComponent)."
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
            SummaryCard(title: "On Disk Only", value: "\(analyzer.summary.diskOnlySwiftFileCount)", accentColor: .yellow)
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

private struct SourceCodeEditorView: NSViewRepresentable {
    let fileURL: URL
    let targetLine: Int
    @Binding var commandRequest: EditorCommandRequest?
    var onDirtyStateChange: (Bool) -> Void
    var onUndoRedoStateChange: (Bool, Bool) -> Void
    var onSaveFinished: (Result<Void, Error>) -> Void
    var onCursorPositionChange: (URL, Int, Int) -> Void
    private let highlighter = SwiftSyntaxHighlighter()

    func makeCoordinator() -> Coordinator {
        Coordinator(
            highlighter: highlighter,
            onDirtyStateChange: onDirtyStateChange,
            onUndoRedoStateChange: onUndoRedoStateChange,
            onSaveFinished: onSaveFinished,
            onCursorPositionChange: onCursorPositionChange
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return NSScrollView()
        }

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.hasVerticalRuler = false
        scrollView.rulersVisible = false

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = false
            textContainer.heightTracksTextView = true
            textContainer.lineBreakMode = .byClipping
            textContainer.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }

        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: scrollView.contentSize.width, height: scrollView.contentSize.height)
        textView.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.labelColor
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.drawsBackground = true
        textView.allowsUndo = true
        textView.delegate = context.coordinator
        textView.insertionPointColor = NSColor.controlAccentColor

        context.coordinator.textView = textView
        context.coordinator.reloadStates()
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        let currentModificationDate = modificationDate(for: fileURL)
        let shouldReloadFile =
            context.coordinator.currentFileURL != fileURL ||
            context.coordinator.fileModificationDate != currentModificationDate

        if shouldReloadFile {
            do {
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                context.coordinator.loadSource(source, for: fileURL, modificationDate: currentModificationDate)
            } catch {
                textView.string = "Unable to open file:\n\(fileURL.path)\n\n\(error.localizedDescription)"
                context.coordinator.currentFileURL = fileURL
                context.coordinator.fileModificationDate = currentModificationDate
            }
        }

        if shouldReloadFile || context.coordinator.lastJumpLine != targetLine {
            jump(to: targetLine, in: textView)
            context.coordinator.lastJumpLine = targetLine
        }

        if let commandRequest, context.coordinator.lastHandledCommandID != commandRequest.id {
            context.coordinator.handle(commandRequest.action)
            context.coordinator.lastHandledCommandID = commandRequest.id
            DispatchQueue.main.async {
                self.commandRequest = nil
            }
        }

    }

    private func modificationDate(for url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    private func jump(to line: Int, in textView: NSTextView) {
        let text = textView.string as NSString
        guard text.length > 0 else {
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            return
        }

        var currentLine = 1
        var location = 0
        let target = max(1, line)

        while currentLine < target && location < text.length {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            let next = NSMaxRange(lineRange)
            guard next > location else { break }
            location = next
            currentLine += 1
        }

        let clampedLocation = min(location, max(0, text.length - 1))
        let targetRange = text.lineRange(for: NSRange(location: clampedLocation, length: 0))
        textView.setSelectedRange(targetRange)
        textView.scrollRangeToVisible(targetRange)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var textView: NSTextView?
        var currentFileURL: URL?
        var fileModificationDate: Date?
        var lastJumpLine: Int?
        var lastHandledCommandID: UUID?
        var originalSource = ""
        var pendingHighlightWorkItem: DispatchWorkItem?
        var isApplyingHighlight = false
        var pendingCursorSyncWorkItem: DispatchWorkItem?
        var lastPublishedCursorLocation: Int = -1
        private let highlighter: SwiftSyntaxHighlighter
        private let onDirtyStateChange: (Bool) -> Void
        private let onUndoRedoStateChange: (Bool, Bool) -> Void
        private let onSaveFinished: (Result<Void, Error>) -> Void
        private let onCursorPositionChange: (URL, Int, Int) -> Void
        private let liveHighlightLimit = 160_000
        private let cursorSyncQueue = DispatchQueue(label: "swiftcleaner.editor.cursor-sync", qos: .utility)

        init(
            highlighter: SwiftSyntaxHighlighter,
            onDirtyStateChange: @escaping (Bool) -> Void,
            onUndoRedoStateChange: @escaping (Bool, Bool) -> Void,
            onSaveFinished: @escaping (Result<Void, Error>) -> Void,
            onCursorPositionChange: @escaping (URL, Int, Int) -> Void
        ) {
            self.highlighter = highlighter
            self.onDirtyStateChange = onDirtyStateChange
            self.onUndoRedoStateChange = onUndoRedoStateChange
            self.onSaveFinished = onSaveFinished
            self.onCursorPositionChange = onCursorPositionChange
        }

        func loadSource(_ source: String, for url: URL, modificationDate: Date?) {
            guard let textView, let textStorage = textView.textStorage else { return }
            textView.string = source
            if !source.isEmpty {
                highlighter.highlightInPlace(textStorage: textStorage)
            }
            originalSource = source
            currentFileURL = url
            fileModificationDate = modificationDate
            reloadStates()
            publishCursorPosition(immediate: true)
        }

        func textDidChange(_ notification: Notification) {
            if isApplyingHighlight {
                return
            }
            guard let textView, let textStorage = textView.textStorage else { return }
            reloadStates()
            scheduleDeferredHighlight(textStorage: textStorage, textView: textView)
            publishCursorPosition(immediate: false)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            publishCursorPosition(immediate: false)
        }

        func reloadStates() {
            guard let textView else { return }
            onDirtyStateChange(textView.string != originalSource)
            onUndoRedoStateChange(textView.undoManager?.canUndo ?? false, textView.undoManager?.canRedo ?? false)
        }

        func handle(_ action: EditorAction) {
            guard let textView else { return }

            switch action {
            case .undo:
                textView.undoManager?.undo()
            case .redo:
                textView.undoManager?.redo()
            case .save:
                saveCurrentText()
            case .revert:
                revertToOriginal()
            }

            reloadStates()
        }

        private func saveCurrentText() {
            guard let currentFileURL, let textView else { return }
            do {
                try textView.string.write(to: currentFileURL, atomically: true, encoding: .utf8)
                originalSource = textView.string
                fileModificationDate = (try? FileManager.default.attributesOfItem(atPath: currentFileURL.path)[.modificationDate]) as? Date
                onSaveFinished(.success(()))
            } catch {
                onSaveFinished(.failure(error))
            }
        }

        private func revertToOriginal() {
            guard let textView, let textStorage = textView.textStorage else { return }
            textStorage.setAttributedString(highlighter.highlight(source: originalSource))
            textView.undoManager?.removeAllActions()
            reloadStates()
        }

        private func scheduleDeferredHighlight(textStorage: NSTextStorage, textView: NSTextView) {
            pendingHighlightWorkItem?.cancel()
            guard textView.string.count <= liveHighlightLimit else { return }

            let workItem = DispatchWorkItem { [weak self, weak textStorage, weak textView] in
                guard let self, let textStorage, let textView else { return }
                guard !self.isApplyingHighlight else { return }
                self.isApplyingHighlight = true
                let selectedRange = textView.selectedRange()
                self.highlighter.highlightInPlace(textStorage: textStorage)
                textView.setSelectedRange(selectedRange)
                self.isApplyingHighlight = false
            }
            pendingHighlightWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: workItem)
        }

        private func publishCursorPosition(immediate: Bool) {
            guard let textView, let currentFileURL else { return }
            let location = textView.selectedRange().location
            let content = textView.string as NSString
            let clampedLocation = min(max(0, location), content.length)

            if clampedLocation == lastPublishedCursorLocation && !immediate {
                return
            }

            pendingCursorSyncWorkItem?.cancel()
            let fileURL = currentFileURL
            let textSnapshot = content
            var workItem: DispatchWorkItem?
            workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let (line, column) = Self.lineAndColumn(in: textSnapshot, at: clampedLocation)
                DispatchQueue.main.async {
                    guard workItem?.isCancelled == false else { return }
                    self.lastPublishedCursorLocation = clampedLocation
                    self.onCursorPositionChange(fileURL, line, column)
                }
            }

            pendingCursorSyncWorkItem = workItem
            if immediate {
                if let workItem {
                    cursorSyncQueue.async(execute: workItem)
                }
            } else {
                if let workItem {
                    cursorSyncQueue.asyncAfter(deadline: .now() + 0.10, execute: workItem)
                }
            }
        }

        private static func lineAndColumn(in text: NSString, at location: Int) -> (Int, Int) {
            guard text.length > 0 else { return (1, 1) }
            let clamped = min(max(0, location), text.length)
            var line = 1
            var column = 1
            var index = 0

            while index < clamped {
                if text.character(at: index) == 10 {
                    line += 1
                    column = 1
                } else {
                    column += 1
                }
                index += 1
            }

            return (line, column)
        }
    }
}

private struct UnusedFilesNavigatorView: View {
    let likelyUnusedFiles: [LikelyUnusedFile]
    let diskOnlySwiftFiles: [DiskOnlySwiftFile]
    var onSelectLikelyUnusedFile: (LikelyUnusedFile) -> Void
    var onSelectDiskOnlyFile: (DiskOnlySwiftFile) -> Void

    var body: some View {
        List {
            if likelyUnusedFiles.isEmpty && diskOnlySwiftFiles.isEmpty {
                ContentUnavailableView(
                    "No Unused Files",
                    systemImage: "doc.text",
                    description: Text("No likely unused or disk-only Swift files were found.")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                if !likelyUnusedFiles.isEmpty {
                    Section("Likely Unused In Project") {
                        ForEach(likelyUnusedFiles) { file in
                            HStack(spacing: 8) {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(file.file.lastPathComponent)
                                        .font(.system(.body, design: .monospaced))
                                        .lineLimit(1)
                                    Text("L\(file.line)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelectLikelyUnusedFile(file)
                            }
                        }
                    }
                }

                if !diskOnlySwiftFiles.isEmpty {
                    Section("On Disk But Not In Xcode") {
                        ForEach(diskOnlySwiftFiles) { file in
                            HStack(spacing: 8) {
                                Image(systemName: "externaldrive.badge.xmark")
                                    .foregroundStyle(.yellow)
                                Text(file.file.lastPathComponent)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelectDiskOnlyFile(file)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct UsageLocationsView: View {
    let symbolName: String
    let locations: [UsageReference]
    var onSelectLocation: (UsageReference) -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Usages: \(symbolName)")
                    .font(.headline)
                Spacer()
                Button("Close") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if locations.isEmpty {
                ContentUnavailableView(
                    "No Usage Locations",
                    systemImage: "location.slash",
                    description: Text("No source locations were recorded for this symbol.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(locations) { location in
                    Button {
                        onSelectLocation(location)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "location")
                                .foregroundStyle(Color.accentColor)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(location.file.lastPathComponent)
                                    .font(.system(.body, design: .monospaced))

                                Text(location.file.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                Text("Line \(location.line), Column \(location.column)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct UsagePresentation: Identifiable {
    let id = UUID()
    let symbolName: String
    let locations: [UsageReference]
}

private struct EditorCommandRequest: Identifiable {
    let id: UUID
    let action: EditorAction
}

private final class SafeLineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private let labelColor = NSColor.secondaryLabelColor
    private let gutterColor = NSColor.controlBackgroundColor

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 52
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView else { return }

        gutterColor.setFill()
        rect.fill()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: labelColor,
            .paragraphStyle: paragraphStyle
        ]

        // Safe v2: line numbers are based on a fixed line-height estimate and visible scroll range.
        // This avoids layout manager geometry queries during drawing, preventing layout recursion.
        let lineHeight = max(1, textView.layoutManager?.defaultLineHeight(for: font) ?? 14)
        let visibleY = textView.enclosingScrollView?.contentView.bounds.origin.y ?? 0
        let insetTop = textView.textContainerInset.height
        let totalLines = max(1, textView.string.split(separator: "\n", omittingEmptySubsequences: false).count)

        let startLine = max(1, Int(floor((visibleY - insetTop) / lineHeight)) + 1)
        let endLine = min(totalLines, Int(ceil((visibleY + rect.height) / lineHeight)) + 2)
        guard startLine <= endLine else { return }

        for line in startLine...endLine {
            let y = insetTop + CGFloat(line - 1) * lineHeight - visibleY
            let text = "\(line)" as NSString
            text.draw(
                in: NSRect(x: 4, y: y, width: ruleThickness - 8, height: lineHeight),
                withAttributes: attributes
            )
        }

        NSColor.separatorColor.setStroke()
        let borderPath = NSBezierPath()
        borderPath.move(to: NSPoint(x: ruleThickness - 0.5, y: rect.minY))
        borderPath.line(to: NSPoint(x: ruleThickness - 0.5, y: rect.maxY))
        borderPath.lineWidth = 1
        borderPath.stroke()
    }
}

private struct SwiftSyntaxHighlighter {
    private let keywordColor = NSColor.systemPink
    private let typeColor = NSColor.systemTeal
    private let stringColor = NSColor.systemRed
    private let commentColor = NSColor.systemGray
    private let numberColor = NSColor.systemOrange
    private let attributeColor = NSColor.systemPurple
    private let baseFont = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)

    func highlight(source: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: source,
            attributes: [
                .font: baseFont,
                .foregroundColor: NSColor.labelColor
            ]
        )
        let fullRange = NSRange(location: 0, length: (source as NSString).length)

        apply(pattern: Self.keywordPattern, color: keywordColor, in: attributed, range: fullRange)
        apply(pattern: Self.typePattern, color: typeColor, in: attributed, range: fullRange)
        apply(pattern: Self.numberPattern, color: numberColor, in: attributed, range: fullRange)
        apply(pattern: Self.attributePattern, color: attributeColor, in: attributed, range: fullRange)
        apply(pattern: Self.stringPattern, color: stringColor, in: attributed, range: fullRange)
        apply(pattern: Self.commentPattern, color: commentColor, in: attributed, range: fullRange)

        return attributed
    }

    func highlightInPlace(textStorage: NSTextStorage) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.beginEditing()
        textStorage.setAttributes(
            [
                .font: baseFont,
                .foregroundColor: NSColor.labelColor
            ],
            range: fullRange
        )
        apply(pattern: Self.keywordPattern, color: keywordColor, in: textStorage, range: fullRange)
        apply(pattern: Self.typePattern, color: typeColor, in: textStorage, range: fullRange)
        apply(pattern: Self.numberPattern, color: numberColor, in: textStorage, range: fullRange)
        apply(pattern: Self.attributePattern, color: attributeColor, in: textStorage, range: fullRange)
        apply(pattern: Self.stringPattern, color: stringColor, in: textStorage, range: fullRange)
        apply(pattern: Self.commentPattern, color: commentColor, in: textStorage, range: fullRange)
        textStorage.endEditing()
    }

    private func apply(pattern: NSRegularExpression, color: NSColor, in attributed: NSAttributedString, range: NSRange) {
        guard let mutable = attributed as? NSMutableAttributedString else { return }
        pattern.enumerateMatches(in: mutable.string, options: [], range: range) { match, _, _ in
            guard let match else { return }
            mutable.addAttributes([.foregroundColor: color], range: match.range)
        }
    }

    private static let keywordPattern = regex(
        #"(?<!\.)\b(associatedtype|actor|as|async|await|break|case|catch|class|continue|convenience|default|defer|do|else|enum|extension|fallthrough|false|fileprivate|final|for|func|guard|if|import|in|indirect|init|inout|internal|is|let|mutating|nil|nonisolated|open|operator|private|protocol|public|repeat|required|rethrows|return|self|Self|static|struct|subscript|super|switch|throw|throws|true|try|typealias|var|where|while)\b"#
    )
    private static let typePattern = regex(#"\b[A-Z][A-Za-z0-9_]*\b"#)
    private static let numberPattern = regex(#"\b\d+(?:\.\d+)?\b"#)
    private static let attributePattern = regex(#"@[A-Za-z_][A-Za-z0-9_]*"#)
    private static let stringPattern = regex(#""(?:\\.|[^"\\])*""#)
    private static let commentPattern = regex(#"//.*|/\*[\s\S]*?\*/"#)

    private static func regex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            fatalError("Invalid regex pattern: \(pattern)")
        }
    }
}
