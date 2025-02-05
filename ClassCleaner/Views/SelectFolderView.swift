//
//  SelectFolderView.swift
//  ClassCleaner
//
//  Created by Holger Krupp on 04.02.25.
//

import SwiftUI

struct SelectFolderView: View {
    @ObservedObject var project: Project

    var body: some View {
        Button(action: selectFolder) {
            Text("Select Folder")
                .font(.headline)
                .padding()

        }
        .padding()
    }
    
     func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let folder = panel.url {
            project.path = folder
            

        }
    }
}

