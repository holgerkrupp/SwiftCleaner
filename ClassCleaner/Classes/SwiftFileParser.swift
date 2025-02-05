

import SwiftSyntax
import SwiftParser
import Foundation


class SwiftFileParser: SyntaxVisitor {
    var fileURL: URL
    var classes: [ClassElement] = []
    private var classStack: [ClassElement] = []
    private var instanceTypes: [String: String] = [:] // Maps instance name -> Class type
    private var classMethods: [String: String] = [:]
    var calls: [Call] = []
    
    let sourceLocationConverter: SourceLocationConverter
   
    
    
    init(fileURL: URL, sourceFile: SourceFileSyntax) {
        self.sourceLocationConverter = SourceLocationConverter(fileName: fileURL.path, tree: sourceFile)
        self.fileURL = fileURL
        super.init(viewMode: .all)
    }
    
    override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
        return .visitChildren
    }
    
    override func visit(_ node: CodeBlockItemSyntax) -> SyntaxVisitorContinueKind {
        return .visitChildren
    }
    
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        var functionName: String = "Unknown"
        var instanceName: String? = nil
        var classType: String? = nil
        var parameters: [String] = []
        if let memberAccessExpr = node.calledExpression.as(MemberAccessExprSyntax.self) {
            functionName = memberAccessExpr.declName.baseName.text
            
            
            
            if let baseExpr = memberAccessExpr.base {
                if let identifier = baseExpr.as(IdentifierExprSyntax.self) {
                    // Simple case: Direct instance method call, like `gm.someFunction()`
                    instanceName = identifier.identifier.text
                    classType = instanceTypes[instanceName!] ?? classMethods[functionName] ?? classStack.last?.name// Lookup
                } else if let baseMemberAccess = baseExpr.as(MemberAccessExprSyntax.self) {
                    // Case for `GameManager.shared.checkGameObjectExists(...)`
                    if let baseIdentifier = baseMemberAccess.base?.as(IdentifierExprSyntax.self) {
                        classType = baseIdentifier.identifier.text  ?? classStack.last?.name// "GameManager"
                    }
                }
            }
        } else if let identifierExpr = node.calledExpression.as(IdentifierExprSyntax.self) {
            functionName = identifierExpr.identifier.text
            classType = classMethods[functionName]  ?? classStack.last?.name// Lookup standalone function
        }
            
        
         
        
        for argument in node.arguments {
           
          
                let argumentExpression = argument.expression
            if let identifier = argumentExpression.as(DeclReferenceExprSyntax.self) {
                print("identifier: \(identifier.baseName.text)")
                parameters.append(identifier.baseName.text)  // Extract identifier name
            } else {
                print("argumentExpression: \(argumentExpression.description)")
                parameters.append(argumentExpression.description)
            }
               
            
        }
       
        let line = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia).line
        
        // print("📞 Function call detected: \(functionName) (Instance: \(instanceName ?? "global"), Class: \(classType ?? "Unknown"), Line: \(line))")
        calls.append(Call(name: functionName, file: fileURL, line: line, className: classType, paramaters: parameters))
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        
        if let extendedType = node.extendedType.as(IdentifierTypeSyntax.self)?.name.text {
            // Create a temporary ClassElement for the extension
            let extensionElement = ClassElement(type: .extension, name: extendedType, file: fileURL, line: location.line)
            classStack.append(extensionElement)
            // print("🛠 Found extension for class: \(extendedType) at line \(location.line)")
        }
        
        return .visitChildren
    }
    override func visitPost(_ node: ExtensionDeclSyntax) {
        if let last = classStack.last, last.type == .extension {
            // print("✅ Finished processing extension for class: \(last.name)")
            classStack.removeLast()
        }
    }
    func findMatchingFunction(name: String, instance: String?) -> ClassElement? {
        if let instance = instance {
            // Look for the class in `classes`
            if let classElement = classes.first(where: { $0.name == instance }) {
                return classElement.children.first { $0.name == name }
            }
        } else {
            // Look for a standalone function
            return classes.flatMap { $0.children }.first { $0.name == name }
        }
        return nil
    }
    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        
        let calledFunction = node.baseName.description
        let line = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia).line
        let newElement = ClassElement(type: .property, name: calledFunction, file: fileURL, line: line)
        
      //  append(newElement: newElement)
        
        return .visitChildren
    }
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
      //  // print("visited call: \(node.description)")
        let calledFunction = node.description
        let line = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia).line
        
        calls.append(Call(name: calledFunction, file: fileURL, line: line))
        
        return .visitChildren
    }
    override func visit(_ node: SubscriptCallExprSyntax) -> SyntaxVisitorContinueKind {
     //   // print("visited call: \(node.description)")
        if let calledFunction = node.calledExpression.as(SubscriptCallExprSyntax.self)?.description{
            let line = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia).line
            
            calls.append(Call(name: calledFunction, file: fileURL, line: line))
        }
        return .visitChildren
    }
    func getFunctionCalls() ->[Call] {
    //    // print("found \(calls.count.description) function Calls")
        return calls
    }
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        
    //   // print("visited class: \(node.name.text)")
        
        let location = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        let className = node.name.text
        
        let newClass = ClassElement(type: .class, name: className, file: fileURL, line: location.line)
        classStack.append(newClass)
       
        return .visitChildren
    }
    override func visitPost(_ node: ClassDeclSyntax) {
        // When leaving the class, pop it from the stack and store it
        if let lastClass = classStack.popLast() {
            classes.append(lastClass)
        }
    }
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        
    //    // print("visited: \(node.name.text)")
        
        let location = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        let structName = node.name.text
        
        
        return .visitChildren
    }
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let functionName = node.name.text
        let location = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        
        // Retrieve the current class or extension context
        let parentClass = classStack.last?.name ?? "Unknown"
        
        // Store the function name with its corresponding class
        classMethods[functionName] = parentClass
        
        var parameterNames: [String] = []
        for parameter in node.signature.parameterClause.parameters {
           parameterNames.append(parameter.firstName.text)
            
        }
        
        let newElement = ClassElement(
            type: .method,
            name: functionName,
            paramaters: parameterNames,
            signature: node.signature.description,
            file: fileURL,
            line: location.line
        )
        
        if let extensionElement = classStack.last, extensionElement.type == .extension {
            extensionElement.children.append(newElement)
            // print("🔗 Added method '\(functionName)' to extension of class '\(parentClass)'")
        } else {
            append(newElement: newElement)
            // print("🔗 Added method '\(functionName)' to class '\(parentClass)'")
        }
        
        return .visitChildren
    }


    
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        
        for binding in node.bindings {
            if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                let propertyName = identifier.identifier.text
                
                // 🛠 Check if this variable is assigned a class instance (e.g., `let gm = GameManager()`)
                if let initializer = binding.initializer?.value {
                    if let functionCall = initializer.as(FunctionCallExprSyntax.self),
                       let typeName = functionCall.calledExpression.as(IdentifierExprSyntax.self)?.identifier.text {
                        
                        // 🔗 Store instance name → Class Type (direct instantiation)
                        instanceTypes[propertyName] = typeName
                        // print("🔗 Instance '\(propertyName)' → Class '\(typeName)' (Line \(location.line))")
                        
                    }
                    // 🛠 Detect shared instances (e.g., `let gm = GameManager.shared`)
                    else if let memberAccess = initializer.as(MemberAccessExprSyntax.self),
                            let baseName = memberAccess.base?.as(IdentifierExprSyntax.self)?.identifier.text {
                        
                        // Assume `baseName` is the class name
                        instanceTypes[propertyName] = baseName
                        // print("🔗 Shared Instance '\(propertyName)' → Class '\(baseName)' (Line \(location.line))")
                    }
                } else {
                    // ✅ Regular property inside a class
                    let newElement = ClassElement(type: .property, name: propertyName, file: fileURL, line: location.line)
                    append(newElement: newElement)
                }
            }
        }
        
        // print("📋 All instances: \(instanceTypes)")
        return .visitChildren
    }

    
    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        
     //   // print("visited: Closure")
        
        
        let name = "Closure"
        let location = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        let description = node.description.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let newElement = ClassElement(type: .closure, name: name, file: fileURL, line: location.line)
        append(newElement: newElement)
        
        return .visitChildren
    }
    
    func append(newElement: ClassElement){
        if let currentClass = classStack.last {
            currentClass.children.append(newElement)
        } else{
            classes.append(newElement)
        }
    }
    
}
func parseSwiftSourceCode(_ sourceCode: String) -> SourceFileSyntax? {
    // Parse the source code string into a syntax tree
    let sourceFile = Parser.parse(source: sourceCode)
    return sourceFile
    
}
