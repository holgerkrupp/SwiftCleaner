//
//  ContentView.swift
//  ClassCleaner
//
//  Created by Holger Krupp on 04.02.25.
//

import SwiftUI

struct ContentView: View {
    
    enum SubViews:Int, Codable, CaseIterable, Identifiable, CustomStringConvertible {
        var id: Self { self }
        
        var description: String {
            switch self {
            case .files:
                "File Tree"
            case .classes:
                "Class Tree"
            }
        }
        
        case files, classes
    }
    
    
    
    @StateObject private var project: Project = Project.shared
    @State private var viewDetail: SubViews = .classes
   
    var body: some View {
        SelectFolderView(project: project)
            
            
            
        if project.rootNode != nil{
            HStack{
                VStack{
                    Picker("", selection: $viewDetail) {
                        
                        ForEach(SubViews.allCases) { option in
                            
                            Text(String(describing: option))
                                .tag(option)
                            
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    switch viewDetail{
                        
                    case .files:
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
                    case .classes:
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
                }
            //    CodeEditorView(project: project)
                  
            }
        }
    }
}
