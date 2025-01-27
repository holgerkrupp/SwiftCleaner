//
//  DeleteAllView.swift
//  SwiftCleaner
//
//  Created by Holger Krupp on 22.01.25.
//

import SwiftUI
import SwiftData

struct DeleteAllView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Button {
            deleteAll()
        } label: {
            Text("Delete all data")
        }

    }
    private func deleteAll() {
        do {
 //        try modelContext.delete(model: ClassTree.self)
 //          try modelContext.delete(model: FileNode.self)
 //           try modelContext.delete(model: Project.self)
 //           try modelContext.delete(model: ClassElement.self)
        } catch {
            print("Failed to clear all SwiftData Data")
        }
    }
}



#Preview {
    DeleteAllView()
}
