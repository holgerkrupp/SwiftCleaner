//
//  FileTree.swift
//  ClassCleaner
//
//  Created by Holger Krupp on 04.02.25.
//
import Foundation
import SwiftSyntax
import SwiftParser

public enum FileError: Error {
    case notASwiftFile(URL)
    case couldNotReadFile(URL)
    
}

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
    
    func parseSwiftFileWithSyntax() throws -> ([ClassElement], [Call])? {
     
            guard fileType == .swift else { throw FileError.notASwiftFile(url) }
        
            guard let sourceCode = try? String(contentsOf: url, encoding: .utf8) else { throw FileError.couldNotReadFile(url) }
            
            let sourceFile = Parser.parse(source: sourceCode)
            
            let parser = SwiftFileParser(fileURL: url, sourceFile: sourceFile)
            parser.walk(sourceFile)
            let classTree = parser.classes
            let calls = parser.calls
            return (classTree, calls)
        }
    
    
    
    

}
