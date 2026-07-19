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
    
    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(StorageMedium.self, forKey: .type)
        
        switch type {
        case .string:
            self = .string(value: try container.decode(String.self, forKey: .value))
        case .date:
            self = .date(date: try container.decode(Date.self, forKey: .value))
        case .int:
            self = .int(int: try container.decode(Int.self, forKey: .value))
        case .bool:
            self = .bool(bool: try container.decode(Bool.self, forKey: .value))
        case .float:
            self = .float(float: try container.decode(Float.self, forKey: .value))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .string(let value):
            try container.encode(StorageMedium.string, forKey: .type)
            try container.encode(value, forKey: .value)
        case .date(let date):
            try container.encode(StorageMedium.date, forKey: .type)
            try container.encode(date, forKey: .value)
        case .int(let int):
            try container.encode(StorageMedium.int, forKey: .type)
            try container.encode(int, forKey: .value)
        case .bool(let bool):
            try container.encode(StorageMedium.bool, forKey: .type)
            try container.encode(bool, forKey: .value)
        case .float(let float):
            try container.encode(StorageMedium.float, forKey: .type)
            try container.encode(float, forKey: .value)
        }
    }
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
    var booleanValue: Bool? {
        switch self {
        case .bool(bool: let value):
            return value
        default:
            return nil
        }
    }
    
    var dateValue: Date? {
        switch self {
        case .date(date: let value):
            return value
        default: return nil
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
