//
//  SelectFolderView.swift
//  ClassCleaner
//
//  Created by Holger Krupp on 04.02.25.
//

import SwiftUI

struct SelectFolderView: View {
    @ObservedObject var project: Project
    @State private var dragOver = false
    var body: some View {
        Button(action: selectFolder) {
            Text("Select or Drop Folder")
                .font(.headline)
                .padding()

        }
        .onDrop(of: ["public.file-url"], isTargeted: $dragOver) { providers -> Bool in
            providers.first?.loadDataRepresentation(forTypeIdentifier: "public.file-url", completionHandler: { (data, error) in
                if let data = data, let path = NSString(data: data, encoding: 4), let url = URL(string: path as String) {
                    DispatchQueue.main.async {
                        project.path = url
                        project.analyzeProject()
                    }
                }
            })
            return true
        }
        .padding()
        .border(dragOver ? Color.red : Color.clear)
    }
    
     func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let folder = panel.url {
            project.path = folder
            project.analyzeProject()

        }
    }
}

