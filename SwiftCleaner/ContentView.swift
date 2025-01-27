//
//  ContentView.swift
//  SwiftCleaner
//
//  Created by Holger Krupp on 22.01.25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
   
    @State private var selectedProject: Project? // Track selection state

    var body: some View {
        
        NavigationSplitView {
            DeleteAllView()
        //    ProjectsListView(selectedProject: $selectedProject)
        } detail: {
            if let selectedProject {
                ProjectView(project: selectedProject)
            } else {
                List{
                    FolderScannerView()
                        .padding()
                }
                
            }
        }
        

        
        
        
       // DeleteAllView()
      //  FolderScannerView()
    }


}

#Preview {
    ContentView()
}
