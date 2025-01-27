//
//  ProjectView.swift
//  SwiftCleaner
//
//  Created by Holger Krupp on 24.01.25.
//

import SwiftUI

struct ProjectView: View {
    @ObservedObject var project: Project
    @State private var isScanning: Bool = false // Loading state
    @Environment(\.modelContext) private var modelContext

    var body: some View {
       
        
            Text(project.name)
                .font(.title2)
           
                Text(project.path.absoluteString)
                    .font(.caption)
                    .lineLimit(3)
            if isScanning {
                ProgressView("Scanning…")
                    .padding()
            }else{
                HStack{
                    Button {
                        startScanning(folder: project.path)
                    } label: {
                        Text("Scan folder")
                    }
                    
                    Button {
                        project.findAllClasses()
                    } label: {
                        Text("Find Classes")
                    }
                    .disabled(project.rootNode == nil)
                    Button {
                        project.findAllCalls()
                    } label: {
                        Text("Find Calls")
                    }
                    .disabled(project.rootNode == nil)
                    
                }
            }
            
            if let node = project.rootNode{
                VStack{
                    FileTreeView(node: node)
                        .padding()
                    Spacer()
                    ClassTreeView(classTree: project.classes)
                    ForEach(project.calls, id: \.0) { call in
                        Text("call: \(call.name) in line \(call.line.description)")
                    }
                }
            }
        
        
 
    }
    
    
    /// Function to start scanning the folder
    private func startScanning(folder: URL) {
        project.findFiles()
    }
    

    
    
}

