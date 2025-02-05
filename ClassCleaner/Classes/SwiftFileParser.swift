

import SwiftSyntax
import SwiftParser
import Foundation


class SwiftFileParser: SyntaxVisitor {
    var fileURL: URL
    var classes: [ClassElement] = []
    private var classStack: [ClassElement] = []
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
        // Check if the called expression is a member access (e.g., gm.addTo2)
        let functionName: String
        if let memberAccessExpr = node.calledExpression.as(MemberAccessExprSyntax.self) {
            // Extract the function name from the declName
            functionName = memberAccessExpr.declName.baseName.text
        } else if let awaitExpr = node.calledExpression.as(AwaitExprSyntax.self) {
            // If it's wrapped in await, extract the function name from the inner expression
            if let identifierExpr = awaitExpr.expression.as(DeclReferenceExprSyntax.self) {
                functionName = identifierExpr.baseName.text
            } else {
                functionName = "Unknown"
            }
        } else if let identifierExpr = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            // Regular function call
            functionName = identifierExpr.baseName.text
        } else {
            functionName = "Unknown"
        }
        
        // Capture the line number
        let line = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia).line
        
        // Append the call to the list
        calls.append(Call(name: functionName, file: fileURL, line: line))
        
        print("Recorded function call: \(functionName) at line \(line) of file \(fileURL)")
        
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        
        let calledFunction = node.baseName.description
        let line = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia).line
        let newElement = ClassElement(type: .property, name: calledFunction, file: fileURL, line: line)
        
      //  append(newElement: newElement)
        
        return .visitChildren
    }
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
      //  print("visited call: \(node.description)")
        let calledFunction = node.description
        let line = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia).line
        
        calls.append(Call(name: calledFunction, file: fileURL, line: line))
        
        return .visitChildren
    }
    override func visit(_ node: SubscriptCallExprSyntax) -> SyntaxVisitorContinueKind {
     //   print("visited call: \(node.description)")
        if let calledFunction = node.calledExpression.as(SubscriptCallExprSyntax.self)?.description{
            let line = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia).line
            
            calls.append(Call(name: calledFunction, file: fileURL, line: line))
        }
        return .visitChildren
    }
    
    func getFunctionCalls() ->[Call] {
    //    print("found \(calls.count.description) function Calls")
        return calls
    }
    
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        
    //   print("visited class: \(node.name.text)")
        
        let location = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        let className = node.name.text
        
        let newClass = ClassElement(type: .clas, name: className, file: fileURL, line: location.line)
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
        
    //    print("visited: \(node.name.text)")
        
        let location = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        let structName = node.name.text
        
        
        return .visitChildren
    }
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        
       
        
        let location = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        let methodName = node.name.text
        let signature = node.signature.parameterClause.description
        
        let newElement = ClassElement(type: .method, name: methodName, signature: signature, file: fileURL, line: location.line)
        append(newElement: newElement)

    
        
        return .visitChildren
    }
    
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        
        
     //   print("visited Variable: \(node.description)")
        
        
        let location = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        for binding in node.bindings {
            if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                let propertyName = identifier.identifier.text
                
           
                let newElement = ClassElement(type: .property, name: propertyName, file: fileURL, line: location.line)
                append(newElement: newElement)
             
            }
        }
        return .visitChildren
    }
    
    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        
     //   print("visited: Closure")
        
        
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
