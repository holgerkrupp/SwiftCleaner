#if false
//
//  ClassTree.swift
//  SwiftCleaner
//
//  Created by Holger Krupp on 22.01.25.
//

import Foundation
import SwiftData



class ClassTree: Identifiable, ObservableObject {
    var name: String
    var id = UUID()
    var file: String
    var line: Int
    var elements: [ClassElement] // Unified list of elements (methods, properties, closures)
    
    init(name: String, file: String, line: Int, elements: [ClassElement] = []) {
        self.name = name
        self.file = file
        self.line = line
        self.elements = elements
    }
}


class ClassElement: Identifiable, ObservableObject {
    enum ElementType: String, Codable {
        case method
        case property
        case closure
    }
    var id = UUID()
    var type: ElementType      // Indicates whether it's a method, property, or closure
    var name: String           // Name of the element (e.g., method name, property name)
    var signature: String?     // Optional, used for methods or closures
    var file: String           // File where the element is declared
    var line: Int              // Line number in the file
    var usageCount: Int        // How often this element is used
    var usageReferences: [String] // Optional: List of references (file:line) where it's used
    
    init(type: ElementType, name: String, signature: String? = nil, file: String, line: Int, usageCount: Int = 0, usageReferences: [String] = []) {
        self.type = type
        self.name = name
        self.signature = signature
        self.file = file
        self.line = line
        self.usageCount = usageCount
        self.usageReferences = usageReferences
    }
}
#endif
