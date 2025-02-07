//
//  ClassTree.swift
//  SwiftCleaner
//
//  Created by Holger Krupp on 22.01.25.
//

import Foundation


enum ElementType: String, Codable {
    case `class`
    case method
    case property
    case closure
    case `extension`
}

class ClassElement: Identifiable, ObservableObject {

    var id = UUID()
    var type: ElementType      // Indicates whether it's a method, property, or closure
    var name: String           // Name of the element (e.g., method name, property name)
    var paramaters: [String]?
    var signature: String?     // Optional, used for methods or closures
    var file: URL           // File where the element is declared
    var line: Int              // Line number in the file
    var endline: Int?             // Line number in the file
    @Published var children: [ClassElement] = []// Unified list of elements (methods, properties, closures)
    
    init(type: ElementType, name: String, paramaters: [String]? = nil, signature: String? = nil, file: URL, line: Int, endline: Int? = nil) {
        self.type = type
        self.name = name
        self.paramaters = paramaters
        self.signature = signature
        self.file = file
        self.line = line
        self.endline = endline
    }
    
    var description: String{
        var temp = name
        
        let parameterlist = paramaters?.joined(separator: ", ") ?? ""
        temp.append("(")
        temp.append(parameterlist)
        temp.append(")")
        return temp
        
    }
    
    var location: String{
        if let endline{
            return ("\(file.lastPathComponent) Line \(line) - \(endline)")
        }else{
            return ("\(file.lastPathComponent) Line \(line)")
        }
        
    }
}

class Call: Identifiable, ObservableObject{
            
    var element: ClassElement?
    var className: String?
    var paramaters: [String]?
    var name: String
    var file: URL           // File where the element is called
    var line: Int
    
    var description: String{
        var temp = name
        
        let parameterlist = paramaters?.joined(separator: ", ") ?? ""
        temp.append("(")
        temp.append(parameterlist)
        temp.append(")")
        return temp
        
    }
    
    
    init(name: String, file: URL, line: Int, element: ClassElement? = nil, className: String? = nil, paramaters: [String]? = nil) {
        self.element = element
        self.className = className
        self.paramaters = paramaters

        self.name = name
        self.file = file
        self.line = line
    }
}
