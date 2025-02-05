//
//  ContentView.swift
//  ClassCleaner
//
//  Created by Holger Krupp on 04.02.25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var project: Project = Project.shared
    var body: some View {
        SelectFolderView(project: project)
        
        HStack{
            if let node = project.rootNode{
                FileTreeView(node: node)
                    .padding([.leading, .bottom])
            }else{
                if project.path != nil{
                    Button {
                        project.findFiles()
                    } label: {
                        Text("Find Files")
                    }
                }
            }
            if !project.classes.isEmpty{
                ClassTreeView( project: project)
                    .padding([.leading, .bottom, .trailing])
            }else{
                Button {
                    project.findAllCalls()
                } label: {
                    Text("Find Classes und so")
                }
            }
            
        }
        Text("classes: \(project.classes.count)")
        Text("calls: \(project.calls.count)")
    }
}

#Preview {
    ContentView()
}
