//
//  EmptyProjectView.swift
//  ClassCleaner
//
//  Created by Holger Krupp on 04.02.25.
//

import SwiftUI

struct NoUnusedElementsView: View {
    var body: some View {
        ContentUnavailableView(
            "No Unused Elements Found",
            systemImage: "checkmark.circle",
            description: Text("All elements in your project appear to be in use.")
        )
    }
}

#Preview {
    NoUnusedElementsView()
}
