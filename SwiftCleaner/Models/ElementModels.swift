import Foundation

enum ElementType: String, CaseIterable, Identifiable {
    case `class` = "Class"
    case actor = "Actor"
    case `struct` = "Struct"
    case `enum` = "Enum"
    case `protocol` = "Protocol"
    case typeAlias = "Type Alias"
    case function = "Function"
    case method = "Method"
    case property = "Property"
    case variable = "Variable"
    case enumCase = "Enum Case"

    var id: String { rawValue }

    var sortRank: Int {
        switch self {
        case .class: return 0
        case .actor: return 1
        case .struct: return 2
        case .enum: return 3
        case .protocol: return 4
        case .typeAlias: return 5
        case .function: return 6
        case .method: return 7
        case .property: return 8
        case .variable: return 9
        case .enumCase: return 10
        }
    }

    var isTypeLike: Bool {
        switch self {
        case .class, .actor, .struct, .enum, .protocol, .typeAlias:
            return true
        case .function, .method, .property, .variable, .enumCase:
            return false
        }
    }
}

enum OutlineKind: String, Identifiable {
    case file = "File"
    case `class` = "Class"
    case actor = "Actor"
    case `struct` = "Struct"
    case `enum` = "Enum"
    case `protocol` = "Protocol"
    case extensionDecl = "Extension"
    case typeAlias = "Type Alias"
    case function = "Function"
    case method = "Method"
    case initializer = "Initializer"
    case property = "Property"
    case variable = "Variable"
    case parameter = "Parameter"
    case enumCase = "Enum Case"

    var id: String { rawValue }
}

struct OutlineNode: Identifiable, Hashable {
    let id: String
    let name: String
    let kind: OutlineKind
    let file: URL
    let line: Int
    let column: Int
    let detail: String?
    let children: [OutlineNode]
}

struct OutlineFile: Identifiable, Hashable {
    let id: String
    let url: URL
    let children: [OutlineNode]
}

struct ElementDeclaration: Identifiable, Hashable {
    let id: String
    let name: String
    let qualifiedName: String
    let type: ElementType
    let file: URL
    let line: Int
    let column: Int
    let endLine: Int
    let endColumn: Int
    let containingType: String?
    let accessLevel: String?
    let modifiers: [String]
    let isStatic: Bool
    let isOverride: Bool
    let attributes: [String]
    let inheritedTypeNames: [String]
    let declaredTypeName: String?
    let isFromExtension: Bool
}

struct UnusedElement: Identifiable, Hashable {
    let id: String
    let name: String
    let qualifiedName: String
    let type: ElementType
    let file: URL
    let line: Int
    let column: Int
    let endLine: Int
    let endColumn: Int
    let containingType: String?
    let accessLevel: String?
    let note: String?

    init(from usage: ElementUsage) {
        self.id = usage.id
        self.name = usage.name
        self.qualifiedName = usage.qualifiedName
        self.type = usage.type
        self.file = usage.file
        self.line = usage.line
        self.column = usage.column
        self.endLine = usage.endLine
        self.endColumn = usage.endColumn
        self.containingType = usage.containingType
        self.accessLevel = usage.accessLevel
        self.note = usage.note
    }
}

struct LikelyUnusedFile: Identifiable, Hashable {
    let id: String
    let file: URL
    let line: Int
    let primaryDeclarations: [String]
    let reason: String
}

struct DiskOnlySwiftFile: Identifiable, Hashable {
    let id: String
    let file: URL
    let reason: String
}

struct ElementUsage: Identifiable, Hashable {
    let id: String
    let name: String
    let qualifiedName: String
    let type: ElementType
    let file: URL
    let line: Int
    let column: Int
    let endLine: Int
    let endColumn: Int
    let containingType: String?
    let accessLevel: String?
    let usageCount: Int
    let usageReferences: [UsageReference]
    let isUnused: Bool
    let note: String?

    init(
        from declaration: ElementDeclaration,
        usageCount: Int,
        usageReferences: [UsageReference] = [],
        isUnused: Bool,
        note: String? = nil
    ) {
        self.id = declaration.id
        self.name = declaration.name
        self.qualifiedName = declaration.qualifiedName
        self.type = declaration.type
        self.file = declaration.file
        self.line = declaration.line
        self.column = declaration.column
        self.endLine = declaration.endLine
        self.endColumn = declaration.endColumn
        self.containingType = declaration.containingType
        self.accessLevel = declaration.accessLevel
        self.usageCount = usageCount
        self.usageReferences = usageReferences
        self.isUnused = isUnused
        self.note = note
    }
}

struct UsageReference: Identifiable, Hashable {
    let file: URL
    let line: Int
    let column: Int

    var id: String {
        "\(file.standardizedFileURL.path)#\(line)#\(column)"
    }
}

struct AnalysisSummary: Equatable {
    let fileCount: Int
    let declarationCount: Int
    let trackedDeclarationCount: Int
    let referenceCount: Int
    let unusedCount: Int
    let unusedFileCount: Int
    let diskOnlySwiftFileCount: Int

    static let empty = AnalysisSummary(
        fileCount: 0,
        declarationCount: 0,
        trackedDeclarationCount: 0,
        referenceCount: 0,
        unusedCount: 0,
        unusedFileCount: 0,
        diskOnlySwiftFileCount: 0
    )
}

struct AnalysisOptions: Equatable {
    var includePublicDeclarations = false
}

enum UnusedItemAction: String, CaseIterable, Identifiable {
    case ignore = "Ignore"
    case commentOut = "Comment Out"
    case addMarkComment = "Add // MARK: Comment"
    case delete = "Delete"

    var id: String { rawValue }

    var isDestructive: Bool {
        self == .delete
    }

    var shortTitle: String {
        switch self {
        case .ignore: return "Ignore"
        case .commentOut: return "Comment Out"
        case .addMarkComment: return "Add MARK"
        case .delete: return "Delete"
        }
    }

    var systemImage: String {
        switch self {
        case .ignore: return "eye.slash"
        case .commentOut: return "text.badge.minus"
        case .addMarkComment: return "text.insert"
        case .delete: return "trash"
        }
    }

    func confirmationTitle(count: Int) -> String {
        "\(shortTitle) \(count) unused item\(count == 1 ? "" : "s")?"
    }

    func confirmationMessage(count: Int) -> String {
        switch self {
        case .ignore:
            return "This will hide the selected declarations from the unused list for this project without changing source files."
        case .commentOut:
            return "This will comment out the selected declarations in their source files."
        case .addMarkComment:
            return "This will insert a // MARK: comment above each selected declaration."
        case .delete:
            return "This will remove the selected declarations from their source files."
        }
    }
}

struct AnalysisReport {
    let unusedElements: [UnusedElement]
    let likelyUnusedFiles: [LikelyUnusedFile]
    let diskOnlySwiftFiles: [DiskOnlySwiftFile]
    let elementUsages: [ElementUsage]
    let outlineFiles: [OutlineFile]
    let summary: AnalysisSummary
}
