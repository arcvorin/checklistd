//
//  Variable.swift
//  Checklistd
//
//  Created by Arc Vorin on 2026-07-13.
//

import Foundation

enum StorageMedium: String, Codable {
    case string
    case date
    case int
    case bool
    case float
}

enum Variable: Codable {
    case string(value: String)
    case date(date: Date)
    case int(int: Int)
    case bool(bool: Bool)
    case float(float: Float)
}

extension Variable {
    var interpolatedValue: String {
        switch self {
            case .string(let value):
                value
            case .date(let date):
                date.formatted(date: .abbreviated, time: .omitted)
            case .int(let int):
                String(int)
            case .bool(let bool):
                String(bool)
            case .float(let float):
                String(float)
        }
    }
    
    func storageMediumRepresentation() -> StorageMedium {
        switch self {
            case .string:
                .string
        case .date:
                .date
        case .int:
                .int
        case .bool:
                .bool
        case .float:
                .float
        }
    }
    
    var numericValue: Double? {
        switch self {
            case .int(let int):
                Double(int)
            case .float(let float):
                Double(float)
            case .string, .date, .bool:
                nil
        }
    }
}

struct Parser {
    enum ParserError: Error, Equatable {
        case emptyVariableName
        case missingVariable(String)
        case unexpectedClosingTag
        case unterminatedVariable
    }
    
    static func interpolate(_ template: String, variables: [String: Variable]) throws -> String {
        var result = ""
        var currentIndex = template.startIndex
        
        while currentIndex < template.endIndex {
            let remaining = currentIndex..<template.endIndex
            let nextOpeningTag = template.range(of: "{{", range: remaining)
            let nextClosingTag = template.range(of: "}}", range: remaining)
            
            if let nextClosingTag, nextOpeningTag == nil || nextClosingTag.lowerBound < nextOpeningTag!.lowerBound {
                throw ParserError.unexpectedClosingTag
            }
            
            guard let openingTag = nextOpeningTag else {
                result += template[currentIndex...]
                break
            }
            
            result += template[currentIndex..<openingTag.lowerBound]
            
            let valueStartIndex = openingTag.upperBound
            guard let closingTag = template.range(of: "}}", range: valueStartIndex..<template.endIndex) else {
                throw ParserError.unterminatedVariable
            }
            
            let variableName = template[valueStartIndex..<closingTag.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !variableName.isEmpty else {
                throw ParserError.emptyVariableName
            }
            
            guard let variable = variables[variableName] else {
                throw ParserError.missingVariable(variableName)
            }
            
            result += variable.interpolatedValue
            currentIndex = closingTag.upperBound
        }
        
        return result
    }
}

