#if false
import SwiftSyntax
import SwiftParser
import Foundation





class SwiftFileParser: SyntaxVisitor {
    var classes: [ClassTree] = []
    var currentClass: ClassTree? = nil
    let sourceLocationConverter: SourceLocationConverter
    private var functionCalls: [(name: String, line: Int)] = []
   
    
    init(fileURL: URL, sourceFile: SourceFileSyntax) {
        self.sourceLocationConverter = SourceLocationConverter(fileName: fileURL.path, tree: sourceFile)
        super.init(viewMode: .all)
    }
    
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        print("visited call: \(node.description)")
        if let calledFunction = node.calledExpression.as(FunctionCallExprSyntax.self)?.description {
            let line = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia).line
            functionCalls.append((name: calledFunction, line: line ?? 0))
        }
        return .visitChildren
    }
    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        print("visited call: \(node.description)")
        
        let calledFunction = node.baseName.description
            let line = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia).line
            functionCalls.append((name: calledFunction, line: line ?? 0))
        
        return .visitChildren
    }
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        print("visited call: \(node.description)")
        let calledFunction = node.description
            let line = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia).line
            functionCalls.append((name: calledFunction, line: line ?? 0))
        
        return .visitChildren
    }
    
    override func visit(_ node: SubscriptCallExprSyntax) -> SyntaxVisitorContinueKind {
        print("visited call: \(node.description)")
        if let calledFunction = node.calledExpression.as(SubscriptCallExprSyntax.self)?.description{
            let line = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia).line
            functionCalls.append((name: calledFunction, line: line ?? 0))
        }
        return .visitChildren
    }
    
    func getFunctionCalls() -> [(name: String, line: Int)] {
        print("found \(functionCalls.count.description) function Calls")
        return functionCalls
    }
    
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        
        print("visited class: \(node.name.text)")
        
        let location = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        let className = node.name.text
        
        currentClass = ClassTree(name: className, file: location.file, line: location.line ?? 0)
        if let currentClass = currentClass {
            classes.append(currentClass)
        }
        return .visitChildren
    }
    
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        
        print("visited: \(node.name.text)")
        
        let location = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        let structName = node.name.text
        
        
        
        currentClass = ClassTree(name: structName, file: location.file, line: location.line ?? 0)
        if let currentClass = currentClass {
            classes.append(currentClass)
        }
        return .visitChildren
    }
    
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        
        
        print("visited: \(node.name.text)")
        
        guard let currentClass = currentClass else { return .skipChildren }
        
        let location = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        let methodName = node.name.text
        let signature = node.description.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let element = ClassElement(
            type: .method,
            name: methodName,
            signature: signature,
            file: location.file,
            line: location.line ?? 0
        )
        currentClass.elements.append(element)
        return .skipChildren
    }
    
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        
        
        print("visited Variable: \(node.description)")
        
        guard let currentClass = currentClass else { return .skipChildren }
        
        let location = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        for binding in node.bindings {
            if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                let propertyName = identifier.identifier.text
                
                print("visited: \(propertyName)")
                
                
                let element = ClassElement(
                    type: .property,
                    name: propertyName,
                    file: location.file,
                    line: location.line ?? 0
                )
                currentClass.elements.append(element)
            }
        }
        return .skipChildren
    }
    
    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        
        print("visited: Closure")
        
        
        guard let currentClass = currentClass else { return .skipChildren }
        
        let location = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        let description = node.description.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let element = ClassElement(
            type: .closure,
            name: "Closure",
            signature: description,
            file: location.file,
            line: location.line ?? 0
        )
        currentClass.elements.append(element)
        return .skipChildren
    }
}
func parseSwiftSourceCode(_ sourceCode: String) -> SourceFileSyntax? {
        // Parse the source code string into a syntax tree
        let sourceFile = Parser.parse(source: sourceCode)
        return sourceFile
    
}
#endif
