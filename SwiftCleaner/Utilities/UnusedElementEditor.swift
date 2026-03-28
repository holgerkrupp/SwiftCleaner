import Foundation

enum UnusedElementEditorError: LocalizedError {
    case invalidLineRange(file: URL, startLine: Int, endLine: Int)

    var errorDescription: String? {
        switch self {
        case let .invalidLineRange(file, startLine, endLine):
            return "Unable to edit \(file.lastPathComponent) because the declaration range \(startLine)-\(endLine) is invalid."
        }
    }
}

private struct PlannedUnusedEdit {
    let file: URL
    let elements: [UnusedElement]
    let startLine: Int
    let endLine: Int

    var primaryElement: UnusedElement {
        elements[0]
    }
}

struct UnusedElementEditor {
    func apply(_ action: UnusedItemAction, to elements: [UnusedElement]) throws {
        let elementsByFile = Dictionary(grouping: elements, by: \.file)
        for fileURL in elementsByFile.keys.sorted(by: { $0.path < $1.path }) {
            guard let fileElements = elementsByFile[fileURL] else { continue }
            try apply(action, to: fileElements, in: fileURL)
        }
    }

    private func apply(_ action: UnusedItemAction, to elements: [UnusedElement], in fileURL: URL) throws {
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        var lines = splitLines(in: source)
        let edits = plannedEdits(from: elements)
        guard !edits.isEmpty else { return }

        switch action {
        case .commentOut:
            try commentOut(edits, in: &lines)
        case .addMarkComment:
            try addMarkComments(for: edits, in: &lines)
        case .delete:
            try delete(edits, from: &lines)
        }

        let updatedSource = lines.joined(separator: "\n")
        if updatedSource != source {
            try updatedSource.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    private func plannedEdits(from elements: [UnusedElement]) -> [PlannedUnusedEdit] {
        let sortedElements = elements.sorted { lhs, rhs in
            let lhsStart = min(lhs.line, lhs.endLine)
            let rhsStart = min(rhs.line, rhs.endLine)
            if lhsStart != rhsStart {
                return lhsStart < rhsStart
            }

            let lhsEnd = max(lhs.line, lhs.endLine)
            let rhsEnd = max(rhs.line, rhs.endLine)
            if lhsEnd != rhsEnd {
                return lhsEnd > rhsEnd
            }

            return lhs.qualifiedName < rhs.qualifiedName
        }

        var edits: [PlannedUnusedEdit] = []

        for element in sortedElements {
            let startLine = min(element.line, element.endLine)
            let endLine = max(element.line, element.endLine)
            guard startLine > 0, endLine >= startLine else { continue }

            if let lastEdit = edits.last, startLine <= lastEdit.endLine {
                edits[edits.count - 1] = PlannedUnusedEdit(
                    file: lastEdit.file,
                    elements: lastEdit.elements + [element],
                    startLine: lastEdit.startLine,
                    endLine: max(lastEdit.endLine, endLine)
                )
            } else {
                edits.append(PlannedUnusedEdit(
                    file: element.file,
                    elements: [element],
                    startLine: startLine,
                    endLine: endLine
                ))
            }
        }

        return edits
    }

    private func commentOut(_ edits: [PlannedUnusedEdit], in lines: inout [String]) throws {
        for edit in edits {
            let lineRange = try zeroBasedLineRange(for: edit, in: lines)
            for index in lineRange {
                lines[index] = commentPrefixing(lines[index])
            }
        }
    }

    private func addMarkComments(for edits: [PlannedUnusedEdit], in lines: inout [String]) throws {
        for edit in edits.reversed() {
            let insertionLine = edit.startLine - 1
            guard insertionLine >= 0, insertionLine <= lines.count else {
                throw UnusedElementEditorError.invalidLineRange(
                    file: edit.file,
                    startLine: edit.startLine,
                    endLine: edit.endLine
                )
            }

            let indentation = insertionLine < lines.count ? leadingWhitespace(in: lines[insertionLine]) : ""
            let markLine = "\(indentation)// MARK: Unused \(edit.primaryElement.type.rawValue) \(edit.primaryElement.name)"

            if insertionLine > 0 {
                let previousLine = lines[insertionLine - 1].trimmingCharacters(in: .whitespaces)
                if previousLine == markLine.trimmingCharacters(in: .whitespaces) {
                    continue
                }
            }

            lines.insert(markLine, at: insertionLine)
        }
    }

    private func delete(_ edits: [PlannedUnusedEdit], from lines: inout [String]) throws {
        for edit in edits.reversed() {
            let lineRange = try zeroBasedLineRange(for: edit, in: lines)
            lines.removeSubrange(lineRange)
        }
    }

    private func zeroBasedLineRange(
        for edit: PlannedUnusedEdit,
        in lines: [String]
    ) throws -> ClosedRange<Int> {
        let lowerBound = edit.startLine - 1
        let upperBound = edit.endLine - 1

        guard lowerBound >= 0, upperBound >= lowerBound, upperBound < lines.count else {
            throw UnusedElementEditorError.invalidLineRange(
                file: edit.file,
                startLine: edit.startLine,
                endLine: edit.endLine
            )
        }

        return lowerBound...upperBound
    }

    private func splitLines(in source: String) -> [String] {
        guard !source.isEmpty else { return [] }
        return source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private func commentPrefixing(_ line: String) -> String {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else {
            return line
        }

        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("//") else {
            return line
        }

        let indentation = leadingWhitespace(in: line)
        let content = line.dropFirst(indentation.count)
        return "\(indentation)// \(content)"
    }

    private func leadingWhitespace(in line: String) -> String {
        String(line.prefix { $0 == " " || $0 == "\t" })
    }
}
