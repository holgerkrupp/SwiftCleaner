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
    
    var body: some View {
        if !node.children.isEmpty {
            DisclosureGroup(node.name) {
                ForEach(sortedNodes(node.children), id: \.id) { child in
                    ClassNodeView(node: child, calls: calls)
                        .padding(.leading, 20)
                }
            }
            .fontWeight(.bold)
        } else {
            let callCount = calls.filter { $0.name == node.name }.count
            
            HStack {
                Label(node.name, systemImage: systemImage(for: node.type))
                    .foregroundStyle(.primary)
                
                if node.type == .method || node.type == .closure {
                    Text(node.signature ?? "")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                
               
                    Text("(\(callCount) calls)")
                        .foregroundStyle(callCount > 0 ? .blue : .red)
                        .fontWeight(.bold)
                
                
                Spacer()
                Text("Line \(node.line)")
                    .foregroundStyle(.secondary)
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
        case .clas: return "folder"
        case .method: return "function"
        case .property: return "circle.fill"
        case .closure: return "curlybraces"
        }
    }
}

