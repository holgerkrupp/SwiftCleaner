//
//  Project.swift
//  ClassCleaner
//
//  Created by Holger Krupp on 04.02.25.
//

import Foundation
import SwiftSyntax
import SwiftParser

class Project: ObservableObject{

    @Published var rootNode: FileNode?
    @Published var path: URL?
    private var visitedNodes = Set<UUID>() // Use the node's unique ID
    
    @Published var classes :[ClassElement] = []
    @Published var calls: [Call] = []
    
    static var shared = Project()
    
    private init(){}
   
    func findFiles(){
        if let path{
            self.rootNode = self.buildFileTree(at: path)
        }
    }
    
    
    private func buildFileTree(at directory: URL, depth: Int = 0) -> FileNode? {
        
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        
        // Check if the URL is valid and is a directory
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        
        
        let folderName = directory.lastPathComponent
        var children: [FileNode] = []
        
        // Get the contents of the directory
        if let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            for item in contents {
                
                let isFolder = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if isFolder {
                    // Recursively build the tree for subfolders
                    let newdepth = depth + 1
                    if let childNode = buildFileTree(at: item, depth: newdepth) {
                        children.append(childNode)
                    }
                } else {
                    // Add files directly
                    children.append(FileNode(name: item.lastPathComponent, url: item, isFolder: false, children: nil, depth: depth))
                }
            }
        }
        
        // Return the current folder node with its children
        //    self.rootNote = FileNode(name: folderName, url: directory, isFolder: true, children: children, depth: depth)
        return FileNode(name: folderName, url: directory, isFolder: true, children: children, depth: depth)
    }
    
    func parseFiles(fileURLs: [URL]){
        for fileURL in fileURLs {
            DispatchQueue.global(qos: .background).async {
                do{
                    let result = try self.parseSwiftFileWithSyntax(fileURL: fileURL)
                    
                    
                    DispatchQueue.main.async  {
                       
                            if let newClasses = result?.0 as? [ClassElement]{
                                self.classes = self.classes + newClasses
                               

                            }
                            if let newCalls = result?.1 as? [Call]{
                                self.calls = self.calls + newCalls
                         
                            }
                        
                    }
                }catch{
                    print(error)
                }
            }
        }
    }
    
    func parseSwiftFileWithSyntax(fileURL: URL) throws -> ([ClassElement], [Call])? {
        
        guard let sourceCode = try? String(contentsOf: fileURL, encoding: .utf8) else { throw FileError.couldNotReadFile(fileURL) }
        
        let sourceFile = Parser.parse(source: sourceCode)
        
        let parser = SwiftFileParser(fileURL: fileURL, sourceFile: sourceFile)
        parser.walk(sourceFile)
        let classTree = parser.classes
        let calls = parser.calls
        return (classTree, calls)
    }
    
    
    
    private func walkFileTree(node: FileNode, perform action: (FileNode) -> Void) {
        guard !visitedNodes.contains(node.id) else {
            // print("Node \(node.id) already visited")
            return
        }
        
        visitedNodes.insert(node.id) // Mark the node as visited
        action(node)
        if let children = node.children {
            for child in children {
                
                walkFileTree(node: child, perform: action)
            }
        }
    }
    
    func findAllCalls(){
        calls.removeAll()
        visitedNodes.removeAll()
        
        guard let node = rootNode  else {
            
            
            return }
        
     
        
        self.walkFileTree(node: node) { node in
    
            if !node.isFolder && node.fileType == .swift {
                
                parseFiles(fileURLs: [node.url])
            }
        }
        
        // Notify the UI or handle any final updates on the main thread
        DispatchQueue.main.async {
            print("Call analysis completed.")
        }
    }
    
}
