import SwiftUI

struct FileTreeView: View {
    @ObservedObject var node: FileNode

    var body: some View {
        
        ScrollView {
            LazyVStack(alignment: .leading) {
                if node.isFolder {
                    DisclosureGroup(node.name) {
                        if let children = node.children {
                            ForEach(children) { child in
                                FileTreeView(node: child)
                                    .padding(.leading, CGFloat(node.depth * 20)) // Indent based on depth
                                
                            }
                        }
                    }
               //     .padding([.leading])
                    .fontWeight(.bold)
                } else {
                    if node.fileType == .swift{
                        HStack{
                            Label(node.name, systemImage: "swift")
                            Button {
                              
                                    Project.shared.parseFiles(fileURLs: [node.url])
                               
                            } label: {
                                Text("Parse")
                            }
                        }
                    }else{
                        Text(node.name)
                            .foregroundStyle(.secondary)
                    }
                    
                }
            }
            
        }
       
    }
}
