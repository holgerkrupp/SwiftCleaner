import AppKit
import Foundation

@MainActor
final class ProjectAnalyzer: ObservableObject {
    @Published var projectPath: URL?
    @Published var isAnalyzing = false
    @Published private(set) var isApplyingEdit = false
    @Published private(set) var cleanupStatistics: CleanupActionStatistics
    @Published var unusedElements: [UnusedElement] = []
    @Published var likelyUnusedFiles: [LikelyUnusedFile] = []
    @Published var diskOnlySwiftFiles: [DiskOnlySwiftFile] = []
    @Published var elementUsages: [ElementUsage] = []
    @Published var outlineFiles: [OutlineFile] = []
    @Published var summary: AnalysisSummary = .empty
    @Published var includePublicDeclarations = false
    @Published var errorMessage: String?

    private var writeAccessRootURL: URL?
    private let cleanupStatisticsStore: CleanupActionStatisticsStore

    init(cleanupStatisticsStore: CleanupActionStatisticsStore = CleanupActionStatisticsStore()) {
        self.cleanupStatisticsStore = cleanupStatisticsStore
        self.cleanupStatistics = cleanupStatisticsStore.load()
    }

    func setProjectPath(_ url: URL) {
        projectPath = url
        errorMessage = nil

        if let writeAccessRootURL, !project(url, isInsideGrantedFolder: writeAccessRootURL) {
            self.writeAccessRootURL = nil
        }
    }

    func analyzeSelectedProject() async {
        guard let projectPath else {
            errorMessage = "Select a Swift project folder first."
            return
        }

        await analyzeProject(at: projectPath)
    }

    func analyzeProject(at url: URL) async {
        projectPath = url
        isAnalyzing = true
        errorMessage = nil
        unusedElements = []
        likelyUnusedFiles = []
        diskOnlySwiftFiles = []
        elementUsages = []
        outlineFiles = []
        summary = .empty

        let startedAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if startedAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let options = AnalysisOptions(includePublicDeclarations: includePublicDeclarations)
            let report = try await Task.detached(priority: .userInitiated) {
                try ProjectAnalysisEngine().analyze(at: url, options: options)
            }.value

            unusedElements = report.unusedElements
            likelyUnusedFiles = report.likelyUnusedFiles
            diskOnlySwiftFiles = report.diskOnlySwiftFiles
            elementUsages = report.elementUsages
            outlineFiles = report.outlineFiles
            summary = report.summary
        } catch {
            errorMessage = error.localizedDescription
        }

        isAnalyzing = false
    }

    func apply(_ action: UnusedItemAction, to element: UnusedElement) async {
        await apply(action, to: [element])
    }

    func apply(_ action: UnusedItemAction, to elements: [UnusedElement]) async {
        guard !elements.isEmpty else { return }
        errorMessage = nil

        guard let projectPath else {
            errorMessage = "Select a Swift project folder first."
            return
        }

        guard let writeAccessURL = requestWriteAccessIfNeeded(for: projectPath) else {
            return
        }

        isApplyingEdit = true

        let startedAccessing = writeAccessURL.startAccessingSecurityScopedResource()
        defer {
            if startedAccessing {
                writeAccessURL.stopAccessingSecurityScopedResource()
            }
        }

        let appliedResult: CleanupActionResult

        do {
            appliedResult = try await Task.detached(priority: .userInitiated) {
                try UnusedElementEditor().apply(action, to: elements)
            }.value
        } catch {
            errorMessage = error.localizedDescription
            isApplyingEdit = false
            return
        }

        cleanupStatistics = cleanupStatisticsStore.record(
            action,
            result: appliedResult,
            projectURL: projectPath
        )

        if action == .delete {
            removeDeletedElementsFromCurrentResults(elements)
        }

        isApplyingEdit = false
    }

    private func requestWriteAccessIfNeeded(for projectURL: URL) -> URL? {
        if let writeAccessRootURL, project(projectURL, isInsideGrantedFolder: writeAccessRootURL) {
            return writeAccessRootURL
        }

        let alert = NSAlert()
        alert.messageText = "Allow SwiftCleaner to modify files?"
        alert.informativeText = """
        SwiftCleaner only asks this when you choose a write action. To continue, grant access to the whole project directory once, and SwiftCleaner will reuse that permission for later edits in the same project.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = projectURL
        panel.prompt = "Allow Changes"
        panel.message = "Select the whole project directory once so SwiftCleaner can reuse that permission for later source edits."

        guard panel.runModal() == .OK, let selectedURL = panel.url?.standardizedFileURL else {
            return nil
        }

        guard project(projectURL, isInsideGrantedFolder: selectedURL) else {
            errorMessage = "Select the current project folder or one of its parent folders to allow source edits."
            return nil
        }

        writeAccessRootURL = selectedURL
        return selectedURL
    }

    private func project(_ projectURL: URL, isInsideGrantedFolder grantedFolderURL: URL) -> Bool {
        let projectPath = projectURL.standardizedFileURL.path
        let grantedPath = grantedFolderURL.standardizedFileURL.path

        return projectPath == grantedPath || projectPath.hasPrefix(grantedPath + "/")
    }

    private func removeDeletedElementsFromCurrentResults(_ elements: [UnusedElement]) {
        let deletedIDs = Set(elements.map(\.id))
        let deletedElements = elements.reduce(into: [String: UnusedElement]()) { partialResult, element in
            partialResult[element.id] = element
        }
        let touchedFiles = Set(elements.map(\.file))

        unusedElements.removeAll { deletedIDs.contains($0.id) }
        likelyUnusedFiles.removeAll { touchedFiles.contains($0.file) }
        elementUsages.removeAll { deletedIDs.contains($0.id) }
        outlineFiles = outlineFiles.map { prune($0, deleting: deletedElements) }

        summary = AnalysisSummary(
            fileCount: summary.fileCount,
            declarationCount: max(0, summary.declarationCount - deletedIDs.count),
            trackedDeclarationCount: max(0, summary.trackedDeclarationCount - deletedIDs.count),
            referenceCount: summary.referenceCount,
            unusedCount: unusedElements.count,
            unusedFileCount: likelyUnusedFiles.count,
            diskOnlySwiftFileCount: diskOnlySwiftFiles.count
        )
    }

    private func prune(_ file: OutlineFile, deleting deletedElements: [String: UnusedElement]) -> OutlineFile {
        OutlineFile(
            id: file.id,
            url: file.url,
            children: file.children.compactMap { prune($0, deleting: deletedElements) }
        )
    }

    private func prune(_ node: OutlineNode, deleting deletedElements: [String: UnusedElement]) -> OutlineNode? {
        if deletedElements.values.contains(where: { matches($0, node: node) }) {
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
            children: node.children.compactMap { prune($0, deleting: deletedElements) }
        )
    }

    private func matches(_ element: UnusedElement, node: OutlineNode) -> Bool {
        guard element.file == node.file else { return false }
        guard element.name == node.name else { return false }
        guard element.line == node.line else { return false }
        return outlineKind(for: element) == node.kind
    }

    private func outlineKind(for element: UnusedElement) -> OutlineKind {
        switch element.type {
        case .class: return .class
        case .actor: return .actor
        case .struct: return .struct
        case .enum: return .enum
        case .protocol: return .protocol
        case .typeAlias: return .typeAlias
        case .function: return .function
        case .method: return .method
        case .property: return .property
        case .variable: return .variable
        case .enumCase: return .enumCase
        }
    }
}
