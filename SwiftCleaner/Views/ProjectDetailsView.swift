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

    @ObservedObject var analyzer: ProjectAnalyzer
    @State private var selectedFileURL: URL?
    @State private var selectedLine: Int = 1
    @State private var selectedSymbolName: String?
    @State private var selectedNavigatorMode: NavigatorMode = .allSymbols
    @State private var usagePresentation: UsagePresentation?
    @State private var pendingEditorCommand: EditorCommandRequest?
    @State private var isEditorDirty = false
    @State private var canUndo = false
    @State private var canRedo = false
    @State private var editorStatusMessage: String?

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
        editorStatusMessage = nil
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
    private let highlighter = SwiftSyntaxHighlighter()

    func makeCoordinator() -> Coordinator {
        Coordinator(
            highlighter: highlighter,
            onDirtyStateChange: onDirtyStateChange,
            onUndoRedoStateChange: onUndoRedoStateChange,
            onSaveFinished: onSaveFinished
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
        private let highlighter: SwiftSyntaxHighlighter
        private let onDirtyStateChange: (Bool) -> Void
        private let onUndoRedoStateChange: (Bool, Bool) -> Void
        private let onSaveFinished: (Result<Void, Error>) -> Void
        private let liveHighlightLimit = 160_000

        init(
            highlighter: SwiftSyntaxHighlighter,
            onDirtyStateChange: @escaping (Bool) -> Void,
            onUndoRedoStateChange: @escaping (Bool, Bool) -> Void,
            onSaveFinished: @escaping (Result<Void, Error>) -> Void
        ) {
            self.highlighter = highlighter
            self.onDirtyStateChange = onDirtyStateChange
            self.onUndoRedoStateChange = onUndoRedoStateChange
            self.onSaveFinished = onSaveFinished
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
        }

        func textDidChange(_ notification: Notification) {
            if isApplyingHighlight {
                return
            }
            guard let textView, let textStorage = textView.textStorage else { return }
            reloadStates()
            scheduleDeferredHighlight(textStorage: textStorage, textView: textView)
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
