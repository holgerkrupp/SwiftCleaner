import Foundation
import SwiftParser

enum ProjectAnalysisError: LocalizedError {
    case noSwiftFilesFound

    var errorDescription: String? {
        switch self {
        case .noSwiftFilesFound:
            return "No Swift files were found in the selected folder."
        }
    }
}

private enum UsageDisposition {
    case analyzed
    case implicitlyUsed(String)
    case excludedFromUnused(String)
}

private struct AnalysisIndexes {
    let declarationsByID: [String: ElementDeclaration]
    let declarationsByQualifiedName: [String: ElementDeclaration]
    let typeDeclarationsByName: [String: [ElementDeclaration]]
    let hostTypesByName: [String: Set<String>]
    let membersByType: [String: [String: [ElementDeclaration]]]
    let globalsByName: [String: [ElementDeclaration]]
    let inheritedHostsByType: [String: Set<String>]
    let projectProtocolRequirementsByName: [String: Set<String>]
    let extensionInheritedTypeNames: [String: Set<String>]
}

private struct ProjectFileCatalog {
    var usesProjectMetadata = false
    var swiftFiles = Set<URL>()
    var interfaceBuilderFiles = Set<URL>()
}

private struct LocatedReference {
    let reference: CollectedReference
    let file: URL
}

private struct UsageResolution {
    let usageCounts: [String: Int]
    let usageReferencesByDeclarationID: [String: [UsageReference]]
}

struct ProjectAnalysisEngine {
    private static let interfaceBuilderCustomClassPattern = try! NSRegularExpression(
        pattern: #"customClass="([A-Za-z_][A-Za-z0-9_]*)""#
    )

    private let skippedDirectories: Set<String> = [
        ".build", ".git", ".swiftpm", "Build", "Carthage", "DerivedData",
        "Pods", "SourcePackages", "build"
    ]

    private let dynamicRuntimeAttributes: Set<String> = [
        "IBAction", "IBOutlet", "NSManaged", "objc"
    ]

    private let knownProtocolRequirements: [String: Set<String>] = [
        "App": ["body"],
        "Animatable": ["animatableData"],
        "AppIntentTimelineProvider": ["placeholder", "snapshot", "timeline"],
        "ButtonStyle": ["makeBody"],
        "Commands": ["body"],
        "Decodable": ["init"],
        "DynamicProperty": ["update"],
        "Encodable": ["encode"],
        "GaugeStyle": ["makeBody"],
        "Hashable": ["hash"],
        "IntentTimelineProvider": ["placeholder", "getSnapshot", "getTimeline"],
        "LabelStyle": ["makeBody"],
        "Layout": ["placeSubviews", "sizeThatFits"],
        "MenuStyle": ["makeBody"],
        "NSViewControllerRepresentable": ["makeNSViewController", "updateNSViewController"],
        "NSViewRepresentable": ["makeNSView", "updateNSView"],
        "PickerStyle": ["makeBody"],
        "PreviewProvider": ["previews"],
        "PrimitiveButtonStyle": ["makeBody"],
        "ProgressViewStyle": ["makeBody"],
        "Scene": ["body"],
        "Shape": ["path"],
        "TabViewStyle": ["makeBody"],
        "TimelineProvider": ["placeholder", "getSnapshot", "getTimeline"],
        "ToggleStyle": ["makeBody"],
        "UIViewControllerRepresentable": ["makeUIViewController", "updateUIViewController"],
        "UIViewRepresentable": ["makeUIView", "updateUIView"],
        "View": ["body"],
        "Widget": ["body"],
        "XCTestCase": ["setUp", "setUpWithError", "tearDown", "tearDownWithError"]
    ]

    func analyze(at rootURL: URL, options: AnalysisOptions) throws -> AnalysisReport {
        let folderSwiftFiles = try findSwiftFiles(in: rootURL)
        let projectFileCatalog = try findProjectFileCatalog(in: rootURL)
        let swiftFiles = projectFileCatalog.usesProjectMetadata
            ? projectFileCatalog.swiftFiles.sorted { $0.path < $1.path }
            : folderSwiftFiles
        guard !swiftFiles.isEmpty else {
            throw ProjectAnalysisError.noSwiftFilesFound
        }

        let interfaceBuilderFiles = projectFileCatalog.usesProjectMetadata
            ? projectFileCatalog.interfaceBuilderFiles.sorted { $0.path < $1.path }
            : try findFiles(in: rootURL, pathExtensions: ["storyboard", "xib"])
        let diskOnlySwiftFiles = projectFileCatalog.usesProjectMetadata
            ? buildDiskOnlySwiftFiles(
                allSwiftFiles: folderSwiftFiles,
                projectSwiftFiles: projectFileCatalog.swiftFiles
            )
            : []

        var declarations: [ElementDeclaration] = []
        var references: [LocatedReference] = []
        var outlineFiles: [OutlineFile] = []
        var projectProtocolRequirements: [String: Set<String>] = [:]
        var extensionInheritedTypeNames: [String: Set<String>] = [:]

        for fileURL in swiftFiles {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let syntax = Parser.parse(source: source)
            let visitor = SourceVisitor(url: fileURL, source: source)
            visitor.walk(syntax)

            declarations.append(contentsOf: visitor.declarations)
            references.append(contentsOf: visitor.references.map {
                LocatedReference(reference: $0, file: fileURL)
            })
            outlineFiles.append(visitor.outlineFile)

            for (protocolName, requirementNames) in visitor.protocolRequirements {
                projectProtocolRequirements[protocolName, default: []].formUnion(requirementNames)
                projectProtocolRequirements[lastIdentifier(in: protocolName), default: []].formUnion(requirementNames)
            }

            for (typeName, inheritedNames) in visitor.extensionInheritedTypeNames {
                extensionInheritedTypeNames[typeName, default: []].formUnion(inheritedNames)
            }
        }

        references.append(contentsOf: try interfaceBuilderReferences(in: interfaceBuilderFiles))

        let indexes = buildIndexes(
            declarations: declarations,
            projectProtocolRequirements: projectProtocolRequirements,
            extensionInheritedTypeNames: extensionInheritedTypeNames
        )

        let usageResolution = resolveUsageData(for: references, indexes: indexes)
        let usages = buildUsageRows(
            declarations: declarations,
            usageCounts: usageResolution.usageCounts,
            usageReferencesByDeclarationID: usageResolution.usageReferencesByDeclarationID,
            indexes: indexes,
            options: options
        )

        let unusedElements = usages
            .filter(\.isUnused)
            .map(UnusedElement.init)
        let likelyUnusedFiles = buildLikelyUnusedFiles(
            allSwiftFiles: swiftFiles,
            declarations: declarations,
            usages: usages,
            indexes: indexes
        )

        let sortedUsages = usages.sorted(by: usageSort)
        let sortedUnused = unusedElements.sorted(by: unusedSort)
        let sortedUnusedFiles = likelyUnusedFiles.sorted(by: unusedFileSort)
        let sortedDiskOnlySwiftFiles = diskOnlySwiftFiles.sorted(by: diskOnlyFileSort)

        return AnalysisReport(
            unusedElements: sortedUnused,
            likelyUnusedFiles: sortedUnusedFiles,
            diskOnlySwiftFiles: sortedDiskOnlySwiftFiles,
            elementUsages: sortedUsages,
            outlineFiles: outlineFiles.sorted { $0.url.path < $1.url.path },
            summary: AnalysisSummary(
                fileCount: swiftFiles.count,
                declarationCount: declarations.count,
                trackedDeclarationCount: usages.count,
                referenceCount: references.count,
                unusedCount: sortedUnused.count,
                unusedFileCount: sortedUnusedFiles.count,
                diskOnlySwiftFileCount: sortedDiskOnlySwiftFiles.count
            )
        )
    }

    private func findProjectFileCatalog(in rootURL: URL) throws -> ProjectFileCatalog {
        let xcodeProjectURLs = try findXcodeProjects(in: rootURL)
        guard !xcodeProjectURLs.isEmpty else {
            return ProjectFileCatalog()
        }

        var catalog = ProjectFileCatalog(usesProjectMetadata: true)

        for xcodeProjectURL in xcodeProjectURLs {
            let projectCatalog = try projectFileCatalog(
                from: xcodeProjectURL,
                limitedTo: rootURL
            )
            catalog.swiftFiles.formUnion(projectCatalog.swiftFiles)
            catalog.interfaceBuilderFiles.formUnion(projectCatalog.interfaceBuilderFiles)
        }

        return catalog
    }

    private func findXcodeProjects(in rootURL: URL) throws -> [URL] {
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var projectURLs: [URL] = []

        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: resourceKeys)
            guard values.isDirectory == true else { continue }

            if skippedDirectories.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }

            if url.pathExtension == "xcodeproj" {
                projectURLs.append(url)
                enumerator.skipDescendants()
            }
        }

        return projectURLs.sorted { $0.path < $1.path }
    }

    private func projectFileCatalog(
        from xcodeProjectURL: URL,
        limitedTo rootURL: URL
    ) throws -> ProjectFileCatalog {
        let projectFileURL = xcodeProjectURL.appendingPathComponent("project.pbxproj")
        let data = try Data(contentsOf: projectFileURL)
        var format = PropertyListSerialization.PropertyListFormat.openStep
        let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: &format
        )

        guard
            let projectDictionary = propertyList as? [String: Any],
            let objects = projectDictionary["objects"] as? [String: Any],
            let rootObjectID = projectDictionary["rootObject"] as? String,
            let rootObject = objects[rootObjectID] as? [String: Any]
        else {
            return ProjectFileCatalog(usesProjectMetadata: true)
        }

        let projectBaseURL = xcodeProjectURL.deletingLastPathComponent()
        var catalog = ProjectFileCatalog(usesProjectMetadata: true)
        var visitedObjectIDs = Set<String>()

        var rootGroupIDs: [String] = []
        if let mainGroupID = rootObject["mainGroup"] as? String {
            rootGroupIDs.append(mainGroupID)
        }

        for targetID in rootObject["targets"] as? [String] ?? [] {
            guard let target = objects[targetID] as? [String: Any] else { continue }
            rootGroupIDs.append(contentsOf: target["fileSystemSynchronizedGroups"] as? [String] ?? [])
        }

        for groupID in rootGroupIDs {
            try collectProjectFiles(
                from: groupID,
                parentURL: projectBaseURL,
                projectBaseURL: projectBaseURL,
                limitedTo: rootURL,
                objects: objects,
                catalog: &catalog,
                visitedObjectIDs: &visitedObjectIDs
            )
        }

        return catalog
    }

    private func collectProjectFiles(
        from objectID: String,
        parentURL: URL,
        projectBaseURL: URL,
        limitedTo rootURL: URL,
        objects: [String: Any],
        catalog: inout ProjectFileCatalog,
        visitedObjectIDs: inout Set<String>
    ) throws {
        guard visitedObjectIDs.insert(objectID).inserted else { return }
        guard let object = objects[objectID] as? [String: Any] else { return }

        switch object["isa"] as? String {
        case "PBXGroup":
            let groupURL = resolveContainerURL(
                for: object,
                parentURL: parentURL,
                projectBaseURL: projectBaseURL
            )

            for childID in object["children"] as? [String] ?? [] {
                try collectProjectFiles(
                    from: childID,
                    parentURL: groupURL,
                    projectBaseURL: projectBaseURL,
                    limitedTo: rootURL,
                    objects: objects,
                    catalog: &catalog,
                    visitedObjectIDs: &visitedObjectIDs
                )
            }

        case "PBXVariantGroup":
            if let variantURL = resolveFileURL(
                for: object,
                parentURL: parentURL,
                projectBaseURL: projectBaseURL
            ) {
                addProjectFile(at: variantURL, limitedTo: rootURL, catalog: &catalog)
            }

            for childID in object["children"] as? [String] ?? [] {
                try collectProjectFiles(
                    from: childID,
                    parentURL: parentURL,
                    projectBaseURL: projectBaseURL,
                    limitedTo: rootURL,
                    objects: objects,
                    catalog: &catalog,
                    visitedObjectIDs: &visitedObjectIDs
                )
            }

        case "PBXFileSystemSynchronizedRootGroup":
            let groupURL = resolveContainerURL(
                for: object,
                parentURL: parentURL,
                projectBaseURL: projectBaseURL
            )
            let synchronizedFiles = try findFiles(
                in: groupURL,
                pathExtensions: ["swift", "storyboard", "xib"]
            )

            for fileURL in synchronizedFiles {
                addProjectFile(at: fileURL, limitedTo: rootURL, catalog: &catalog)
            }

        case "PBXFileReference":
            if let fileURL = resolveFileURL(
                for: object,
                parentURL: parentURL,
                projectBaseURL: projectBaseURL
            ) {
                addProjectFile(at: fileURL, limitedTo: rootURL, catalog: &catalog)
            }

        default:
            return
        }
    }

    private func resolveContainerURL(
        for object: [String: Any],
        parentURL: URL,
        projectBaseURL: URL
    ) -> URL {
        let sourceTree = object["sourceTree"] as? String ?? "<group>"
        let rawPath = normalizedPathComponent(object["path"] as? String)

        return resolveURL(
            sourceTree: sourceTree,
            rawPath: rawPath,
            parentURL: parentURL,
            projectBaseURL: projectBaseURL
        ) ?? parentURL
    }

    private func resolveFileURL(
        for object: [String: Any],
        parentURL: URL,
        projectBaseURL: URL
    ) -> URL? {
        let sourceTree = object["sourceTree"] as? String ?? "<group>"
        let rawPath = normalizedPathComponent(object["path"] as? String)
            ?? normalizedPathComponent(object["name"] as? String)

        return resolveURL(
            sourceTree: sourceTree,
            rawPath: rawPath,
            parentURL: parentURL,
            projectBaseURL: projectBaseURL
        )
    }

    private func resolveURL(
        sourceTree: String,
        rawPath: String?,
        parentURL: URL,
        projectBaseURL: URL
    ) -> URL? {
        if let rawPath {
            if rawPath.hasPrefix("$(SRCROOT)/") {
                let relativePath = String(rawPath.dropFirst("$(SRCROOT)/".count))
                return projectBaseURL.appendingPathComponent(relativePath).standardizedFileURL
            }

            if rawPath.hasPrefix("${SRCROOT}/") {
                let relativePath = String(rawPath.dropFirst("${SRCROOT}/".count))
                return projectBaseURL.appendingPathComponent(relativePath).standardizedFileURL
            }

            if rawPath.hasPrefix("/") {
                return URL(fileURLWithPath: rawPath).standardizedFileURL
            }
        }

        switch sourceTree {
        case "<group>":
            guard let rawPath else { return parentURL.standardizedFileURL }
            return parentURL.appendingPathComponent(rawPath).standardizedFileURL

        case "SOURCE_ROOT", "<sourceRoot>":
            guard let rawPath else { return projectBaseURL.standardizedFileURL }
            return projectBaseURL.appendingPathComponent(rawPath).standardizedFileURL

        case "<absolute>":
            guard let rawPath else { return nil }
            return URL(fileURLWithPath: rawPath).standardizedFileURL

        default:
            return nil
        }
    }

    private func addProjectFile(
        at fileURL: URL,
        limitedTo rootURL: URL,
        catalog: inout ProjectFileCatalog
    ) {
        let standardizedFileURL = fileURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardizedFileURL.path) else { return }
        guard isInside(rootURL, fileURL: standardizedFileURL) else { return }

        let pathExtension = standardizedFileURL.pathExtension.lowercased()
        switch pathExtension {
        case "swift":
            catalog.swiftFiles.insert(standardizedFileURL)
        case "storyboard", "xib":
            catalog.interfaceBuilderFiles.insert(standardizedFileURL)
        default:
            break
        }
    }

    private func isInside(_ rootURL: URL, fileURL: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        return filePath == rootPath || filePath.hasPrefix(rootPath + "/")
    }

    private func normalizedPathComponent(_ rawPath: String?) -> String? {
        guard let rawPath else { return nil }
        let trimmedPath = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPath.isEmpty ? nil : trimmedPath
    }

    private func findSwiftFiles(in rootURL: URL) throws -> [URL] {
        try findFiles(in: rootURL, pathExtensions: ["swift"])
    }

    private func findFiles(
        in rootURL: URL,
        pathExtensions: Set<String>
    ) throws -> [URL] {
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []

        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: resourceKeys)

            if values.isDirectory == true {
                if skippedDirectories.contains(url.lastPathComponent) || values.isPackage == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            if pathExtensions.contains(url.pathExtension) {
                files.append(url)
            }
        }

        return files.sorted { $0.path < $1.path }
    }

    private func buildIndexes(
        declarations: [ElementDeclaration],
        projectProtocolRequirements: [String: Set<String>],
        extensionInheritedTypeNames: [String: Set<String>]
    ) -> AnalysisIndexes {
        var declarationsByID: [String: ElementDeclaration] = [:]
        var declarationsByQualifiedName: [String: ElementDeclaration] = [:]
        var typeDeclarationsByName: [String: [ElementDeclaration]] = [:]
        var hostTypesByName: [String: Set<String>] = [:]
        var membersByType: [String: [String: [ElementDeclaration]]] = [:]
        var globalsByName: [String: [ElementDeclaration]] = [:]
        var inheritedHostsByType: [String: Set<String>] = extensionInheritedTypeNames

        for declaration in declarations {
            declarationsByID[declaration.id] = declaration
            declarationsByQualifiedName[declaration.qualifiedName] = declaration

            if declaration.type.isTypeLike {
                typeDeclarationsByName[declaration.name, default: []].append(declaration)
                typeDeclarationsByName[declaration.qualifiedName, default: []].append(declaration)
                hostTypesByName[declaration.name, default: []].insert(declaration.qualifiedName)
                hostTypesByName[declaration.qualifiedName, default: []].insert(declaration.qualifiedName)
            }

            if let containingType = declaration.containingType {
                membersByType[containingType, default: [:]][declaration.name, default: []].append(declaration)
                hostTypesByName[lastIdentifier(in: containingType), default: []].insert(containingType)
                hostTypesByName[containingType, default: []].insert(containingType)
            } else if !declaration.type.isTypeLike {
                globalsByName[declaration.name, default: []].append(declaration)
            }

            if declaration.type.isTypeLike, !declaration.inheritedTypeNames.isEmpty {
                inheritedHostsByType[declaration.qualifiedName, default: []].formUnion(declaration.inheritedTypeNames)
            }
        }

        return AnalysisIndexes(
            declarationsByID: declarationsByID,
            declarationsByQualifiedName: declarationsByQualifiedName,
            typeDeclarationsByName: typeDeclarationsByName,
            hostTypesByName: hostTypesByName,
            membersByType: membersByType,
            globalsByName: globalsByName,
            inheritedHostsByType: inheritedHostsByType,
            projectProtocolRequirementsByName: projectProtocolRequirements,
            extensionInheritedTypeNames: extensionInheritedTypeNames
        )
    }

    private func resolveUsageData(
        for references: [LocatedReference],
        indexes: AnalysisIndexes
    ) -> UsageResolution {
        var usageCounts: [String: Int] = [:]
        var usageReferencesByDeclarationID: [String: [UsageReference]] = [:]

        for locatedReference in references {
            let matchedIDs = matchReference(locatedReference.reference, indexes: indexes)
            for matchedID in matchedIDs {
                usageCounts[matchedID, default: 0] += 1
                usageReferencesByDeclarationID[matchedID, default: []].append(
                    UsageReference(
                        file: locatedReference.file,
                        line: locatedReference.reference.line,
                        column: locatedReference.reference.column
                    )
                )
            }
        }

        let sortedReferencesByDeclarationID = usageReferencesByDeclarationID.mapValues { references in
            references
                .sorted {
                    if $0.file.path != $1.file.path { return $0.file.path < $1.file.path }
                    if $0.line != $1.line { return $0.line < $1.line }
                    return $0.column < $1.column
                }
        }

        return UsageResolution(
            usageCounts: usageCounts,
            usageReferencesByDeclarationID: sortedReferencesByDeclarationID
        )
    }

    private func matchReference(
        _ reference: CollectedReference,
        indexes: AnalysisIndexes
    ) -> Set<String> {
        switch reference.kind {
        case .type:
            return resolveTypeReferenceIDs(named: reference.name, indexes: indexes)

        case .unqualified:
            var matches = Set(memberIDs(
                named: reference.name,
                from: reference.currentType,
                indexes: indexes
            ))

            if matches.isEmpty {
                matches.formUnion(indexes.globalsByName[reference.name, default: []].map(\.id))
            }

            if matches.isEmpty {
                matches.formUnion(resolveTypeReferenceIDs(named: reference.name, indexes: indexes))
            }

            return matches

        case .member:
            var matches = Set<String>()
            let candidateHosts = resolveBaseHosts(for: reference, indexes: indexes)

            for host in candidateHosts {
                matches.formUnion(memberIDs(named: reference.name, from: host, indexes: indexes))
            }

            if matches.isEmpty, reference.baseChain.isEmpty {
                matches.formUnion(memberIDs(named: reference.name, from: reference.currentType, indexes: indexes))
            }

            return matches
        }
    }

    private func resolveBaseHosts(
        for reference: CollectedReference,
        indexes: AnalysisIndexes
    ) -> Set<String> {
        guard !reference.baseChain.isEmpty else {
            return []
        }

        var remainingComponents = reference.baseChain
        let firstComponent = remainingComponents.removeFirst()
        var currentHosts = Set<String>()

        if firstComponent == "self" {
            if let currentType = reference.currentType {
                currentHosts.insert(currentType)
            }
        } else if firstComponent == "super" {
            if let currentType = reference.currentType {
                currentHosts.formUnion(resolveInheritedHosts(of: currentType, indexes: indexes))
            }
        } else {
            if let baseTypeHint = reference.baseTypeHint {
                currentHosts.formUnion(resolveHostTypes(named: baseTypeHint, indexes: indexes))
            } else if let currentType = reference.currentType {
                let memberTypes = declaredTypeNames(
                    forMemberNamed: firstComponent,
                    on: currentType,
                    indexes: indexes
                )
                for memberType in memberTypes {
                    currentHosts.formUnion(resolveHostTypes(named: memberType, indexes: indexes))
                }
            }

            if currentHosts.isEmpty {
                currentHosts.formUnion(resolveHostTypes(named: firstComponent, indexes: indexes))
            }
        }

        for component in remainingComponents {
            if currentHosts.isEmpty {
                return []
            }

            currentHosts = advanceHosts(
                from: currentHosts,
                using: component,
                indexes: indexes
            )
        }

        return currentHosts
    }

    private func advanceHosts(
        from hostTypes: Set<String>,
        using component: String,
        indexes: AnalysisIndexes
    ) -> Set<String> {
        var nextHosts = Set<String>()

        for host in hostTypes {
            let memberDeclarations = indexes.membersByType[host]?[component, default: []] ?? []

            for declaration in memberDeclarations {
                if declaration.type.isTypeLike {
                    nextHosts.insert(declaration.qualifiedName)
                }

                if let declaredTypeName = declaration.declaredTypeName {
                    nextHosts.formUnion(resolveHostTypes(named: declaredTypeName, indexes: indexes))
                }
            }
        }

        return nextHosts
    }

    private func memberIDs(
        named name: String,
        from hostType: String?,
        indexes: AnalysisIndexes
    ) -> [String] {
        guard let hostType else { return [] }

        var results: [String] = []
        var visited = Set<String>()
        var queue = [hostType]

        while let current = queue.first {
            queue.removeFirst()
            guard visited.insert(current).inserted else { continue }

            results.append(contentsOf: indexes.membersByType[current]?[name, default: []].map(\.id) ?? [])
            queue.append(contentsOf: resolveInheritedHosts(of: current, indexes: indexes))
        }

        return results
    }

    private func declaredTypeNames(
        forMemberNamed name: String,
        on hostType: String,
        indexes: AnalysisIndexes
    ) -> Set<String> {
        let members = indexes.membersByType[hostType]?[name, default: []] ?? []
        let directTypeNames = members.compactMap(\.declaredTypeName)
        return Set(directTypeNames)
    }

    private func resolveInheritedHosts(
        of hostType: String,
        indexes: AnalysisIndexes
    ) -> Set<String> {
        let inheritedNames = indexes.inheritedHostsByType[hostType, default: []]
        var hosts = Set<String>()

        for inheritedName in inheritedNames {
            hosts.formUnion(resolveHostTypes(named: inheritedName, indexes: indexes))
        }

        return hosts
    }

    private func resolveTypeReferenceIDs(
        named name: String,
        indexes: AnalysisIndexes
    ) -> Set<String> {
        Set(indexes.typeDeclarationsByName[name, default: []].map(\.id))
    }

    private func resolveHostTypes(
        named name: String,
        indexes: AnalysisIndexes,
        visitedAliases: Set<String> = []
    ) -> Set<String> {
        var hosts = indexes.hostTypesByName[name, default: []]

        for declaration in indexes.typeDeclarationsByName[name, default: []] where declaration.type == .typeAlias {
            guard !visitedAliases.contains(declaration.qualifiedName) else { continue }
            guard let targetTypeName = declaration.declaredTypeName else { continue }

            var nextVisitedAliases = visitedAliases
            nextVisitedAliases.insert(declaration.qualifiedName)
            hosts.formUnion(resolveHostTypes(
                named: targetTypeName,
                indexes: indexes,
                visitedAliases: nextVisitedAliases
            ))
        }

        return hosts
    }

    private func buildUsageRows(
        declarations: [ElementDeclaration],
        usageCounts: [String: Int],
        usageReferencesByDeclarationID: [String: [UsageReference]],
        indexes: AnalysisIndexes,
        options: AnalysisOptions
    ) -> [ElementUsage] {
        declarations.map { declaration in
            let usageCount = usageCounts[declaration.id, default: 0]
            let usageReferences = usageReferencesByDeclarationID[declaration.id, default: []]
            let disposition = usageDisposition(
                for: declaration,
                indexes: indexes,
                options: options
            )

            switch disposition {
            case .analyzed:
                return ElementUsage(
                    from: declaration,
                    usageCount: usageCount,
                    usageReferences: usageReferences,
                    isUnused: usageCount == 0
                )

            case .implicitlyUsed(let reason):
                return ElementUsage(
                    from: declaration,
                    usageCount: usageCount,
                    usageReferences: usageReferences,
                    isUnused: false,
                    note: reason
                )

            case .excludedFromUnused(let reason):
                return ElementUsage(
                    from: declaration,
                    usageCount: usageCount,
                    usageReferences: usageReferences,
                    isUnused: false,
                    note: reason
                )
            }
        }
    }

    private func buildLikelyUnusedFiles(
        allSwiftFiles: [URL],
        declarations: [ElementDeclaration],
        usages: [ElementUsage],
        indexes: AnalysisIndexes
    ) -> [LikelyUnusedFile] {
        let usageByID = Dictionary(uniqueKeysWithValues: usages.map { ($0.id, $0) })
        let topLevelDeclarationsByFile = Dictionary(grouping: declarations.filter(shouldTrackFileCandidate)) { $0.file }
        var likelyUnusedFiles: [LikelyUnusedFile] = topLevelDeclarationsByFile.compactMap { entry in
            let (fileURL, fileDeclarations) = entry
            let topLevelUsages = fileDeclarations.compactMap { usageByID[$0.id] }
            guard !topLevelUsages.isEmpty else { return nil }
            guard topLevelUsages.allSatisfy(\.isUnused) else { return nil }

            let primaryDeclarations = fileDeclarations
                .map(\.name)
                .sorted()
            let sortedDeclarations = fileDeclarations.sorted {
                if $0.line != $1.line {
                    return $0.line < $1.line
                }
                return $0.name < $1.name
            }

            return LikelyUnusedFile(
                id: fileURL.path,
                file: fileURL,
                line: sortedDeclarations.first?.line ?? 1,
                primaryDeclarations: primaryDeclarations,
                reason: fileReason(for: sortedDeclarations, indexes: indexes)
            )
        }

        let filesWithAnyDeclarations = Set(declarations.map { $0.file.standardizedFileURL })
        let declarationFreeFiles = Set(allSwiftFiles.map(\.standardizedFileURL)).subtracting(filesWithAnyDeclarations)

        for fileURL in declarationFreeFiles {
            likelyUnusedFiles.append(LikelyUnusedFile(
                id: fileURL.path,
                file: fileURL,
                line: 1,
                primaryDeclarations: [],
                reason: "This file contains no active declarations (for example, only comments, imports, or whitespace)."
            ))
        }

        return likelyUnusedFiles
    }

    private func buildDiskOnlySwiftFiles(
        allSwiftFiles: [URL],
        projectSwiftFiles: Set<URL>
    ) -> [DiskOnlySwiftFile] {
        allSwiftFiles.compactMap { fileURL in
            let standardizedFileURL = fileURL.standardizedFileURL
            guard !projectSwiftFiles.contains(standardizedFileURL) else { return nil }

            return DiskOnlySwiftFile(
                id: standardizedFileURL.path,
                file: standardizedFileURL,
                reason: "This Swift file exists on disk but is not included in any Xcode project found in the selected folder."
            )
        }
    }

    private func usageDisposition(
        for declaration: ElementDeclaration,
        indexes: AnalysisIndexes,
        options: AnalysisOptions
    ) -> UsageDisposition {
        if !options.includePublicDeclarations,
           let accessLevel = declaration.accessLevel,
           accessLevel == "public" || accessLevel == "open" {
            return .excludedFromUnused("Excluded from the unused list because it may be part of an external API.")
        }

        if declaration.attributes.contains("main") || declaration.name == "main" && declaration.containingType == nil {
            return .implicitlyUsed("Marked as an entry point.")
        }

        if isSwiftPackageManifestDeclaration(declaration) {
            return .implicitlyUsed("Marked as used because Swift Package Manager reads the manifest package declaration.")
        }

        if declaration.isOverride {
            return .implicitlyUsed("Marked as used because it overrides a superclass member.")
        }

        if !dynamicRuntimeAttributes.isDisjoint(with: Set(declaration.attributes)) {
            return .implicitlyUsed("Marked as used because it is referenced by runtime metadata.")
        }

        if declaration.modifiers.contains("dynamic") {
            return .implicitlyUsed("Marked as used because it is dynamically dispatched.")
        }

        if declaration.type == .enumCase,
           typeConformsTo(named: "CaseIterable", declaration.containingType, indexes: indexes) {
            return .implicitlyUsed("Marked as used because CaseIterable synthesizes allCases from enum cases.")
        }

        if declaration.type == .property,
           declaration.attributes.contains("Published"),
           typeConformsTo(named: "ObservableObject", declaration.containingType, indexes: indexes) {
            return .implicitlyUsed("Marked as used because @Published ObservableObject members are observed dynamically.")
        }

        if declaration.type == .property,
           declaration.isFromExtension,
           typeConformsTo(named: "NSManagedObject", declaration.containingType, indexes: indexes) {
            return .implicitlyUsed("Marked as used because Core Data extension members are frequently resolved dynamically.")
        }

        if declaration.type == .method,
           declaration.name.hasPrefix("test"),
           typeConformsTo(named: "XCTestCase", declaration.containingType, indexes: indexes) {
            return .implicitlyUsed("Marked as used because XCTest discovers test methods by name.")
        }

        if declaration.type == .enum || declaration.type == .enumCase,
           declaration.name == "CodingKeys" || declaration.containingType?.hasSuffix(".CodingKeys") == true,
           let parentType = declaration.type == .enum ? declaration.containingType : declaration.containingType?.replacingOccurrences(of: ".CodingKeys", with: ""),
           typeConformsToAny(named: ["Codable", "Decodable", "Encodable"], parentType, indexes: indexes) {
            return .implicitlyUsed("Marked as used because Codable uses CodingKeys implicitly.")
        }

        if let containingType = declaration.containingType {
            let matchingRequirements = requirementNames(for: containingType, indexes: indexes)
            if matchingRequirements.contains(declaration.name) {
                return .implicitlyUsed("Marked as used because it satisfies a protocol requirement.")
            }
        }

        if declaration.type == .class || declaration.type == .struct || declaration.type == .actor || declaration.type == .enum || declaration.type == .protocol,
           typeConformsTo(named: "PreviewProvider", declaration.qualifiedName, indexes: indexes) {
            return .implicitlyUsed("Marked as used because previews discover this type at runtime.")
        }

        if declaration.type == .class,
           typeConformsTo(named: "XCTestCase", declaration.qualifiedName, indexes: indexes) {
            return .implicitlyUsed("Marked as used because XCTest discovers this test case at runtime.")
        }

        return .analyzed
    }

    private func requirementNames(
        for typeName: String,
        indexes: AnalysisIndexes
    ) -> Set<String> {
        let inheritedNames = indexes.inheritedHostsByType[typeName, default: []]
        var requirements = Set<String>()

        for inheritedName in inheritedNames {
            requirements.formUnion(indexes.projectProtocolRequirementsByName[inheritedName, default: []])
            requirements.formUnion(indexes.projectProtocolRequirementsByName[lastIdentifier(in: inheritedName), default: []])
            requirements.formUnion(knownProtocolRequirements[lastIdentifier(in: inheritedName), default: []])
        }

        return requirements
    }

    private func typeConformsTo(
        named protocolName: String,
        _ typeName: String?,
        indexes: AnalysisIndexes
    ) -> Bool {
        guard let typeName else { return false }
        return indexes.inheritedHostsByType[typeName, default: []].contains(where: {
            lastIdentifier(in: $0) == protocolName || $0 == protocolName
        })
    }

    private func typeConformsToAny(
        named protocolNames: Set<String>,
        _ typeName: String?,
        indexes: AnalysisIndexes
    ) -> Bool {
        guard let typeName else { return false }
        return indexes.inheritedHostsByType[typeName, default: []].contains(where: {
            protocolNames.contains(lastIdentifier(in: $0)) || protocolNames.contains($0)
        })
    }

    private func interfaceBuilderReferences(in files: [URL]) throws -> [LocatedReference] {
        var references: [LocatedReference] = []

        for fileURL in files {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let nsSource = source as NSString
            let matches = Self.interfaceBuilderCustomClassPattern.matches(
                in: source,
                range: NSRange(location: 0, length: nsSource.length)
            )

            for match in matches {
                guard match.numberOfRanges > 1 else { continue }
                let className = nsSource.substring(with: match.range(at: 1))
                references.append(LocatedReference(
                    reference: CollectedReference(
                        kind: .type,
                        name: className,
                        currentType: nil,
                        baseChain: [],
                        baseTypeHint: nil,
                        line: 1,
                        column: 1
                    ),
                    file: fileURL
                ))
            }
        }

        return references
    }

    private func shouldTrackFileCandidate(_ declaration: ElementDeclaration) -> Bool {
        guard declaration.containingType == nil else { return false }
        switch declaration.type {
        case .class, .actor, .struct, .enum, .protocol, .typeAlias, .function, .variable:
            return true
        case .method, .property, .enumCase:
            return false
        }
    }

    private func fileReason(
        for declarations: [ElementDeclaration],
        indexes: AnalysisIndexes
    ) -> String {
        if let controllerDeclaration = declarations.first(where: { isViewControllerLike($0, indexes: indexes) }) {
            return "\(controllerDeclaration.name) looks like an unused view controller because no references were found in Swift code, storyboards, or xibs."
        }

        if declarations.count == 1, let declaration = declarations.first {
            return "The top-level declaration \(declaration.name) has no detected references."
        }

        return "All top-level declarations in this file have no detected references."
    }

    private func isViewControllerLike(
        _ declaration: ElementDeclaration,
        indexes: AnalysisIndexes
    ) -> Bool {
        guard declaration.type == .class else { return false }
        return typeConformsToAny(
            named: ["UIViewController", "NSViewController"],
            declaration.qualifiedName,
            indexes: indexes
        )
    }

    private func isSwiftPackageManifestDeclaration(_ declaration: ElementDeclaration) -> Bool {
        declaration.file.lastPathComponent == "Package.swift"
            && declaration.containingType == nil
            && declaration.type == .variable
            && declaration.name == "package"
    }

    private func usageSort(lhs: ElementUsage, rhs: ElementUsage) -> Bool {
        if lhs.isUnused != rhs.isUnused {
            return lhs.isUnused && !rhs.isUnused
        }

        if lhs.containingType != rhs.containingType {
            return (lhs.containingType ?? "Global Scope") < (rhs.containingType ?? "Global Scope")
        }

        if lhs.type.sortRank != rhs.type.sortRank {
            return lhs.type.sortRank < rhs.type.sortRank
        }

        if lhs.name != rhs.name {
            return lhs.name < rhs.name
        }

        if lhs.file.path != rhs.file.path {
            return lhs.file.path < rhs.file.path
        }

        return lhs.line < rhs.line
    }

    private func unusedSort(lhs: UnusedElement, rhs: UnusedElement) -> Bool {
        if lhs.containingType != rhs.containingType {
            return (lhs.containingType ?? "Global Scope") < (rhs.containingType ?? "Global Scope")
        }

        if lhs.type.sortRank != rhs.type.sortRank {
            return lhs.type.sortRank < rhs.type.sortRank
        }

        if lhs.name != rhs.name {
            return lhs.name < rhs.name
        }

        if lhs.file.path != rhs.file.path {
            return lhs.file.path < rhs.file.path
        }

        return lhs.line < rhs.line
    }

    private func unusedFileSort(lhs: LikelyUnusedFile, rhs: LikelyUnusedFile) -> Bool {
        if lhs.file.path != rhs.file.path {
            return lhs.file.path < rhs.file.path
        }

        return lhs.line < rhs.line
    }

    private func diskOnlyFileSort(lhs: DiskOnlySwiftFile, rhs: DiskOnlySwiftFile) -> Bool {
        lhs.file.path < rhs.file.path
    }

    private func lastIdentifier(in name: String) -> String {
        name.split(separator: ".").last.map(String.init) ?? name
    }
}
