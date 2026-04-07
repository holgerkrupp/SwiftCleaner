#if false
import SwiftUI

struct FolderScannerView: View {
    @State private var selectedFolder: URL? = nil // To hold the selected folder
    @Environment(\.modelContext) private var modelContext
    @State private var project: Project? = nil
    

    var body: some View {
        
            VStack {
                // Folder Selection Button
                Button(action: selectFolder) {
                    Text("Select Folder")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding()
                
                if let project{
                    ProjectView(project: project)
                }
                
               
            }
           
    }
    
    /// Function to select a folder
    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let folder = panel.url {
            selectedFolder = folder
             
            project = Project(name: folder.lastPathComponent, path: folder)
       //     modelContext.insert(newProject)
            try? modelContext.save()
        }
    }
    
 
}



// MARK: - Preview
struct FolderScannerView_Previews: PreviewProvider {
    static var previews: some View {
        FolderScannerView()
    }
}
#endif
