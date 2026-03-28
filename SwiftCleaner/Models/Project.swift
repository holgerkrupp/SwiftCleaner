#if false
//
//  Project.swift
//  SwiftCleaner
//
//  Created by Holger Krupp on 24.01.25.
//

import Foundation
import SwiftData



class Project: Identifiable, ObservableObject {
    var name: String
    var id = UUID()
    @Published var rootNode: FileNode?
    var path: URL
    @Published  var classes: [ClassTree] = []
    @Published  var calls:  [(name: String, line: Int)] = []
    init(name: String, path: URL) {
        self.name = name
        self.path = path
    }
    
    
    func findFiles(){
        
            self.rootNode = self.buildFileTree(at: self.path)
        
    }
    
    
    func findAllClasses() {
        classes.removeAll()
        visitedNodes.removeAll()
        guard let rootNode = self.rootNode else { return }
        
        // Perform the file scan in a background queue
        
            self.walkFileTree(node: rootNode) { node in
                print("checking: \(node.name) - Type: \(node.fileType.rawValue)")
                if !node.isFolder && node.fileType == .swift {
                    
                    let newClasses = self.findClassesIn(file: node.url)
                 
                    self.classes.append(contentsOf: newClasses)
                }
            }
            
            // Notify the UI or handle any final updates on the main thread
            DispatchQueue.main.async {
                print("Class analysis completed.")
            }
        
    }
    
    private var visitedNodes = Set<UUID>() // Use the node's unique ID
    
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
       
        visitedNodes.removeAll()
      
        guard let node = rootNode  else {
            
         
            return }
   
        // Perform the file scan in a background queue
        
        self.walkFileTree(node: node) { node in
            print("checking: \(node.name) - Type: \(node.fileType.rawValue)")
            if !node.isFolder && node.fileType == .swift {
                
                let newCalls = self.findCallsIn(file: node.url)
                
                self.calls.append(contentsOf: newCalls ?? [])
            }
        }
        
        // Notify the UI or handle any final updates on the main thread
        DispatchQueue.main.async {
            print("Call analysis completed.")
        }
    }
    
    
    func findClassesIn(file: URL) -> [ClassTree] {
        var classTrees: [ClassTree] = []
        
        let sourceCode = try? String(contentsOf: file, encoding: .utf8)
        guard let sourceFile = parseSwiftSourceCode(sourceCode ?? "") else { return classTrees }
        
        let parser = SwiftFileParser(fileURL: file, sourceFile: sourceFile)
        parser.walk(sourceFile)
        
        classTrees.append(contentsOf: parser.classes)
       
        return classTrees
    }


    
    func findCallsIn(file: URL) -> [(name: String, line: Int)]? {
        print("findCallsIn: \(file.absoluteString)")
        let sourceCode = try? String(contentsOf: file, encoding: .utf8)
        
        if let sourceFile =  parseSwiftSourceCode( sourceCode ?? "") {
            
            let parser = SwiftFileParser(fileURL: file, sourceFile: sourceFile)
            parser.walk(sourceFile)
            let functionCalls = parser.getFunctionCalls()
            return functionCalls
        }
        return nil
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
                
                print(item.lastPathComponent)
                
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
}
#endif
