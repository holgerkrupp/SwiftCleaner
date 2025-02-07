import SwiftUI

struct ClassTreeView: View {
    @ObservedObject var project: Project
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                ForEach(sortedNodes(project.classes), id: \.id) { node in
                    ClassNodeView(node: node, calls: project.calls)
                

                }
            }
        }
    }
    

    private func sortedNodes(_ nodes: [ClassElement]) -> [ClassElement] {
        nodes.sorted { $0.children.count > $1.children.count } // Nodes with children first
    }
}


struct ClassNodeView: View {
    @State var node: ClassElement
    var calls: [Call]
    var parent: ClassElement? = nil
    
    var body: some View {
        if !node.children.isEmpty {
            HStack(alignment: .top) {
          
                DisclosureGroup(node.name) {
                    ForEach(sortedNodes(node.children), id: \.id) { child in
                        HStack{
                            ClassNodeView(node: child, calls: calls, parent: node)
                                .padding(.leading, 20)
                                .onTapGesture {
                                    NSWorkspace.shared.open(node.file)
                                }
                            
                            
                        }
                    }
                }
                .fontWeight(.bold)
            }
           
        } else {
            
            
            let matchingCalls = calls.filter { $0.name == node.name && $0.paramaters?.count == node.paramaters?.count}
            let callCount = matchingCalls.count
            HStack(alignment: .top){
                VStack(alignment: .leading){
                    HStack{
                        
                        Label(node.name, systemImage: systemImage(for: node.type))
                            .foregroundStyle(.primary)
                            .help("\(node.file.standardizedFileURL.absoluteString) Line \(node.line)")
                        
                        if node.type == .method || node.type == .closure {
                            Text(node.signature ?? "")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .fontWeight(.light)
                        }
                    }
                    Text("\(node.location)")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fontWeight(.light)
                }
                .onTapGesture {
                    NSWorkspace.shared.open(node.file)
                }
                Spacer()
                if callCount > 0{
                    DisclosureGroup("(\(callCount) calls)") {
                        VStack(alignment: .trailing) {
                            ForEach(matchingCalls, id: \.id ) { call in
                                HStack{
                                    Text("\(call.className ?? "-") \(call.description)")
                                        .fontWeight(.light)
                                        .help("\(call.file.standardizedFileURL.absoluteString) Line \(call.line)")
                                    Text("\(call.file.lastPathComponent) \(call.line)")
                                        .font(.system(.footnote, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .fontWeight(.light)
                                }
                               
                                .onTapGesture {
                                    NSWorkspace.shared.open(call.file)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                    }
                    .padding(.leading, 40)
                    .foregroundStyle(callCount > 0 ? .blue : .red)
                    .fontWeight(.bold)
                }else{
                    Text("not used")
                        .foregroundStyle(callCount > 0 ? .blue : .red)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 40)
                }
            }
            
            
                
            }
        }
    
    
    private func sortedNodes(_ nodes: [ClassElement]) -> [ClassElement] {
        nodes.sorted { elementPriority($0.type) < elementPriority($1.type) }
    }
    
    private func elementPriority(_ type: ElementType) -> Int {
        switch type {
        case .method:
            return 0 // Methods first
        case .property:
            return 1 // Properties second
        case .closure:
            return 2 // Closures last
        default:
            return 3 // Other types (if any)
        }
    }
    
    private func systemImage(for type: ElementType) -> String {
        switch type {
        case .class: return "folder"
        case .method: return "function"
        case .property: return "circle.fill"
        case .closure: return "curlybraces"
        case .extension: return "folder"
    
        }
    }
}

