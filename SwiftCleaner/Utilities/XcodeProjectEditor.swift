import Foundation

struct XcodeProjectEditor {
    func removeFileReferences(to fileURL: URL, inProjectRoot rootURL: URL) throws -> Int {
        let projectURLs = try findXcodeProjects(in: rootURL)
        var totalRemoved = 0

        for projectURL in projectURLs {
            totalRemoved += try removeFileReferences(to: fileURL, inXcodeProject: projectURL)
        }

        return totalRemoved
    }

    private func removeFileReferences(to fileURL: URL, inXcodeProject projectURL: URL) throws -> Int {
        let pbxprojURL = projectURL.appendingPathComponent("project.pbxproj")
        let data = try Data(contentsOf: pbxprojURL)
        var format = PropertyListSerialization.PropertyListFormat.openStep
        guard
            var plist = try PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Any],
            var objects = plist["objects"] as? [String: [String: Any]]
        else {
            return 0
        }

        let projectBaseURL = projectURL.deletingLastPathComponent()
        let normalizedTargetPath = fileURL.standardizedFileURL.path
        let targetRelativePath = normalizedRelativePath(from: projectBaseURL, to: fileURL)

        var fileReferenceIDsToDelete = Set<String>()
        for (id, object) in objects {
            guard object["isa"] as? String == "PBXFileReference" else { continue }
            guard matchesFileReference(object: object, targetPath: normalizedTargetPath, targetRelativePath: targetRelativePath) else { continue }
            fileReferenceIDsToDelete.insert(id)
        }

        guard !fileReferenceIDsToDelete.isEmpty else { return 0 }

        var buildFileIDsToDelete = Set<String>()
        for (id, object) in objects {
            guard object["isa"] as? String == "PBXBuildFile" else { continue }
            if let fileRef = object["fileRef"] as? String, fileReferenceIDsToDelete.contains(fileRef) {
                buildFileIDsToDelete.insert(id)
            }
        }

        for fileRefID in fileReferenceIDsToDelete {
            objects.removeValue(forKey: fileRefID)
        }
        for buildFileID in buildFileIDsToDelete {
            objects.removeValue(forKey: buildFileID)
        }

        for (id, var object) in objects {
            if var children = object["children"] as? [String] {
                children.removeAll { fileReferenceIDsToDelete.contains($0) }
                object["children"] = children
            }
            if var files = object["files"] as? [String] {
                files.removeAll { buildFileIDsToDelete.contains($0) }
                object["files"] = files
            }
            if let fileRef = object["fileRef"] as? String, fileReferenceIDsToDelete.contains(fileRef) {
                continue
            }
            objects[id] = object
        }

        plist["objects"] = objects
        let outputData = try PropertyListSerialization.data(fromPropertyList: plist, format: .openStep, options: 0)
        try outputData.write(to: pbxprojURL, options: .atomic)
        return fileReferenceIDsToDelete.count
    }

    private func matchesFileReference(object: [String: Any], targetPath: String, targetRelativePath: String?) -> Bool {
        let path = (object["path"] as? String)?.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        let name = (object["name"] as? String)?.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        let sourceTree = (object["sourceTree"] as? String) ?? "<group>"

        if path == URL(fileURLWithPath: targetPath).lastPathComponent || name == URL(fileURLWithPath: targetPath).lastPathComponent {
            return true
        }
        if let targetRelativePath, path == targetRelativePath || name == targetRelativePath {
            return true
        }
        if sourceTree == "<absolute>", path == targetPath {
            return true
        }
        return false
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
            if url.pathExtension == "xcodeproj" {
                projectURLs.append(url)
                enumerator.skipDescendants()
            }
        }
        return projectURLs
    }

    private func normalizedRelativePath(from baseURL: URL, to fileURL: URL) -> String? {
        let basePath = baseURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(basePath + "/") else { return nil }
        return String(filePath.dropFirst(basePath.count + 1))
    }
}
