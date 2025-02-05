//
//  ClassTree.swift
//  SwiftCleaner
//
//  Created by Holger Krupp on 22.01.25.
//

import Foundation


enum ElementType: String, Codable {
    case clas
    case method
    case property
    case closure
}

class ClassElement: Identifiable, ObservableObject {

    var id = UUID()
    var type: ElementType      // Indicates whether it's a method, property, or closure
    var name: String           // Name of the element (e.g., method name, property name)
    var paramaters: [String]?
    var signature: String?     // Optional, used for methods or closures
    var file: URL           // File where the element is declared
    var line: Int              // Line number in the file
    @Published var children: [ClassElement] = []// Unified list of elements (methods, properties, closures)
    
    init(type: ElementType, name: String, paramaters: [String]? = nil, signature: String? = nil, file: URL, line: Int) {
        self.type = type
        self.name = name
        self.paramaters = paramaters
        self.signature = signature
        self.file = file
        self.line = line
    }
}

class Call: Identifiable, ObservableObject{
            
    var element: ClassElement?
    var name: String
    var file: URL           // File where the element is called
    var line: Int
    
    
    init(name: String, file: URL, line: Int, element: ClassElement? = nil) {
        self.element = element
        self.name = name
        self.file = file
        self.line = line
    }
}
