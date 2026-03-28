#if false
//
//  FileTree.swift
//  SwiftCleaner
//
//  Created by Holger Krupp on 22.01.25.
//

import Foundation
import SwiftData
import SwiftSyntax
import SwiftParser


class FileNode: Identifiable, ObservableObject {
    
    enum FileType: String, Codable {
        case swift
        case other
    }
    
    var id = UUID()
    var name: String // Name of the file or folder
    var url: URL // Full URL path
    var isFolder: Bool // Whether it's a folder
    var children: [FileNode]? // Child nodes (only for folders)

    var depth: Int // Depth in the tree
    
    var fileType: FileType {
        print(url.absoluteString)
        if url.pathExtension.isEmpty {
            return FileType.other
        }else{
            switch url.pathExtension {
            case "swift":
                return FileType.swift
            default:
                return FileType.other
            }
        }
    }
    
   
    
    init(name: String, url: URL, isFolder: Bool, children: [FileNode]?, depth: Int) {
        self.name = name
        self.url = url
        self.isFolder = isFolder
        self.children = children
        self.depth = depth

    }
    
    
   
    func parseSwiftFileWithSyntax(_ fileURL: URL) -> [ClassTree] {
        guard let sourceCode = try? String(contentsOf: fileURL, encoding: .utf8) else { return []}
        
        let sourceFile = Parser.parse(source: sourceCode)
        
        let parser = SwiftFileParser(fileURL: fileURL, sourceFile: sourceFile)
        parser.walk(sourceFile)
        
        return parser.classes
    }
}
#endif
