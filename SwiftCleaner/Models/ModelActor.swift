/*

import SwiftData

@ModelActor
actor ProjectModelActor {
    private let context: ModelContext
    
    init(context: ModelContext) {
        self.context = context
    }
    
    // Fetch all projects
    func fetchAllProjects() async throws -> [Project] {
        let descriptor = FetchDescriptor<Project>()
        return try context.fetch(descriptor)
    }
    

    
    // Find all classes in the project's file tree
    func findAllClasses(for project: Project, progressHandler: ((Double) -> Void)? = nil) async throws {
        project.classes.removeAll()
        guard let rootNode = project.rootNode else { return }
        
        var totalNodes = 0
        var processedNodes = 0
        
        // Count total nodes
        await walkFileTree(node: rootNode) { _ in totalNodes += 1 }
        
        // Process nodes asynchronously
        
            await self.walkFileTree(node: rootNode) { node in
                
                    if !node.isFolder && node.fileType == .swift {
                        let foundClasses = project.findClassesIn(file: node.url)
                        await self.addClasses(foundClasses)
                    }
                    processedNodes += 1
                    progressHandler?(Double(processedNodes) / Double(totalNodes))
                
            }
        
        
        try context.save()
        print("Class analysis completed.")
    }
    
    // Recursive file tree walker
    private func walkFileTree(node: FileNode, perform action: @escaping (FileNode) async -> Void) async {
        await action(node)
        if let children = node.children {
            for child in children {
                await walkFileTree(node: child, perform: action)
            }
        }
    }
    
    // Add classes to the ModelContext
    private func addClasses(_ classes: [ClassTree]) async {
        for classTree in classes {
            context.insert(classTree)
        }
    }
}
*/
