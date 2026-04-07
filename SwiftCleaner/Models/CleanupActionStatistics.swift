import Foundation

extension Notification.Name {
    static let cleanupStatisticsDidChange = Notification.Name("CleanupStatisticsDidChange")
}

struct CleanupActionCounts: Codable, Equatable {
    var commentedOutItems = 0
    var commentedOutLines = 0
    var markedItems = 0
    var markedLines = 0
    var deletedItems = 0
    var deletedLines = 0

    private enum CodingKeys: String, CodingKey {
        case commentedOut
        case commentedOutItems
        case commentedOutLines
        case marked
        case markedItems
        case markedLines
        case deleted
        case deletedItems
        case deletedLines
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        commentedOutItems = try container.decodeIfPresent(Int.self, forKey: .commentedOutItems)
            ?? container.decodeIfPresent(Int.self, forKey: .commentedOut)
            ?? 0
        commentedOutLines = try container.decodeIfPresent(Int.self, forKey: .commentedOutLines) ?? 0
        markedItems = try container.decodeIfPresent(Int.self, forKey: .markedItems)
            ?? container.decodeIfPresent(Int.self, forKey: .marked)
            ?? 0
        markedLines = try container.decodeIfPresent(Int.self, forKey: .markedLines) ?? 0
        deletedItems = try container.decodeIfPresent(Int.self, forKey: .deletedItems)
            ?? container.decodeIfPresent(Int.self, forKey: .deleted)
            ?? 0
        deletedLines = try container.decodeIfPresent(Int.self, forKey: .deletedLines) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(commentedOutItems, forKey: .commentedOutItems)
        try container.encode(commentedOutLines, forKey: .commentedOutLines)
        try container.encode(markedItems, forKey: .markedItems)
        try container.encode(markedLines, forKey: .markedLines)
        try container.encode(deletedItems, forKey: .deletedItems)
        try container.encode(deletedLines, forKey: .deletedLines)
    }

    mutating func record(_ action: UnusedItemAction, result: CleanupActionResult) {
        switch action {
        case .commentOut:
            commentedOutItems += result.itemCount
            commentedOutLines += result.lineCount
        case .addMarkComment:
            markedItems += result.itemCount
            markedLines += result.lineCount
        case .delete:
            deletedItems += result.itemCount
            deletedLines += result.lineCount
        }
    }
}

struct CleanupActionResult: Equatable {
    let itemCount: Int
    let lineCount: Int

    static let zero = CleanupActionResult(itemCount: 0, lineCount: 0)

    static func + (lhs: CleanupActionResult, rhs: CleanupActionResult) -> CleanupActionResult {
        CleanupActionResult(
            itemCount: lhs.itemCount + rhs.itemCount,
            lineCount: lhs.lineCount + rhs.lineCount
        )
    }
}

struct CleanupActionStatistics: Codable, Equatable {
    var totals = CleanupActionCounts()
    var projectTotals: [String: CleanupActionCounts] = [:]
    var lastUpdated: Date?

    mutating func record(
        _ action: UnusedItemAction,
        result: CleanupActionResult,
        projectURL: URL?
    ) {
        guard result.itemCount > 0 || result.lineCount > 0 else { return }

        totals.record(action, result: result)
        lastUpdated = Date()

        guard let projectPath = projectURL?.standardizedFileURL.path else { return }
        var projectCounts = projectTotals[projectPath, default: CleanupActionCounts()]
        projectCounts.record(action, result: result)
        projectTotals[projectPath] = projectCounts
    }
}

struct CleanupActionStatisticsStore {
    private let defaults: UserDefaults
    private let storageKey = "cleanupActionStatistics"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        encoder.outputFormatting = [.sortedKeys]
    }

    func load() -> CleanupActionStatistics {
        guard let data = defaults.data(forKey: storageKey) else {
            return CleanupActionStatistics()
        }

        return (try? decoder.decode(CleanupActionStatistics.self, from: data))
            ?? CleanupActionStatistics()
    }

    @discardableResult
    func record(
        _ action: UnusedItemAction,
        result: CleanupActionResult,
        projectURL: URL?
    ) -> CleanupActionStatistics {
        var statistics = load()
        statistics.record(action, result: result, projectURL: projectURL)
        save(statistics)
        return statistics
    }

    func save(_ statistics: CleanupActionStatistics) {
        guard let data = try? encoder.encode(statistics) else { return }
        defaults.set(data, forKey: storageKey)
        NotificationCenter.default.post(name: .cleanupStatisticsDidChange, object: nil)
    }
}
