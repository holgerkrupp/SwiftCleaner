import SwiftUI

struct ClassTreeView: View {
    var classTree: [ClassTree]
    
    var body: some View {
        Text("Class Tree")
        ForEach(classTree) { classObject in
            Section(header: Text("Class: \(classObject.name)").font(.headline)) {
                // Display Methods
                if !classObject.elements.filter({ $0.type == .method }).isEmpty {
                    DisclosureGroup("Methods (\(classObject.elements.filter({ $0.type == .method }).count))") {
                        ForEach(classObject.elements.filter { $0.type == .method }) { element in
                            HStack {
                                Text(element.name)
                                    .font(.body)
                                Spacer()
                                if let signature = element.signature {
                                    Text(signature)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                }
                
                // Display Properties
                if !classObject.elements.filter({ $0.type == .property }).isEmpty {
                    DisclosureGroup("Properties (\(classObject.elements.filter({ $0.type == .property }).count))") {
                        ForEach(classObject.elements.filter { $0.type == .property }) { element in
                            Text(element.name)
                                .font(.body)
                        }
                    }
                }
                
                // Display Closures
                if !classObject.elements.filter({ $0.type == .closure }).isEmpty {
                    DisclosureGroup("Closures (\(classObject.elements.filter({ $0.type == .closure }).count))") {
                        ForEach(classObject.elements.filter { $0.type == .closure }) { element in
                            Text(element.name)
                                .font(.body)
                        }
                    }
                }
            }
        }
            // Display the classObject name

        
    }
}
