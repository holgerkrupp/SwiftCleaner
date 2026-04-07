#if false
//
//  FileTreeView.swift
//  SwiftCleaner
//
//  Created by Holger Krupp on 24.01.25.
//

import SwiftUI

struct FileTreeView: View {
    @State var node: FileNode
    @State var classtrees: [ClassTree]?
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                if node.isFolder {
                    DisclosureGroup(node.name) {
                        if let children = node.children {
                            ForEach(children) { child in
                                FileTreeView(node: child)
                                    .padding(.leading, CGFloat(node.depth * 20)) // Indent based on depth
                                
                            }
                        }
                    }
                    .padding()
                } else {
                    
                    HStack{
                        Text(node.name)
                        if node.fileType == .swift
                        {
                            Button {
                                
                                let sourceCode = try? String(contentsOf: node.url, encoding: .utf8)
                                
                                if let sourceFile =  parseSwiftSourceCode( sourceCode ?? "") {
                                    print("Parsing \(node.url.absoluteString)")
                                    
                                    let parser = SwiftFileParser(fileURL: node.url, sourceFile: sourceFile)
                                    parser.walk(sourceFile)
                                    
                                    
                                    classtrees = parser.classes
                              
                                    ForEach(classtrees ?? []) { cla in
                                        Text(cla.elements.count.description)
                                        
                                    }
                                    
                                   
                                }
                            } label: {
                                Text("Parse")
                            }
                        }}
                    
                    
                }
                
                
            }}
    }
}

#endif
