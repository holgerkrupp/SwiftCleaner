#if false
//
//  ProjectsListView.swift
//  SwiftCleaner
//
//  Created by Holger Krupp on 24.01.25.
//

import SwiftUI
import SwiftData

/*
struct ProjectsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedProject: Project? // Binding to track selection in parent view

    
   @Query private var projects: [Project]
    var body: some View {
        FolderScannerView()
        
        List(projects, id: \.id, selection: $selectedProject) { project in
            NavigationLink(
                value: project,
                label: {
                    VStack{
                        Text(project.name)
                            .font(.title2)
                            Text(project.path.absoluteString)
                                .font(.caption)
                                .lineLimit(3)
                        
                    }
                }
            )
        }

       
        
        
        
    }
}
*/
#endif
