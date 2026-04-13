import Foundation
import SwiftSyntax

enum CollectedReferenceKind {
    case unqualified
    case member
    case type
}

struct CollectedReference: Hashable {
    let kind: CollectedReferenceKind
    let name: String
    let currentType: String?
    let baseChain: [String]
    let baseTypeHint: String?
    let line: Int
    let column: Int
}

struct BaseReferenceContext {
    var chain: [String]
    let typeHint: String?
}

struct TypeContext {
    let qualifiedName: String
    let kind: ElementType
    let isFromExtension: Bool
}

struct SourceLineMap {
    private let lineStarts: [Int]

    init(source: String) {
        var starts = [0]
        var offset = 0
        for byte in source.utf8 {
            if byte == 10 {
                starts.append(offset + 1)
            }
            offset += 1
        }
        self.lineStarts = starts
    }

    func location(for position: AbsolutePosition) -> (line: Int, column: Int) {
        let offset = position.utf8Offset
        var low = 0
        var high = lineStarts.count - 1
        var best = 0

        while low <= high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= offset {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return (line: best + 1, column: offset - lineStarts[best] + 1)
    }
}

final class OutlineNodeBuilder {
    let id: String
    let name: String
    let kind: OutlineKind
    let file: URL
    let line: Int
    let column: Int
    let detail: String?
    var children: [OutlineNodeBuilder] = []

    init(
        id: String,
        name: String,
        kind: OutlineKind,
        file: URL,
        line: Int,
        column: Int,
        detail: String?
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.file = file
        self.line = line
        self.column = column
        self.detail = detail
    }

    func build() -> OutlineNode {
        OutlineNode(
            id: id,
            name: name,
            kind: kind,
            file: file,
            line: line,
            column: column,
            detail: detail,
            children: children.map { $0.build() }
        )
    }
}

final class SourceVisitor: SyntaxVisitor {
    private static let identifierPattern = try! NSRegularExpression(pattern: "[A-Za-z_][A-Za-z0-9_]*")
    private static let ignoredTypeKeywords: Set<String> = [
        "any", "async", "await", "borrowing", "consuming", "each", "inout",
        "isolated", "rethrows", "some", "throws"
    ]
    private static let ignoredReferenceNames: Set<String> = [
        "_", "false", "nil", "self", "Self", "super", "true"
    ]

    private let url: URL
    private let lineMap: SourceLineMap
    private let previewIgnoredLines: Set<Int>

    private var typeStack: [TypeContext] = []
    private var valueScopes: [[String: String]] = [[:]]
    private var callableDepth = 0
    private var outlineRoots: [OutlineNodeBuilder] = []
    private var outlineStack: [OutlineNodeBuilder] = []

    var declarations: [ElementDeclaration] = []
    var references: [CollectedReference] = []
    var protocolRequirements: [String: Set<String>] = [:]
    var extensionInheritedTypeNames: [String: Set<String>] = [:]
    var outlineFile: OutlineFile {
        OutlineFile(
            id: url.path,
            url: url,
            children: outlineRoots.map { $0.build() }
        )
    }

    init(url: URL, source: String) {
        self.url = url
        self.lineMap = SourceLineMap(source: source)
        self.previewIgnoredLines = Self.previewLineNumbersToIgnore(in: source)
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        enterNominalType(
            name: node.name.text,
            kind: .class,
            startPosition: node.positionAfterSkippingLeadingTrivia,
            endPosition: node.endPositionBeforeTrailingTrivia,
            modifiers: node.modifiers,
            attributes: node.attributes,
            inheritedTypeNames: inheritedTypeNames(from: node.inheritanceClause)
        )
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        leaveType()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        enterNominalType(
            name: node.name.text,
            kind: .actor,
            startPosition: node.positionAfterSkippingLeadingTrivia,
            endPosition: node.endPositionBeforeTrailingTrivia,
            modifiers: node.modifiers,
            attributes: node.attributes,
            inheritedTypeNames: inheritedTypeNames(from: node.inheritanceClause)
        )
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        leaveType()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        enterNominalType(
            name: node.name.text,
            kind: .struct,
            startPosition: node.positionAfterSkippingLeadingTrivia,
            endPosition: node.endPositionBeforeTrailingTrivia,
            modifiers: node.modifiers,
            attributes: node.attributes,
            inheritedTypeNames: inheritedTypeNames(from: node.inheritanceClause)
        )
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        leaveType()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        enterNominalType(
            name: node.name.text,
            kind: .enum,
            startPosition: node.positionAfterSkippingLeadingTrivia,
            endPosition: node.endPositionBeforeTrailingTrivia,
            modifiers: node.modifiers,
            attributes: node.attributes,
            inheritedTypeNames: inheritedTypeNames(from: node.inheritanceClause)
        )
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        leaveType()
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        enterNominalType(
            name: node.name.text,
            kind: .protocol,
            startPosition: node.positionAfterSkippingLeadingTrivia,
            endPosition: node.endPositionBeforeTrailingTrivia,
            modifiers: node.modifiers,
            attributes: node.attributes,
            inheritedTypeNames: inheritedTypeNames(from: node.inheritanceClause)
        )
        return .visitChildren
    }

    override func visitPost(_ node: ProtocolDeclSyntax) {
        leaveType()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let extendedTypeName = normalizedQualifiedTypeName(from: node.extendedType.description) else {
            return .visitChildren
        }

        let inheritedTypeNames = inheritedTypeNames(from: node.inheritanceClause)
        if !inheritedTypeNames.isEmpty {
            extensionInheritedTypeNames[extendedTypeName, default: []].formUnion(inheritedTypeNames)
        }

        typeStack.append(TypeContext(
            qualifiedName: extendedTypeName,
            kind: .struct,
            isFromExtension: true
        ))
        addOutlineNode(
            kind: .extensionDecl,
            name: extendedTypeName,
            position: node.positionAfterSkippingLeadingTrivia,
            detail: inheritedTypeNames.isEmpty ? nil : inheritedTypeNames.joined(separator: ", "),
            pushOntoStack: true
        )

        for typeName in inheritedTypeNames {
            addTypeReference(typeName, at: node.positionAfterSkippingLeadingTrivia)
        }

        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        leaveType()
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        let containingType = currentTypeName
        let qualifiedName = qualifiedName(for: node.name.text)
        let startLocation = location(for: node.positionAfterSkippingLeadingTrivia)
        let endLocation = location(for: node.endPositionBeforeTrailingTrivia)
        let aliasedTypeName = extractTypeNames(from: node.initializer.value.description).first
        let modifiers = modifierNames(from: node.modifiers)
        let attributes = attributeNames(from: node.attributes)

        declarations.append(ElementDeclaration(
            id: declarationID(for: qualifiedName, at: startLocation),
            name: node.name.text,
            qualifiedName: qualifiedName,
            type: .typeAlias,
            file: url,
            line: startLocation.line,
            column: startLocation.column,
            endLine: endLocation.line,
            endColumn: endLocation.column,
            containingType: containingType,
            accessLevel: accessLevel(from: modifiers),
            modifiers: modifiers,
            isStatic: currentTypeName != nil,
            isOverride: false,
            attributes: attributes,
            inheritedTypeNames: [],
            declaredTypeName: aliasedTypeName,
            isFromExtension: typeStack.last?.isFromExtension ?? false
        ))
        addOutlineNode(
            kind: .typeAlias,
            name: node.name.text,
            position: node.positionAfterSkippingLeadingTrivia,
            detail: trimmed(node.initializer.value.description)
        )

        for typeName in extractTypeNames(from: node.initializer.value.description) {
            addTypeReference(typeName, at: node.positionAfterSkippingLeadingTrivia)
        }

        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let containingType = currentTypeName
        let modifiers = modifierNames(from: node.modifiers)
        let attributes = attributeNames(from: node.attributes)
        let startLocation = location(for: node.positionAfterSkippingLeadingTrivia)
        let endLocation = location(for: node.endPositionBeforeTrailingTrivia)

        let outlineNode = addOutlineNode(
            kind: containingType == nil ? .function : .method,
            name: node.name.text,
            position: node.positionAfterSkippingLeadingTrivia,
            detail: trimmed(node.signature.description),
            pushOntoStack: true
        )
        addParameterOutlineNodes(from: node.signature.parameterClause.parameters, to: outlineNode)

        if currentTypeKind == .protocol && callableDepth == 0, let currentTypeName {
            protocolRequirements[currentTypeName, default: []].insert(node.name.text)
        } else {
            declarations.append(ElementDeclaration(
                id: declarationID(for: qualifiedName(for: node.name.text), at: startLocation),
                name: node.name.text,
                qualifiedName: qualifiedName(for: node.name.text),
                type: containingType == nil ? .function : .method,
                file: url,
                line: startLocation.line,
                column: startLocation.column,
                endLine: endLocation.line,
                endColumn: endLocation.column,
                containingType: containingType,
                accessLevel: accessLevel(from: modifiers),
                modifiers: modifiers,
                isStatic: modifiers.contains("static") || modifiers.contains("class"),
                isOverride: modifiers.contains("override"),
                attributes: attributes,
                inheritedTypeNames: [],
                declaredTypeName: nil,
                isFromExtension: typeStack.last?.isFromExtension ?? false
            ))
        }

        for parameter in node.signature.parameterClause.parameters {
            let type = parameter.type
            addTypeReferences(from: type.description, at: parameter.positionAfterSkippingLeadingTrivia)
        }

        if let returnType = node.signature.returnClause?.type {
            addTypeReferences(from: returnType.description, at: returnType.positionAfterSkippingLeadingTrivia)
        }

        callableDepth += 1
        pushScope(functionBindings(from: node.signature.parameterClause.parameters))
        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        popOutlineNode()
        popScope()
        callableDepth -= 1
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        let outlineNode = addOutlineNode(
            kind: .initializer,
            name: "init",
            position: node.positionAfterSkippingLeadingTrivia,
            detail: trimmed(node.signature.description),
            pushOntoStack: true
        )
        addParameterOutlineNodes(from: node.signature.parameterClause.parameters, to: outlineNode)

        for parameter in node.signature.parameterClause.parameters {
            let type = parameter.type
            addTypeReferences(from: type.description, at: parameter.positionAfterSkippingLeadingTrivia)
        }

        callableDepth += 1
        pushScope(functionBindings(from: node.signature.parameterClause.parameters))
        return .visitChildren
    }

    override func visitPost(_ node: InitializerDeclSyntax) {
        popOutlineNode()
        popScope()
        callableDepth -= 1
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        callableDepth += 1
        pushScope([:])
        return .visitChildren
    }

    override func visitPost(_ node: ClosureExprSyntax) {
        popScope()
        callableDepth -= 1
    }

    override func visit(_ node: AccessorDeclSyntax) -> SyntaxVisitorContinueKind {
        callableDepth += 1
        pushScope([:])
        return .visitChildren
    }

    override func visitPost(_ node: AccessorDeclSyntax) {
        popScope()
        callableDepth -= 1
    }

    override func visit(_ node: CodeBlockSyntax) -> SyntaxVisitorContinueKind {
        pushScope([:])
        return .visitChildren
    }

    override func visitPost(_ node: CodeBlockSyntax) {
        popScope()
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let containingType = currentTypeName
        let modifiers = modifierNames(from: node.modifiers)
        let attributes = attributeNames(from: node.attributes)
        let startLocation = location(for: node.positionAfterSkippingLeadingTrivia)
        let endLocation = location(for: node.endPositionBeforeTrailingTrivia)

        for binding in node.bindings {
            guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
                continue
            }

            let name = identifier.identifier.text
            let declaredTypeName = binding.typeAnnotation
                .flatMap { extractTypeNames(from: $0.type.description).first }
                ?? binding.initializer.flatMap { inferTypeName(from: $0.value) }
            let outlineKind: OutlineKind =
                callableDepth == 0 ? (containingType == nil ? .variable : .property) : .variable
            let outlineDetail = binding.typeAnnotation
                .map { trimmed($0.type.description) }
                ?? declaredTypeName

            if let typeAnnotation = binding.typeAnnotation {
                addTypeReferences(from: typeAnnotation.type.description, at: typeAnnotation.positionAfterSkippingLeadingTrivia)
            }

            addOutlineNode(
                kind: outlineKind,
                name: name,
                position: identifier.positionAfterSkippingLeadingTrivia,
                detail: outlineDetail
            )

            if callableDepth == 0 {
                if currentTypeKind == .protocol, let currentTypeName {
                    protocolRequirements[currentTypeName, default: []].insert(name)
                } else {
                    declarations.append(ElementDeclaration(
                        id: declarationID(for: qualifiedName(for: name), at: startLocation),
                        name: name,
                        qualifiedName: qualifiedName(for: name),
                        type: containingType == nil ? .variable : .property,
                        file: url,
                        line: startLocation.line,
                        column: startLocation.column,
                        endLine: endLocation.line,
                        endColumn: endLocation.column,
                        containingType: containingType,
                        accessLevel: accessLevel(from: modifiers),
                        modifiers: modifiers,
                        isStatic: modifiers.contains("static") || modifiers.contains("class"),
                        isOverride: modifiers.contains("override"),
                        attributes: attributes,
                        inheritedTypeNames: [],
                        declaredTypeName: declaredTypeName,
                        isFromExtension: typeStack.last?.isFromExtension ?? false
                    ))
                }
            } else if let declaredTypeName {
                addBinding(name, typeName: declaredTypeName)
            }
        }

        return .visitChildren
    }

    override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
        guard currentTypeKind == .enum else {
            return .visitChildren
        }

        let startLocation = location(for: node.positionAfterSkippingLeadingTrivia)
        let endLocation = location(for: node.endPositionBeforeTrailingTrivia)
        let modifiers = modifierNames(from: node.modifiers)

        for element in node.elements {
            addOutlineNode(
                kind: .enumCase,
                name: element.name.text,
                position: element.positionAfterSkippingLeadingTrivia,
                detail: nil
            )
            declarations.append(ElementDeclaration(
                id: declarationID(for: qualifiedName(for: element.name.text), at: startLocation),
                name: element.name.text,
                qualifiedName: qualifiedName(for: element.name.text),
                type: .enumCase,
                file: url,
                line: startLocation.line,
                column: startLocation.column,
                endLine: endLocation.line,
                endColumn: endLocation.column,
                containingType: currentTypeName,
                accessLevel: accessLevel(from: modifiers),
                modifiers: modifiers,
                isStatic: true,
                isOverride: false,
                attributes: [],
                inheritedTypeNames: [],
                declaredTypeName: nil,
                isFromExtension: typeStack.last?.isFromExtension ?? false
            ))
        }

        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        addIdentifierReference(node.baseName.text, at: node.positionAfterSkippingLeadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        let location = location(for: node.positionAfterSkippingLeadingTrivia)
        guard !previewIgnoredLines.contains(location.line) else {
            return .visitChildren
        }

        let base = baseReferenceContext(for: node.base)

        for referenceName in referenceNames(from: memberAccessName(for: node)) {
            references.append(CollectedReference(
                kind: .member,
                name: referenceName,
                currentType: currentTypeName,
                baseChain: base.chain,
                baseTypeHint: base.typeHint,
                line: location.line,
                column: location.column
            ))
        }

        return .visitChildren
    }

    private var currentTypeName: String? {
        typeStack.last?.qualifiedName
    }

    private var currentTypeKind: ElementType? {
        typeStack.last?.kind
    }

    private func enterNominalType(
        name: String,
        kind: ElementType,
        startPosition: AbsolutePosition,
        endPosition: AbsolutePosition,
        modifiers: DeclModifierListSyntax?,
        attributes: AttributeListSyntax?,
        inheritedTypeNames: [String]
    ) {
        let containingType = currentTypeName
        let qualifiedName = containingType.map { "\($0).\(name)" } ?? name
        let startLocation = location(for: startPosition)
        let endLocation = location(for: endPosition)
        let modifierNames = modifierNames(from: modifiers)
        let attributeNames = attributeNames(from: attributes)

        declarations.append(ElementDeclaration(
            id: declarationID(for: qualifiedName, at: startLocation),
            name: name,
            qualifiedName: qualifiedName,
            type: kind,
            file: url,
            line: startLocation.line,
            column: startLocation.column,
            endLine: endLocation.line,
            endColumn: endLocation.column,
            containingType: containingType,
            accessLevel: accessLevel(from: modifierNames),
            modifiers: modifierNames,
            isStatic: containingType != nil,
            isOverride: false,
            attributes: attributeNames,
            inheritedTypeNames: inheritedTypeNames,
            declaredTypeName: nil,
            isFromExtension: typeStack.last?.isFromExtension ?? false
        ))

        for typeName in inheritedTypeNames {
            addTypeReference(typeName, at: startPosition)
        }

        typeStack.append(TypeContext(
            qualifiedName: qualifiedName,
            kind: kind,
            isFromExtension: false
        ))
        addOutlineNode(
            kind: outlineKind(for: kind),
            name: name,
            position: startPosition,
            detail: inheritedTypeNames.isEmpty ? nil : inheritedTypeNames.joined(separator: ", "),
            pushOntoStack: true
        )
    }

    private func leaveType() {
        if !typeStack.isEmpty {
            typeStack.removeLast()
        }
        popOutlineNode()
    }

    private func declarationID(for qualifiedName: String, at location: (line: Int, column: Int)) -> String {
        "\(url.path)#\(location.line):\(location.column):\(qualifiedName)"
    }

    @discardableResult
    private func addOutlineNode(
        kind: OutlineKind,
        name: String,
        position: AbsolutePosition,
        detail: String?,
        pushOntoStack: Bool = false
    ) -> OutlineNodeBuilder {
        let location = location(for: position)
        let node = OutlineNodeBuilder(
            id: outlineID(for: kind, name: name, location: location),
            name: name,
            kind: kind,
            file: url,
            line: location.line,
            column: location.column,
            detail: detail
        )

        if let parent = outlineStack.last {
            parent.children.append(node)
        } else {
            outlineRoots.append(node)
        }

        if pushOntoStack {
            outlineStack.append(node)
        }

        return node
    }

    private func popOutlineNode() {
        if !outlineStack.isEmpty {
            outlineStack.removeLast()
        }
    }

    private func addParameterOutlineNodes(
        from parameters: FunctionParameterListSyntax,
        to parent: OutlineNodeBuilder
    ) {
        for parameter in parameters {
            let name = parameterLocalName(for: parameter)
            parent.children.append(OutlineNodeBuilder(
                id: outlineID(
                    for: .parameter,
                    name: name,
                    location: location(for: parameter.positionAfterSkippingLeadingTrivia)
                ),
                name: name,
                kind: .parameter,
                file: url,
                line: location(for: parameter.positionAfterSkippingLeadingTrivia).line,
                column: location(for: parameter.positionAfterSkippingLeadingTrivia).column,
                detail: trimmed(parameter.type.description)
            ))
        }
    }

    private func outlineID(
        for kind: OutlineKind,
        name: String,
        location: (line: Int, column: Int)
    ) -> String {
        "\(url.path)#outline:\(location.line):\(location.column):\(kind.rawValue):\(name)"
    }

    private func outlineKind(for kind: ElementType) -> OutlineKind {
        switch kind {
        case .class: return .class
        case .actor: return .actor
        case .struct: return .struct
        case .enum: return .enum
        case .protocol: return .protocol
        case .typeAlias: return .typeAlias
        case .function: return .function
        case .method: return .method
        case .property: return .property
        case .variable: return .variable
        case .enumCase: return .enumCase
        }
    }

    private func qualifiedName(for name: String) -> String {
        currentTypeName.map { "\($0).\(name)" } ?? name
    }

    private func location(for position: AbsolutePosition) -> (line: Int, column: Int) {
        lineMap.location(for: position)
    }

    private func pushScope(_ bindings: [String: String]) {
        valueScopes.append(bindings)
    }

    private func popScope() {
        if valueScopes.count > 1 {
            valueScopes.removeLast()
        }
    }

    private func addBinding(_ name: String, typeName: String) {
        guard !valueScopes.isEmpty else { return }
        valueScopes[valueScopes.count - 1][name] = typeName
    }

    private func lookupBinding(named name: String) -> String? {
        for scope in valueScopes.reversed() {
            if let typeName = scope[name] {
                return typeName
            }
        }
        return nil
    }

    private func functionBindings(from parameters: FunctionParameterListSyntax) -> [String: String] {
        var bindings: [String: String] = [:]

        for parameter in parameters {
            let type = parameter.type
            let name = parameterLocalName(for: parameter)
            guard name != "_" else { continue }
            guard let typeName = extractTypeNames(from: type.description).first else { continue }
            bindings[name] = typeName
        }

        return bindings
    }

    private func inheritedTypeNames(from clause: InheritanceClauseSyntax?) -> [String] {
        guard let clause else { return [] }
        return clause.inheritedTypes.compactMap { normalizedQualifiedTypeName(from: $0.type.description) }
    }

    private func modifierNames(from modifiers: DeclModifierListSyntax?) -> [String] {
        guard let modifiers else { return [] }
        return modifiers.map(\.name.text)
    }

    private func accessLevel(from modifiers: [String]) -> String? {
        let orderedAccessLevels = ["open", "public", "package", "internal", "fileprivate", "private"]
        return orderedAccessLevels.first(where: modifiers.contains)
    }

    private func attributeNames(from attributes: AttributeListSyntax?) -> [String] {
        guard let attributes else { return [] }

        var names: [String] = []
        for attribute in attributes {
            guard let syntax = attribute.as(AttributeSyntax.self) else { continue }
            guard let name = normalizedQualifiedTypeName(from: syntax.attributeName.description) else { continue }
            names.append(lastIdentifier(in: name))
        }
        return names
    }

    private func addIdentifierReference(_ rawName: String, at position: AbsolutePosition) {
        let location = location(for: position)
        guard !previewIgnoredLines.contains(location.line) else { return }

        for referenceName in referenceNames(from: rawName) {
            guard !Self.ignoredReferenceNames.contains(referenceName) else { continue }
            references.append(CollectedReference(
                kind: .unqualified,
                name: referenceName,
                currentType: currentTypeName,
                baseChain: [],
                baseTypeHint: nil,
                line: location.line,
                column: location.column
            ))
        }
    }

    private func addTypeReferences(from text: String, at position: AbsolutePosition) {
        for typeName in extractTypeNames(from: text) {
            addTypeReference(typeName, at: position)
        }
    }

    private func addTypeReference(_ typeName: String, at position: AbsolutePosition) {
        let location = location(for: position)
        guard !previewIgnoredLines.contains(location.line) else { return }

        references.append(CollectedReference(
            kind: .type,
            name: typeName,
            currentType: currentTypeName,
            baseChain: [],
            baseTypeHint: nil,
            line: location.line,
            column: location.column
        ))
    }

    private func inferTypeName(from expression: ExprSyntax) -> String? {
        if let functionCall = expression.as(FunctionCallExprSyntax.self) {
            return inferTypeName(fromCalledExpression: functionCall.calledExpression)
        }

        if let declReference = expression.as(DeclReferenceExprSyntax.self) {
            return lookupBinding(named: declReference.baseName.text)
        }

        if let typeExpression = expression.as(TypeExprSyntax.self) {
            return extractTypeNames(from: typeExpression.type.description).first
        }

        return nil
    }

    private func inferTypeName(fromCalledExpression expression: ExprSyntax) -> String? {
        if let declReference = expression.as(DeclReferenceExprSyntax.self) {
            return normalizedQualifiedTypeName(from: declReference.baseName.text)
        }

        if let memberAccess = expression.as(MemberAccessExprSyntax.self) {
            return normalizedQualifiedTypeName(from: memberAccess.description)
        }

        return nil
    }

    private func baseReferenceContext(for expression: ExprSyntax?) -> BaseReferenceContext {
        guard let expression else {
            return BaseReferenceContext(chain: [], typeHint: nil)
        }

        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            let name = preferredBaseReferenceName(from: reference.baseName.text)
            return BaseReferenceContext(
                chain: [name],
                typeHint: name == "self" ? currentTypeName : lookupBinding(named: name)
            )
        }

        if let memberAccess = expression.as(MemberAccessExprSyntax.self) {
            var base = baseReferenceContext(for: memberAccess.base)
            let component = memberAccessName(for: memberAccess)
            if !component.isEmpty {
                base.chain.append(component)
            }
            return base
        }

        return BaseReferenceContext(chain: [], typeHint: nil)
    }

    private func memberAccessName(for node: MemberAccessExprSyntax) -> String {
        node.declName.baseName.text
    }

    private func parameterLocalName(for parameter: FunctionParameterSyntax) -> String {
        parameter.secondName?.text ?? parameter.firstName.text
    }

    private func extractTypeNames(from text: String) -> [String] {
        let nsText = text as NSString
        let matches = Self.identifierPattern.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        var results: [String] = []
        for match in matches {
            let identifier = nsText.substring(with: match.range)
            guard !Self.ignoredTypeKeywords.contains(identifier) else { continue }
            guard identifier != "Self" else {
                if let currentTypeName {
                    results.append(lastIdentifier(in: currentTypeName))
                }
                continue
            }
            results.append(lastIdentifier(in: identifier))
        }

        return Array(NSOrderedSet(array: results)) as? [String] ?? results
    }

    private func referenceNames(from rawName: String) -> [String] {
        var names = [rawName]

        let strippedDollar = rawName.hasPrefix("$") ? String(rawName.dropFirst()) : rawName
        if strippedDollar != rawName && !strippedDollar.isEmpty {
            names.append(strippedDollar)
        }

        let strippedUnderscore = rawName.hasPrefix("_") ? String(rawName.dropFirst()) : rawName
        if strippedUnderscore != rawName && !strippedUnderscore.isEmpty {
            names.append(strippedUnderscore)
        }

        return Array(NSOrderedSet(array: names)) as? [String] ?? names
    }

    private func preferredBaseReferenceName(from rawName: String) -> String {
        let candidates = referenceNames(from: rawName)

        if let bindingMatch = candidates.first(where: { lookupBinding(named: $0) != nil }) {
            return bindingMatch
        }

        if rawName.hasPrefix("$"),
           let projectedCandidate = candidates.first(where: { !$0.hasPrefix("$") }) {
            return projectedCandidate
        }

        if rawName.hasPrefix("_"),
           let strippedCandidate = candidates.first(where: { !$0.hasPrefix("_") }) {
            return strippedCandidate
        }

        return candidates.first ?? rawName
    }

    private func normalizedQualifiedTypeName(from rawText: String) -> String? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let parts = text
            .split(separator: ".")
            .compactMap { part in
                let identifiers = extractTypeNames(from: String(part))
                return identifiers.last
            }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ".")
    }

    private func lastIdentifier(in text: String) -> String {
        text.split(separator: ".").last.map(String.init) ?? text
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func previewLineNumbersToIgnore(in source: String) -> Set<Int> {
        let lines = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard !lines.isEmpty else { return [] }

        var ignoredLines = Set<Int>()
        var lineIndex = 0

        while lineIndex < lines.count {
            let lineText = String(lines[lineIndex])
            guard lineText.contains("#Preview") else {
                lineIndex += 1
                continue
            }

            var currentLine = lineIndex
            var inString = false
            var foundOpeningBrace = false
            var braceDepth = 0

            while currentLine < lines.count {
                let text = String(lines[currentLine])
                var index = text.startIndex
                var escaped = false

                while index < text.endIndex {
                    let character = text[index]
                    let nextIndex = text.index(after: index)
                    let nextCharacter = nextIndex < text.endIndex ? text[nextIndex] : nil

                    if !inString, character == "/", nextCharacter == "/" {
                        break
                    }

                    if character == "\"", !escaped {
                        inString.toggle()
                    }

                    if !inString {
                        if character == "{" {
                            foundOpeningBrace = true
                            braceDepth += 1
                        } else if character == "}", foundOpeningBrace {
                            braceDepth -= 1
                            if braceDepth == 0 {
                                for ignoredLine in (lineIndex + 1)...(currentLine + 1) {
                                    ignoredLines.insert(ignoredLine)
                                }
                                lineIndex = currentLine
                                break
                            }
                        }
                    }

                    escaped = (character == "\\") && !escaped
                    if character != "\\" {
                        escaped = false
                    }
                    index = nextIndex
                }

                if foundOpeningBrace, braceDepth == 0 {
                    break
                }

                currentLine += 1
            }

            if foundOpeningBrace, braceDepth > 0 {
                for ignoredLine in (lineIndex + 1)...lines.count {
                    ignoredLines.insert(ignoredLine)
                }
                break
            }

            lineIndex += 1
        }

        return ignoredLines
    }
}
