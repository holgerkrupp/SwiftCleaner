import AppKit
import Foundation

enum ProjectAccessMode {
    case readOnly
    case readWrite
}

@MainActor
final class ProjectAnalyzer: ObservableObject {
    @Published var projectPath: URL?
    @Published var isAnalyzing = false
    @Published private(set) var projectAccessMode: ProjectAccessMode = .readOnly
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
    private let ignoredUnusedElementsStore: IgnoredUnusedElementsStore
    private var ignoredUnusedElementIDsByProjectPath: [String: Set<String>]

    init(
        cleanupStatisticsStore: CleanupActionStatisticsStore = CleanupActionStatisticsStore(),
        ignoredUnusedElementsStore: IgnoredUnusedElementsStore = IgnoredUnusedElementsStore()
    ) {
        self.cleanupStatisticsStore = cleanupStatisticsStore
        self.ignoredUnusedElementsStore = ignoredUnusedElementsStore
        self.cleanupStatistics = cleanupStatisticsStore.load()
        self.ignoredUnusedElementIDsByProjectPath = ignoredUnusedElementsStore.load()
    }

    func setProjectPath(_ url: URL) {
        projectPath = url
        errorMessage = nil

        if let writeAccessRootURL, !project(url, isInsideGrantedFolder: writeAccessRootURL) {
            self.writeAccessRootURL = nil
        }
        refreshProjectAccessMode()
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

            let ignoredIDs = ignoredDeclarationIDs(for: url)
            let visibleUnusedElements = report.unusedElements.filter { !ignoredIDs.contains($0.id) }

            unusedElements = visibleUnusedElements
            likelyUnusedFiles = report.likelyUnusedFiles
            diskOnlySwiftFiles = report.diskOnlySwiftFiles
            elementUsages = report.elementUsages
            outlineFiles = report.outlineFiles
            summary = AnalysisSummary(
                fileCount: report.summary.fileCount,
                declarationCount: report.summary.declarationCount,
                trackedDeclarationCount: report.summary.trackedDeclarationCount,
                referenceCount: report.summary.referenceCount,
                unusedCount: visibleUnusedElements.count,
                unusedFileCount: report.summary.unusedFileCount,
                diskOnlySwiftFileCount: report.summary.diskOnlySwiftFileCount
            )
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

        if action == .ignore {
            ignore(elements, for: projectPath)
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

    func deleteUnusedFile(_ fileURL: URL, removeFromProject: Bool) async {
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

        do {
            try FileManager.default.removeItem(at: fileURL)
            if removeFromProject {
                _ = try XcodeProjectEditor().removeFileReferences(
                    to: fileURL,
                    inProjectRoot: projectPath
                )
            }

            likelyUnusedFiles.removeAll { $0.file.standardizedFileURL == fileURL.standardizedFileURL }
            diskOnlySwiftFiles.removeAll { $0.file.standardizedFileURL == fileURL.standardizedFileURL }
            outlineFiles.removeAll { $0.url.standardizedFileURL == fileURL.standardizedFileURL }
            unusedElements.removeAll { $0.file.standardizedFileURL == fileURL.standardizedFileURL }
            elementUsages.removeAll { $0.file.standardizedFileURL == fileURL.standardizedFileURL }

            summary = AnalysisSummary(
                fileCount: summary.fileCount,
                declarationCount: summary.declarationCount,
                trackedDeclarationCount: elementUsages.count,
                referenceCount: summary.referenceCount,
                unusedCount: unusedElements.count,
                unusedFileCount: likelyUnusedFiles.count,
                diskOnlySwiftFileCount: diskOnlySwiftFiles.count
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isApplyingEdit = false
    }

    func clearIgnoredUnusedDeclarationsForCurrentProject() {
        guard let projectPath else { return }
        ignoredUnusedElementIDsByProjectPath.removeValue(forKey: projectPath.standardizedFileURL.path)
        ignoredUnusedElementsStore.save(ignoredUnusedElementIDsByProjectPath)
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
        refreshProjectAccessMode()
        return selectedURL
    }

    private func project(_ projectURL: URL, isInsideGrantedFolder grantedFolderURL: URL) -> Bool {
        let projectPath = projectURL.standardizedFileURL.path
        let grantedPath = grantedFolderURL.standardizedFileURL.path

        return projectPath == grantedPath || projectPath.hasPrefix(grantedPath + "/")
    }

    private func refreshProjectAccessMode() {
        guard let projectPath, let writeAccessRootURL else {
            projectAccessMode = .readOnly
            return
        }

        projectAccessMode = project(projectPath, isInsideGrantedFolder: writeAccessRootURL) ? .readWrite : .readOnly
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

    private func ignoredDeclarationIDs(for projectURL: URL) -> Set<String> {
        ignoredUnusedElementIDsByProjectPath[projectURL.standardizedFileURL.path, default: []]
    }

    private func ignore(_ elements: [UnusedElement], for projectURL: URL) {
        let ignoredIDs = Set(elements.map(\.id))
        guard !ignoredIDs.isEmpty else { return }

        let projectPath = projectURL.standardizedFileURL.path
        ignoredUnusedElementIDsByProjectPath[projectPath, default: []].formUnion(ignoredIDs)
        ignoredUnusedElementsStore.save(ignoredUnusedElementIDsByProjectPath)

        unusedElements.removeAll { ignoredIDs.contains($0.id) }
        summary = AnalysisSummary(
            fileCount: summary.fileCount,
            declarationCount: summary.declarationCount,
            trackedDeclarationCount: summary.trackedDeclarationCount,
            referenceCount: summary.referenceCount,
            unusedCount: unusedElements.count,
            unusedFileCount: summary.unusedFileCount,
            diskOnlySwiftFileCount: summary.diskOnlySwiftFileCount
        )
    }
}
